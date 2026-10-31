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
