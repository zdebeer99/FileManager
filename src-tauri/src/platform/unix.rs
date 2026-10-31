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
    let mut roots = vec![
        Root { name: "Home".into(), path: home.to_string_lossy().into_owned(), kind: "home" },
        Root { name: "File System".into(), path: "/".into(), kind: "drive" },
    ];
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
            let kind = if is_slow_path(&path) { "network" } else { "removable" };
            roots.push(Root { name, path: path.to_string_lossy().into_owned(), kind });
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

/// True when the path is on a network or other slow file system, so its
/// I/O runs on the separate slow-path threads (spec 4.3).
pub fn is_slow_path(path: &Path) -> bool {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unescapes_mount_points() {
        assert_eq!(unescape_mount("/mnt/my\\040drive"), "/mnt/my drive");
    }
}
