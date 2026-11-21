//! topics.toml: Topics (REQ-021, spec 6.4.6). A topic is a title, a short
//! description and a list of related folders, like a group of browser tabs.
//! Kept only in the app settings folder, so the folders themselves are never
//! touched (no lock-in). Edits go through toml_edit, keeping comments.

use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};
use toml_edit::{Array, ArrayOfTables, DocumentMut, Item, Table};

use crate::paths::{normalize, write_atomic, AppPaths};

const NEW_FILE: &str = "# File Catalog topics. Safe to edit by hand; changes apply when you save.
# A topic groups related folders, for example everything for one project.
#
# [[topic]]
# title       = \"Acme renewal\"
# description = \"Contract renewal 2026\"
# folders     = ['C:\\Vendors\\Acme', 'C:\\Projects\\Acme renewal']
# archived    = false

";

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Topic {
    /// Position in the file; used to edit this topic.
    pub index: usize,
    pub title: String,
    pub description: String,
    pub folders: Vec<String>,
    pub archived: bool,
}

#[derive(Serialize, Debug, Default)]
pub struct Topics {
    pub topics: Vec<Topic>,
    pub warnings: Vec<String>,
}

/// One change requested by the UI.
#[derive(Deserialize, Debug)]
#[serde(tag = "op", rename_all = "camelCase")]
pub enum Edit {
    Add {
        title: String,
        description: String,
        folders: Vec<String>,
    },
    Update {
        index: usize,
        title: String,
        description: String,
    },
    Remove {
        index: usize,
    },
    Archive {
        index: usize,
        archived: bool,
    },
    /// Drag and drop: put a topic before another one, or at the end.
    MoveTo {
        index: usize,
        before: Option<usize>,
    },
    /// Adds folders that are not in the topic yet; files are skipped.
    AddFolders {
        index: usize,
        paths: Vec<String>,
    },
    RemoveFolder {
        index: usize,
        path: String,
    },
}

pub fn load(paths: &AppPaths) -> Topics {
    let text = match fs::read_to_string(paths.topics_file()) {
        Ok(text) => text,
        Err(_) => return Topics::default(),
    };
    let table = match text.parse::<toml::Table>() {
        Ok(table) => table,
        Err(e) => {
            return Topics {
                warnings: vec![format!("topics.toml has an error, so no topics are shown. {e}")],
                ..Topics::default()
            }
        }
    };
    let mut result = Topics::default();
    let entries = table.get("topic").and_then(|t| t.as_array());
    for (index, entry) in entries.into_iter().flatten().enumerate() {
        let text = |key: &str| entry.get(key).and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let title = text("title");
        let folders = entry
            .get("folders")
            .and_then(|v| v.as_array())
            .map(|a| a.iter().filter_map(|p| p.as_str()).map(expand_home).collect())
            .unwrap_or_default();
        result.topics.push(Topic {
            index,
            title: if title.trim().is_empty() { format!("Topic {}", index + 1) } else { title },
            description: text("description"),
            folders,
            archived: entry.get("archived").and_then(|v| v.as_bool()).unwrap_or(false),
        });
    }
    result
}

/// Applies one change to topics.toml. A file with syntax errors is never overwritten.
pub fn apply(paths: &AppPaths, edit: Edit) -> Result<(), String> {
    let file = paths.topics_file();
    let (text, is_new) = match fs::read_to_string(&file) {
        Ok(text) => (text, false),
        Err(e) if e.kind() == io::ErrorKind::NotFound => (String::new(), true),
        Err(e) => return Err(e.to_string()),
    };
    let mut doc = text
        .parse::<DocumentMut>()
        .map_err(|e| format!("topics.toml has an error, so the change was not saved. {e}"))?;
    let missing = || "That topic no longer exists.".to_string();

    match edit {
        Edit::Add { title, description, folders } => {
            let mut entry = Table::new();
            entry["title"] = toml_edit::value(title.trim());
            entry["description"] = toml_edit::value(description.trim());
            entry["folders"] = toml_edit::value(folder_array(&unique_folders(&[], &folders)));
            entry["archived"] = toml_edit::value(false);
            topic_tables(&mut doc).push(entry);
        }
        Edit::Update { index, title, description } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            entry["title"] = toml_edit::value(title.trim());
            entry["description"] = toml_edit::value(description.trim());
        }
        Edit::Remove { index } => {
            let tables = topic_tables(&mut doc);
            if index >= tables.len() {
                return Err(missing());
            }
            tables.remove(index);
        }
        Edit::Archive { index, archived } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            entry["archived"] = toml_edit::value(archived);
        }
        Edit::MoveTo { index, before } => {
            let tables = topic_tables(&mut doc);
            let mut all: Vec<Table> = tables.iter().cloned().collect();
            if index >= all.len() {
                return Err(missing());
            }
            let positions: Vec<Option<isize>> = all.iter().map(Table::position).collect();
            let entry = all.remove(index);
            let to = match before {
                Some(b) if b != index && b <= all.len() => {
                    if b > index {
                        b - 1
                    } else {
                        b
                    }
                }
                _ => all.len(),
            };
            all.insert(to, entry);
            tables.clear();
            for (mut entry, position) in all.into_iter().zip(positions) {
                entry.set_position(position);
                tables.push(entry);
            }
        }
        Edit::AddFolders { index, paths } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            let current = folders_of(entry);
            let wanted: Vec<String> = paths.into_iter().filter(|p| Path::new(p).is_dir()).collect();
            if wanted.is_empty() {
                return Err("Only folders can be added to a topic.".into());
            }
            entry["folders"] = toml_edit::value(folder_array(&unique_folders(&current, &wanted)));
        }
        Edit::RemoveFolder { index, path } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            let key = normalize(&path);
            let kept: Vec<String> =
                folders_of(entry).into_iter().filter(|f| normalize(&expand_home(f)) != key).collect();
            entry["folders"] = toml_edit::value(folder_array(&kept));
        }
    }

    if !is_new {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    let header = if is_new { NEW_FILE } else { "" };
    write_atomic(&file, format!("{header}{doc}").as_bytes()).map_err(|e| e.to_string())
}

fn topic_tables(doc: &mut DocumentMut) -> &mut ArrayOfTables {
    if !doc.get("topic").is_some_and(Item::is_array_of_tables) {
        doc["topic"] = Item::ArrayOfTables(ArrayOfTables::new());
    }
    doc["topic"].as_array_of_tables_mut().expect("just created")
}

fn folders_of(entry: &Table) -> Vec<String> {
    entry
        .get("folders")
        .and_then(Item::as_array)
        .map(|a| a.iter().filter_map(|v| v.as_str().map(String::from)).collect())
        .unwrap_or_default()
}

/// `current` followed by the `added` folders it does not have yet.
fn unique_folders(current: &[String], added: &[String]) -> Vec<String> {
    let mut result: Vec<String> = current.to_vec();
    for folder in added {
        let key = normalize(folder);
        if !result.iter().any(|f| normalize(&expand_home(f)) == key) {
            result.push(key);
        }
    }
    result
}

fn folder_array(folders: &[String]) -> Array {
    folders.iter().map(String::as_str).collect()
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
    fn topics_are_added_edited_archived_reordered_and_removed() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        let a = dir.path().join("A");
        let b = dir.path().join("B");
        fs::create_dir_all(&a).unwrap();
        fs::create_dir_all(&b).unwrap();
        let (a, b) = (a.to_string_lossy().into_owned(), b.to_string_lossy().into_owned());

        apply(&paths, Edit::Add { title: "One".into(), description: "first".into(), folders: vec![a.clone()] })
            .unwrap();
        apply(&paths, Edit::Add { title: "Two".into(), description: String::new(), folders: vec![] }).unwrap();
        assert!(fs::read_to_string(paths.topics_file()).unwrap().starts_with("# File Catalog topics"));

        // Folders: added once, files and missing paths skipped.
        let file = dir.path().join("note.txt");
        fs::write(&file, "x").unwrap();
        apply(&paths, Edit::AddFolders { index: 1, paths: vec![b.clone(), b.clone(), a.clone()] }).unwrap();
        assert!(apply(&paths, Edit::AddFolders { index: 1, paths: vec![file.to_string_lossy().into()] }).is_err());
        let loaded = load(&paths);
        assert_eq!(loaded.topics[1].folders, [normalize(&b), normalize(&a)]);

        apply(&paths, Edit::RemoveFolder { index: 1, path: a.clone() }).unwrap();
        apply(&paths, Edit::Update { index: 0, title: "First".into(), description: "edited".into() }).unwrap();
        apply(&paths, Edit::Archive { index: 0, archived: true }).unwrap();
        apply(&paths, Edit::MoveTo { index: 1, before: Some(0) }).unwrap();
        let loaded = load(&paths);
        let titles: Vec<&str> = loaded.topics.iter().map(|t| t.title.as_str()).collect();
        assert_eq!(titles, ["Two", "First"]);
        assert_eq!(loaded.topics[0].folders, [normalize(&b)]);
        assert!(loaded.topics[1].archived);
        assert_eq!(loaded.topics[1].description, "edited");

        apply(&paths, Edit::Remove { index: 0 }).unwrap();
        assert_eq!(load(&paths).topics.len(), 1);
        assert!(apply(&paths, Edit::Remove { index: 5 }).is_err());
    }

    #[test]
    fn a_broken_file_is_reported_and_never_overwritten() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        fs::write(paths.topics_file(), "[[topic]\n").unwrap();
        assert_eq!(load(&paths).warnings.len(), 1);
        assert!(apply(&paths, Edit::Add { title: "x".into(), description: String::new(), folders: vec![] }).is_err());
        assert_eq!(fs::read_to_string(paths.topics_file()).unwrap(), "[[topic]\n");
    }
}
