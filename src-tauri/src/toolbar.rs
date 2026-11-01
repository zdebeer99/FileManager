//! toolbar.toml (spec 5.3, 8.5): which buttons the toolbar shows, in order.
//! `"|"` is a separator and `"->"` pushes the rest to the right.

use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::paths::{self, write_atomic};

/// The default toolbar; it includes Save View (FR-TB-04).
pub const DEFAULT_ITEMS: &[&str] = &[
    "nav.back",
    "nav.forward",
    "nav.up",
    "nav.refresh",
    "|",
    "nav.home",
    "view.toggleSidebar",
    "|",
    "new.folder",
    "new.file",
    "new.fromTemplate",
    "|",
    "edit.cut",
    "edit.copy",
    "edit.paste",
    "edit.delete",
    "|",
    "view.saveForFolder",
    "->",
    "find.open",
    "palette.open",
];

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Toolbar {
    /// "icon", "iconText" or "text".
    pub style: String,
    pub items: Vec<String>,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub warnings: Vec<String>,
    /// The default items, for *Restore Defaults* in Customise Toolbar.
    #[serde(default)]
    pub defaults: Vec<String>,
}

impl Toolbar {
    fn defaults(file: &Path) -> Self {
        let items: Vec<String> = DEFAULT_ITEMS.iter().map(|s| s.to_string()).collect();
        Self {
            style: "icon".into(),
            defaults: items.clone(),
            items,
            file: file.to_string_lossy().into_owned(),
            warnings: Vec::new(),
        }
    }
}

pub fn load(file: &Path) -> Toolbar {
    let mut toolbar = Toolbar::defaults(file);
    let text = match fs::read_to_string(file) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return toolbar,
        Err(e) => {
            toolbar.warnings.push(format!("Could not read toolbar.toml ({e}). The default toolbar is shown."));
            return toolbar;
        }
    };
    let table = match text.parse::<toml::Table>() {
        Ok(table) => table,
        Err(e) => {
            toolbar.warnings.push(format!("toolbar.toml has an error, so the default toolbar is shown. {e}"));
            return toolbar;
        }
    };
    match table.get("style") {
        None => {}
        Some(toml::Value::String(s)) if ["icon", "iconText", "text"].contains(&s.as_str()) => toolbar.style = s.clone(),
        Some(_) => toolbar.warnings.push("toolbar.toml: style must be \"icon\", \"iconText\" or \"text\".".into()),
    }
    match table.get("items") {
        None => {}
        Some(toml::Value::Array(items)) => {
            toolbar.items = items.iter().filter_map(|v| v.as_str().map(str::to_string)).collect();
            if toolbar.items.len() != items.len() {
                toolbar.warnings.push("toolbar.toml: every item must be a command name in quotes.".into());
            }
        }
        Some(_) => toolbar.warnings.push("toolbar.toml: items must be a list, such as [\"nav.back\", \"|\"].".into()),
    }
    toolbar
}

const HEADER: &str = "# toolbar.toml — the toolbar buttons, in order. Right-click the toolbar to change them.
# \"|\" is a separator and \"->\" pushes the rest to the right.
# Command names are listed in Help › Keyboard Shortcuts.
";

/// Writes the style and items, keeping the user's comments (FR-TB-02).
pub fn save(file: &Path, style: &str, items: &[String]) -> Result<(), String> {
    let text = match fs::read_to_string(file) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => HEADER.to_string(),
        Err(e) => return Err(e.to_string()),
    };
    let (header, body) = paths::split_header(&text);
    let mut doc = body
        .parse::<toml_edit::DocumentMut>()
        .map_err(|e| format!("toolbar.toml has an error, so the change was not saved. {e}"))?;
    doc["style"] = toml_edit::value(style);
    let mut array: toml_edit::Array = items.iter().map(String::as_str).collect();
    for value in array.iter_mut() {
        value.decor_mut().set_prefix("\n  ");
    }
    array.set_trailing("\n");
    array.set_trailing_comma(true);
    doc["items"] = toml_edit::value(array);
    if file.exists() {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    write_atomic(file, paths::join_header(header, &doc.to_string()).as_bytes()).map_err(|e| e.to_string())
}

/// Creates the file with the current toolbar, so there is something to edit.
pub fn ensure_file(file: &Path) -> Result<(), String> {
    if file.exists() {
        return Ok(());
    }
    let defaults = Toolbar::defaults(file);
    save(file, &defaults.style, &defaults.items)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_file_gives_the_default_toolbar_with_save_view() {
        let dir = tempfile::tempdir().unwrap();
        let toolbar = load(&dir.path().join("toolbar.toml"));
        assert!(toolbar.items.contains(&"view.saveForFolder".to_string()));
        assert!(toolbar.warnings.is_empty());
    }

    #[test]
    fn save_keeps_comments_and_reads_back() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("toolbar.toml");
        fs::write(&file, "# my toolbar\nstyle = \"text\"\n").unwrap();
        save(&file, "iconText", &["nav.back".into(), "|".into(), "palette.open".into()]).unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.starts_with("# my toolbar"), "{text}");

        let fresh = dir.path().join("new.toml");
        ensure_file(&fresh).unwrap();
        assert!(fs::read_to_string(&fresh).unwrap().starts_with("# toolbar.toml"));
        let toolbar = load(&file);
        assert_eq!(toolbar.style, "iconText");
        assert_eq!(toolbar.items, ["nav.back", "|", "palette.open"]);
    }

    #[test]
    fn mistakes_are_reported_and_defaults_kept() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("toolbar.toml");
        fs::write(&file, "style = \"huge\"\nitems = \"nav.back\"\n").unwrap();
        let toolbar = load(&file);
        assert_eq!(toolbar.warnings.len(), 2);
        assert_eq!(toolbar.style, "icon");
        assert_eq!(toolbar.items.len(), DEFAULT_ITEMS.len());
    }
}
