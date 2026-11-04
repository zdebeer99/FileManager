//! The IPC commands the Elm UI calls (spec 4.4). Every command is async, so
//! it runs on a Tokio worker; file system work goes to the I/O pools.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;

use serde::Serialize;
use tauri::ipc::Channel;
use tauri::{AppHandle, State};

use crate::bookmarks::{self, Bookmarks};
use crate::colours::{self, Colours};
use crate::editor;
use crate::fileops;
use crate::find::{self, FindEvent};
use crate::folder_view::{self, FolderView};
use crate::icons;
use crate::jobs::{self, Action, JobManager, JobRequest, UndoStep};
use crate::keybindings::{self, KeyBindings};
use crate::listing::{diff, error_kind, read_dir_streaming, DirCache, DirEvent};
use crate::paths::{self, AppPaths};
use crate::platform;
use crate::pools::IoPools;
use crate::session::{self, Session};
use crate::settings::{self, Settings};
use crate::templates;
use crate::toolbar::{self, Toolbar};
use crate::watcher::DirWatcher;

pub struct AppState {
    paths: AppPaths,
    pools: Arc<IoPools>,
    cache: Arc<DirCache>,
    settings: Arc<RwLock<Settings>>,
    session: Mutex<Session>,
    watcher: Mutex<Option<DirWatcher>>,
    jobs: Mutex<Option<Arc<JobManager>>>,
    /// Kept open: on Linux, clipboard text lives only as long as its owner.
    clipboard: Mutex<Option<arboard::Clipboard>>,
    /// Running Quick Find searches by id, with their cancel flags.
    searches: Arc<Mutex<HashMap<u64, Arc<AtomicBool>>>>,
    /// System icons already looked up (FR-ICON-02).
    icons: Arc<icons::IconCache>,
}

impl AppState {
    pub fn new(paths: AppPaths) -> Self {
        Self {
            paths,
            pools: Arc::new(IoPools::new()),
            cache: Arc::new(DirCache::default()),
            settings: Arc::new(RwLock::new(Settings::default())),
            session: Mutex::new(Session::default()),
            watcher: Mutex::new(None),
            jobs: Mutex::new(None),
            clipboard: Mutex::new(None),
            searches: Arc::default(),
            icons: Arc::default(),
        }
    }

    fn timeout(&self) -> Duration {
        Duration::from_secs(self.settings.read().unwrap().network.timeout_seconds.max(1))
    }

    /// Saves the listings of the open tabs so the next start can show them at once.
    pub fn write_snapshot(&self) {
        let tabs = self.session.lock().unwrap().tabs.clone();
        let folders = tabs.into_iter().filter_map(|tab| self.cache.get(&tab).map(|items| (tab, items))).collect();
        if let Err(e) = session::save_snapshot(&self.paths, &folders) {
            tracing::warn!("could not save the start-up snapshot: {e}");
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct InitData {
    settings: Settings,
    warnings: Vec<String>,
    session: Session,
    home: String,
    sep: &'static str,
    sync_status: bool,
    /// Whether programs and shortcuts can show their own icon (FR-ICON-02).
    per_file_icons: bool,
    roots: Vec<platform::Root>,
    settings_file: String,
    bookmarks_file: String,
    keybindings: KeyBindings,
    toolbar: Toolbar,
    version: &'static str,
}

/// First call from the UI: settings, last session, and platform facts.
#[tauri::command]
pub async fn app_init(app: AppHandle, state: State<'_, AppState>) -> Result<InitData, String> {
    let elapsed = crate::STARTED.get().map_or(0, |start| start.elapsed().as_millis() as u64);
    tracing::info!(label = "app-init-called", elapsed_ms = elapsed, "perf");
    let paths = state.paths.clone();
    let cache = state.cache.clone();
    let config = paths.config.clone();
    let (loaded, warnings, last_session, key_bindings, tool_bar) = state
        .pools
        .run(&config, Duration::from_secs(10), move || {
            let (loaded, warnings) = settings::load(&paths);
            let last_session = session::load(&paths);
            for (folder, items) in session::load_snapshot(&paths) {
                cache.put_if_absent(folder, Arc::new(items));
            }
            (
                loaded,
                warnings,
                last_session,
                keybindings::load(&paths.keybindings_file()),
                toolbar::load(&paths.toolbar_file()),
            )
        })
        .await?;
    let roots_home = paths::home_dir();
    let roots = state.pools.run(&roots_home.clone(), state.timeout(), move || platform::roots(&roots_home)).await?;

    *state.settings.write().unwrap() = loaded.clone();
    *state.session.lock().unwrap() = last_session.clone();

    let home = if loaded.general.home_folder.trim().is_empty() || loaded.general.home_folder == "~" {
        paths::home_dir()
    } else {
        PathBuf::from(paths::expand(&loaded.general.home_folder, &paths::home_dir()))
    };

    if state.jobs.lock().unwrap().is_none() {
        *state.jobs.lock().unwrap() = Some(JobManager::start(app.clone()));
    }

    match DirWatcher::start(app, state.cache.clone(), state.paths.clone(), state.settings.clone()) {
        Ok(watcher) => *state.watcher.lock().unwrap() = Some(watcher),
        Err(e) => tracing::warn!("folder watching is not available: {e}"),
    }

    for warning in &warnings {
        tracing::warn!("{warning}");
    }

    Ok(InitData {
        settings: loaded,
        warnings,
        session: last_session,
        home: paths::normalize(&home.to_string_lossy()),
        sep: platform::PATH_SEPARATOR,
        sync_status: platform::SYNC_STATUS_SUPPORTED,
        per_file_icons: platform::PER_FILE_ICONS,
        roots,
        settings_file: state.paths.settings_file().to_string_lossy().into_owned(),
        bookmarks_file: state.paths.bookmarks_file().to_string_lossy().into_owned(),
        keybindings: key_bindings,
        toolbar: tool_bar,
        version: env!("CARGO_PKG_VERSION"),
    })
}

/// Lists a folder, streaming the result: the cached listing first (if any),
/// then either chunks (first read) or a patch (cached folder), then `done`.
#[tauri::command]
pub async fn dir_list(state: State<'_, AppState>, path: String, on_event: Channel<DirEvent>) -> Result<(), String> {
    let key = paths::normalize(&path);
    let cache = state.cache.clone();
    let cached = cache.get(&key);
    if let Some(items) = &cached {
        let _ = on_event.send(DirEvent::Cached { items: items.to_vec() });
    }

    let cancelled = Arc::new(AtomicBool::new(false));
    let (first_tx, first_rx) = tokio::sync::oneshot::channel::<()>();
    let channel = on_event.clone();
    let worker_cancelled = cancelled.clone();
    let dir = PathBuf::from(&key);

    state.pools.spawn(&dir.clone(), move || {
        let mut first = Some(first_tx);
        let stream_chunks = cached.is_none();
        let result = read_dir_streaming(&dir, |chunk| {
            if let Some(tx) = first.take() {
                let _ = tx.send(());
            }
            if stream_chunks && !worker_cancelled.load(Ordering::Relaxed) {
                let _ = channel.send(DirEvent::Chunk { items: chunk.to_vec() });
            }
        });
        if let Some(tx) = first.take() {
            let _ = tx.send(());
        }
        if worker_cancelled.load(Ordering::Relaxed) {
            return;
        }
        match result {
            Ok(items) => {
                if let Some(old) = &cached {
                    let patch = diff(old, &items);
                    if !patch.is_empty() {
                        let _ = channel.send(DirEvent::Patch(patch));
                    }
                }
                let total = items.len();
                cache.put(key, Arc::new(items));
                let _ = channel.send(DirEvent::Done { total });
            }
            Err(e) => {
                cache.remove(&key);
                let _ = channel.send(DirEvent::Error { kind: error_kind(&e), message: e.to_string() });
            }
        }
    });

    // A folder that has not answered within the timeout is shown as unavailable.
    let timeout = state.timeout();
    tauri::async_runtime::spawn(async move {
        if tokio::time::timeout(timeout, first_rx).await.is_err() {
            cancelled.store(true, Ordering::Relaxed);
            let _ = on_event
                .send(DirEvent::Error { kind: "unavailable", message: "The location did not respond in time.".into() });
        }
    });
    Ok(())
}

/// Sets which folders are watched for changes: the folders open in tabs.
#[tauri::command]
pub async fn watch_set(state: State<'_, AppState>, paths: Vec<String>) -> Result<(), String> {
    if let Some(watcher) = state.watcher.lock().unwrap().as_ref() {
        watcher.set(paths.iter().map(|p| paths::normalize(p)).collect());
    }
    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Resolved {
    dir: String,
    /// Set when the input was a file: select it in its folder.
    select: Option<String>,
}

/// Turns what the user typed in the Address Bar into a folder (FR-ADDR-03).
#[tauri::command]
pub async fn resolve_path(state: State<'_, AppState>, input: String, base: String) -> Result<Resolved, String> {
    let expanded = PathBuf::from(paths::expand(&input, &paths::home_dir()));
    let full = paths::clean(&if expanded.is_relative() { Path::new(&base).join(expanded) } else { expanded });
    let probe = full.clone();
    state
        .pools
        .run(&full, state.timeout(), move || {
            if probe.is_dir() {
                Ok(Resolved { dir: paths::normalize(&probe.to_string_lossy()), select: None })
            } else if probe.exists() {
                let dir = probe.parent().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default();
                let select = probe.file_name().map(|n| n.to_string_lossy().into_owned());
                Ok(Resolved { dir: paths::normalize(&dir), select })
            } else {
                Err(format!("Can't find \"{}\".", input.trim()))
            }
        })
        .await?
}

#[derive(Serialize)]
pub struct Subfolder {
    name: String,
    path: String,
}

/// Sub-folders of a folder, for the breadcrumb drop-downs and Tab completion.
#[tauri::command]
pub async fn list_subfolders(
    state: State<'_, AppState>,
    path: String,
    show_hidden: bool,
) -> Result<Vec<Subfolder>, String> {
    let dir = PathBuf::from(paths::normalize(&path));
    let probe = dir.clone();
    state
        .pools
        .run(&dir, state.timeout(), move || {
            let entries = std::fs::read_dir(&probe).map_err(|e| e.to_string())?;
            let mut folders: Vec<Subfolder> = entries
                .filter_map(Result::ok)
                .filter(|entry| entry.path().is_dir())
                .filter_map(|entry| {
                    let name = entry.file_name().to_string_lossy().into_owned();
                    let meta = entry.metadata().ok()?;
                    (show_hidden || !platform::is_hidden(&name, &meta))
                        .then(|| Subfolder { path: entry.path().to_string_lossy().into_owned(), name })
                })
                .take(1000)
                .collect();
            folders.sort_by_key(|f| f.name.to_lowercase());
            Ok(folders)
        })
        .await?
}

/// Opens a file with its default app, or a link with its target (FR-OPEN-01).
#[tauri::command]
pub async fn open_item(state: State<'_, AppState>, path: String) -> Result<(), String> {
    let target = PathBuf::from(&path);
    state
        .pools
        .run(&target.clone(), state.timeout(), move || {
            open::that_detached(&target).map_err(|e| format!("Could not open \"{path}\": {e}"))
        })
        .await?
}

/// Free space on the volume that holds `path`, in bytes.
#[tauri::command]
pub async fn free_space(state: State<'_, AppState>, path: String) -> Result<Option<u64>, String> {
    let dir = PathBuf::from(&path);
    state.pools.run(&dir.clone(), state.timeout(), move || fs4::available_space(&dir).ok()).await
}

#[tauri::command]
pub async fn session_save(state: State<'_, AppState>, session: Session) -> Result<(), String> {
    *state.session.lock().unwrap() = session.clone();
    let paths = state.paths.clone();
    let config = paths.config.clone();
    state
        .pools
        .run(&config, Duration::from_secs(10), move || session::save(&paths, &session).map_err(|e| e.to_string()))
        .await?
}

/// Logs how long after process start a UI milestone was reached (NFR-PERF-01).
#[tauri::command]
pub async fn perf_mark(label: String) -> Result<u64, String> {
    let elapsed = crate::STARTED.get().map_or(0, |start| start.elapsed().as_millis() as u64);
    tracing::info!(label = %label, elapsed_ms = elapsed, "perf");
    Ok(elapsed)
}

/// Changes one value in settings.toml, keeping the user's comments (FR-UI-01).
/// The watcher then reloads the file and tells the UI.
#[tauri::command]
pub async fn settings_set(state: State<'_, AppState>, key: String, value: serde_json::Value) -> Result<(), String> {
    let file = state.paths.settings_file();
    state.pools.run(&file.clone(), Duration::from_secs(10), move || settings::set_value(&file, &key, &value)).await?
}

/// The saved view that applies to a folder (FR-VIEW-04).
#[tauri::command]
pub async fn folder_view_get(state: State<'_, AppState>, path: String) -> Result<folder_view::Resolved, String> {
    let paths = state.paths.clone();
    state.pools.run(&paths.config.clone(), Duration::from_secs(10), move || folder_view::resolve(&paths, &path)).await
}

#[tauri::command]
pub async fn folder_view_save(
    state: State<'_, AppState>,
    path: String,
    view: FolderView,
    apply_to_subfolders: bool,
) -> Result<(), String> {
    let paths = state.paths.clone();
    state
        .pools
        .run(&paths.config.clone(), Duration::from_secs(10), move || {
            folder_view::save(&paths, &path, &view, apply_to_subfolders).map_err(|e| e.to_string())
        })
        .await?
}

#[tauri::command]
pub async fn folder_view_reset(state: State<'_, AppState>, path: String) -> Result<(), String> {
    let paths = state.paths.clone();
    state
        .pools
        .run(&paths.config.clone(), Duration::from_secs(10), move || {
            folder_view::reset(&paths, &path).map_err(|e| e.to_string())
        })
        .await?
}

/// Where a folder's saved view is (or would be) stored.
#[tauri::command]
pub async fn folder_view_file(state: State<'_, AppState>, path: String) -> Result<String, String> {
    Ok(folder_view::file_for(&state.paths, &path).to_string_lossy().into_owned())
}

#[tauri::command]
pub async fn bookmarks_get(state: State<'_, AppState>) -> Result<Bookmarks, String> {
    let paths = state.paths.clone();
    state.pools.run(&paths.config.clone(), state.timeout(), move || bookmarks::load(&paths)).await
}

#[tauri::command]
pub async fn bookmarks_edit(state: State<'_, AppState>, edit: bookmarks::Edit) -> Result<(), String> {
    let paths = state.paths.clone();
    state.pools.run(&paths.config.clone(), Duration::from_secs(10), move || bookmarks::apply(&paths, edit)).await?
}

/// System icons for folders, file types and single files, as `data:` URLs;
/// `null` where there is none (FR-ICON-02).
#[tauri::command]
pub async fn icons_get(
    state: State<'_, AppState>,
    keys: Vec<String>,
) -> Result<HashMap<String, Option<String>>, String> {
    let paths = state.paths.clone();
    let cache = state.icons.clone();
    state.pools.run(&paths.cache.clone(), Duration::from_secs(30), move || icons::get(&cache, &paths, keys)).await
}

/// Folder colours (spec 6.4.5).
#[tauri::command]
pub async fn colours_get(state: State<'_, AppState>) -> Result<Colours, String> {
    let paths = state.paths.clone();
    state.pools.run(&paths.config.clone(), state.timeout(), move || colours::load(&paths)).await
}

/// Sets a folder's colour, or clears it when `colour` is null (spec 6.4.5).
#[tauri::command]
pub async fn colours_set(state: State<'_, AppState>, path: String, colour: Option<String>) -> Result<(), String> {
    let paths = state.paths.clone();
    state
        .pools
        .run(&paths.config.clone(), Duration::from_secs(10), move || colours::set(&paths, &path, colour.as_deref()))
        .await?
}

#[tauri::command]
pub async fn app_exit(app: AppHandle) -> Result<(), String> {
    app.exit(0);
    Ok(())
}

impl AppState {
    fn jobs(&self) -> Result<Arc<JobManager>, String> {
        self.jobs.lock().unwrap().clone().ok_or_else(|| "File operations are not ready yet.".into())
    }
}

/// Starts a copy, move, duplicate or delete job and returns its id (FR-OP-02).
#[tauri::command]
pub async fn job_start(state: State<'_, AppState>, request: JobRequest) -> Result<u64, String> {
    if request.sources.is_empty() {
        return Err("Nothing is selected.".into());
    }
    Ok(state.jobs()?.submit(request))
}

#[tauri::command]
pub async fn job_cancel(state: State<'_, AppState>, job_id: u64) -> Result<(), String> {
    state.jobs()?.cancel(job_id);
    Ok(())
}

#[tauri::command]
pub async fn job_pause(state: State<'_, AppState>, job_id: u64, paused: bool) -> Result<(), String> {
    state.jobs()?.pause(job_id, paused);
    Ok(())
}

/// The answer to a name conflict (FR-COPY-04).
#[tauri::command]
pub async fn job_resolve(
    state: State<'_, AppState>,
    job_id: u64,
    action: Action,
    apply_to_all: bool,
) -> Result<(), String> {
    state.jobs()?.resolve(job_id, action, apply_to_all);
    Ok(())
}

/// Renames in place and returns the new path (FR-REN-01, FR-REN-02).
#[tauri::command]
pub async fn fs_rename(state: State<'_, AppState>, path: String, new_name: String) -> Result<String, String> {
    let jobs = state.jobs()?;
    let from = PathBuf::from(&path);
    let renamed = state.pools.run(&from.clone(), state.timeout(), move || fileops::rename(&from, &new_name)).await??;
    jobs.push_undo(UndoStep::Renamed { from: PathBuf::from(path), to: renamed.clone() });
    Ok(renamed.to_string_lossy().into_owned())
}

/// What to create in `fs_create`.
#[derive(serde::Deserialize, Debug)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum NewItem {
    Folder,
    File { name: String },
    Shortcut { name: String, target: String },
    WebLink { name: String, url: String },
}

/// Creates a folder, file, shortcut or web link and returns its path (spec 6.7).
#[tauri::command]
pub async fn fs_create(state: State<'_, AppState>, parent: String, item: NewItem) -> Result<String, String> {
    let jobs = state.jobs()?;
    let dir = PathBuf::from(&parent);
    let created = state
        .pools
        .run(&dir.clone(), state.timeout(), move || match item {
            NewItem::Folder => fileops::create_folder(&dir, "New folder").map_err(|e| fileops::describe(&e, &dir)),
            NewItem::File { name } => fileops::create_file(&dir, &name),
            NewItem::Shortcut { name, target } => fileops::create_shortcut(&dir, &name, Path::new(&target)),
            NewItem::WebLink { name, url } => fileops::create_weblink(&dir, &name, &url),
        })
        .await??;
    jobs.push_undo(UndoStep::Created(vec![created.clone()]));
    Ok(created.to_string_lossy().into_owned())
}

/// Takes back the last operation of this session (FR-UNDO-01).
#[tauri::command]
pub async fn undo_last(state: State<'_, AppState>) -> Result<String, String> {
    let step = state.jobs()?.pop_undo().ok_or("There is nothing to undo.")?;
    let home = paths::home_dir();
    state.pools.run(&home, Duration::from_secs(60), move || jobs::undo(step)).await?
}

/// Puts text on the OS clipboard (Copy Path, FR-OPEN-04).
#[tauri::command]
pub async fn clipboard_write_text(state: State<'_, AppState>, text: String) -> Result<(), String> {
    let mut clipboard = state.clipboard.lock().unwrap();
    if clipboard.is_none() {
        *clipboard = Some(arboard::Clipboard::new().map_err(|e| format!("The clipboard is not available: {e}"))?);
    }
    clipboard.as_mut().expect("just set").set_text(text).map_err(|e| format!("Could not copy to the clipboard: {e}"))
}

/// Opens a terminal in the folder (FR-OPEN-03).
#[tauri::command]
pub async fn open_terminal(state: State<'_, AppState>, path: String) -> Result<(), String> {
    let configured = state.settings.read().unwrap().general.terminal.clone();
    platform::open_terminal(Path::new(&path), configured.trim())
}

/// The text editor that "Open with …" uses; an empty name when none was found (FR-OPEN-06).
#[tauri::command]
pub async fn editor_info(state: State<'_, AppState>) -> Result<editor::EditorInfo, String> {
    let settings = state.settings.read().unwrap().editor.clone();
    let paths = state.paths.clone();
    state.pools.run(&paths.config, Duration::from_secs(10), move || editor::info(&settings)).await
}

/// Opens files or folders in the text editor (FR-OPEN-06).
#[tauri::command]
pub async fn open_in_editor(state: State<'_, AppState>, paths: Vec<String>) -> Result<(), String> {
    let settings = state.settings.read().unwrap().editor.clone();
    let config = state.paths.config.clone();
    state.pools.run(&config, Duration::from_secs(10), move || editor::open(&settings, &paths)).await?
}

/// Shows the item in the system file manager.
#[tauri::command]
pub async fn reveal_item(path: String) -> Result<(), String> {
    platform::reveal(Path::new(&path))
}

/// The templates and the folder new templates are saved to (FR-TPL-01, FR-TPL-02).
#[tauri::command]
pub async fn templates_list(state: State<'_, AppState>) -> Result<templates::Templates, String> {
    let folders = templates::folders(&state.paths, &state.settings.read().unwrap().templates.folders);
    let first = folders[0].clone();
    state.pools.run(&first, state.timeout(), move || templates::list(&folders)).await
}

/// Makes sure the first templates folder exists and returns it (Tools › Edit Templates Folder).
#[tauri::command]
pub async fn templates_folder(state: State<'_, AppState>) -> Result<String, String> {
    let folder = templates::folders(&state.paths, &state.settings.read().unwrap().templates.folders).remove(0);
    let created = folder.clone();
    state
        .pools
        .run(&folder, state.timeout(), move || std::fs::create_dir_all(&created).map_err(|e| e.to_string()))
        .await??;
    Ok(folder.to_string_lossy().into_owned())
}

/// Creates an item from a template. `today` is [year, month, day] in the user's time zone (FR-TPL-03, FR-TPL-04).
#[tauri::command]
pub async fn fs_create_from_template(
    state: State<'_, AppState>,
    parent: String,
    template: String,
    name: String,
    today: (i32, u32, u32),
) -> Result<String, String> {
    let jobs = state.jobs()?;
    let date_format = state.settings.read().unwrap().templates.date_format.clone();
    let dir = PathBuf::from(&parent);
    let created = state
        .pools
        .run(&dir.clone(), Duration::from_secs(60), move || {
            let values = templates::Values::new(&name, &dir, today, &date_format);
            templates::create(Path::new(&template), &dir, &values)
        })
        .await??;
    jobs.push_undo(UndoStep::Created(vec![created.clone()]));
    Ok(created.to_string_lossy().into_owned())
}

/// Creates shortcuts to `targets` in `parent` (Paste as Shortcut, Alt+drag).
#[tauri::command]
pub async fn fs_create_shortcuts(
    state: State<'_, AppState>,
    parent: String,
    targets: Vec<String>,
) -> Result<Vec<String>, String> {
    let jobs = state.jobs()?;
    let dir = PathBuf::from(&parent);
    let created = state
        .pools
        .run(&dir.clone(), state.timeout(), move || {
            targets.iter().map(|t| fileops::create_shortcut_auto(&dir, Path::new(t))).collect::<Result<Vec<_>, _>>()
        })
        .await??;
    jobs.push_undo(UndoStep::Created(created.clone()));
    Ok(created.iter().map(|p| p.to_string_lossy().into_owned()).collect())
}

/// Files on the system clipboard, shared with Explorer and other file managers (FR-OP-01).
#[derive(Serialize)]
pub struct ClipboardFiles {
    paths: Vec<String>,
    /// Set by another app's *Cut* (Windows only); None when unknown.
    cut: Option<bool>,
}

#[tauri::command]
pub async fn clipboard_set_files(state: State<'_, AppState>, paths: Vec<String>, cut: bool) -> Result<(), String> {
    let mut clipboard = state.clipboard.lock().unwrap();
    if clipboard.is_none() {
        *clipboard = Some(arboard::Clipboard::new().map_err(|e| format!("The clipboard is not available: {e}"))?);
    }
    clipboard
        .as_mut()
        .expect("just set")
        .set()
        .file_list(&paths)
        .map_err(|e| format!("Could not copy to the clipboard: {e}"))?;
    platform::set_clipboard_cut(cut);
    Ok(())
}

#[tauri::command]
pub async fn clipboard_get_files(state: State<'_, AppState>) -> Result<ClipboardFiles, String> {
    let mut clipboard = state.clipboard.lock().unwrap();
    if clipboard.is_none() {
        *clipboard = Some(arboard::Clipboard::new().map_err(|e| format!("The clipboard is not available: {e}"))?);
    }
    let paths = clipboard.as_mut().expect("just set").get().file_list().unwrap_or_default();
    Ok(ClipboardFiles {
        paths: paths.iter().map(|p| p.to_string_lossy().into_owned()).collect(),
        cut: platform::clipboard_cut(),
    })
}

/// Starts a native drag of the files out of the window, to Explorer, the
/// desktop or another app (FR-CC-08).
#[tauri::command]
pub async fn drag_out(window: tauri::WebviewWindow, paths: Vec<String>) -> Result<(), String> {
    let files: Vec<PathBuf> = paths.iter().map(PathBuf::from).collect();
    let target = window.clone();
    window
        .run_on_main_thread(move || {
            let item = drag::DragItem::Files(files);
            let image = drag::Image::Raw(include_bytes!("../icons/32x32.png").to_vec());
            #[cfg(target_os = "linux")]
            let handle = target.gtk_window();
            #[cfg(target_os = "linux")]
            let result = handle.map_err(|e| e.to_string()).and_then(|w| {
                drag::start_drag(&w, item, image, |_, _| {}, drag::Options::default()).map_err(|e| e.to_string())
            });
            #[cfg(not(target_os = "linux"))]
            let result =
                drag::start_drag(&target, item, image, |_, _| {}, drag::Options::default()).map_err(|e| e.to_string());
            if let Err(e) = result {
                tracing::warn!("drag out failed: {e}");
            }
        })
        .map_err(|e| e.to_string())
}

/// Starts Quick Find in `root` (spec 6.6). Results stream to `on_event`;
/// a query with a mistake is refused with a message.
#[tauri::command]
pub async fn find_start(
    state: State<'_, AppState>,
    search_id: u64,
    root: String,
    query: String,
    clock: find::Clock,
    on_event: Channel<FindEvent>,
) -> Result<(), String> {
    let parsed = find::Query::parse(&query, clock)?;
    if parsed.is_empty() {
        return Err("Type what to look for.".into());
    }
    let cancelled = Arc::new(AtomicBool::new(false));
    state.searches.lock().unwrap().insert(search_id, cancelled.clone());
    let search = find::Search {
        root: PathBuf::from(paths::normalize(&root)),
        query: parsed,
        options: state.settings.read().unwrap().search.clone(),
        cancelled,
    };
    let searches = state.searches.clone();
    // The walk starts its own threads on all cores (FR-FIND-05); this thread only waits for it.
    std::thread::Builder::new()
        .name("find".into())
        .spawn(move || {
            find::run(search, move |event| {
                let _ = on_event.send(event);
            });
            searches.lock().unwrap().remove(&search_id);
        })
        .map_err(|e| format!("Could not start the search: {e}"))?;
    Ok(())
}

/// Stops a running search (`Esc`, FR-FIND-03). Results found so far stay.
#[tauri::command]
pub async fn find_cancel(state: State<'_, AppState>, search_id: u64) -> Result<(), String> {
    if let Some(flag) = state.searches.lock().unwrap().get(&search_id) {
        flag.store(true, Ordering::Relaxed);
    }
    Ok(())
}

#[tauri::command]
pub async fn keybindings_get(state: State<'_, AppState>) -> Result<KeyBindings, String> {
    let file = state.paths.keybindings_file();
    state.pools.run(&file.clone(), Duration::from_secs(10), move || keybindings::load(&file)).await
}

/// One command's new keys, from Help › Keyboard Shortcuts.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyChange {
    command: String,
    when: String,
    keys: Vec<String>,
    remove_defaults: bool,
}

/// Sets the keys of one or more commands in keybindings.toml, in order
/// (FR-KEY-04). The watcher then reloads the file and tells the UI.
#[tauri::command]
pub async fn keybindings_set(state: State<'_, AppState>, changes: Vec<KeyChange>) -> Result<KeyBindings, String> {
    let file = state.paths.keybindings_file();
    state
        .pools
        .run(&file.clone(), Duration::from_secs(10), move || {
            for c in &changes {
                keybindings::set(&file, &c.command, &c.when, &c.keys, c.remove_defaults)?;
            }
            Ok(keybindings::load(&file))
        })
        .await?
}

/// The key bindings file, created with an explanatory header if needed.
#[tauri::command]
pub async fn keybindings_file(state: State<'_, AppState>) -> Result<String, String> {
    let file = state.paths.keybindings_file();
    state
        .pools
        .run(&file.clone(), Duration::from_secs(10), move || {
            keybindings::ensure_file(&file).map_err(|e| e.to_string())?;
            Ok(file.to_string_lossy().into_owned())
        })
        .await?
}

#[tauri::command]
pub async fn toolbar_get(state: State<'_, AppState>) -> Result<Toolbar, String> {
    let file = state.paths.toolbar_file();
    state.pools.run(&file.clone(), Duration::from_secs(10), move || toolbar::load(&file)).await
}

/// Writes the toolbar chosen in *Customise Toolbar* (FR-TB-02).
#[tauri::command]
pub async fn toolbar_save(state: State<'_, AppState>, style: String, items: Vec<String>) -> Result<Toolbar, String> {
    let file = state.paths.toolbar_file();
    state
        .pools
        .run(&file.clone(), Duration::from_secs(10), move || {
            toolbar::save(&file, &style, &items)?;
            Ok(toolbar::load(&file))
        })
        .await?
}

/// The toolbar file, created with the current toolbar if needed.
#[tauri::command]
pub async fn toolbar_file(state: State<'_, AppState>) -> Result<String, String> {
    let file = state.paths.toolbar_file();
    state
        .pools
        .run(&file.clone(), Duration::from_secs(10), move || {
            toolbar::ensure_file(&file)?;
            Ok(file.to_string_lossy().into_owned())
        })
        .await?
}

/// The closest folder that still exists on the way up from `path`; where
/// *Locate…* searches for a bookmark whose target was moved (FR-BM-03).
#[tauri::command]
pub async fn nearest_folder(state: State<'_, AppState>, path: String) -> Result<String, String> {
    let start = PathBuf::from(&path);
    state
        .pools
        .run(&start.clone(), state.timeout(), move || {
            start
                .ancestors()
                .skip(1)
                .find(|dir| dir.is_dir())
                .map(|dir| paths::normalize(&dir.to_string_lossy()))
                .ok_or_else(|| "None of the folders above it exist.".to_string())
        })
        .await?
}
