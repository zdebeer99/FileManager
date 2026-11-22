//! topics.toml: Topics (REQ-021, spec 6.4.6). A topic is a title, a short
//! description and a list of related folders, like a group of browser tabs.
//! Kept only in the app settings folder, so the folders themselves are never
//! touched (no lock-in). Edits go through toml_edit, keeping comments.

use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};
use toml_edit::{Array, ArrayOfTables, DocumentMut, InlineTable, Item, Table, Value};

use crate::paths::{normalize, write_atomic, AppPaths};

const NEW_FILE: &str = "# File Catalog topics. Safe to edit by hand; changes apply when you save.
# A topic groups related folders, for example everything for one project.
#
# [[topic]]
# title       = \"Acme renewal\"
# description = \"Contract renewal 2026\"
# folders     = ['C:\\Vendors\\Acme', { path = 'C:\\Projects\\Acme renewal', name = \"Project\" }]
# archived    = false

";

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Topic {
    /// Position in the file; used to edit this topic.
    pub index: usize,
    pub title: String,
    pub description: String,
    pub folders: Vec<TopicFolder>,
    pub archived: bool,
}

/// A folder in a topic: its path and, optionally, the name shown for it
/// instead of the folder's own name (REQ-023).
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct TopicFolder {
    pub path: String,
    pub name: String,
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
    /// Changes one folder's path and shown name (REQ-023). An empty name shows the folder's own name.
    UpdateFolder {
        index: usize,
        path: String,
        // `rename_all` on the enum renames only the variants, so the field needs its own.
        #[serde(rename = "newPath")]
        new_path: String,
        name: String,
    },
    /// Drag and drop: put a folder before another folder of the topic, or at the end (REQ-023).
    MoveFolder {
        index: usize,
        path: String,
        before: Option<String>,
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
            .map(|a| {
                a.iter()
                    .filter_map(|f| match f {
                        toml::Value::String(path) => Some((path.as_str(), "")),
                        toml::Value::Table(t) => Some((
                            t.get("path").and_then(|p| p.as_str())?,
                            t.get("name").and_then(|n| n.as_str()).unwrap_or_default(),
                        )),
                        _ => None,
                    })
                    .map(|(path, name)| TopicFolder { path: expand_home(path), name: name.trim().to_string() })
                    .collect()
            })
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
            entry["folders"] = toml_edit::value(folder_array(&unique_folders(Vec::new(), &folders)));
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
            entry["folders"] = toml_edit::value(folder_array(&unique_folders(current, &wanted)));
        }
        Edit::RemoveFolder { index, path } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            let kept: Vec<Folder> = folders_of(entry).into_iter().filter(|f| !f.is(&path)).collect();
            entry["folders"] = toml_edit::value(folder_array(&kept));
        }
        Edit::UpdateFolder { index, path, new_path, name } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            let new_path = new_path.trim();
            if new_path.is_empty() {
                return Err("Enter the folder's path.".into());
            }
            let new_path = normalize(&expand_home(new_path));
            let mut folders = folders_of(entry);
            let at = folders.iter().position(|f| f.is(&path)).ok_or("That folder is no longer in the topic.")?;
            if folders.iter().enumerate().any(|(i, f)| i != at && f.is(&new_path)) {
                return Err("That folder is already in the topic.".into());
            }
            // Keep the user's spelling (for example with `~`) when the path did not change.
            if !folders[at].is(&new_path) {
                folders[at].path = new_path;
            }
            folders[at].name = name.trim().to_string();
            entry["folders"] = toml_edit::value(folder_array(&folders));
        }
        Edit::MoveFolder { index, path, before } => {
            let entry = topic_tables(&mut doc).get_mut(index).ok_or_else(missing)?;
            let mut folders = folders_of(entry);
            let from = folders.iter().position(|f| f.is(&path)).ok_or("That folder is no longer in the topic.")?;
            let moved = folders.remove(from);
            let to = before.and_then(|b| folders.iter().position(|f| f.is(&b))).unwrap_or(folders.len());
            folders.insert(to, moved);
            entry["folders"] = toml_edit::value(folder_array(&folders));
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

/// A folder as written in the file: the path keeps the user's spelling (`~`).
#[derive(Clone, Debug)]
struct Folder {
    path: String,
    name: String,
}

impl Folder {
    fn is(&self, path: &str) -> bool {
        same_path(&normalize(&expand_home(&self.path)), &normalize(&expand_home(path)))
    }
}

/// Paths compare without case on Windows.
fn same_path(a: &str, b: &str) -> bool {
    if cfg!(windows) {
        a.eq_ignore_ascii_case(b) || a.to_lowercase() == b.to_lowercase()
    } else {
        a == b
    }
}

fn folders_of(entry: &Table) -> Vec<Folder> {
    let Some(array) = entry.get("folders").and_then(Item::as_array) else { return Vec::new() };
    array
        .iter()
        .filter_map(|v| match v {
            Value::String(s) => Some(Folder { path: s.value().clone(), name: String::new() }),
            Value::InlineTable(t) => Some(Folder {
                path: t.get("path")?.as_str()?.to_string(),
                name: t.get("name").and_then(Value::as_str).unwrap_or_default().to_string(),
            }),
            _ => None,
        })
        .collect()
}

/// `current` followed by the `added` folders it does not have yet.
fn unique_folders(mut current: Vec<Folder>, added: &[String]) -> Vec<Folder> {
    for folder in added {
        if !current.iter().any(|f| f.is(folder)) {
            current.push(Folder { path: normalize(folder), name: String::new() });
        }
    }
    current
}

/// A folder without a name is written as a plain path; one with a name as
/// `{ path = '…', name = "…" }`.
fn folder_array(folders: &[Folder]) -> Array {
    folders
        .iter()
        .map(|f| -> Value {
            if f.name.is_empty() {
                f.path.as_str().into()
            } else {
                let mut table = InlineTable::new();
                table.insert("path", f.path.as_str().into());
                table.insert("name", f.name.as_str().into());
                table.into()
            }
        })
        .collect()
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
        let paths_of = |t: &Topic| t.folders.iter().map(|f| f.path.clone()).collect::<Vec<_>>();
        assert_eq!(paths_of(&loaded.topics[1]), [normalize(&b), normalize(&a)]);

        apply(&paths, Edit::RemoveFolder { index: 1, path: a.clone() }).unwrap();
        apply(&paths, Edit::Update { index: 0, title: "First".into(), description: "edited".into() }).unwrap();
        apply(&paths, Edit::Archive { index: 0, archived: true }).unwrap();
        apply(&paths, Edit::MoveTo { index: 1, before: Some(0) }).unwrap();
        let loaded = load(&paths);
        let titles: Vec<&str> = loaded.topics.iter().map(|t| t.title.as_str()).collect();
        assert_eq!(titles, ["Two", "First"]);
        assert_eq!(paths_of(&loaded.topics[0]), [normalize(&b)]);
        assert!(loaded.topics[1].archived);
        assert_eq!(loaded.topics[1].description, "edited");

        apply(&paths, Edit::Remove { index: 0 }).unwrap();
        assert_eq!(load(&paths).topics.len(), 1);
        assert!(apply(&paths, Edit::Remove { index: 5 }).is_err());
    }

    #[test]
    fn folders_are_renamed_repointed_and_reordered() {
        let dir = tempfile::tempdir().unwrap();
        let paths = test_paths(dir.path());
        let folder = |name: &str| {
            let p = dir.path().join(name);
            fs::create_dir_all(&p).unwrap();
            normalize(&p.to_string_lossy())
        };
        let (a, b, c, d) = (folder("A"), folder("B"), folder("C"), folder("D"));
        apply(
            &paths,
            Edit::Add { title: "T".into(), description: String::new(), folders: vec![a.clone(), b.clone(), c.clone()] },
        )
        .unwrap();
        let list = |p: &AppPaths| load(p).topics[0].folders.clone();

        // A shown name is written as an inline table and read back.
        apply(
            &paths,
            Edit::UpdateFolder { index: 0, path: b.clone(), new_path: b.clone(), name: " Contracts ".into() },
        )
        .unwrap();
        assert!(fs::read_to_string(paths.topics_file()).unwrap().contains("name = \"Contracts\""));
        assert_eq!(list(&paths)[1], TopicFolder { path: b.clone(), name: "Contracts".into() });

        // A new path keeps the name; a path already in the topic is refused.
        apply(&paths, Edit::UpdateFolder { index: 0, path: b.clone(), new_path: d.clone(), name: "Contracts".into() })
            .unwrap();
        assert_eq!(list(&paths)[1].path, d);
        assert!(apply(
            &paths,
            Edit::UpdateFolder { index: 0, path: d.clone(), new_path: a.clone(), name: String::new() }
        )
        .is_err());

        // Moving before another folder, and to the end.
        apply(&paths, Edit::MoveFolder { index: 0, path: c.clone(), before: Some(a.clone()) }).unwrap();
        let order = |p: &AppPaths| list(p).into_iter().map(|f| f.path).collect::<Vec<_>>();
        assert_eq!(order(&paths), [c.clone(), a.clone(), d.clone()]);
        apply(&paths, Edit::MoveFolder { index: 0, path: c.clone(), before: None }).unwrap();
        assert_eq!(order(&paths), [a.clone(), d.clone(), c.clone()]);

        // Clearing the name writes a plain path again; removing works on named folders.
        apply(&paths, Edit::UpdateFolder { index: 0, path: d.clone(), new_path: d.clone(), name: String::new() })
            .unwrap();
        assert!(!fs::read_to_string(paths.topics_file()).unwrap().contains("name = \"Contracts\""));
        apply(&paths, Edit::RemoveFolder { index: 0, path: d.clone() }).unwrap();
        assert_eq!(order(&paths), [a, c]);
    }

    /// The ops exactly as the UI sends them (REQ-023: `newPath` was not read).
    #[test]
    fn edits_are_read_as_the_ui_sends_them() {
        let read = |json: &str| serde_json::from_str::<Edit>(json).unwrap();
        assert!(matches!(
            read(r#"{"op":"updateFolder","index":0,"path":"/a","newPath":"/b","name":"Label"}"#),
            Edit::UpdateFolder { new_path, name, .. } if new_path == "/b" && name == "Label"
        ));
        assert!(matches!(
            read(r#"{"op":"moveFolder","index":1,"path":"/a","before":null}"#),
            Edit::MoveFolder { index: 1, before: None, .. }
        ));
        assert!(matches!(read(r#"{"op":"addFolders","index":0,"paths":["/a"]}"#), Edit::AddFolders { .. }));
        assert!(matches!(read(r#"{"op":"removeFolder","index":0,"path":"/a"}"#), Edit::RemoveFolder { .. }));
        assert!(matches!(read(r#"{"op":"moveTo","index":0,"before":2}"#), Edit::MoveTo { before: Some(2), .. }));
        assert!(matches!(read(r#"{"op":"archive","index":0,"archived":true}"#), Edit::Archive { archived: true, .. }));
        assert!(matches!(read(r#"{"op":"add","title":"T","description":"","folders":[]}"#), Edit::Add { .. }));
        assert!(matches!(read(r#"{"op":"update","index":0,"title":"T","description":"d"}"#), Edit::Update { .. }));
        assert!(matches!(read(r#"{"op":"remove","index":0}"#), Edit::Remove { index: 0 }));
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
