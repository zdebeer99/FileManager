//! System icons for the file list (FR-ICON-02). The UI asks for icons by key:
//!
//! - `folder`: the folder icon,
//! - `ext:<extension>`: a file type's icon (found without touching any file),
//! - `file:<path>`: one file's own icon (programs, shortcuts), where the
//!   platform has them (`platform::PER_FILE_ICONS`).
//!
//! Answers are kept in memory for the session. Folder and file type icons are
//! also kept in the cache folder (spec 4.5), so the next start needs no lookups.
//! A key with no icon answers `None`, and the UI keeps its built-in icon.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::model::SyncState;
use crate::paths::{write_atomic, AppPaths};
use crate::platform::{self, Icon, IconTarget};

/// Icons bigger than this (some SVGs) are not worth sending to the UI.
const MAX_ICON_BYTES: usize = 256 * 1024;

#[derive(Default)]
pub struct IconCache {
    memory: Mutex<HashMap<String, Option<String>>>,
}

/// Looks up icons for `keys`, as `data:` URLs.
pub fn get(cache: &IconCache, paths: &AppPaths, keys: Vec<String>) -> HashMap<String, Option<String>> {
    keys.into_iter()
        .map(|key| {
            if let Some(known) = cache.memory.lock().unwrap().get(&key) {
                return (key, known.clone());
            }
            let url = parse_key(&key).and_then(|target| lookup(paths, &target)).map(|icon| data_url(&icon));
            cache.memory.lock().unwrap().insert(key.clone(), url.clone());
            (key, url)
        })
        .collect()
}

fn parse_key(key: &str) -> Option<IconTarget> {
    if key == "folder" {
        Some(IconTarget::Folder)
    } else if let Some(ext) = key.strip_prefix("ext:") {
        Some(IconTarget::Extension(ext.to_lowercase()))
    } else {
        key.strip_prefix("file:").map(|path| IconTarget::File(PathBuf::from(path)))
    }
}

fn lookup(paths: &AppPaths, target: &IconTarget) -> Option<Icon> {
    match target {
        IconTarget::File(path) => {
            // Never for slow or online-only files: reading the icon could hang
            // or download the file (spec 4.3, FR-SYNC-03).
            if !platform::PER_FILE_ICONS || platform::is_slow_path(path) {
                return None;
            }
            let meta = fs::metadata(path).ok()?;
            if platform::sync_state(&meta) == SyncState::OnlineOnly {
                return None;
            }
            platform::icon(target).filter(|i| i.bytes.len() <= MAX_ICON_BYTES)
        }
        _ => {
            let file = disk_file(paths, target)?;
            if let Some(icon) = read_cached(&file) {
                return Some(icon);
            }
            let icon = platform::icon(target).filter(|i| i.bytes.len() <= MAX_ICON_BYTES)?;
            let file = file.with_extension(if icon.mime == "image/svg+xml" { "svg" } else { "png" });
            if let Err(e) = write_atomic(&file, &icon.bytes) {
                tracing::debug!("could not cache an icon in {}: {e}", file.display());
            }
            Some(icon)
        }
    }
}

/// `<cache>/icons/<app version>/<name>`, without the image extension. A new
/// app version starts a new folder, so icons are looked up again (spec 4.5).
fn disk_file(paths: &AppPaths, target: &IconTarget) -> Option<PathBuf> {
    let name = match target {
        IconTarget::Folder => "folder".to_string(),
        IconTarget::Extension(ext) => {
            let safe: String = ext.chars().map(|c| if c.is_ascii_alphanumeric() { c } else { '_' }).collect();
            // A hash keeps different extensions apart when they look the same once made safe.
            format!("ext-{safe}-{:08x}", fnv(ext.as_bytes()))
        }
        IconTarget::File(_) => return None,
    };
    Some(paths.cache.join("icons").join(env!("CARGO_PKG_VERSION")).join(name))
}

fn read_cached(file: &Path) -> Option<Icon> {
    [("png", "image/png"), ("svg", "image/svg+xml")]
        .iter()
        .find_map(|(ext, mime)| fs::read(file.with_extension(ext)).ok().map(|bytes| Icon { bytes, mime }))
}

fn fnv(bytes: &[u8]) -> u32 {
    bytes.iter().fold(0x811c9dc5u32, |hash, b| (hash ^ *b as u32).wrapping_mul(0x01000193))
}

fn data_url(icon: &Icon) -> String {
    format!("data:{};base64,{}", icon.mime, base64(&icon.bytes))
}

fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n =
            (chunk[0] as u32) << 16 | (*chunk.get(1).unwrap_or(&0) as u32) << 8 | *chunk.get(2).unwrap_or(&0) as u32;
        for i in 0..4 {
            if i <= chunk.len() {
                out.push(TABLE[(n >> (18 - 6 * i) & 63) as usize] as char);
            } else {
                out.push('=');
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_the_standard() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
        assert_eq!(base64(&[0xff, 0xfe, 0x00]), "//4A");
    }

    #[test]
    fn keys_are_parsed() {
        assert_eq!(parse_key("folder"), Some(IconTarget::Folder));
        assert_eq!(parse_key("ext:PDF"), Some(IconTarget::Extension("pdf".into())));
        assert_eq!(parse_key("ext:"), Some(IconTarget::Extension(String::new())));
        assert_eq!(parse_key("file:/a/b.exe"), Some(IconTarget::File(PathBuf::from("/a/b.exe"))));
        assert_eq!(parse_key("nonsense"), None);
    }

    #[test]
    fn cached_icons_are_read_back_and_unknown_keys_answer_none() {
        let dir = tempfile::tempdir().unwrap();
        let paths =
            AppPaths { config: dir.path().join("c"), cache: dir.path().join("cache"), logs: dir.path().join("l") };
        let file = disk_file(&paths, &IconTarget::Extension("abc".into())).unwrap();
        write_atomic(&file.with_extension("png"), b"\x89PNG").unwrap();

        let cache = IconCache::default();
        let found = get(&cache, &paths, vec!["ext:abc".into(), "nonsense".into()]);
        assert_eq!(found["ext:abc"].as_deref(), Some("data:image/png;base64,iVBORw=="));
        assert_eq!(found["nonsense"], None);
        // Kept in memory: removing the file changes nothing this session.
        fs::remove_file(file.with_extension("png")).unwrap();
        assert!(get(&cache, &paths, vec!["ext:abc".into()])["ext:abc"].is_some());
    }

    #[test]
    fn file_icons_are_never_read_from_missing_files() {
        let dir = tempfile::tempdir().unwrap();
        let paths = AppPaths { config: dir.path().into(), cache: dir.path().join("cache"), logs: dir.path().into() };
        let missing = dir.path().join("gone.exe").to_string_lossy().into_owned();
        assert_eq!(get(&IconCache::default(), &paths, vec![format!("file:{missing}")]).values().next(), Some(&None));
    }
}
