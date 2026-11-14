//! colours.toml: folder colours (spec 6.4.5). Kept only in the app settings
//! folder, so nothing is written into the user's folders (spec 8.1, no lock-in).
//! Edits go through toml_edit so comments and hand-made formatting are kept.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::PathBuf;

use serde::Serialize;
use toml_edit::{DocumentMut, Item, Table};

use crate::paths::{normalize, write_atomic, AppPaths};

/// The colours a folder can have. The UI maps each name to a colour that
/// suits the current theme.
pub const COLOURS: [&str; 9] = ["red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "grey"];

const NEW_FILE: &str = "# File Catalog folder colours. Safe to edit by hand; changes apply when you save.
# One line per folder. Colours: red, orange, yellow, green, teal, blue, purple, pink, grey.
#
# [folders]
# 'C:\\Vendors' = \"blue\"

";

#[derive(Serialize, Debug, Default, Clone)]
pub struct Colours {
    /// Folder path (normalised) → colour name.
    pub folders: BTreeMap<String, String>,
    pub warnings: Vec<String>,
}

pub fn load(paths: &AppPaths) -> Colours {
    let text = match fs::read_to_string(paths.colours_file()) {
        Ok(text) => text,
        Err(_) => return Colours::default(),
    };
    let table = match text.parse::<toml::Table>() {
        Ok(table) => table,
        Err(e) => {
            return Colours {
                warnings: vec![format!("colours.toml has an error, so no folder colours are shown. {e}")],
                ..Colours::default()
            }
        }
    };
    let mut result = Colours::default();
    let folders = table.get("folders").and_then(|f| f.as_table());
    for (path, colour) in folders.into_iter().flatten() {
        match colour.as_str().map(str::to_lowercase) {
            Some(colour) if COLOURS.contains(&colour.as_str()) => {
                result.folders.insert(normalize(&expand_home(path)), colour);
            }
            _ => result.warnings.push(format!(
                "colours.toml: \"{path}\" has an unknown colour and is skipped. Use one of: {}.",
                COLOURS.join(", ")
            )),
        }
    }
    result
}

/// Sets or clears (`None`) one folder's colour. A file with syntax errors is never overwritten.
pub fn set(paths: &AppPaths, path: &str, colour: Option<&str>) -> Result<(), String> {
    if let Some(colour) = colour {
        if !COLOURS.contains(&colour) {
            return Err(format!("\"{colour}\" is not a folder colour."));
        }
    }
    let file = paths.colours_file();
    let (text, is_new) = match fs::read_to_string(&file) {
        Ok(text) => (text, false),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), true),
        Err(e) => return Err(e.to_string()),
    };
    let mut doc = text
        .parse::<DocumentMut>()
        .map_err(|e| format!("colours.toml has an error, so the change was not saved. {e}"))?;

    if !doc.get("folders").is_some_and(Item::is_table_like) {
        doc["folders"] = Item::Table(Table::new());
    }
    let folders = doc["folders"].as_table_like_mut().expect("just created");
    let key = normalize(path);
    // Remove every spelling of this folder (for example one written with `~`).
    let same: Vec<String> =
        folders.iter().map(|(k, _)| k.to_string()).filter(|k| normalize(&expand_home(k)) == key).collect();
    for k in same {
        folders.remove(&k);
    }
    if let Some(colour) = colour {
        folders.insert(&key, toml_edit::value(colour));
    }

    if !is_new {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    let header = if is_new { NEW_FILE } else { "" };
    write_atomic(&file, format!("{header}{doc}").as_bytes()).map_err(|e| e.to_string())
}

/// Keeps colours with folders that File Catalog renamed or moved (REQ-013):
/// each `(from, to)` pair moves the colour of `from` and of every folder
/// inside it. Does nothing when no coloured folder was involved.
pub fn moved(paths: &AppPaths, pairs: &[(PathBuf, PathBuf)]) -> Result<(), String> {
    let file = paths.colours_file();
    let Ok(text) = fs::read_to_string(&file) else { return Ok(()) };
    let mut doc = text
        .parse::<DocumentMut>()
        .map_err(|e| format!("colours.toml has an error, so folder colours were not moved. {e}"))?;
    let Some(folders) = doc.get_mut("folders").and_then(Item::as_table_like_mut) else { return Ok(()) };
    let sep = std::path::MAIN_SEPARATOR;
    let mut changes: Vec<(String, String, Item)> = Vec::new();
    for (key, value) in folders.iter() {
        let current = normalize(&expand_home(key));
        for (from, to) in pairs {
            let (from, to) = (normalize(&from.to_string_lossy()), normalize(&to.to_string_lossy()));
            let rest = if current == from {
                Some("")
            } else {
                current.strip_prefix(&from).filter(|r| r.starts_with(sep)).or_else(|| {
                    // Windows paths are not case-sensitive.
                    (cfg!(windows) && current.to_lowercase().starts_with(&format!("{}{sep}", from.to_lowercase())))
                        .then(|| &current[from.len()..])
                })
            };
            if let Some(rest) = rest {
                changes.push((key.to_string(), format!("{to}{rest}"), value.clone()));
                break;
            }
        }
    }
    if changes.is_empty() {
        return Ok(());
    }
    for (old, _, _) in &changes {
        folders.remove(old);
    }
    for (_, new, value) in changes {
        folders.insert(&new, value);
    }
    let _ = fs::write(file.with_extension("toml.bak"), &text);
    write_atomic(&file, doc.to_string().as_bytes()).map_err(|e| e.to_string())
}

fn expand_home(path: &str) -> String {
    crate::paths::expand(path, &crate::paths::home_dir())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn test_paths(dir: &Path) -> AppPaths {
        AppPaths { config: dir.to_path_buf(), cache: dir.join("cache"), logs: dir.join("logs") }
    }

    #[test]
    fn set_change_and_clear_a_colour() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        let folder = dir.path().join("Vendors").to_string_lossy().into_owned();

        set(&paths, &folder, Some("blue")).unwrap();
        assert_eq!(load(&paths).folders.get(&normalize(&folder)).map(String::as_str), Some("blue"));
        assert!(fs::read_to_string(paths.colours_file()).unwrap().starts_with("# File Catalog folder colours"));

        set(&paths, &folder, Some("red")).unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.folders.len(), 1);
        assert_eq!(loaded.folders.get(&normalize(&folder)).map(String::as_str), Some("red"));

        set(&paths, &folder, None).unwrap();
        assert!(load(&paths).folders.is_empty());
    }

    #[test]
    fn colours_follow_renamed_and_moved_folders() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        let root = dir.path().to_path_buf();
        let p = |rel: &str| root.join(rel).to_string_lossy().into_owned();
        set(&paths, &p("Vendors"), Some("blue")).unwrap();
        set(&paths, &p("Vendors/Acme"), Some("green")).unwrap();
        set(&paths, &p("VendorsOld"), Some("red")).unwrap();

        // Renaming Vendors moves its colour and its sub-folder's, not VendorsOld's.
        moved(&paths, &[(root.join("Vendors"), root.join("Suppliers"))]).unwrap();
        let loaded = load(&paths);
        let colour = |rel: &str| loaded.folders.get(&normalize(&p(rel))).map(String::as_str);
        assert_eq!(colour("Suppliers"), Some("blue"));
        assert_eq!(colour("Suppliers/Acme"), Some("green"));
        assert_eq!(colour("VendorsOld"), Some("red"));
        assert_eq!(colour("Vendors"), None);

        // Moving (or undoing) back restores the old keys; unrelated moves change nothing.
        moved(&paths, &[(root.join("Suppliers"), root.join("Vendors"))]).unwrap();
        moved(&paths, &[(root.join("Elsewhere"), root.join("Other"))]).unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.folders.get(&normalize(&p("Vendors/Acme"))).map(String::as_str), Some("green"));
        assert_eq!(loaded.folders.len(), 3);
    }

    #[test]
    fn unknown_colours_are_refused_and_reported() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        assert!(set(&paths, "/x", Some("magenta")).is_err());

        fs::write(paths.colours_file(), "# mine\n[folders]\n'/a' = \"Green\"\n'/b' = \"magenta\"\n").unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.folders.get(&normalize("/a")).map(String::as_str), Some("green"));
        assert_eq!(loaded.warnings.len(), 1);
    }

    #[test]
    fn comments_are_kept_and_broken_files_are_not_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        fs::write(paths.colours_file(), "# my colours\n[folders]\n'/a' = \"teal\" # work\n").unwrap();
        set(&paths, "/b", Some("pink")).unwrap();
        let text = fs::read_to_string(paths.colours_file()).unwrap();
        assert!(text.contains("# my colours") && text.contains("# work") && text.contains("pink"));

        fs::write(paths.colours_file(), "[folders\n").unwrap();
        assert!(set(&paths, "/c", Some("red")).is_err());
        assert_eq!(fs::read_to_string(paths.colours_file()).unwrap(), "[folders\n");
        assert_eq!(load(&paths).warnings.len(), 1);
    }
}
