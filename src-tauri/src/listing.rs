//! Directory listing, the in-memory directory cache, and change patches (spec 4.5, 4.6).

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::path::Path;
use std::sync::{Arc, Mutex};

use serde::Serialize;

use crate::model::{read_item, Item};

/// Items sent to the UI per message while a folder is being read.
const CHUNK: usize = 500;
/// Folders kept in the cache.
const CACHE_FOLDERS: usize = 200;

/// Messages streamed to the UI for one `dir_list` request.
#[derive(Serialize, Clone)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum DirEvent {
    /// The last known listing, shown at once while the folder is read again.
    Cached {
        items: Vec<Item>,
    },
    Chunk {
        items: Vec<Item>,
    },
    /// Differences between the cached listing and the fresh one.
    Patch(Patch),
    Done {
        total: usize,
    },
    Error {
        kind: &'static str,
        message: String,
    },
}

#[derive(Serialize, Clone, Default, Debug)]
pub struct Patch {
    pub added: Vec<Item>,
    pub removed: Vec<String>,
    pub changed: Vec<Item>,
}

impl Patch {
    pub fn is_empty(&self) -> bool {
        self.added.is_empty() && self.removed.is_empty() && self.changed.is_empty()
    }
}

/// Reads a folder, calling `on_chunk` for every `CHUNK` items as they are read.
pub fn read_dir_streaming(dir: &Path, mut on_chunk: impl FnMut(&[Item])) -> io::Result<Vec<Item>> {
    let mut items = Vec::new();
    let mut sent = 0;
    for entry in fs::read_dir(dir)? {
        let Ok(entry) = entry else { continue };
        if let Some(item) = read_item(dir, &entry) {
            items.push(item);
            if items.len() - sent >= CHUNK {
                on_chunk(&items[sent..]);
                sent = items.len();
            }
        }
    }
    if sent < items.len() {
        on_chunk(&items[sent..]);
    }
    Ok(items)
}

pub fn error_kind(error: &io::Error) -> &'static str {
    match error.kind() {
        io::ErrorKind::NotFound => "notFound",
        io::ErrorKind::PermissionDenied => "denied",
        io::ErrorKind::NotADirectory => "notADirectory",
        _ => "unavailable",
    }
}

/// What changed between two listings of the same folder, matched by name.
pub fn diff(old: &[Item], new: &[Item]) -> Patch {
    let old_by_name: HashMap<&str, &Item> = old.iter().map(|item| (item.name.as_str(), item)).collect();
    let new_names: HashSet<&str> = new.iter().map(|item| item.name.as_str()).collect();
    let mut patch = Patch::default();
    for item in new {
        match old_by_name.get(item.name.as_str()) {
            None => patch.added.push(item.clone()),
            Some(previous) if *previous != item => patch.changed.push(item.clone()),
            Some(_) => {}
        }
    }
    patch.removed =
        old.iter().filter(|item| !new_names.contains(item.name.as_str())).map(|item| item.name.clone()).collect();
    patch
}

/// Recently read folders, so going back to a folder shows it instantly.
#[derive(Default)]
pub struct DirCache {
    inner: Mutex<CacheInner>,
}

#[derive(Default)]
struct CacheInner {
    folders: HashMap<String, (Arc<Vec<Item>>, u64)>,
    tick: u64,
}

impl DirCache {
    pub fn get(&self, key: &str) -> Option<Arc<Vec<Item>>> {
        let mut inner = self.inner.lock().unwrap();
        inner.tick += 1;
        let tick = inner.tick;
        inner.folders.get_mut(key).map(|(items, used)| {
            *used = tick;
            items.clone()
        })
    }

    pub fn put(&self, key: String, items: Arc<Vec<Item>>) {
        let mut inner = self.inner.lock().unwrap();
        inner.tick += 1;
        let tick = inner.tick;
        inner.folders.insert(key, (items, tick));
        if inner.folders.len() > CACHE_FOLDERS {
            if let Some(oldest) = inner.folders.iter().min_by_key(|(_, (_, used))| *used).map(|(k, _)| k.clone()) {
                inner.folders.remove(&oldest);
            }
        }
    }

    /// Adds an entry only if the folder is not cached yet (used for the start-up snapshot).
    pub fn put_if_absent(&self, key: String, items: Arc<Vec<Item>>) {
        if self.get(&key).is_none() {
            self.put(key, items);
        }
    }

    pub fn remove(&self, key: &str) {
        self.inner.lock().unwrap().folders.remove(key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Kind, SyncState};

    fn item(name: &str, size: u64) -> Item {
        Item {
            name: name.into(),
            path: format!("/x/{name}"),
            kind: Kind::File,
            is_dir: false,
            size,
            created: None,
            modified: None,
            accessed: None,
            attributes: String::new(),
            ext: String::new(),
            hidden: false,
            readonly: false,
            sync: SyncState::None,
            target: None,
        }
    }

    #[test]
    fn diff_finds_added_removed_and_changed() {
        let old = vec![item("a", 1), item("b", 1), item("c", 1)];
        let new = vec![item("a", 1), item("b", 2), item("d", 1)];
        let patch = diff(&old, &new);
        assert_eq!(patch.added.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["d"]);
        assert_eq!(patch.changed.iter().map(|i| i.name.as_str()).collect::<Vec<_>>(), ["b"]);
        assert_eq!(patch.removed, ["c"]);
    }

    #[test]
    fn streaming_read_returns_all_entries_in_chunks() {
        let dir = tempfile::tempdir().unwrap();
        for i in 0..1203 {
            fs::write(dir.path().join(format!("f{i}.txt")), b"x").unwrap();
        }
        fs::create_dir(dir.path().join("sub")).unwrap();
        let mut chunks = Vec::new();
        let items = read_dir_streaming(dir.path(), |chunk| chunks.push(chunk.len())).unwrap();
        assert_eq!(items.len(), 1204);
        assert_eq!(chunks, [500, 500, 204]);
        let sub = items.iter().find(|i| i.name == "sub").unwrap();
        assert!(sub.is_dir);
        assert_eq!(sub.kind, Kind::Folder);
        let file = items.iter().find(|i| i.name == "f7.txt").unwrap();
        assert_eq!((file.ext.as_str(), file.size), ("txt", 1));
    }

    #[test]
    fn cache_evicts_least_recently_used() {
        let cache = DirCache::default();
        for i in 0..CACHE_FOLDERS {
            cache.put(format!("/d{i}"), Arc::new(vec![]));
        }
        // Touch /d0 so /d1 is now the oldest.
        cache.get("/d0");
        cache.put("/extra".into(), Arc::new(vec![]));
        assert!(cache.get("/d0").is_some());
        assert!(cache.get("/d1").is_none());
    }
}
