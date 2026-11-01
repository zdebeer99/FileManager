//! Background jobs: copy, move, duplicate and delete (FR-OP-02 to 04).
//! Jobs run one after another on their own thread, so the UI never waits
//! and two jobs never compete for the same disk. Progress goes to the UI as
//! `job-progress` events; name conflicts pause the job and ask the UI with a
//! `job-conflict` event (FR-COPY-04).

use std::collections::{HashMap, VecDeque};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;
use std::time::{Duration, Instant, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};

/// Sends an event to the UI. Tests replace it with a recorder.
pub type EventSink = Arc<dyn Fn(&'static str, serde_json::Value) + Send + Sync>;

use crate::fileops::{self, Naming};

const EMIT_EVERY: Duration = Duration::from_millis(100);
const UNDO_STEPS: usize = 50;

#[derive(Deserialize, Serialize, Clone, Copy, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum JobKind {
    Copy,
    Move,
    Duplicate,
    Delete,
    /// Drag and drop: a move on the same volume, otherwise a copy (FR-COPY-06).
    /// Resolved to Move or Copy when the job is submitted.
    Transfer,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct JobRequest {
    pub kind: JobKind,
    pub sources: Vec<String>,
    #[serde(default)]
    pub dest: Option<String>,
    #[serde(default)]
    pub permanent: bool,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct JobError {
    pub path: String,
    pub message: String,
    /// "noTrash" when an item can't go to the Recycle Bin (FR-DEL-03).
    pub code: &'static str,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct JobStatus {
    pub id: u64,
    pub kind: JobKind,
    /// "queued", "running", "paused", "waiting" (for a conflict answer), "done" or "cancelled".
    pub state: &'static str,
    pub permanent: bool,
    pub count: usize,
    pub first: String,
    pub dest: Option<String>,
    pub done_items: u64,
    pub total_items: u64,
    pub done_bytes: u64,
    pub total_bytes: u64,
    pub current: String,
    pub elapsed_ms: u64,
    pub errors: Vec<JobError>,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct ConflictEvent {
    job_id: u64,
    source: FileInfo,
    target: FileInfo,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct FileInfo {
    name: String,
    path: String,
    size: u64,
    modified: Option<i64>,
    is_dir: bool,
}

#[derive(Deserialize, Clone, Copy, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum Action {
    Replace,
    Skip,
    KeepBoth,
    ReplaceIfNewer,
}

/// One step that Ctrl+Z can take back (FR-UNDO-01).
#[derive(Clone, Debug)]
pub enum UndoStep {
    Created(Vec<PathBuf>),
    Moved(Vec<(PathBuf, PathBuf)>),
    Trashed(Vec<PathBuf>),
    Renamed { from: PathBuf, to: PathBuf },
}

#[derive(Default)]
struct Control {
    cancel: AtomicBool,
    pause: AtomicBool,
    reply: Mutex<Option<mpsc::Sender<(Action, bool)>>>,
}

struct Job {
    status: JobStatus,
    request: JobRequest,
    control: Arc<Control>,
}

pub struct JobManager {
    events: EventSink,
    next_id: AtomicU64,
    queue: Mutex<VecDeque<Job>>,
    wake: Condvar,
    controls: Mutex<HashMap<u64, Arc<Control>>>,
    undo: Mutex<Vec<UndoStep>>,
}

impl JobManager {
    pub fn start(app: AppHandle) -> Arc<Self> {
        Self::start_with(Arc::new(move |name, payload| {
            let _ = app.emit(name, payload);
        }))
    }

    pub fn start_with(events: EventSink) -> Arc<Self> {
        let manager = Arc::new(Self {
            events,
            next_id: AtomicU64::new(1),
            queue: Mutex::new(VecDeque::new()),
            wake: Condvar::new(),
            controls: Mutex::new(HashMap::new()),
            undo: Mutex::new(Vec::new()),
        });
        let worker = manager.clone();
        thread::Builder::new()
            .name("jobs".into())
            .spawn(move || worker.run_queue())
            .expect("failed to start the job thread");
        manager
    }

    /// Queues a job and returns its id.
    pub fn submit(&self, mut request: JobRequest) -> u64 {
        if request.kind == JobKind::Transfer {
            let dest = PathBuf::from(request.dest.clone().unwrap_or_default());
            let same = request.sources.iter().all(|s| fileops::same_volume(Path::new(s), &dest));
            request.kind = if same { JobKind::Move } else { JobKind::Copy };
        }
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let control = Arc::new(Control::default());
        let first = request
            .sources
            .first()
            .map(|s| Path::new(s).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or(s.clone()))
            .unwrap_or_default();
        let status = JobStatus {
            id,
            kind: request.kind,
            state: "queued",
            permanent: request.permanent,
            count: request.sources.len(),
            first,
            dest: request.dest.clone(),
            done_items: 0,
            total_items: request.sources.len() as u64,
            done_bytes: 0,
            total_bytes: 0,
            current: String::new(),
            elapsed_ms: 0,
            errors: Vec::new(),
        };
        self.send("job-progress", &status);
        self.controls.lock().unwrap().insert(id, control.clone());
        self.queue.lock().unwrap().push_back(Job { status, request, control });
        self.wake.notify_one();
        id
    }

    pub fn cancel(&self, id: u64) {
        if let Some(control) = self.controls.lock().unwrap().get(&id) {
            control.cancel.store(true, Ordering::Relaxed);
        }
        // A job that hasn't started yet is simply dropped from the queue.
        let mut queue = self.queue.lock().unwrap();
        if let Some(index) = queue.iter().position(|job| job.status.id == id) {
            if let Some(mut job) = queue.remove(index) {
                job.status.state = "cancelled";
                self.send("job-progress", &job.status);
            }
        }
    }

    pub fn pause(&self, id: u64, paused: bool) {
        if let Some(control) = self.controls.lock().unwrap().get(&id) {
            control.pause.store(paused, Ordering::Relaxed);
        }
    }

    /// The UI's answer to a name conflict.
    pub fn resolve(&self, id: u64, action: Action, apply_to_all: bool) {
        if let Some(control) = self.controls.lock().unwrap().get(&id) {
            if let Some(reply) = control.reply.lock().unwrap().take() {
                let _ = reply.send((action, apply_to_all));
            }
        }
    }

    fn send(&self, name: &'static str, payload: &impl Serialize) {
        (self.events)(name, serde_json::to_value(payload).unwrap_or_default());
    }

    pub fn push_undo(&self, step: UndoStep) {
        let mut undo = self.undo.lock().unwrap();
        undo.push(step);
        if undo.len() > UNDO_STEPS {
            undo.remove(0);
        }
    }

    pub fn pop_undo(&self) -> Option<UndoStep> {
        self.undo.lock().unwrap().pop()
    }

    fn run_queue(&self) {
        loop {
            let job = {
                let mut queue = self.queue.lock().unwrap();
                while queue.is_empty() {
                    queue = self.wake.wait(queue).unwrap();
                }
                queue.pop_front().expect("the queue is not empty")
            };
            let id = job.status.id;
            // A panic in one job must not stop the queue (NFR-REL-04).
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| Runner::new(self, job).run()));
            if result.is_err() {
                tracing::error!(job = id, "a job stopped unexpectedly");
            }
            self.controls.lock().unwrap().remove(&id);
        }
    }
}

struct Runner<'a> {
    manager: &'a JobManager,
    request: JobRequest,
    control: Arc<Control>,
    status: JobStatus,
    started: Instant,
    last_emit: Instant,
    apply_to_all: Option<Action>,
}

impl<'a> Runner<'a> {
    fn new(manager: &'a JobManager, job: Job) -> Self {
        Self {
            manager,
            request: job.request,
            control: job.control,
            status: job.status,
            started: Instant::now(),
            last_emit: Instant::now() - EMIT_EVERY,
            apply_to_all: None,
        }
    }

    fn run(mut self) {
        self.status.state = "running";
        let sources: Vec<PathBuf> = self.request.sources.iter().map(PathBuf::from).collect();
        let undo = match self.request.kind {
            JobKind::Copy | JobKind::Duplicate => {
                let (bytes, items) = fileops::measure(&sources);
                self.status.total_bytes = bytes;
                self.status.total_items = items;
                self.emit(true);
                let mut created = Vec::new();
                for source in &sources {
                    let dest = match (self.request.kind, &self.request.dest) {
                        (JobKind::Copy, Some(dest)) => PathBuf::from(dest),
                        _ => source.parent().map(Path::to_path_buf).unwrap_or_default(),
                    };
                    // Pasting into the item's own folder makes a copy, like Explorer.
                    let naming = (source.parent() == Some(dest.as_path())).then_some(Naming::Copy);
                    if let Some(target) = self.copy_entry(source, &dest, naming) {
                        created.push(target);
                    }
                }
                (!created.is_empty()).then_some(UndoStep::Created(created))
            }
            JobKind::Move | JobKind::Transfer => {
                self.emit(true);
                let dest = PathBuf::from(self.request.dest.clone().unwrap_or_default());
                let moved: Vec<(PathBuf, PathBuf)> = sources.iter().filter_map(|s| self.move_entry(s, &dest)).collect();
                (!moved.is_empty()).then_some(UndoStep::Moved(moved))
            }
            JobKind::Delete => {
                self.emit(true);
                let mut trashed = Vec::new();
                for source in &sources {
                    if !self.checkpoint() {
                        break;
                    }
                    self.status.current = name_of(source);
                    if self.request.permanent {
                        if let Err(e) = fileops::remove_permanently(source) {
                            self.fail(source, fileops::describe(&e, source), "");
                        }
                    } else {
                        match trash::delete(source) {
                            Ok(()) => trashed.push(source.clone()),
                            Err(e) => self.fail(
                                source,
                                format!("Can't move \"{}\" to the Recycle Bin: {e}", name_of(source)),
                                "noTrash",
                            ),
                        }
                    }
                    self.status.done_items += 1;
                    self.emit(false);
                }
                (!trashed.is_empty()).then_some(UndoStep::Trashed(trashed))
            }
        };
        if let Some(step) = undo {
            self.manager.push_undo(step);
        }
        self.status.state = if self.cancelled() { "cancelled" } else { "done" };
        self.status.current.clear();
        self.emit(true);
    }

    /// Copies `source` into `dest_dir`, handling name conflicts. Returns the new path.
    fn copy_entry(&mut self, source: &Path, dest_dir: &Path, naming: Option<Naming>) -> Option<PathBuf> {
        if !self.checkpoint() {
            return None;
        }
        let name = name_of(source);
        let meta = match source.symlink_metadata() {
            Ok(meta) => meta,
            Err(e) => {
                self.fail(source, fileops::describe(&e, source), "");
                return None;
            }
        };
        if meta.is_dir() && fileops::is_inside(dest_dir, source) && naming.is_none() {
            self.fail(source, format!("Can't copy the folder \"{name}\" into itself."), "");
            return None;
        }
        let mut target = match naming {
            Some(naming) => fileops::free_name(dest_dir, &name, naming),
            None => dest_dir.join(&name),
        };
        let existing = target.symlink_metadata().ok();

        if meta.is_dir() {
            match existing {
                // Folders with the same name are merged; conflicts are asked per file.
                Some(existing) if existing.is_dir() => {}
                Some(_) => match self.ask(source, &target) {
                    Action::KeepBoth => target = fileops::free_name(dest_dir, &name, Naming::Numbered),
                    _ => {
                        self.skip(source);
                        return None;
                    }
                },
                None => {}
            }
            if !target.exists() {
                if let Err(e) = fs::create_dir(&target) {
                    self.fail(source, fileops::describe(&e, &target), "");
                    return None;
                }
            }
            self.status.done_items += 1;
            let mut children: Vec<PathBuf> = match fs::read_dir(source) {
                Ok(entries) => entries.filter_map(Result::ok).map(|e| e.path()).collect(),
                Err(e) => {
                    self.fail(source, fileops::describe(&e, source), "");
                    return Some(target);
                }
            };
            children.sort();
            for child in children {
                self.copy_entry(&child, &target, None);
            }
            return Some(target);
        }

        if existing.is_some() {
            match self.ask(source, &target) {
                Action::Replace => {}
                Action::ReplaceIfNewer => {
                    if modified(source) <= modified(&target) {
                        self.skip(source);
                        return None;
                    }
                }
                Action::KeepBoth => target = fileops::free_name(dest_dir, &name, Naming::Numbered),
                Action::Skip => {
                    self.skip(source);
                    return None;
                }
            }
        }
        self.status.current = name;
        self.emit(false);
        let result = if meta.file_type().is_symlink() {
            copy_symlink(source, &target)
        } else {
            fileops::copy_file(source, &target)
        };
        match result {
            Ok(bytes) => self.status.done_bytes += bytes,
            Err(e) => self.fail(source, fileops::describe(&e, source), ""),
        }
        self.status.done_items += 1;
        self.emit(false);
        Some(target)
    }

    /// Moves `source` into `dest_dir`: a rename on the same volume, otherwise
    /// copy, check, then delete the original (FR-COPY-01).
    fn move_entry(&mut self, source: &Path, dest_dir: &Path) -> Option<(PathBuf, PathBuf)> {
        if !self.checkpoint() {
            return None;
        }
        let name = name_of(source);
        self.status.current = name.clone();
        self.emit(false);
        if source.parent() == Some(dest_dir) {
            self.status.done_items += 1;
            return None;
        }
        if source.is_dir() && fileops::is_inside(dest_dir, source) {
            self.fail(source, format!("Can't move the folder \"{name}\" into itself."), "");
            return None;
        }
        let mut target = dest_dir.join(&name);
        if let Ok(existing) = target.symlink_metadata() {
            if existing.is_dir() && source.is_dir() {
                return self.move_by_copy(source, dest_dir, &target);
            }
            match self.ask(source, &target) {
                Action::Skip => {
                    self.skip(source);
                    return None;
                }
                Action::KeepBoth => target = fileops::free_name(dest_dir, &name, Naming::Numbered),
                Action::ReplaceIfNewer if modified(source) <= modified(&target) => {
                    self.skip(source);
                    return None;
                }
                _ => {
                    if let Err(e) = fileops::remove_permanently(&target) {
                        self.fail(source, fileops::describe(&e, &target), "");
                        return None;
                    }
                }
            }
        }
        match fs::rename(source, &target) {
            Ok(()) => {
                self.status.done_items += 1;
                self.emit(false);
                Some((source.to_path_buf(), target))
            }
            Err(e) if fileops::is_cross_device(&e) => self.move_by_copy(source, dest_dir, &target),
            Err(e) => {
                self.fail(source, fileops::describe(&e, source), "");
                None
            }
        }
    }

    fn move_by_copy(&mut self, source: &Path, dest_dir: &Path, target: &Path) -> Option<(PathBuf, PathBuf)> {
        let errors_before = self.status.errors.len();
        let (bytes, _) = fileops::measure(&[source.to_path_buf()]);
        self.status.total_bytes += bytes;
        let naming = (target.file_name() != source.file_name()).then_some(Naming::Numbered);
        let copied = self.copy_entry(source, dest_dir, naming)?;
        let (copied_bytes, _) = fileops::measure(std::slice::from_ref(&copied));
        if self.status.errors.len() != errors_before || self.cancelled() || copied_bytes < bytes {
            self.fail(source, format!("\"{}\" was not fully copied, so the original was kept.", name_of(source)), "");
            return None;
        }
        if let Err(e) = fileops::remove_permanently(source) {
            self.fail(source, fileops::describe(&e, source), "");
        }
        Some((source.to_path_buf(), copied))
    }

    /// Asks the UI what to do about a name conflict, and waits for the answer.
    fn ask(&mut self, source: &Path, target: &Path) -> Action {
        if let Some(action) = self.apply_to_all {
            return action;
        }
        let (tx, rx) = mpsc::channel();
        *self.control.reply.lock().unwrap() = Some(tx);
        self.status.state = "waiting";
        self.emit(true);
        self.manager.send(
            "job-conflict",
            &ConflictEvent { job_id: self.status.id, source: file_info(source), target: file_info(target) },
        );
        let action = loop {
            match rx.recv_timeout(Duration::from_millis(200)) {
                Ok((action, all)) => {
                    if all {
                        self.apply_to_all = Some(action);
                    }
                    break action;
                }
                Err(RecvTimeoutError::Timeout) if !self.cancelled() => continue,
                _ => break Action::Skip,
            }
        };
        self.status.state = "running";
        self.emit(true);
        action
    }

    /// Waits while paused. Returns false once the job is cancelled.
    fn checkpoint(&mut self) -> bool {
        while self.control.pause.load(Ordering::Relaxed) && !self.cancelled() {
            if self.status.state != "paused" {
                self.status.state = "paused";
                self.emit(true);
            }
            thread::sleep(Duration::from_millis(100));
        }
        if self.status.state == "paused" {
            self.status.state = "running";
            self.emit(true);
        }
        !self.cancelled()
    }

    fn cancelled(&self) -> bool {
        self.control.cancel.load(Ordering::Relaxed)
    }

    fn skip(&mut self, source: &Path) {
        let (bytes, items) = fileops::measure(&[source.to_path_buf()]);
        self.status.done_bytes += bytes;
        self.status.done_items += items;
    }

    fn fail(&mut self, path: &Path, message: String, code: &'static str) {
        tracing::warn!(path = %path.display(), "{message}");
        self.status.errors.push(JobError { path: path.to_string_lossy().into_owned(), message, code });
    }

    fn emit(&mut self, force: bool) {
        if force || self.last_emit.elapsed() >= EMIT_EVERY {
            self.status.elapsed_ms = self.started.elapsed().as_millis() as u64;
            self.last_emit = Instant::now();
            self.manager.send("job-progress", &self.status);
        }
    }
}

/// Takes back one step (FR-UNDO-01). Returns a short description for the
/// status bar. Steps whose files changed meanwhile are refused (FR-UNDO-02).
pub fn undo(step: UndoStep) -> Result<String, String> {
    match step {
        UndoStep::Renamed { from, to } => {
            if !to.exists() {
                return Err(format!("Can't undo: \"{}\" no longer exists.", name_of(&to)));
            }
            if from.exists() && !name_of(&from).eq_ignore_ascii_case(&name_of(&to)) {
                return Err(format!("Can't undo: \"{}\" exists again.", name_of(&from)));
            }
            fs::rename(&to, &from).map_err(|e| fileops::describe(&e, &to))?;
            Ok(format!("Renamed back to \"{}\"", name_of(&from)))
        }
        UndoStep::Created(paths) => {
            let existing: Vec<PathBuf> = paths.into_iter().filter(|p| p.symlink_metadata().is_ok()).collect();
            trash::delete_all(&existing).map_err(|e| format!("Can't undo: {e}"))?;
            Ok(format!("Moved {} new item(s) to the Recycle Bin", existing.len()))
        }
        UndoStep::Moved(pairs) => {
            let mut errors = Vec::new();
            for (from, to) in pairs.iter().rev() {
                if from.symlink_metadata().is_ok() {
                    errors.push(format!("\"{}\" exists in its old place again.", name_of(from)));
                    continue;
                }
                if let Err(e) = fs::rename(to, from) {
                    errors.push(fileops::describe(&e, to));
                }
            }
            if errors.is_empty() {
                Ok(format!("Moved {} item(s) back", pairs.len()))
            } else {
                Err(format!("Undo was not complete. {}", errors.join(" ")))
            }
        }
        UndoStep::Trashed(paths) => restore_from_trash(&paths),
    }
}

#[cfg(any(windows, all(unix, not(target_os = "macos"), not(target_os = "ios"), not(target_os = "android"))))]
fn restore_from_trash(paths: &[PathBuf]) -> Result<String, String> {
    let items = trash::os_limited::list().map_err(|e| format!("Can't read the Recycle Bin: {e}"))?;
    let mut chosen: Vec<trash::TrashItem> = Vec::new();
    for path in paths {
        if let Some(item) =
            items.iter().filter(|item| item.original_path() == *path).max_by_key(|item| item.time_deleted).cloned()
        {
            chosen.push(item);
        }
    }
    let count = chosen.len();
    trash::os_limited::restore_all(chosen).map_err(|e| format!("Can't restore from the Recycle Bin: {e}"))?;
    Ok(format!("Restored {count} item(s) from the Recycle Bin"))
}

#[cfg(not(any(windows, all(unix, not(target_os = "macos"), not(target_os = "ios"), not(target_os = "android")))))]
fn restore_from_trash(_paths: &[PathBuf]) -> Result<String, String> {
    Err("Restoring from the Recycle Bin is not supported on this system.".into())
}

#[cfg(unix)]
fn copy_symlink(source: &Path, target: &Path) -> std::io::Result<u64> {
    let link = fs::read_link(source)?;
    if target.symlink_metadata().is_ok() {
        fs::remove_file(target)?;
    }
    std::os::unix::fs::symlink(link, target)?;
    Ok(0)
}

#[cfg(not(unix))]
fn copy_symlink(source: &Path, target: &Path) -> std::io::Result<u64> {
    fileops::copy_file(source, target)
}

fn name_of(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.display().to_string())
}

fn modified(path: &Path) -> Option<std::time::SystemTime> {
    path.metadata().and_then(|m| m.modified()).ok()
}

fn file_info(path: &Path) -> FileInfo {
    let meta = path.metadata().ok();
    FileInfo {
        name: name_of(path),
        path: path.to_string_lossy().into_owned(),
        size: meta.as_ref().map_or(0, |m| m.len()),
        modified: meta
            .as_ref()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map(|d| d.as_millis() as i64),
        is_dir: meta.is_some_and(|m| m.is_dir()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    type Log = Arc<Mutex<Vec<(String, serde_json::Value)>>>;

    /// Starts a job manager whose events are recorded, and which answers
    /// every conflict with `answer`.
    fn start(answer: Action) -> (Arc<JobManager>, Log) {
        let log = Arc::new(Mutex::new(Vec::new()));
        let recorded = log.clone();
        let cell: Arc<Mutex<Option<Arc<JobManager>>>> = Arc::new(Mutex::new(None));
        let reply_to = cell.clone();
        let manager = JobManager::start_with(Arc::new(move |name, payload| {
            if name == "job-conflict" {
                let id = payload["jobId"].as_u64().unwrap();
                let target = reply_to.clone();
                thread::spawn(move || {
                    while target.lock().unwrap().is_none() {
                        thread::sleep(Duration::from_millis(5));
                    }
                    target.lock().unwrap().as_ref().unwrap().resolve(id, answer, false);
                });
            }
            recorded.lock().unwrap().push((name.to_string(), payload));
        }));
        *cell.lock().unwrap() = Some(manager.clone());
        (manager, log)
    }

    /// Runs one job and returns its final status.
    fn run(
        manager: &JobManager,
        log: &Mutex<Vec<(String, serde_json::Value)>>,
        request: JobRequest,
    ) -> serde_json::Value {
        let id = manager.submit(request);
        for _ in 0..500 {
            let finished = log
                .lock()
                .unwrap()
                .iter()
                .rev()
                .find(|(name, p)| {
                    name == "job-progress" && p["id"] == id && (p["state"] == "done" || p["state"] == "cancelled")
                })
                .map(|(_, status)| status.clone());
            if let Some(status) = finished {
                return status;
            }
            thread::sleep(Duration::from_millis(10));
        }
        panic!("the job did not finish");
    }

    fn request(kind: JobKind, sources: &[&Path], dest: Option<&Path>) -> JobRequest {
        JobRequest {
            kind,
            sources: sources.iter().map(|p| p.to_string_lossy().into_owned()).collect(),
            dest: dest.map(|d| d.to_string_lossy().into_owned()),
            permanent: false,
        }
    }

    #[test]
    fn copy_a_folder_tree_and_undo_it() {
        let dir = tempfile::tempdir().unwrap();
        let (src, dst) = (dir.path().join("src"), dir.path().join("dst"));
        fs::create_dir_all(src.join("sub")).unwrap();
        fs::write(src.join("a.txt"), "aaa").unwrap();
        fs::write(src.join("sub/b.txt"), "bb").unwrap();
        fs::create_dir(&dst).unwrap();
        let (manager, log) = start(Action::Skip);
        let status = run(&manager, &log, request(JobKind::Copy, &[&src], Some(&dst)));
        assert_eq!(status["errors"].as_array().unwrap().len(), 0);
        assert_eq!(status["doneBytes"], 5);
        assert_eq!(fs::read_to_string(dst.join("src/sub/b.txt")).unwrap(), "bb");
        assert!(matches!(manager.pop_undo(), Some(UndoStep::Created(paths)) if paths == vec![dst.join("src")]));
    }

    #[test]
    fn conflicts_are_asked_and_keep_both_adds_a_number() {
        let dir = tempfile::tempdir().unwrap();
        let (src, dst) = (dir.path().join("src"), dir.path().join("dst"));
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();
        fs::write(src.join("a.txt"), "new").unwrap();
        fs::write(dst.join("a.txt"), "old").unwrap();
        let (manager, log) = start(Action::KeepBoth);
        run(&manager, &log, request(JobKind::Copy, &[&src.join("a.txt")], Some(&dst)));
        assert_eq!(fs::read_to_string(dst.join("a.txt")).unwrap(), "old");
        assert_eq!(fs::read_to_string(dst.join("a (2).txt")).unwrap(), "new");
        assert!(log.lock().unwrap().iter().any(|(name, _)| name == "job-conflict"));

        let (manager, log) = start(Action::Replace);
        run(&manager, &log, request(JobKind::Copy, &[&src.join("a.txt")], Some(&dst)));
        assert_eq!(fs::read_to_string(dst.join("a.txt")).unwrap(), "new");
    }

    #[test]
    fn a_folder_is_not_copied_into_itself() {
        let dir = tempfile::tempdir().unwrap();
        let src = dir.path().join("src");
        fs::create_dir_all(src.join("inner")).unwrap();
        let (manager, log) = start(Action::Skip);
        let status = run(&manager, &log, request(JobKind::Copy, &[&src], Some(&src.join("inner"))));
        assert_eq!(status["errors"].as_array().unwrap().len(), 1);
        assert!(!src.join("inner/src").exists());
    }

    #[test]
    fn duplicate_and_paste_into_the_same_folder_make_copies() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("Report.docx");
        fs::write(&file, "x").unwrap();
        let (manager, log) = start(Action::Skip);
        run(&manager, &log, request(JobKind::Duplicate, &[&file], None));
        run(&manager, &log, request(JobKind::Copy, &[&file], Some(dir.path())));
        assert!(dir.path().join("Report - Copy.docx").exists());
        assert!(dir.path().join("Report - Copy (2).docx").exists());
    }

    #[test]
    fn move_and_undo_the_move() {
        let dir = tempfile::tempdir().unwrap();
        let (src, dst) = (dir.path().join("a.txt"), dir.path().join("dst"));
        fs::write(&src, "x").unwrap();
        fs::create_dir(&dst).unwrap();
        let (manager, log) = start(Action::Skip);
        run(&manager, &log, request(JobKind::Move, &[&src], Some(&dst)));
        assert!(!src.exists());
        assert!(dst.join("a.txt").exists());
        let message = undo(manager.pop_undo().unwrap()).unwrap();
        assert!(message.contains("back"), "{message}");
        assert!(src.exists());
    }

    #[test]
    fn a_transfer_on_the_same_volume_is_a_move() {
        let dir = tempfile::tempdir().unwrap();
        let (src, dst) = (dir.path().join("a.txt"), dir.path().join("dst"));
        fs::write(&src, "x").unwrap();
        fs::create_dir(&dst).unwrap();
        let (manager, log) = start(Action::Skip);
        let status = run(&manager, &log, request(JobKind::Transfer, &[&src], Some(&dst)));
        assert_eq!(status["kind"], "move");
        assert!(!src.exists() && dst.join("a.txt").exists());
    }

    #[test]
    fn rename_undo_refuses_when_the_file_is_gone() {
        let dir = tempfile::tempdir().unwrap();
        let step = UndoStep::Renamed { from: dir.path().join("a"), to: dir.path().join("b") };
        assert!(undo(step).is_err());
    }

    #[test]
    fn a_paused_job_can_be_cancelled_and_leaves_no_partial_files() {
        let dir = tempfile::tempdir().unwrap();
        let (src, dst) = (dir.path().join("src"), dir.path().join("dst"));
        fs::create_dir_all(&src).unwrap();
        fs::create_dir_all(&dst).unwrap();
        for i in 0..50 {
            fs::write(src.join(format!("{i}.bin")), vec![0u8; 10_000]).unwrap();
        }
        let (manager, log) = start(Action::Skip);
        let id = manager.submit(request(JobKind::Copy, &[&src], Some(&dst)));
        manager.pause(id, true);
        let paused = (0..300).any(|_| {
            thread::sleep(Duration::from_millis(10));
            log.lock()
                .unwrap()
                .iter()
                .any(|(name, p)| name == "job-progress" && p["id"] == id && p["state"] == "paused")
        });
        assert!(paused, "the job should report that it is paused");
        manager.cancel(id);
        let cancelled = (0..300).any(|_| {
            thread::sleep(Duration::from_millis(10));
            log.lock()
                .unwrap()
                .iter()
                .any(|(name, p)| name == "job-progress" && p["id"] == id && p["state"] == "cancelled")
        });
        assert!(cancelled);
        let copied = fs::read_dir(dst.join("src")).map(|d| d.count()).unwrap_or(0);
        assert!(copied < 50, "a cancelled copy stops early ({copied} files)");
        let partial = fs::read_dir(dst.join("src"))
            .into_iter()
            .flatten()
            .flatten()
            .any(|e| e.file_name().to_string_lossy().ends_with(".fc-partial"));
        assert!(!partial);
    }

    #[test]
    fn permanent_delete_removes_files_and_folders() {
        let dir = tempfile::tempdir().unwrap();
        let folder = dir.path().join("f");
        fs::create_dir_all(folder.join("x")).unwrap();
        let file = dir.path().join("a.txt");
        fs::write(&file, "x").unwrap();
        let (manager, log) = start(Action::Skip);
        let mut req = request(JobKind::Delete, &[&folder, &file], None);
        req.permanent = true;
        let status = run(&manager, &log, req);
        assert_eq!(status["doneItems"], 2);
        assert!(!folder.exists() && !file.exists());
    }
}
