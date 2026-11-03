//! Everything that differs between operating systems lives here (spec 2.1).
//! Adding macOS later means adding one more implementation module.

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use self::windows::*;

#[cfg(not(windows))]
mod unix;
#[cfg(not(windows))]
pub use self::unix::*;

#[cfg(not(windows))]
mod freedesktop;
#[cfg(not(windows))]
pub use self::freedesktop::icon;

/// Whether the Sync status column is available (FR-SYNC-04).
pub const SYNC_STATUS_SUPPORTED: bool = cfg!(windows);

pub const PATH_SEPARATOR: &str = if cfg!(windows) { "\\" } else { "/" };

/// A top-level entry of the sidebar Tree (FR-SB-01).
#[derive(serde::Serialize, Clone, Debug)]
pub struct Root {
    pub name: String,
    pub path: String,
    /// "home", "drive", "removable", "network", "cloud" or "folder".
    pub kind: &'static str,
}

/// What a system icon is wanted for (FR-ICON-02).
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum IconTarget {
    /// The icon every folder gets.
    Folder,
    /// The icon for a file type, by lower-case extension ("" for none).
    /// Found without touching any file.
    Extension(String),
    /// A file's own icon (a program, a shortcut). Only asked for where
    /// `PER_FILE_ICONS` is true, and never for slow or online-only files.
    File(std::path::PathBuf),
}

/// An icon image as the operating system gives it.
pub struct Icon {
    pub bytes: Vec<u8>,
    /// "image/png" or "image/svg+xml".
    pub mime: &'static str,
}

/// Whether files such as programs and shortcuts can have their own icon (FR-ICON-02).
pub const PER_FILE_ICONS: bool = cfg!(windows);
