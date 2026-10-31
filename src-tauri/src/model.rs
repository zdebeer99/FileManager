//! The item record shared with the UI (spec 4.4).

use std::fs::{self, DirEntry, Metadata};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::platform;

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum Kind {
    Folder,
    File,
    /// `.lnk` on Windows, a symbolic link on Linux.
    Shortcut,
    /// A `.url` Internet Shortcut file.
    Weblink,
}

#[derive(Serialize, Deserialize, Clone, Copy, PartialEq, Eq, Debug)]
#[serde(rename_all = "camelCase")]
pub enum SyncState {
    None,
    Local,
    Pinned,
    OnlineOnly,
    Syncing,
    Error,
}

#[derive(Serialize, Deserialize, Clone, PartialEq, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Item {
    pub name: String,
    pub path: String,
    pub kind: Kind,
    /// True when opening the item navigates into it (a folder, or a link to one).
    pub is_dir: bool,
    pub size: u64,
    /// Milliseconds since 1970-01-01 UTC.
    pub created: Option<i64>,
    pub modified: Option<i64>,
    pub accessed: Option<i64>,
    /// `RHSA…` letters on Windows, `rwxr-xr-x` on Linux.
    pub attributes: String,
    /// Lower-case extension without the dot; empty for folders.
    pub ext: String,
    pub hidden: bool,
    pub readonly: bool,
    pub sync: SyncState,
    pub target: Option<String>,
}

/// Reads one directory entry. Returns `None` if the entry vanished meanwhile.
pub fn read_item(dir: &Path, entry: &DirEntry) -> Option<Item> {
    let name = entry.file_name().to_string_lossy().into_owned();
    let link_meta = entry.metadata().ok()?;
    Some(build(name, dir.join(entry.file_name()), &link_meta))
}

fn build(name: String, path: PathBuf, link_meta: &Metadata) -> Item {
    let is_symlink = link_meta.file_type().is_symlink();
    let followed = if is_symlink { fs::metadata(&path).ok() } else { None };
    let meta = followed.as_ref().unwrap_or(link_meta);
    let is_dir = meta.is_dir();

    let ext = if is_dir && !is_symlink {
        String::new()
    } else {
        Path::new(&name).extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
    };

    let kind = if is_symlink {
        Kind::Shortcut
    } else if is_dir {
        Kind::Folder
    } else if cfg!(windows) && ext == "lnk" {
        Kind::Shortcut
    } else if ext == "url" {
        Kind::Weblink
    } else {
        Kind::File
    };

    let target = if is_symlink { fs::read_link(&path).ok().map(|t| t.to_string_lossy().into_owned()) } else { None };

    Item {
        hidden: platform::is_hidden(&name, link_meta),
        sync: platform::sync_state(link_meta),
        name,
        path: path.to_string_lossy().into_owned(),
        kind,
        is_dir,
        size: if is_dir { 0 } else { meta.len() },
        created: meta.created().ok().map(to_millis),
        modified: meta.modified().ok().map(to_millis),
        accessed: meta.accessed().ok().map(to_millis),
        attributes: platform::attributes(meta),
        ext,
        readonly: meta.permissions().readonly(),
        target,
    }
}

fn to_millis(time: SystemTime) -> i64 {
    match time.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_millis() as i64,
        Err(e) => -(e.duration().as_millis() as i64),
    }
}
