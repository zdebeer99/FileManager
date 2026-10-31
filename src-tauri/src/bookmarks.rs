//! bookmarks.toml: favourites and bookmarks (spec 6.4, 8.6). Edits go
//! through toml_edit so comments and hand-made formatting are kept.

use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};
use toml_edit::{ArrayOfTables, DocumentMut, Item, Table};

use crate::paths::{normalize, write_atomic, AppPaths};
use crate::platform;

const NEW_FILE: &str = "# File Catalog bookmarks. Safe to edit by hand; changes apply when you save.
#
# [favourites]
# paths = ['C:\\Vendors', '~/Documents']
#
# [[bookmark]]
# name   = \"Acme\"
# target = 'C:\\Vendors\\Acme'      # a folder, a file, or a web address
# group  = [\"bar\"]                 # [\"bar\"] = Bookmark Bar; [\"bar\", \"Legal\"] = a drop-down on the bar

";

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Bookmark {
    /// Position in the file; used to edit or delete this entry.
    pub index: usize,
    pub name: String,
    pub target: String,
    /// "folder", "file" or "url".
    pub kind: &'static str,
    pub group: Vec<String>,
    pub scope: Vec<String>,
    pub exists: bool,
}

#[derive(Serialize, Clone, Debug)]
pub struct Favourite {
    pub path: String,
    pub exists: bool,
}

#[derive(Serialize, Debug, Default)]
pub struct Bookmarks {
    pub favourites: Vec<Favourite>,
    pub bookmarks: Vec<Bookmark>,
    pub warnings: Vec<String>,
}

/// One change requested by the UI.
#[derive(Deserialize, Debug)]
#[serde(tag = "op", rename_all = "camelCase")]
pub enum Edit {
    Add { name: String, target: String, group: Vec<String> },
    Update { index: usize, name: String, target: String, group: Vec<String> },
    Remove { index: usize },
    Move { index: usize, delta: i64 },
    AddFavourite { path: String },
    RemoveFavourite { path: String },
    MoveFavourite { path: String, delta: i64 },
}

pub fn load(paths: &AppPaths) -> Bookmarks {
    let text = match fs::read_to_string(paths.bookmarks_file()) {
        Ok(text) => text,
        Err(_) => return Bookmarks::default(),
    };
    let table = match text.parse::<toml::Table>() {
        Ok(table) => table,
        Err(e) => {
            return Bookmarks {
                warnings: vec![format!("bookmarks.toml has an error, so no bookmarks are shown. {e}")],
                ..Bookmarks::default()
            }
        }
    };
    let mut result = Bookmarks::default();
    let favourites = table.get("favourites").and_then(|f| f.get("paths")).and_then(|p| p.as_array());
    for path in favourites.into_iter().flatten().filter_map(|p| p.as_str()) {
        let path = expand_home(path);
        let exists = platform::is_slow_path(Path::new(&path)) || Path::new(&path).is_dir();
        result.favourites.push(Favourite { path, exists });
    }
    let entries = table.get("bookmark").and_then(|b| b.as_array());
    for (index, entry) in entries.into_iter().flatten().enumerate() {
        let Some(target) = entry.get("target").and_then(|t| t.as_str()) else {
            result.warnings.push(format!("bookmarks.toml: bookmark {} has no target and is skipped.", index + 1));
            continue;
        };
        let target = if target.contains("://") { target.to_string() } else { expand_home(target) };
        let strings = |key: &str| -> Vec<String> {
            entry
                .get(key)
                .and_then(|v| v.as_array())
                .map(|a| a.iter().filter_map(|s| s.as_str().map(String::from)).collect())
                .unwrap_or_default()
        };
        let (kind, exists) = classify(&target);
        let name =
            entry.get("name").and_then(|n| n.as_str()).map(String::from).unwrap_or_else(|| default_name(&target));
        result.bookmarks.push(Bookmark {
            index,
            name,
            target,
            kind,
            group: strings("group"),
            scope: strings("scope"),
            exists,
        });
    }
    result
}

/// Applies one change to bookmarks.toml. A file with syntax errors is never overwritten.
pub fn apply(paths: &AppPaths, edit: Edit) -> Result<(), String> {
    let file = paths.bookmarks_file();
    let (text, is_new) = match fs::read_to_string(&file) {
        Ok(text) => (text, false),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), true),
        Err(e) => return Err(e.to_string()),
    };
    let mut doc = text
        .parse::<DocumentMut>()
        .map_err(|e| format!("bookmarks.toml has an error, so the change was not saved. {e}"))?;

    match edit {
        Edit::Add { name, target, group } => {
            let mut entry = Table::new();
            fill(&mut entry, &name, &target, &group);
            bookmark_tables(&mut doc).push(entry);
        }
        Edit::Update { index, name, target, group } => {
            let entry = bookmark_tables(&mut doc).get_mut(index).ok_or("That bookmark no longer exists.")?;
            fill(entry, &name, &target, &group);
        }
        Edit::Remove { index } => {
            let tables = bookmark_tables(&mut doc);
            if index >= tables.len() {
                return Err("That bookmark no longer exists.".into());
            }
            tables.remove(index);
        }
        Edit::Move { index, delta } => {
            let tables = bookmark_tables(&mut doc);
            let mut all: Vec<Table> = tables.iter().cloned().collect();
            let to = (index as i64 + delta).clamp(0, all.len() as i64 - 1) as usize;
            if index < all.len() && to != index {
                // Tables are written in their document positions, so hand the
                // existing positions out again in the new order.
                let positions: Vec<Option<isize>> = all.iter().map(Table::position).collect();
                let entry = all.remove(index);
                all.insert(to, entry);
                tables.clear();
                for (mut entry, position) in all.into_iter().zip(positions) {
                    entry.set_position(position);
                    tables.push(entry);
                }
            }
        }
        Edit::AddFavourite { path } => {
            let list = favourite_paths(&mut doc);
            if !list.iter().any(|p| p.as_str() == Some(path.as_str())) {
                list.push(path);
            }
        }
        Edit::RemoveFavourite { path } => favourite_paths(&mut doc).retain(|p| p.as_str() != Some(path.as_str())),
        Edit::MoveFavourite { path, delta } => {
            let list = favourite_paths(&mut doc);
            let mut all: Vec<String> = list.iter().filter_map(|p| p.as_str().map(String::from)).collect();
            if let Some(from) = all.iter().position(|p| *p == path) {
                let to = (from as i64 + delta).clamp(0, all.len() as i64 - 1) as usize;
                let entry = all.remove(from);
                all.insert(to, entry);
                list.clear();
                for p in all {
                    list.push(p);
                }
            }
        }
    }

    if !is_new {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    let header = if is_new { NEW_FILE } else { "" };
    write_atomic(&file, format!("{header}{doc}").as_bytes()).map_err(|e| e.to_string())
}

fn bookmark_tables(doc: &mut DocumentMut) -> &mut ArrayOfTables {
    if !doc.get("bookmark").is_some_and(Item::is_array_of_tables) {
        doc["bookmark"] = Item::ArrayOfTables(ArrayOfTables::new());
    }
    doc["bookmark"].as_array_of_tables_mut().expect("just created")
}

fn favourite_paths(doc: &mut DocumentMut) -> &mut toml_edit::Array {
    if !doc.get("favourites").is_some_and(Item::is_table_like) {
        doc["favourites"] = toml_edit::table();
    }
    if !doc["favourites"].get("paths").is_some_and(Item::is_array) {
        doc["favourites"]["paths"] = toml_edit::value(toml_edit::Array::new());
    }
    doc["favourites"]["paths"].as_array_mut().expect("just created")
}

fn fill(entry: &mut Table, name: &str, target: &str, group: &[String]) {
    entry["name"] = toml_edit::value(name);
    entry["target"] = toml_edit::value(target);
    entry["group"] = toml_edit::value(group.iter().map(String::as_str).collect::<toml_edit::Array>());
}

fn classify(target: &str) -> (&'static str, bool) {
    if target.contains("://") {
        return ("url", true);
    }
    let path = Path::new(target);
    if platform::is_slow_path(path) {
        // Don't wait on a network share just to draw a bookmark.
        return (if path.extension().is_some() { "file" } else { "folder" }, true);
    }
    match fs::metadata(path) {
        Ok(meta) if meta.is_dir() => ("folder", true),
        Ok(_) => ("file", true),
        Err(_) => (if path.extension().is_some() { "file" } else { "folder" }, false),
    }
}

fn default_name(target: &str) -> String {
    Path::new(target).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_else(|| target.to_string())
}

fn expand_home(path: &str) -> String {
    normalize(&crate::paths::expand(path, &crate::paths::home_dir()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_paths(dir: &Path) -> AppPaths {
        AppPaths { config: dir.to_path_buf(), cache: dir.join("cache"), logs: dir.join("logs") }
    }

    #[test]
    fn add_update_move_and_remove_bookmarks() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        let folder = dir.path().to_string_lossy().into_owned();
        apply(&paths, Edit::Add { name: "A".into(), target: folder.clone(), group: vec!["bar".into()] }).unwrap();
        apply(&paths, Edit::Add { name: "B".into(), target: "https://example.com".into(), group: vec![] }).unwrap();
        apply(&paths, Edit::Move { index: 1, delta: -1 }).unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.bookmarks.iter().map(|b| b.name.as_str()).collect::<Vec<_>>(), ["B", "A"]);
        assert_eq!((loaded.bookmarks[0].kind, loaded.bookmarks[1].kind), ("url", "folder"));

        apply(
            &paths,
            Edit::Update { index: 1, name: "A2".into(), target: folder, group: vec!["bar".into(), "X".into()] },
        )
        .unwrap();
        apply(&paths, Edit::Remove { index: 0 }).unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.bookmarks.len(), 1);
        assert_eq!(loaded.bookmarks[0].name, "A2");
        assert_eq!(loaded.bookmarks[0].group, ["bar", "X"]);
        assert!(fs::read_to_string(paths.bookmarks_file()).unwrap().starts_with("# File Catalog bookmarks"));
    }

    #[test]
    fn favourites_are_added_once_and_reordered() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        for p in ["/a", "/b", "/a"] {
            apply(&paths, Edit::AddFavourite { path: p.into() }).unwrap();
        }
        apply(&paths, Edit::MoveFavourite { path: "/b".into(), delta: -1 }).unwrap();
        let loaded = load(&paths);
        assert_eq!(loaded.favourites.iter().map(|f| f.path.as_str()).collect::<Vec<_>>(), ["/b", "/a"]);
        apply(&paths, Edit::RemoveFavourite { path: "/b".into() }).unwrap();
        assert_eq!(load(&paths).favourites.len(), 1);
    }

    #[test]
    fn missing_targets_are_reported_and_broken_files_are_not_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        fs::write(paths.bookmarks_file(), "[[bookmark]]\nname = \"no target\"\n").unwrap();
        assert_eq!(load(&paths).warnings.len(), 1);
        fs::write(paths.bookmarks_file(), "[[bookmark]\n").unwrap();
        assert!(apply(&paths, Edit::AddFavourite { path: "/a".into() }).is_err());
        assert_eq!(fs::read_to_string(paths.bookmarks_file()).unwrap(), "[[bookmark]\n");
    }
}
