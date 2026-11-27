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

#[cfg(not(windows))]
mod apps;
#[cfg(not(windows))]
pub use self::apps::{choices as open_with_choices, launch as open_with_app};

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
    /// For "cloud": "dropbox", "onedrive", "gdrive" or "proton" (REQ-028).
    #[serde(skip_serializing_if = "str::is_empty")]
    pub provider: &'static str,
}

impl Root {
    pub fn new(name: impl Into<String>, path: impl Into<String>, kind: &'static str) -> Self {
        Root { name: name.into(), path: path.into(), kind, provider: "" }
    }
}

/// The online drives as sidebar roots (REQ-028).
pub fn cloud_roots() -> Vec<Root> {
    crate::cloud::roots()
        .iter()
        .map(|c| Root { name: c.name.clone(), path: c.path.clone(), kind: "cloud", provider: c.provider })
        .collect()
}

/// True for network shares, removable drives and online drives, so their I/O
/// runs on the separate slow-path threads (spec 4.3, REQ-028).
pub fn is_slow_path(path: &std::path::Path) -> bool {
    is_slow_device(path) || crate::cloud::provider_of(path).is_some()
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
    /// A folder's own icon (REQ-025): Downloads, Pictures, a custom icon, an
    /// online drive. Only asked for folders that `may_have_own_icon`.
    Dir(std::path::PathBuf),
}

/// An icon image as the operating system gives it.
pub struct Icon {
    pub bytes: Vec<u8>,
    /// "image/png" or "image/svg+xml".
    pub mime: &'static str,
}

/// Whether files such as programs and shortcuts can have their own icon (FR-ICON-02).
pub const PER_FILE_ICONS: bool = cfg!(windows);

/// An app that can open a file, for Open With on Linux (FR-OPEN-02).
#[derive(serde::Serialize, Clone, Debug, PartialEq)]
pub struct App {
    /// The desktop file id, used to start it.
    pub id: String,
    pub name: String,
    /// The default app for the file type.
    pub default: bool,
}

/// What Open With found (FR-OPEN-02). On Windows the system's own dialog was
/// shown (`shown`); elsewhere the UI shows `apps`, and `others` on request.
#[derive(serde::Serialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct OpenWithChoices {
    pub shown: bool,
    pub apps: Vec<App>,
    pub others: Vec<App>,
}

/// A folder in the file manager's Quick access list (REQ-029).
#[derive(serde::Serialize, Clone, Debug, PartialEq)]
pub struct Place {
    pub name: String,
    pub path: String,
}

/// The computer named by `\\server` or `\\server\` (a network computer on its
/// own, without a share), on Windows (REQ-037).
pub fn server_root(path: &std::path::Path) -> Option<String> {
    if !cfg!(windows) {
        return None;
    }
    let text = path.to_string_lossy().replace('/', "\\");
    let server = text.strip_prefix("\\\\")?.trim_end_matches('\\');
    (!server.is_empty() && !server.contains('\\') && server != "?" && server != ".").then(|| server.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    #[test]
    fn a_server_on_its_own_is_recognised_on_windows() {
        let found = |p: &str| server_root(Path::new(p));
        if cfg!(windows) {
            assert_eq!(found(r"\\nas"), Some("nas".into()));
            assert_eq!(found(r"\\192.168.1.20\"), Some("192.168.1.20".into()));
            assert_eq!(found("//nas/"), Some("nas".into()));
            assert_eq!(found(r"\\nas\photos"), None);
            assert_eq!(found(r"\\?\C:\x"), None);
        } else {
            assert_eq!(found(r"\\nas"), None);
        }
        assert_eq!(found("C:\\"), None);
    }
}
