//! Watches the folders shown in tabs and the settings files, on its own thread.
//! Folder changes are debounced (100 ms) and sent to the UI as patches (spec 4.6).

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{channel, Receiver};
use std::sync::{Arc, Mutex, RwLock};
use std::thread;
use std::time::{Duration, Instant};

use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde::Serialize;
use tauri::{AppHandle, Emitter};

use crate::keybindings;
use crate::listing::{diff, read_dir_streaming, DirCache, Patch};
use crate::paths::AppPaths;
use crate::platform;
use crate::settings::{self, Settings};
use crate::toolbar;

const DEBOUNCE: Duration = Duration::from_millis(100);

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct DirChanged {
    path: String,
    #[serde(flatten)]
    patch: Patch,
    /// The folder itself was deleted or moved away.
    gone: bool,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct SettingsChanged {
    settings: Settings,
    warnings: Vec<String>,
}

pub struct DirWatcher {
    watcher: Mutex<RecommendedWatcher>,
    /// Watched folder -> the key the UI uses for it.
    watched: Arc<Mutex<HashMap<PathBuf, String>>>,
}

type Events = Receiver<notify::Result<notify::Event>>;

impl DirWatcher {
    pub fn start(
        app: AppHandle,
        cache: Arc<DirCache>,
        paths: AppPaths,
        settings: Arc<RwLock<Settings>>,
    ) -> notify::Result<Self> {
        let (tx, rx) = channel();
        let mut watcher = notify::recommended_watcher(tx)?;
        if let Err(e) = watcher.watch(&paths.config, RecursiveMode::NonRecursive) {
            tracing::warn!("cannot watch the settings folder: {e}");
        }
        let watched = Arc::new(Mutex::new(HashMap::new()));
        let loop_watched = watched.clone();
        thread::Builder::new()
            .name("fs-watch".into())
            .spawn(move || event_loop(rx, app, cache, paths, settings, loop_watched))
            .map_err(|e| notify::Error::generic(&e.to_string()))?;
        Ok(Self { watcher: Mutex::new(watcher), watched })
    }

    /// Makes the watched set equal to `folders`. Slow (network) folders are not
    /// watched; they are refreshed when the user navigates or presses F5.
    pub fn set(&self, folders: Vec<String>) {
        let wanted: HashMap<PathBuf, String> = folders
            .into_iter()
            .filter(|f| !platform::is_slow_path(Path::new(f)))
            .map(|f| (PathBuf::from(&f), f))
            .collect();
        let mut watched = self.watched.lock().unwrap();
        let mut watcher = self.watcher.lock().unwrap();
        watched.retain(|path, _| {
            let keep = wanted.contains_key(path);
            if !keep {
                let _ = watcher.unwatch(path);
            }
            keep
        });
        for (path, key) in wanted {
            if !watched.contains_key(&path) && watcher.watch(&path, RecursiveMode::NonRecursive).is_ok() {
                watched.insert(path, key);
            }
        }
    }
}

fn event_loop(
    rx: Events,
    app: AppHandle,
    cache: Arc<DirCache>,
    paths: AppPaths,
    settings: Arc<RwLock<Settings>>,
    watched: Arc<Mutex<HashMap<PathBuf, String>>>,
) {
    let settings_file = paths.settings_file();
    let bookmarks_file = paths.bookmarks_file();
    let keybindings_file = paths.keybindings_file();
    let toolbar_file = paths.toolbar_file();
    while let Ok(first) = rx.recv() {
        let mut dirty: HashSet<PathBuf> = HashSet::new();
        let mut settings_dirty = false;
        let mut bookmarks_dirty = false;
        let mut keybindings_dirty = false;
        let mut toolbar_dirty = false;
        let mut collect = |event: notify::Result<notify::Event>| {
            let Ok(event) = event else { return };
            if matches!(event.kind, EventKind::Access(_)) {
                return;
            }
            let watched = watched.lock().unwrap();
            for path in event.paths {
                if path == settings_file {
                    settings_dirty = true;
                }
                if path == bookmarks_file {
                    bookmarks_dirty = true;
                }
                keybindings_dirty |= path == keybindings_file;
                toolbar_dirty |= path == toolbar_file;
                if watched.contains_key(&path) {
                    dirty.insert(path.clone());
                }
                if let Some(parent) = path.parent().filter(|p| watched.contains_key(*p)) {
                    dirty.insert(parent.to_path_buf());
                }
            }
        };
        collect(first);
        let deadline = Instant::now() + DEBOUNCE;
        while let Ok(event) = rx.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
            collect(event);
        }

        if settings_dirty {
            let (new_settings, warnings) = settings::load(&paths);
            *settings.write().unwrap() = new_settings.clone();
            let _ = app.emit("settings-changed", SettingsChanged { settings: new_settings, warnings });
        }

        if bookmarks_dirty {
            let _ = app.emit("bookmarks-changed", ());
        }

        if keybindings_dirty {
            let _ = app.emit("keybindings-changed", keybindings::load(&keybindings_file));
        }

        if toolbar_dirty {
            let _ = app.emit("toolbar-changed", toolbar::load(&toolbar_file));
        }

        for dir in dirty {
            let Some(key) = watched.lock().unwrap().get(&dir).cloned() else { continue };
            let changed = match read_dir_streaming(&dir, |_| {}) {
                Ok(items) => {
                    let patch = cache
                        .get(&key)
                        .map(|old| diff(&old, &items))
                        .unwrap_or_else(|| Patch { added: items.clone(), ..Patch::default() });
                    cache.put(key.clone(), Arc::new(items));
                    (!patch.is_empty()).then_some(DirChanged { path: key, patch, gone: false })
                }
                Err(_) => {
                    cache.remove(&key);
                    Some(DirChanged { path: key, patch: Patch::default(), gone: true })
                }
            };
            if let Some(changed) = changed {
                let _ = app.emit("dir-changed", changed);
            }
        }
    }
}
