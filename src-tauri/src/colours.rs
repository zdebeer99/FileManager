//! colours.toml: folder colours (spec 6.4.5). Kept only in the app settings
//! folder, so nothing is written into the user's folders (spec 8.1, no lock-in).
//! Edits go through toml_edit so comments and hand-made formatting are kept.

use std::collections::BTreeMap;
use std::fs;
use std::io;

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
