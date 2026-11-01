//! File operations used by jobs and commands (spec 6.7, 6.12). Everything
//! here is blocking and runs on the I/O pools or the job thread.

use std::fs::{self, File, FileTimes};
use std::io;
use std::path::{Path, PathBuf};

/// Characters that can't be used in a name on this platform (FR-REN-02).
const INVALID_CHARS: &[char] = if cfg!(windows) { &['<', '>', ':', '"', '/', '\\', '|', '?', '*'] } else { &['/'] };

const WINDOWS_RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2",
    "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Checks a new file or folder name. The UI runs the same checks as you
/// type; this is the final word (FR-REN-02).
pub fn validate_name(name: &str) -> Result<(), String> {
    if name.trim().is_empty() {
        return Err("Enter a name.".into());
    }
    if name == "." || name == ".." {
        return Err("This name is reserved.".into());
    }
    if let Some(c) = name.chars().find(|c| INVALID_CHARS.contains(c) || c.is_control()) {
        return Err(format!("A name can't contain \"{c}\"."));
    }
    if name.len() > 255 {
        return Err("The name is too long.".into());
    }
    if cfg!(windows) {
        let stem = name.split('.').next().unwrap_or_default().trim_end().to_ascii_uppercase();
        if WINDOWS_RESERVED.contains(&stem.as_str()) {
            return Err(format!("\"{stem}\" is reserved by Windows."));
        }
        if name.ends_with('.') || name.ends_with(' ') {
            return Err("A name can't end with a dot or a space on Windows.".into());
        }
    }
    Ok(())
}

/// How a free name is made when the first choice is taken.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Naming {
    /// `Report (2).docx` (Keep both, new folders).
    Numbered,
    /// `Report - Copy.docx`, then `Report - Copy (2).docx` (Duplicate, FR-DUP-01).
    Copy,
}

/// The first name in `dir` that is not taken, starting from `name`.
pub fn free_name(dir: &Path, name: &str, naming: Naming) -> PathBuf {
    let (stem, ext) = split_name(name);
    let candidate = |n: u32| -> String {
        let base = match (naming, n) {
            (Naming::Numbered, 1) => stem.to_string(),
            (Naming::Numbered, n) => format!("{stem} ({n})"),
            (Naming::Copy, 1) => format!("{stem} - Copy"),
            (Naming::Copy, n) => format!("{stem} - Copy ({n})"),
        };
        format!("{base}{ext}")
    };
    let first = if naming == Naming::Copy { 1 } else { 2 };
    if naming == Naming::Numbered && !exists(&dir.join(name)) {
        return dir.join(name);
    }
    (first..).map(|n| dir.join(candidate(n))).find(|p| !exists(p)).expect("an unbounded range always finds a free name")
}

/// `("Report", ".docx")`; folders and dot-files keep their whole name as the stem.
fn split_name(name: &str) -> (&str, &str) {
    match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    }
}

fn exists(path: &Path) -> bool {
    path.symlink_metadata().is_ok()
}

/// Creates `New folder` (or `New folder (2)` …) and returns its path (FR-NEW-01).
pub fn create_folder(parent: &Path, name: &str) -> io::Result<PathBuf> {
    let path = free_name(parent, name, Naming::Numbered);
    fs::create_dir(&path)?;
    Ok(path)
}

/// Creates an empty file; fails if the name is taken (FR-NEW-02).
pub fn create_file(parent: &Path, name: &str) -> Result<PathBuf, String> {
    validate_name(name)?;
    let path = parent.join(name);
    File::create_new(&path).map_err(|e| describe(&e, &path))?;
    Ok(path)
}

/// Creates a `.url` Internet Shortcut, readable on every platform (FR-NEW-04).
pub fn create_weblink(parent: &Path, name: &str, url: &str) -> Result<PathBuf, String> {
    let file_name = if name.to_lowercase().ends_with(".url") { name.to_string() } else { format!("{name}.url") };
    validate_name(&file_name)?;
    let path = parent.join(&file_name);
    if exists(&path) {
        return Err(format!("\"{file_name}\" already exists."));
    }
    fs::write(&path, format!("[InternetShortcut]\r\nURL={url}\r\n")).map_err(|e| describe(&e, &path))?;
    Ok(path)
}

/// Creates a shortcut: a `.lnk` on Windows, a symbolic link on Linux (FR-NEW-03).
pub fn create_shortcut(parent: &Path, name: &str, target: &Path) -> Result<PathBuf, String> {
    validate_name(name)?;
    if !exists(target) {
        return Err(format!("Can't find \"{}\".", target.display()));
    }
    #[cfg(windows)]
    {
        let file_name = if name.to_lowercase().ends_with(".lnk") { name.to_string() } else { format!("{name}.lnk") };
        let path = parent.join(&file_name);
        if exists(&path) {
            return Err(format!("\"{file_name}\" already exists."));
        }
        let link = mslnk::ShellLink::new(target).map_err(|e| e.to_string())?;
        link.create_lnk(&path).map_err(|e| e.to_string())?;
        Ok(path)
    }
    #[cfg(not(windows))]
    {
        let path = parent.join(name);
        std::os::unix::fs::symlink(target, &path).map_err(|e| describe(&e, &path))?;
        Ok(path)
    }
}

/// Renames in place and returns the new path. A change of case only is allowed.
pub fn rename(path: &Path, new_name: &str) -> Result<PathBuf, String> {
    validate_name(new_name)?;
    let parent = path.parent().ok_or("This item can't be renamed.")?;
    let target = parent.join(new_name);
    let same_item = path.file_name().is_some_and(|old| old.to_string_lossy().eq_ignore_ascii_case(new_name));
    if exists(&target) && !same_item {
        return Err(format!("\"{new_name}\" already exists."));
    }
    fs::rename(path, &target).map_err(|e| describe(&e, path))?;
    Ok(target)
}

/// Copies one file through a temporary name, then renames it into place, so
/// a failed or cancelled copy never leaves a half-written file (FR-COPY-03).
/// `fs::copy` uses CopyFileEx on Windows and copy_file_range on Linux (FR-COPY-02).
pub fn copy_file(source: &Path, target: &Path) -> io::Result<u64> {
    let name = target.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let partial = target.with_file_name(format!(".{name}.fc-partial"));
    let result = fs::copy(source, &partial).and_then(|bytes| {
        let meta = fs::metadata(source)?;
        let mut times = FileTimes::new();
        if let Ok(modified) = meta.modified() {
            times = times.set_modified(modified);
        }
        if let Ok(accessed) = meta.accessed() {
            times = times.set_accessed(accessed);
        }
        File::options().write(true).open(&partial)?.set_times(times)?;
        fs::rename(&partial, target)?;
        Ok(bytes)
    });
    if result.is_err() {
        let _ = fs::remove_file(&partial);
    }
    result
}

/// True when `inner` is `outer` or inside it (FR-COPY-05).
pub fn is_inside(inner: &Path, outer: &Path) -> bool {
    match (dunce_canonical(inner), dunce_canonical(outer)) {
        (Some(inner), Some(outer)) => inner.starts_with(outer),
        _ => inner.starts_with(outer),
    }
}

fn dunce_canonical(path: &Path) -> Option<PathBuf> {
    // The target folder of a copy may not exist yet; check its nearest existing parent.
    path.ancestors()
        .find_map(|p| fs::canonicalize(p).ok().map(|c| c.join(path.strip_prefix(p).unwrap_or(Path::new("")))))
}

/// True when two paths are on different volumes, so a move must copy.
pub fn is_cross_device(error: &io::Error) -> bool {
    matches!(error.kind(), io::ErrorKind::CrossesDevices)
        || error.raw_os_error() == Some(if cfg!(windows) { 17 } else { 18 })
}

/// Total size and number of items under the given paths, for progress.
pub fn measure(paths: &[PathBuf]) -> (u64, u64) {
    let mut bytes = 0;
    let mut items = 0;
    let mut stack: Vec<PathBuf> = paths.to_vec();
    while let Some(path) = stack.pop() {
        let Ok(meta) = path.symlink_metadata() else { continue };
        items += 1;
        if meta.is_dir() {
            if let Ok(entries) = fs::read_dir(&path) {
                stack.extend(entries.filter_map(Result::ok).map(|e| e.path()));
            }
        } else {
            bytes += meta.len();
        }
    }
    (bytes, items)
}

/// Deletes a file or a whole folder for good.
pub fn remove_permanently(path: &Path) -> io::Result<()> {
    let meta = path.symlink_metadata()?;
    if meta.is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
}

/// True when moving between the two paths is a rename, not a copy (FR-COPY-06).
pub fn same_volume(a: &Path, b: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        match (a.symlink_metadata(), b.metadata()) {
            (Ok(x), Ok(y)) => x.dev() == y.dev(),
            _ => false,
        }
    }
    #[cfg(not(unix))]
    {
        let root = |p: &Path| p.components().next().map(|c| c.as_os_str().to_string_lossy().to_lowercase());
        root(a).is_some() && root(a) == root(b)
    }
}

/// Makes a shortcut to `target` in `parent` with a free name, like Explorer's
/// *Paste shortcut*: `Report.docx - Shortcut.lnk` on Windows, `Report.docx`
/// (or `Report (2).docx`) as a symbolic link on Linux.
pub fn create_shortcut_auto(parent: &Path, target: &Path) -> Result<PathBuf, String> {
    let name =
        target.file_name().map(|n| n.to_string_lossy().into_owned()).ok_or("This item can't have a shortcut.")?;
    if cfg!(windows) {
        let free = free_name(parent, &format!("{name} - Shortcut.lnk"), Naming::Numbered);
        let stem = free.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        create_shortcut(parent, stem.trim_end_matches(".lnk"), target)
    } else {
        let free = free_name(parent, &name, Naming::Numbered);
        let free_name = free.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        create_shortcut(parent, &free_name, target)
    }
}

/// A short, readable explanation of a file system error (spec 9).
pub fn describe(error: &io::Error, path: &Path) -> String {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.display().to_string());
    match error.kind() {
        io::ErrorKind::NotFound => format!("\"{name}\" no longer exists."),
        io::ErrorKind::PermissionDenied => format!("Access to \"{name}\" was denied."),
        io::ErrorKind::AlreadyExists => format!("\"{name}\" already exists."),
        io::ErrorKind::StorageFull => "There is not enough free space.".into(),
        _ => format!("\"{name}\": {error}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_are_checked() {
        assert!(validate_name("Report 2026.docx").is_ok());
        assert!(validate_name("").is_err());
        assert!(validate_name("  ").is_err());
        assert!(validate_name("a/b").is_err());
        assert!(validate_name("..").is_err());
        if cfg!(windows) {
            assert!(validate_name("CON.txt").is_err());
            assert!(validate_name("what?").is_err());
        }
    }

    #[test]
    fn free_names_follow_explorer() {
        let dir = tempfile::tempdir().unwrap();
        let d = dir.path();
        assert_eq!(free_name(d, "Report.docx", Naming::Numbered), d.join("Report.docx"));
        fs::write(d.join("Report.docx"), "").unwrap();
        assert_eq!(free_name(d, "Report.docx", Naming::Numbered), d.join("Report (2).docx"));
        assert_eq!(free_name(d, "Report.docx", Naming::Copy), d.join("Report - Copy.docx"));
        fs::write(d.join("Report - Copy.docx"), "").unwrap();
        assert_eq!(free_name(d, "Report.docx", Naming::Copy), d.join("Report - Copy (2).docx"));
        assert_eq!(free_name(d, ".bashrc", Naming::Copy), d.join(".bashrc - Copy"));
    }

    #[test]
    fn copy_keeps_the_modified_time_and_leaves_no_partial_file() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("a.txt");
        fs::write(&source, "hello").unwrap();
        let old = std::time::SystemTime::UNIX_EPOCH + std::time::Duration::from_secs(1_700_000_000);
        File::options().write(true).open(&source).unwrap().set_modified(old).unwrap();
        let target = dir.path().join("b.txt");
        assert_eq!(copy_file(&source, &target).unwrap(), 5);
        assert_eq!(fs::read_to_string(&target).unwrap(), "hello");
        assert_eq!(fs::metadata(&target).unwrap().modified().unwrap(), old);
        assert!(!dir.path().join(".b.txt.fc-partial").exists());
    }

    #[test]
    fn create_and_rename() {
        let dir = tempfile::tempdir().unwrap();
        let d = dir.path();
        assert_eq!(create_folder(d, "New folder").unwrap(), d.join("New folder"));
        assert_eq!(create_folder(d, "New folder").unwrap(), d.join("New folder (2)"));
        let file = create_file(d, "notes.txt").unwrap();
        assert!(create_file(d, "notes.txt").is_err());
        assert!(rename(&file, "New folder").is_err(), "the name is taken");
        let renamed = rename(&file, "Notes.txt").unwrap();
        assert!(renamed.exists());
        let link = create_weblink(d, "Example", "https://example.com").unwrap();
        assert!(fs::read_to_string(link).unwrap().contains("URL=https://example.com"));
    }

    #[test]
    fn shortcuts_get_free_names() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("Report.docx");
        fs::write(&target, "x").unwrap();
        let links = dir.path().join("links");
        fs::create_dir(&links).unwrap();
        let first = create_shortcut_auto(&links, &target).unwrap();
        let second = create_shortcut_auto(&links, &target).unwrap();
        assert_ne!(first, second);
        if cfg!(unix) {
            assert_eq!(fs::read_link(&first).unwrap(), target);
            assert_eq!(second, links.join("Report (2).docx"));
        }
        assert!(same_volume(&target, &links));
    }

    #[test]
    fn inside_check() {
        let dir = tempfile::tempdir().unwrap();
        let outer = dir.path().join("a");
        fs::create_dir_all(outer.join("b")).unwrap();
        assert!(is_inside(&outer.join("b"), &outer));
        assert!(is_inside(&outer, &outer));
        assert!(!is_inside(dir.path(), &outer));
        assert!(is_inside(&outer.join("b/new"), &outer), "a target that doesn't exist yet");
    }
}
