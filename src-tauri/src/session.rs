//! session.toml (open tabs, recent folders) and the start-up snapshot of
//! those folders' listings in the cache folder (spec 4.5).

use std::collections::HashMap;
use std::fs;
use std::io;

use serde::{Deserialize, Serialize};

use crate::model::Item;
use crate::paths::{write_atomic, AppPaths};

/// Folders larger than this are left out of the snapshot to keep start-up fast.
const SNAPSHOT_MAX_ITEMS: usize = 20_000;

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct Session {
    pub active_tab: usize,
    pub tabs: Vec<String>,
    pub recent: Vec<String>,
    /// Command palette picks, most recent first, for ranking (FR-CMD-03).
    pub palette_history: Vec<String>,
    /// The last Quick Find searches (FR-FIND-06).
    pub find_history: Vec<String>,
    /// Bookmark groups folded in the sidebar, as `bar/Legal` (spec 5.7).
    pub folded_groups: Vec<String>,
}

pub fn load(paths: &AppPaths) -> Session {
    fs::read_to_string(paths.session_file()).ok().and_then(|text| toml::from_str(&text).ok()).unwrap_or_default()
}

pub fn save(paths: &AppPaths, session: &Session) -> io::Result<()> {
    let body = toml::to_string(session).map_err(io::Error::other)?;
    let text = format!("# Written by File Catalog: open tabs, recent folders and searches. Safe to delete.\n\n{body}");
    write_atomic(&paths.session_file(), text.as_bytes())
}

pub fn load_snapshot(paths: &AppPaths) -> HashMap<String, Vec<Item>> {
    fs::read(paths.snapshot_file()).ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or_default()
}

pub fn save_snapshot(paths: &AppPaths, folders: &HashMap<String, std::sync::Arc<Vec<Item>>>) -> io::Result<()> {
    let small: HashMap<&str, &Vec<Item>> = folders
        .iter()
        .filter(|(_, items)| items.len() <= SNAPSHOT_MAX_ITEMS)
        .map(|(path, items)| (path.as_str(), items.as_ref()))
        .collect();
    let bytes = serde_json::to_vec(&small).map_err(io::Error::other)?;
    write_atomic(&paths.snapshot_file(), &bytes)
}
