//! Online drives (REQ-028, spec 6.4.7): the Dropbox, OneDrive, Google Drive and
//! Proton Drive folders on this computer, found once at start-up. Their folders
//! run on the slow I/O threads (spec 4.3), the sidebar lists them, and tabs
//! inside them show which drive they are in. Sync itself stays with each
//! provider's own app.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use serde::Serialize;

use crate::paths::normalize;
use crate::platform;

/// One online drive's folder.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct CloudRoot {
    pub name: String,
    pub path: String,
    /// "dropbox", "onedrive", "gdrive" or "proton".
    pub provider: &'static str,
}

/// A folder another part of the app found that may be an online drive.
pub struct Candidate {
    pub path: PathBuf,
    pub provider: &'static str,
    /// The name to show; empty to use the folder's name.
    pub name: String,
}

/// The online drives, found on first use.
pub fn roots() -> &'static [CloudRoot] {
    static ROOTS: OnceLock<Vec<CloudRoot>> = OnceLock::new();
    ROOTS.get_or_init(|| {
        let home = crate::paths::home_dir();
        let mut candidates = platform::cloud_candidates(&home);
        candidates.extend(common_candidates(&home, &dropbox_info_files(&home)));
        let found = resolve(candidates);
        if !found.is_empty() {
            tracing::info!("online drives: {}", found.iter().map(|r| r.path.as_str()).collect::<Vec<_>>().join(", "));
        }
        found
    })
}

/// The online drive a path is in, if any (the deepest match).
pub fn provider_of(path: &Path) -> Option<&'static CloudRoot> {
    let path = normalize(&path.to_string_lossy());
    roots().iter().filter(|root| is_inside(&root.path, &path)).max_by_key(|root| root.path.len())
}

fn is_inside(root: &str, path: &str) -> bool {
    let fold = |s: &str| if cfg!(windows) { s.to_lowercase() } else { s.to_string() };
    let (root, path) = (fold(root), fold(path));
    let sep = std::path::MAIN_SEPARATOR;
    path == root || path.starts_with(&if root.ends_with(sep) { root.clone() } else { format!("{root}{sep}") })
}

/// Keeps the candidates that are folders, once each, in order.
fn resolve(candidates: Vec<Candidate>) -> Vec<CloudRoot> {
    let mut roots: Vec<CloudRoot> = Vec::new();
    for c in candidates {
        if !c.path.is_dir() {
            continue;
        }
        let path = normalize(&c.path.to_string_lossy());
        let key = if cfg!(windows) { path.to_lowercase() } else { path.clone() };
        if roots.iter().any(|r| (if cfg!(windows) { r.path.to_lowercase() } else { r.path.clone() }) == key) {
            continue;
        }
        let name = if c.name.is_empty() {
            c.path
                .file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|| provider_name(c.provider).into())
        } else {
            c.name
        };
        roots.push(CloudRoot { name, path, provider: c.provider });
    }
    roots
}

pub fn provider_name(provider: &str) -> &'static str {
    match provider {
        "dropbox" => "Dropbox",
        "onedrive" => "OneDrive",
        "gdrive" => "Google Drive",
        "proton" => "Proton Drive",
        _ => "Online drive",
    }
}

/// Where Dropbox writes `info.json`, which names its folders.
fn dropbox_info_files(home: &Path) -> Vec<PathBuf> {
    let mut files = vec![home.join(".dropbox").join("info.json")];
    for var in ["APPDATA", "LOCALAPPDATA"] {
        if let Some(dir) = std::env::var_os(var) {
            files.push(PathBuf::from(dir).join("Dropbox").join("info.json"));
        }
    }
    files
}

/// Found the same way everywhere: Dropbox's `info.json`, and the folders the
/// apps create in the home folder by default.
fn common_candidates(home: &Path, dropbox_files: &[PathBuf]) -> Vec<Candidate> {
    let mut found = Vec::new();
    for file in dropbox_files {
        let Ok(text) = fs::read_to_string(file) else { continue };
        let Ok(serde_json::Value::Object(accounts)) = serde_json::from_str::<serde_json::Value>(&text) else {
            continue;
        };
        for account in accounts.values() {
            if let Some(path) = account.get("path").and_then(|p| p.as_str()) {
                found.push(Candidate { path: PathBuf::from(path), provider: "dropbox", name: String::new() });
            }
        }
    }
    for (name, provider) in [
        ("Dropbox", "dropbox"),
        ("OneDrive", "onedrive"),
        ("Google Drive", "gdrive"),
        ("GoogleDrive", "gdrive"),
        ("Proton Drive", "proton"),
        ("ProtonDrive", "proton"),
    ] {
        found.push(Candidate { path: home.join(name), provider, name: String::new() });
    }
    // OneDrive for work or school: "OneDrive - Contoso".
    if let Ok(entries) = fs::read_dir(home) {
        let mut business: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.file_name().is_some_and(|n| n.to_string_lossy().starts_with("OneDrive - ")))
            .collect();
        business.sort();
        found.extend(business.into_iter().map(|path| Candidate { path, provider: "onedrive", name: String::new() }));
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn drives_are_found_from_dropbox_info_and_home_folders() {
        let dir = tempfile::tempdir().unwrap();
        let home = dir.path().join("home");
        for folder in ["Dropbox (Work)", "OneDrive - Contoso", "Proton Drive", "Projects"] {
            fs::create_dir_all(home.join(folder)).unwrap();
        }
        let info = dir.path().join("info.json");
        let work = home.join("Dropbox (Work)");
        fs::write(
            &info,
            format!(r#"{{"business": {{"path": {}, "host": 1}}}}"#, serde_json::to_string(&work).unwrap()),
        )
        .unwrap();

        let roots = resolve(common_candidates(&home, &[info, dir.path().join("missing.json")]));
        let found: Vec<(&str, &str)> = roots.iter().map(|r| (r.name.as_str(), r.provider)).collect();
        assert_eq!(
            found,
            [("Dropbox (Work)", "dropbox"), ("Proton Drive", "proton"), ("OneDrive - Contoso", "onedrive")]
        );
    }

    #[test]
    fn a_path_is_inside_a_root_only_at_a_folder_boundary() {
        let sep = std::path::MAIN_SEPARATOR;
        let root = format!("{sep}home{sep}me{sep}Dropbox");
        assert!(is_inside(&root, &root));
        assert!(is_inside(&root, &format!("{root}{sep}Work")));
        assert!(!is_inside(&root, &format!("{root} (Old){sep}x")));
    }
}
