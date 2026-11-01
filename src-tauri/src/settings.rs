//! settings.toml (spec 8.3). Each section is read on its own, so a mistake in
//! one section only resets that section to its defaults (NFR-REL-03).

use std::fs;
use std::io;
use std::path::Path;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::paths::{write_atomic, AppPaths};

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct Settings {
    pub general: General,
    pub layout: Layout,
    pub view: ViewSection,
    pub templates: TemplateSettings,
    pub network: Network,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct TemplateSettings {
    /// Relative to the settings folder, or full paths (FR-TPL-01).
    pub folders: Vec<String>,
    pub date_format: String,
}

impl Default for TemplateSettings {
    fn default() -> Self {
        Self { folders: vec!["templates".into()], date_format: "yyyy-MM-dd".into() }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct General {
    /// "last", "home", or a folder path.
    pub startup_folder: String,
    pub restore_tabs: bool,
    pub home_folder: String,
    /// "system", "light" or "dark".
    pub theme: String,
    pub confirm_delete: bool,
    pub confirm_extension_change: bool,
    pub typing_starts_filter: bool,
    pub keep_filter_on_navigate: bool,
    pub terminal: String,
}

impl Default for General {
    fn default() -> Self {
        Self {
            startup_folder: "last".into(),
            restore_tabs: true,
            home_folder: "~".into(),
            theme: "system".into(),
            confirm_delete: false,
            confirm_extension_change: true,
            typing_starts_filter: false,
            keep_filter_on_navigate: false,
            terminal: String::new(),
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct Layout {
    pub menu_bar: bool,
    pub toolbar: bool,
    pub bookmark_bar: bool,
    pub tab_bar: bool,
    pub address_bar: bool,
    pub status_bar: bool,
    pub sidebar: Panel,
    pub quick_view: Panel,
}

impl Default for Layout {
    fn default() -> Self {
        Self {
            menu_bar: true,
            toolbar: true,
            bookmark_bar: true,
            tab_bar: true,
            address_bar: true,
            status_bar: true,
            sidebar: Panel { visible: true, side: "left".into(), width: 260, mode: "tree".into() },
            quick_view: Panel { visible: false, side: "right".into(), width: 360, mode: String::new() },
        }
    }
}

/// A dockable side panel (FR-UI-02).
#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct Panel {
    pub visible: bool,
    /// "left" or "right".
    pub side: String,
    pub width: u32,
    /// Sidebar only: "tree", "favourites" or "bookmarks".
    pub mode: String,
}

impl Default for Panel {
    fn default() -> Self {
        Self { visible: true, side: "left".into(), width: 260, mode: "tree".into() }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
#[serde(default, rename_all = "camelCase")]
pub struct ViewSection {
    pub default: ViewSettings,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct ViewSettings {
    pub mode: String,
    pub columns: Vec<String>,
    pub sort: Vec<SortKey>,
    pub folders_first: bool,
    pub show_hidden: bool,
    pub show_extensions: bool,
    pub date_format: String,
}

impl Default for ViewSettings {
    fn default() -> Self {
        Self {
            mode: "details".into(),
            columns: ["name", "modified", "created", "size", "sync"].map(String::from).to_vec(),
            sort: vec![SortKey::default()],
            folders_first: true,
            show_hidden: false,
            show_extensions: true,
            date_format: "yyyy-MM-dd HH:mm".into(),
        }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct SortKey {
    pub column: String,
    pub direction: String,
}

impl Default for SortKey {
    fn default() -> Self {
        Self { column: "name".into(), direction: "asc".into() }
    }
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(default, rename_all = "camelCase")]
pub struct Network {
    pub timeout_seconds: u64,
}

impl Default for Network {
    fn default() -> Self {
        Self { timeout_seconds: 5 }
    }
}

/// Loads settings.toml, creating a commented template the first time.
/// Problems are returned as messages for the user; the file is never overwritten.
pub fn load(paths: &AppPaths) -> (Settings, Vec<String>) {
    let file = paths.settings_file();
    match fs::read_to_string(&file) {
        Ok(text) => parse(&text),
        Err(e) if e.kind() == io::ErrorKind::NotFound => {
            if let Err(e) = write_atomic(&file, DEFAULT_FILE.as_bytes()) {
                tracing::warn!("could not create {}: {e}", file.display());
            }
            (Settings::default(), Vec::new())
        }
        Err(e) => (Settings::default(), vec![format!("Could not read settings.toml ({e}). Using default settings.")]),
    }
}

pub fn parse(text: &str) -> (Settings, Vec<String>) {
    let mut warnings = Vec::new();
    let table = match text.parse::<toml::Table>() {
        Ok(table) => table,
        Err(e) => {
            warnings.push(format!(
                "settings.toml has an error, so default settings are used. The file was not changed. {e}"
            ));
            return (Settings::default(), warnings);
        }
    };
    let view_table = table.get("view").and_then(|v| v.as_table()).cloned().unwrap_or_default();
    let settings = Settings {
        general: section(&table, "general", "general", &mut warnings),
        layout: section(&table, "layout", "layout", &mut warnings),
        view: ViewSection { default: section(&view_table, "default", "view.default", &mut warnings) },
        templates: section(&table, "templates", "templates", &mut warnings),
        network: section(&table, "network", "network", &mut warnings),
    };
    (settings, warnings)
}

fn section<T: DeserializeOwned + Default>(
    table: &toml::Table,
    key: &str,
    label: &str,
    warnings: &mut Vec<String>,
) -> T {
    match table.get(key) {
        None => T::default(),
        Some(value) => value.clone().try_into().unwrap_or_else(|e| {
            warnings.push(format!("settings.toml [{label}]: {e} Default values are used for this section."));
            T::default()
        }),
    }
}

/// Written the first time File Catalog runs. Every value is commented out,
/// so the file documents the defaults without fixing them.
const DEFAULT_FILE: &str = r##"# File Catalog settings.
# Remove the "#" in front of a line to change that value.
# Only values that differ from the defaults are needed. Changes apply as soon as you save.

# [general]
# startupFolder   = "last"          # "last" | "home" | a folder path
# restoreTabs     = true
# homeFolder      = "~"
# theme           = "system"        # "system" | "light" | "dark"
# keepFilterOnNavigate = false      # keep the Quick Filter text when opening another folder

# [layout]
# menuBar     = true
# toolbar     = true
# bookmarkBar = true
# tabBar      = true
# addressBar  = true
# statusBar   = true
# sidebar     = { visible = true, side = "left", width = 260, mode = "tree" }   # mode: "tree" | "favourites" | "bookmarks"

# [view.default]
# columns      = ["name", "modified", "created", "size", "sync"]   # also: "type", "ext"
# sort         = [{ column = "name", direction = "asc" }]
# foldersFirst = true
# showHidden   = false
# showExtensions = true
# dateFormat   = "yyyy-MM-dd HH:mm"

# [templates]
# folders    = ["templates"]        # relative to this settings folder, or full paths (e.g. a shared team folder)
# dateFormat = "yyyy-MM-dd"         # how {date} is written in template names

# [network]
# timeoutSeconds = 5                # how long to wait for a network folder
"##;

/// Changes one value in a TOML file, keeping the user's comments and layout
/// (spec 8.1). `key` is dotted, e.g. `layout.sidebar.width`. The previous
/// file is kept as `<name>.bak` (NFR-REL-02). A file with syntax errors is
/// never overwritten.
pub fn set_value(file: &Path, key: &str, value: &serde_json::Value) -> Result<(), String> {
    let text = match fs::read_to_string(file) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => String::new(),
        Err(e) => return Err(e.to_string()),
    };
    let parse = |text: &str| {
        text.parse::<toml_edit::DocumentMut>().map_err(|e| {
            format!(
                "{} has an error, so the change was not saved. {e}",
                file.file_name().unwrap_or_default().to_string_lossy()
            )
        })
    };
    let mut doc = parse(&text)?;
    let parts: Vec<&str> = key.split('.').collect();
    let (last, parents) = parts.split_last().ok_or("empty settings key")?;
    if !parents.is_empty() && !has_table(doc.as_item(), parents) {
        // A new section goes at the end, below the user's comments.
        let mut extended = text.clone();
        if !extended.is_empty() && !extended.ends_with('\n') {
            extended.push('\n');
        }
        extended.push_str(&format!("\n[{}]\n", parents.join(".")));
        doc = parse(&extended)?;
    }
    let mut item = doc.as_item_mut();
    for part in parents {
        item = &mut item[part];
    }
    item[last] = toml_edit::value(to_toml(value)?);
    if !text.is_empty() {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    write_atomic(file, doc.to_string().as_bytes()).map_err(|e| e.to_string())
}

fn has_table(item: &toml_edit::Item, path: &[&str]) -> bool {
    match path.split_first() {
        None => item.is_table_like(),
        Some((first, rest)) => item.get(first).is_some_and(|child| child.is_table_like() && has_table(child, rest)),
    }
}

fn to_toml(value: &serde_json::Value) -> Result<toml_edit::Value, String> {
    Ok(match value {
        serde_json::Value::Bool(b) => (*b).into(),
        serde_json::Value::Number(n) => match n.as_i64() {
            Some(i) => i.into(),
            None => n.as_f64().unwrap_or_default().into(),
        },
        serde_json::Value::String(s) => s.as_str().into(),
        serde_json::Value::Array(items) => {
            let mut array = toml_edit::Array::new();
            for item in items {
                array.push(to_toml(item)?);
            }
            toml_edit::Value::Array(array)
        }
        other => return Err(format!("unsupported settings value: {other}")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_value_keeps_comments_and_adds_missing_tables() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("settings.toml");
        fs::write(&file, "# my notes\n[general]\ntheme = \"dark\" # keep this\n").unwrap();
        set_value(&file, "layout.sidebar.width", &serde_json::json!(300)).unwrap();
        set_value(&file, "general.theme", &serde_json::json!("light")).unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.starts_with("# my notes"), "{text}");
        assert!(text.trim_end().ends_with("width = 300"), "{text}");
        let (settings, warnings) = parse(&text);
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(settings.layout.sidebar.width, 300);
        assert_eq!(settings.general.theme, "light");
        assert!(file.with_extension("toml.bak").exists());
    }

    #[test]
    fn set_value_refuses_a_broken_file() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("settings.toml");
        fs::write(&file, "[general\n").unwrap();
        assert!(set_value(&file, "general.theme", &serde_json::json!("dark")).is_err());
        assert_eq!(fs::read_to_string(&file).unwrap(), "[general\n");
    }

    #[test]
    fn default_file_parses_to_defaults() {
        let (settings, warnings) = parse(DEFAULT_FILE);
        assert!(warnings.is_empty());
        assert_eq!(settings.view.default.columns, ViewSettings::default().columns);
    }

    #[test]
    fn values_are_read() {
        let (settings, warnings) = parse("[general]\ntheme = \"dark\"\n[view.default]\nshowHidden = true\n");
        assert!(warnings.is_empty());
        assert_eq!(settings.general.theme, "dark");
        assert!(settings.view.default.show_hidden);
        assert!(settings.general.restore_tabs, "unset values keep their default");
    }

    #[test]
    fn a_bad_section_only_resets_that_section() {
        let (settings, warnings) = parse("[general]\ntheme = \"dark\"\n[layout]\ntoolbar = \"yes\"\n");
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("[layout]"));
        assert_eq!(settings.general.theme, "dark");
        assert!(settings.layout.toolbar);
    }

    #[test]
    fn a_syntax_error_uses_all_defaults() {
        let (settings, warnings) = parse("[general\n");
        assert_eq!(warnings.len(), 1);
        assert_eq!(settings.general.theme, "system");
    }
}
