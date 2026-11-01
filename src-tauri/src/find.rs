//! Quick Find (spec 6.6): searches file and folder names in a folder and its
//! sub-folders, in parallel on all CPU cores, without reading file contents.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use ignore::{WalkBuilder, WalkState};
use serde::{Deserialize, Serialize};

use crate::model::{self, Item, SyncState};
use crate::platform;

/// How often found items are sent to the UI (FR-FIND-03).
const BATCH_EVERY: Duration = Duration::from_millis(50);

const DAY_MS: i64 = 24 * 60 * 60 * 1000;

/// Search options (FR-FIND-04), from `[search]` in settings.toml.
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct SearchSettings {
    pub include_hidden: bool,
    pub follow_links: bool,
    /// 0 means no limit.
    pub max_depth: usize,
    pub max_results: usize,
    pub skip_online_only_folders: bool,
}

impl Default for SearchSettings {
    fn default() -> Self {
        Self {
            include_hidden: false,
            follow_links: false,
            max_depth: 0,
            max_results: 10_000,
            skip_online_only_folders: true,
        }
    }
}

/// A found item and its folder relative to the search root (the Folder column).
#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Found {
    #[serde(flatten)]
    pub item: Item,
    pub folder: String,
}

#[derive(Serialize, Clone)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum FindEvent {
    Batch { items: Vec<Found>, scanned: usize, found: usize },
    Done { scanned: usize, found: usize, truncated: bool, cancelled: bool, millis: u64 },
}

// QUERY

#[derive(Debug, Clone, PartialEq)]
enum Term {
    Contains(String),
    Glob(Vec<char>),
    Ext(Vec<String>),
    /// Size in bytes; files only.
    Size(Compare, u64),
    /// Modified time in milliseconds: from (inclusive) and to (exclusive).
    Modified(Option<i64>, Option<i64>),
    Folder(bool),
    In(String),
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Compare {
    Less,
    LessOrEqual,
    Greater,
    GreaterOrEqual,
    Equal,
}

/// A parsed search: the Quick Filter syntax (FR-QF-02) plus `size:`,
/// `modified:`, `type:` and `in:` (FR-FIND-02).
#[derive(Debug, Default, Clone)]
pub struct Query {
    include: Vec<Term>,
    exclude: Vec<Term>,
}

/// The clock the `modified:` terms are measured against.
#[derive(Clone, Copy, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Clock {
    pub now_ms: i64,
    /// Local time minus UTC, in minutes.
    pub utc_offset_minutes: i64,
}

impl Query {
    pub fn parse(text: &str, clock: Clock) -> Result<Self, String> {
        let mut query = Query::default();
        for word in text.split_whitespace() {
            let lower = word.to_lowercase();
            let (negated, body) = match lower.strip_prefix('!') {
                Some(rest) if !rest.is_empty() => (true, rest.to_string()),
                _ => (false, lower),
            };
            let term = parse_term(&body, clock)?;
            if negated {
                query.exclude.push(term);
            } else {
                query.include.push(term);
            }
        }
        Ok(query)
    }

    pub fn is_empty(&self) -> bool {
        self.include.is_empty() && self.exclude.is_empty()
    }

    /// True when `name` alone already rules the item out, so no metadata is read.
    fn name_rejects(&self, name: &str) -> bool {
        let lower = name.to_lowercase();
        let ext = Path::new(&lower).extension().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default();
        self.include.iter().any(|t| name_term(t, &lower, &ext) == Some(false))
            || self.exclude.iter().any(|t| name_term(t, &lower, &ext) == Some(true))
    }

    fn matches(&self, item: &Item, folder: &str) -> bool {
        self.include.iter().all(|t| term_matches(t, item, folder))
            && !self.exclude.iter().any(|t| term_matches(t, item, folder))
    }
}

fn parse_term(word: &str, clock: Clock) -> Result<Term, String> {
    if let Some(list) = word.strip_prefix("ext:") {
        let exts = list.split(',').map(|e| e.trim().trim_start_matches('.').to_string()).filter(|e| !e.is_empty());
        return Ok(Term::Ext(exts.collect()));
    }
    if let Some(value) = word.strip_prefix("size:") {
        let (compare, rest) = comparison(value);
        let bytes =
            parse_size(rest).ok_or_else(|| format!("\"{word}\" is not a size. Try size:>10mb or size:<1kb."))?;
        return Ok(Term::Size(compare, bytes));
    }
    if let Some(value) = word.strip_prefix("modified:") {
        let (from, to) = parse_modified(value, clock).ok_or_else(|| {
            format!("\"{word}\" is not a date. Try modified:today, modified:7d or modified:>2026-01-01.")
        })?;
        return Ok(Term::Modified(from, to));
    }
    if let Some(value) = word.strip_prefix("type:") {
        return match value {
            "folder" | "folders" | "dir" => Ok(Term::Folder(true)),
            "file" | "files" => Ok(Term::Folder(false)),
            _ => Err(format!("\"{word}\" is not a type. Use type:folder or type:file.")),
        };
    }
    if let Some(value) = word.strip_prefix("in:") {
        return Ok(Term::In(value.to_string()));
    }
    if word.contains('*') || word.contains('?') {
        return Ok(Term::Glob(word.chars().collect()));
    }
    Ok(Term::Contains(word.to_string()))
}

fn comparison(value: &str) -> (Compare, &str) {
    for (prefix, compare) in
        [(">=", Compare::GreaterOrEqual), ("<=", Compare::LessOrEqual), (">", Compare::Greater), ("<", Compare::Less)]
    {
        if let Some(rest) = value.strip_prefix(prefix) {
            return (compare, rest);
        }
    }
    (Compare::Equal, value.strip_prefix('=').unwrap_or(value))
}

/// `10mb`, `1.5gb`, `512` (bytes). Units are powers of 1024, as File Explorer uses.
fn parse_size(text: &str) -> Option<u64> {
    let split = text.find(|c: char| c.is_ascii_alphabetic()).unwrap_or(text.len());
    let (number, unit) = text.split_at(split);
    let number: f64 = number.parse().ok()?;
    let factor = match unit {
        "" | "b" => 1u64,
        "k" | "kb" => 1 << 10,
        "m" | "mb" => 1 << 20,
        "g" | "gb" => 1 << 30,
        "t" | "tb" => 1 << 40,
        _ => return None,
    };
    (number >= 0.0).then_some((number * factor as f64) as u64)
}

/// `today`, `yesterday`, `7d` / `2w` / `3m` (within the last…), `2026-01-01`
/// (that day), `>2026-01-01` (after that day), `<2026-01-01` (before it).
fn parse_modified(value: &str, clock: Clock) -> Option<(Option<i64>, Option<i64>)> {
    let midnight = |days: i64| (days * 1440 - clock.utc_offset_minutes) * 60_000;
    let today = (clock.now_ms / 60_000 + clock.utc_offset_minutes).div_euclid(1440);
    match value {
        "today" => return Some((Some(midnight(today)), None)),
        "yesterday" => return Some((Some(midnight(today - 1)), Some(midnight(today)))),
        _ => {}
    }
    if let Some(count) = value.strip_suffix(['d', 'w', 'm', 'y']) {
        let n: i64 = count.parse().ok()?;
        let days = match value.chars().last()? {
            'd' => n,
            'w' => n * 7,
            'm' => n * 30,
            _ => n * 365,
        };
        return Some((Some(clock.now_ms - days * DAY_MS), None));
    }
    let (compare, date) = comparison(value);
    let day = parse_date(date)?;
    let (start, end) = (midnight(day), midnight(day + 1));
    Some(match compare {
        Compare::Equal => (Some(start), Some(end)),
        Compare::Greater => (Some(end), None),
        Compare::GreaterOrEqual => (Some(start), None),
        Compare::Less => (None, Some(start)),
        Compare::LessOrEqual => (None, Some(end)),
    })
}

/// `yyyy-MM-dd` as days since 1970-01-01.
fn parse_date(text: &str) -> Option<i64> {
    let mut parts = text.split('-').map(|p| p.parse::<i64>().ok());
    let (y, m, d) = (parts.next()??, parts.next()??, parts.next()??);
    if parts.next().is_some() || !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    Some(days_from_civil(y, m, d))
}

/// Days since 1970-01-01 for a date in the proleptic Gregorian calendar.
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// The result of a term that only needs the name; `None` when it needs more.
fn name_term(term: &Term, lower: &str, ext: &str) -> Option<bool> {
    match term {
        Term::Contains(word) => Some(lower.contains(word.as_str())),
        Term::Glob(pattern) => Some(glob(pattern, &lower.chars().collect::<Vec<_>>())),
        Term::Ext(exts) => Some(exts.iter().any(|e| e == ext)),
        _ => None,
    }
}

fn term_matches(term: &Term, item: &Item, folder: &str) -> bool {
    match term {
        Term::Size(compare, bytes) => {
            !item.is_dir
                && match compare {
                    Compare::Less => item.size < *bytes,
                    Compare::LessOrEqual => item.size <= *bytes,
                    Compare::Greater => item.size > *bytes,
                    Compare::GreaterOrEqual => item.size >= *bytes,
                    Compare::Equal => item.size == *bytes,
                }
        }
        Term::Modified(from, to) => {
            item.modified.is_some_and(|m| from.is_none_or(|f| m >= f) && to.is_none_or(|t| m < t))
        }
        Term::Folder(folder_wanted) => item.is_dir == *folder_wanted,
        Term::In(name) => folder.split(['/', '\\']).any(|part| part.to_lowercase().contains(name.as_str())),
        _ => name_term(term, &item.name.to_lowercase(), &item.ext).unwrap_or(true),
    }
}

/// Wildcard match of the whole name: `*` any run of characters, `?` one character.
fn glob(pattern: &[char], name: &[char]) -> bool {
    let (mut p, mut n) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while n < name.len() {
        if p < pattern.len() && (pattern[p] == '?' || pattern[p] == name[n]) {
            p += 1;
            n += 1;
        } else if p < pattern.len() && pattern[p] == '*' {
            star = Some((p, n));
            p += 1;
        } else if let Some((sp, sn)) = star {
            p = sp + 1;
            n = sn + 1;
            star = Some((sp, sn + 1));
        } else {
            return false;
        }
    }
    pattern[p..].iter().all(|&c| c == '*')
}

// SEARCH

pub struct Search {
    pub root: PathBuf,
    pub query: Query,
    pub options: SearchSettings,
    pub cancelled: Arc<AtomicBool>,
}

/// Runs a search on its own threads, calling `send` with batches of results
/// at most every 50 ms and once more when it ends (FR-FIND-03, FR-FIND-05).
pub fn run(search: Search, send: impl Fn(FindEvent) + Send + Sync + 'static) {
    let started = Instant::now();
    let Search { root, query, options, cancelled } = search;
    let pending: Arc<Mutex<Vec<Found>>> = Arc::default();
    let scanned = Arc::new(AtomicUsize::new(0));
    let found = Arc::new(AtomicUsize::new(0));
    let finished = Arc::new(AtomicBool::new(false));
    let send = Arc::new(send);

    let flusher = {
        let (pending, scanned, found, finished, send) =
            (pending.clone(), scanned.clone(), found.clone(), finished.clone(), send.clone());
        thread::Builder::new().name("find-batch".into()).spawn(move || loop {
            let done = finished.load(Ordering::Acquire);
            let items = std::mem::take(&mut *pending.lock().unwrap());
            if !items.is_empty() {
                send(FindEvent::Batch {
                    items,
                    scanned: scanned.load(Ordering::Relaxed),
                    found: found.load(Ordering::Relaxed),
                });
            }
            if done {
                break;
            }
            thread::sleep(BATCH_EVERY);
        })
    };

    let threads =
        if platform::is_slow_path(&root) { 4 } else { thread::available_parallelism().map_or(4, |n| n.get()) };
    let skip_online_only = options.skip_online_only_folders;
    let mut builder = WalkBuilder::new(&root);
    builder
        .standard_filters(false)
        .hidden(!options.include_hidden)
        .follow_links(options.follow_links)
        .max_depth((options.max_depth > 0).then_some(options.max_depth))
        .threads(threads)
        .filter_entry(move |entry| {
            // Skip cloud folders that are not downloaded, so searching never downloads them.
            !(skip_online_only
                && entry.depth() > 0
                && entry.file_type().is_some_and(|t| t.is_dir())
                && entry.metadata().is_ok_and(|m| platform::sync_state(&m) == SyncState::OnlineOnly))
        });

    let truncated = Arc::new(AtomicBool::new(false));
    let query = Arc::new(query);
    let max_results = options.max_results.max(1);
    builder.build_parallel().run(|| {
        let (root, query, pending, scanned, found, cancelled, truncated) = (
            root.clone(),
            query.clone(),
            pending.clone(),
            scanned.clone(),
            found.clone(),
            cancelled.clone(),
            truncated.clone(),
        );
        Box::new(move |entry| {
            if cancelled.load(Ordering::Relaxed) {
                return WalkState::Quit;
            }
            // Unreadable folders and link loops are skipped.
            let Ok(entry) = entry else { return WalkState::Continue };
            if entry.depth() == 0 {
                return WalkState::Continue;
            }
            if entry.file_type().is_some_and(|t| t.is_dir()) {
                scanned.fetch_add(1, Ordering::Relaxed);
            }
            let name = entry.file_name().to_string_lossy();
            if query.name_rejects(&name) {
                return WalkState::Continue;
            }
            let path = entry.path();
            let Ok(meta) = std::fs::symlink_metadata(path) else { return WalkState::Continue };
            let item = model::build(name.into_owned(), path.to_path_buf(), &meta);
            let folder = relative_folder(&root, path);
            if !query.matches(&item, &folder) {
                return WalkState::Continue;
            }
            if found.fetch_add(1, Ordering::Relaxed) >= max_results {
                found.fetch_sub(1, Ordering::Relaxed);
                truncated.store(true, Ordering::Relaxed);
                return WalkState::Quit;
            }
            pending.lock().unwrap().push(Found { item, folder });
            WalkState::Continue
        })
    });

    finished.store(true, Ordering::Release);
    if let Ok(flusher) = flusher {
        let _ = flusher.join();
    }
    send(FindEvent::Done {
        scanned: scanned.load(Ordering::Relaxed),
        found: found.load(Ordering::Relaxed),
        truncated: truncated.load(Ordering::Relaxed),
        cancelled: cancelled.load(Ordering::Relaxed),
        millis: started.elapsed().as_millis() as u64,
    });
}

/// The item's folder relative to the search root; empty for items directly in it.
fn relative_folder(root: &Path, path: &Path) -> String {
    path.parent()
        .and_then(|parent| parent.strip_prefix(root).ok())
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    // 2026-03-15 12:00 UTC, two hours ahead of UTC.
    const CLOCK: Clock = Clock { now_ms: 1_773_576_000_000, utc_offset_minutes: 120 };

    fn search(root: &Path, text: &str) -> Vec<String> {
        let results = Arc::new(Mutex::new(Vec::new()));
        let sink = results.clone();
        run(
            Search {
                root: root.to_path_buf(),
                query: Query::parse(text, CLOCK).unwrap(),
                options: SearchSettings::default(),
                cancelled: Arc::default(),
            },
            move |event| {
                if let FindEvent::Batch { items, .. } = event {
                    sink.lock().unwrap().extend(items.into_iter().map(|f| {
                        if f.folder.is_empty() {
                            f.item.name
                        } else {
                            format!("{}/{}", f.folder.replace('\\', "/"), f.item.name)
                        }
                    }));
                }
            },
        );
        let mut found = results.lock().unwrap().clone();
        found.sort();
        found
    }

    fn tree() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("Acme/Contracts")).unwrap();
        fs::create_dir_all(root.join("Beta")).unwrap();
        fs::create_dir_all(root.join(".hidden")).unwrap();
        fs::write(root.join("Acme/Contracts/Contract draft.docx"), vec![0u8; 2048]).unwrap();
        fs::write(root.join("Acme/Contracts/Contract final.pdf"), vec![0u8; 20]).unwrap();
        fs::write(root.join("Beta/contract.pdf"), "").unwrap();
        fs::write(root.join("Beta/notes.txt"), "").unwrap();
        fs::write(root.join(".hidden/contract secret.pdf"), "").unwrap();
        dir
    }

    #[test]
    fn finds_names_with_the_quick_filter_syntax() {
        let dir = tree();
        assert_eq!(
            search(dir.path(), "contract"),
            [
                "Acme/Contracts",
                "Acme/Contracts/Contract draft.docx",
                "Acme/Contracts/Contract final.pdf",
                "Beta/contract.pdf"
            ]
        );
        assert_eq!(
            search(dir.path(), "contract !draft ext:pdf"),
            ["Acme/Contracts/Contract final.pdf", "Beta/contract.pdf"]
        );
        assert_eq!(search(dir.path(), "*.txt"), ["Beta/notes.txt"]);
        assert_eq!(search(dir.path(), "c?ntract.*"), ["Beta/contract.pdf"]);
    }

    #[test]
    fn filters_by_type_size_and_folder() {
        let dir = tree();
        assert_eq!(search(dir.path(), "contract type:folder"), ["Acme/Contracts"]);
        assert_eq!(search(dir.path(), "size:>1kb"), ["Acme/Contracts/Contract draft.docx"]);
        assert_eq!(search(dir.path(), "pdf in:acme"), ["Acme/Contracts/Contract final.pdf"]);
        assert_eq!(search(dir.path(), "modified:today type:file").len(), 4, "hidden folders are skipped");
    }

    #[test]
    fn stops_at_the_result_limit_and_when_cancelled() {
        let dir = tree();
        let events = Arc::new(Mutex::new(Vec::new()));
        let sink = events.clone();
        let options = SearchSettings { max_results: 2, ..SearchSettings::default() };
        run(
            Search {
                root: dir.path().into(),
                query: Query::parse("", CLOCK).unwrap(),
                options,
                cancelled: Arc::default(),
            },
            move |e| sink.lock().unwrap().push(e),
        );
        let events = events.lock().unwrap();
        let Some(FindEvent::Done { found, truncated, .. }) = events.last() else { panic!("no done event") };
        assert_eq!((*found, *truncated), (2, true));

        let cancelled = Arc::new(AtomicBool::new(true));
        let done = Arc::new(Mutex::new(None));
        let sink = done.clone();
        run(
            Search { root: dir.path().into(), query: Query::default(), options: SearchSettings::default(), cancelled },
            move |e| {
                if let FindEvent::Done { found, cancelled, .. } = e {
                    *sink.lock().unwrap() = Some((found, cancelled));
                }
            },
        );
        assert_eq!(*done.lock().unwrap(), Some((0, true)));
    }

    #[test]
    fn parses_dates_and_sizes() {
        assert_eq!(parse_size("10mb"), Some(10 << 20));
        assert_eq!(parse_size("1.5k"), Some(1536));
        assert_eq!(parse_size("ten"), None);
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(2026, 3, 15), 20_527);
        // Local midnight of 2026-03-15 is 22:00 UTC the day before.
        let (from, to) = parse_modified("2026-03-15", CLOCK).unwrap();
        assert_eq!(from, Some(20_527 * DAY_MS - 120 * 60_000));
        assert_eq!(to.unwrap() - from.unwrap(), DAY_MS);
        assert_eq!(parse_modified("today", CLOCK).unwrap().0, from);
        assert_eq!(parse_modified("7d", CLOCK).unwrap().0, Some(CLOCK.now_ms - 7 * DAY_MS));
        assert!(Query::parse("modified:soon", CLOCK).is_err());
        assert!(Query::parse("type:car", CLOCK).is_err());
    }

    #[test]
    fn glob_matches_whole_names() {
        let g = |p: &str, n: &str| glob(&p.chars().collect::<Vec<_>>(), &n.chars().collect::<Vec<_>>());
        assert!(g("*.pdf", "a.pdf"));
        assert!(!g("*.pdf", "a.pdf.txt"));
        assert!(g("report-??", "report-01"));
        assert!(g("*a*b*", "xxaxxbxx"));
        assert!(!g("a?", "a"));
    }
}
