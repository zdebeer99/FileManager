use std::fs::{self, Metadata};
use std::path::{Path, PathBuf};

use super::Root;
use crate::model::SyncState;

/// File systems that can be slow or hang: network shares, FUSE mounts,
/// and WSL's Windows drives (9p / drvfs).
const SLOW_FILE_SYSTEMS: &[&str] = &[
    "nfs",
    "nfs4",
    "cifs",
    "smb3",
    "smbfs",
    "9p",
    "drvfs",
    "davfs",
    "afs",
    "ceph",
    "glusterfs",
    "fuse.sshfs",
    "fuse.rclone",
    "fuse.s3fs",
    "fuse.gvfsd-fuse",
];

pub fn is_hidden(name: &str, _meta: &Metadata) -> bool {
    name.starts_with('.')
}

/// Home, the file system root, and mounted drives (WSL's Windows drives under /mnt).
pub fn roots(home: &Path) -> Vec<Root> {
    let mut roots = vec![Root::new("Home", home.to_string_lossy(), "home")];
    roots.extend(super::cloud_roots());
    roots.push(Root::new("File System", "/", "drive"));
    let user = std::env::var("USER").unwrap_or_default();
    for parent in ["/mnt".to_string(), format!("/media/{user}"), format!("/run/media/{user}")] {
        let Ok(entries) = fs::read_dir(&parent) else { continue };
        let mut found: Vec<PathBuf> = entries.filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_dir()).collect();
        found.sort();
        for path in found {
            let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            if name == "wsl" || name == "wslg" {
                continue;
            }
            let kind = if is_slow_device(&path) { "network" } else { "removable" };
            roots.push(Root::new(name, path.to_string_lossy(), kind));
        }
    }
    roots
}

/// Permissions in `ls` style, e.g. `rwxr-xr-x`.
pub fn attributes(meta: &Metadata) -> String {
    use std::os::unix::fs::PermissionsExt;
    let mode = meta.permissions().mode();
    (0..9).map(|i| if mode & (0o400 >> i) != 0 { ['r', 'w', 'x'][i % 3] } else { '-' }).collect()
}

/// Linux has no standard cloud sync API (FR-SYNC-04).
pub fn sync_state(_meta: &Metadata) -> SyncState {
    SyncState::None
}

/// True when the path is on a network or other slow file system (spec 4.3).
pub fn is_slow_device(path: &Path) -> bool {
    let Ok(mounts) = fs::read_to_string("/proc/self/mounts") else {
        return false;
    };
    let mut best: Option<(usize, String)> = None;
    for line in mounts.lines() {
        let mut fields = line.split_whitespace();
        let (Some(_), Some(mount_point), Some(fs_type)) = (fields.next(), fields.next(), fields.next()) else {
            continue;
        };
        let mount_point = PathBuf::from(unescape_mount(mount_point));
        let depth = mount_point.components().count();
        if path.starts_with(&mount_point) && best.as_ref().is_none_or(|(d, _)| depth > *d) {
            best = Some((depth, fs_type.to_string()));
        }
    }
    best.is_some_and(|(_, fs_type)| SLOW_FILE_SYSTEMS.contains(&fs_type.as_str()))
}

/// /proc/self/mounts writes spaces and tabs as octal escapes (`\040`).
fn unescape_mount(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\\' {
            let code: String = chars.by_ref().take(3).collect();
            match u8::from_str_radix(&code, 8) {
                Ok(byte) => out.push(byte as char),
                Err(_) => {
                    out.push('\\');
                    out.push_str(&code);
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

/// Opens a terminal in `dir`: the configured command, else `$TERMINAL`,
/// else the first common terminal found (FR-OPEN-03).
pub fn open_terminal(dir: &Path, configured: &str) -> Result<(), String> {
    let from_env = std::env::var("TERMINAL").unwrap_or_default();
    let candidates =
        [configured, from_env.as_str(), "x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal", "xterm"];
    for program in candidates.into_iter().filter(|p| !p.is_empty()) {
        if std::process::Command::new(program).current_dir(dir).spawn().is_ok() {
            return Ok(());
        }
    }
    Err("No terminal program was found. Set one with terminal = \"…\" in settings.toml.".into())
}

/// Opens the item's folder in the system file manager.
pub fn reveal(path: &Path) -> Result<(), String> {
    let folder = if path.is_dir() { path } else { path.parent().unwrap_or(path) };
    open::that_detached(folder).map_err(|e| format!("Could not open the file manager: {e}"))
}

/// Linux file managers can't be told about a *cut*; pasting there copies.
pub fn set_clipboard_cut(_cut: bool) {}

/// Unknown on Linux.
pub fn clipboard_cut() -> Option<bool> {
    None
}

/// Linux has no registry of online drives; the common folders are checked in `cloud`.
pub fn cloud_candidates(_home: &Path) -> Vec<crate::cloud::Candidate> {
    Vec::new()
}

/// Whether a folder can have an icon of its own (REQ-025): the XDG special
/// folders (Downloads, Pictures, …), the home folder and online drives.
pub fn may_have_own_icon(path: &Path, _meta: &Metadata) -> bool {
    super::freedesktop::special_folder_icon(path).is_some() || cloud_root(path).is_some()
}

/// The online drive whose root folder `path` is.
pub(super) fn cloud_root(path: &Path) -> Option<&'static crate::cloud::CloudRoot> {
    crate::cloud::provider_of(path).filter(|r| Path::new(&r.path) == path)
}

/// The file manager's places (REQ-029): the standard folders (Desktop,
/// Documents, Downloads, …) and the GTK bookmarks that GNOME Files, Nemo,
/// Caja and Thunar share (`~/.config/gtk-3.0/bookmarks`).
pub fn quick_access(home: &Path) -> Vec<super::Place> {
    let mut places = super::freedesktop::standard_folders(home);
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    for file in [config.join("gtk-3.0/bookmarks"), home.join(".gtk-bookmarks")] {
        if let Ok(text) = fs::read_to_string(file) {
            for place in gtk_bookmarks(&text) {
                if !places.iter().any(|p| p.path == place.path) {
                    places.push(place);
                }
            }
            break;
        }
    }
    places
}

/// `file:///home/me/My%20Work Label` lines; other schemes (sftp://…) are skipped.
fn gtk_bookmarks(text: &str) -> Vec<super::Place> {
    text.lines()
        .filter_map(|line| {
            let (uri, label) = line.split_once(' ').unwrap_or((line, ""));
            let path = percent_decode(uri.strip_prefix("file://")?);
            let name = if label.trim().is_empty() {
                Path::new(&path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| path.clone())
            } else {
                label.trim().to_string()
            };
            Some(super::Place { name, path })
        })
        .collect()
}

fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(byte) = u8::from_str_radix(&text[i + 1..i + 3], 16) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    #[test]
    fn gtk_bookmarks_are_read() {
        let places =
            super::gtk_bookmarks("file:///home/me/My%20Work\nfile:///data/Projects Projects 2026\nsftp://server/x\n");
        let found: Vec<(&str, &str)> = places.iter().map(|p| (p.name.as_str(), p.path.as_str())).collect();
        assert_eq!(found, [("My Work", "/home/me/My Work"), ("Projects 2026", "/data/Projects")]);
    }

    use super::*;

    #[test]
    fn unescapes_mount_points() {
        assert_eq!(unescape_mount("/mnt/my\\040drive"), "/mnt/my drive");
    }
}
