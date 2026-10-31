//! Saved per-folder views (spec 6.5, 8.4). Stored only in the app settings
//! folder, one file per folder: `folders/<folder name>-<hash>.toml`.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::paths::{normalize, write_atomic, AppPaths};
use crate::settings::SortKey;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct FolderView {
    pub mode: String,
    pub columns: Vec<String>,
    /// Column widths in pixels, by column name.
    pub widths: BTreeMap<String, u32>,
    pub sort: Vec<SortKey>,
    pub folders_first: bool,
    pub show_hidden: bool,
}

impl Default for FolderView {
    fn default() -> Self {
        Self {
            mode: "details".into(),
            columns: Vec::new(),
            widths: BTreeMap::new(),
            sort: Vec::new(),
            folders_first: true,
            show_hidden: false,
        }
    }
}

#[derive(Deserialize, Default)]
#[serde(default, rename_all = "camelCase")]
struct FileContents {
    path: String,
    apply_to_subfolders: bool,
    view: FolderView,
}

/// The view that applies to a folder, and where it came from.
#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Resolved {
    pub view: Option<FolderView>,
    /// The folder whose saved view applies (this folder or a parent).
    pub source: Option<String>,
    pub apply_to_subfolders: bool,
}

pub fn file_for(paths: &AppPaths, folder: &str) -> PathBuf {
    let folder = normalize(folder);
    let key = if cfg!(windows) { folder.to_lowercase() } else { folder.clone() };
    let name: String = Path::new(&folder)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "root".into())
        .chars()
        .map(|c| if c.is_alphanumeric() || " -_.".contains(c) { c } else { '_' })
        .take(40)
        .collect();
    paths.config.join("folders").join(format!("{}-{:08x}.toml", name.trim(), fnv1a(key.as_bytes())))
}

/// Saved view for the folder itself, else the nearest parent saved with
/// "apply to subfolders" (FR-VIEW-04).
pub fn resolve(paths: &AppPaths, folder: &str) -> Resolved {
    let folder = normalize(folder);
    if let Some(contents) = read(paths, &folder) {
        return Resolved {
            view: Some(contents.view),
            source: Some(folder),
            apply_to_subfolders: contents.apply_to_subfolders,
        };
    }
    for ancestor in Path::new(&folder).ancestors().skip(1) {
        let ancestor = normalize(&ancestor.to_string_lossy());
        if ancestor.is_empty() || ancestor == folder {
            continue;
        }
        if let Some(contents) = read(paths, &ancestor).filter(|c| c.apply_to_subfolders) {
            return Resolved { view: Some(contents.view), source: Some(ancestor), apply_to_subfolders: true };
        }
    }
    Resolved { view: None, source: None, apply_to_subfolders: false }
}

fn read(paths: &AppPaths, folder: &str) -> Option<FileContents> {
    let text = fs::read_to_string(file_for(paths, folder)).ok()?;
    let contents: FileContents = toml::from_str(&text).ok()?;
    // Guard against two folders sharing a hash.
    let same = if cfg!(windows) { contents.path.eq_ignore_ascii_case(folder) } else { contents.path == folder };
    same.then_some(contents)
}

/// Saves the view, keeping any comments the user added to the file.
pub fn save(paths: &AppPaths, folder: &str, view: &FolderView, apply_to_subfolders: bool) -> io::Result<()> {
    let folder = normalize(folder);
    let file = file_for(paths, &folder);
    let existing = fs::read_to_string(&file).ok();
    let mut doc = existing.as_deref().and_then(|text| text.parse::<toml_edit::DocumentMut>().ok()).unwrap_or_default();
    doc["path"] = toml_edit::value(folder);
    doc["applyToSubfolders"] = toml_edit::value(apply_to_subfolders);

    let mut table = toml_edit::Table::new();
    table["mode"] = toml_edit::value(view.mode.as_str());
    table["columns"] = toml_edit::value(view.columns.iter().map(String::as_str).collect::<toml_edit::Array>());
    let mut sort = toml_edit::Array::new();
    for key in &view.sort {
        let mut entry = toml_edit::InlineTable::new();
        entry.insert("column", key.column.as_str().into());
        entry.insert("direction", key.direction.as_str().into());
        sort.push(entry);
    }
    table["sort"] = toml_edit::value(sort);
    table["foldersFirst"] = toml_edit::value(view.folders_first);
    table["showHidden"] = toml_edit::value(view.show_hidden);
    let mut widths = toml_edit::InlineTable::new();
    for (column, width) in &view.widths {
        widths.insert(column, i64::from(*width).into());
    }
    table["widths"] = toml_edit::value(widths);
    doc["view"] = toml_edit::Item::Table(table);

    let header = if existing.is_some() { "" } else { NEW_FILE_HEADER };
    write_atomic(&file, format!("{header}{doc}").as_bytes())
}

const NEW_FILE_HEADER: &str =
    "# Saved view for one folder, written by File Catalog.\n# Safe to delete; the folder then uses the default view.\n\n";

pub fn reset(paths: &AppPaths, folder: &str) -> io::Result<()> {
    match fs::remove_file(file_for(paths, folder)) {
        Err(e) if e.kind() != io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

/// 32-bit FNV-1a: small, stable across versions and platforms.
fn fnv1a(bytes: &[u8]) -> u32 {
    bytes.iter().fold(0x811c_9dc5, |hash, byte| (hash ^ u32::from(*byte)).wrapping_mul(0x0100_0193))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_paths(dir: &Path) -> AppPaths {
        AppPaths { config: dir.to_path_buf(), cache: dir.join("cache"), logs: dir.join("logs") }
    }

    fn view(column: &str) -> FolderView {
        FolderView {
            columns: vec!["name".into(), column.into()],
            sort: vec![SortKey { column: column.into(), direction: "desc".into() }],
            ..FolderView::default()
        }
    }

    #[test]
    fn saved_view_is_found_for_the_folder_only() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        save(&paths, "/data/vendors", &view("size"), false).unwrap();
        assert_eq!(resolve(&paths, "/data/vendors").view, Some(view("size")));
        assert_eq!(resolve(&paths, "/data/vendors/acme").view, None);
    }

    #[test]
    fn apply_to_subfolders_is_inherited_by_the_nearest_parent() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        save(&paths, "/data", &view("size"), true).unwrap();
        save(&paths, "/data/vendors", &view("modified"), true).unwrap();
        let resolved = resolve(&paths, "/data/vendors/acme/2026");
        assert_eq!(resolved.view, Some(view("modified")));
        assert_eq!(resolved.source.as_deref(), Some("/data/vendors"));
    }

    #[test]
    fn reset_removes_the_saved_view_and_keeps_user_comments_on_save() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        save(&paths, "/data", &view("size"), false).unwrap();
        let file = file_for(&paths, "/data");
        assert!(fs::read_to_string(&file).unwrap().starts_with("# Saved view"));
        let edited = format!("# my note\n{}", fs::read_to_string(&file).unwrap());
        fs::write(&file, edited).unwrap();
        save(&paths, "/data", &view("modified"), false).unwrap();
        assert!(fs::read_to_string(&file).unwrap().contains("# my note"));
        reset(&paths, "/data").unwrap();
        assert_eq!(resolve(&paths, "/data").view, None);
    }
}
