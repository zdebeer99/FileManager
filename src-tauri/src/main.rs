// Hide the console window in Windows release builds.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod bookmarks;
mod commands;
mod folder_view;
mod listing;
mod model;
mod paths;
mod platform;
mod pools;
mod session;
mod settings;
mod watcher;

use std::sync::OnceLock;
use std::time::Instant;

use tauri::Manager;

/// When the process started; used to measure start-up time (NFR-PERF-01).
pub static STARTED: OnceLock<Instant> = OnceLock::new();

fn main() {
    STARTED.get_or_init(Instant::now);

    let app_paths = paths::AppPaths::detect();
    let _log_guard = init_logging(&app_paths);
    tracing::info!(version = env!("CARGO_PKG_VERSION"), "File Catalog starting");

    tauri::Builder::default()
        .manage(commands::AppState::new(app_paths))
        .invoke_handler(tauri::generate_handler![
            commands::app_init,
            commands::dir_list,
            commands::watch_set,
            commands::resolve_path,
            commands::list_subfolders,
            commands::open_item,
            commands::free_space,
            commands::session_save,
            commands::perf_mark,
            commands::settings_set,
            commands::folder_view_get,
            commands::folder_view_save,
            commands::folder_view_reset,
            commands::folder_view_file,
            commands::bookmarks_get,
            commands::bookmarks_edit,
            commands::app_exit,
        ])
        .build(tauri::generate_context!())
        .expect("failed to build the File Catalog window")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                app.state::<commands::AppState>().write_snapshot();
            }
        });
}

/// Daily log files in `<settings folder>/logs`, kept for 7 days (NFR-MNT-03).
fn init_logging(app_paths: &paths::AppPaths) -> Option<tracing_appender::non_blocking::WorkerGuard> {
    use tracing_appender::rolling::{RollingFileAppender, Rotation};

    std::fs::create_dir_all(&app_paths.logs).ok()?;
    let appender = RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix("filecatalog")
        .filename_suffix("log")
        .max_log_files(7)
        .build(&app_paths.logs)
        .ok()?;
    let (writer, guard) = tracing_appender::non_blocking(appender);
    tracing_subscriber::fmt().with_writer(writer).with_ansi(false).with_max_level(tracing::Level::INFO).init();
    Some(guard)
}
