//! keybindings.toml (spec 6.10, 8.3): the user's key bindings, which override
//! the defaults. The UI owns the command list and the default bindings; this
//! module reads and writes the file and reports mistakes with line numbers.

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::paths::{self, write_atomic};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Binding {
    /// `Ctrl+Shift+N`, a chord such as `Ctrl+K Ctrl+B`, or "" to remove the
    /// command's default keys.
    pub key: String,
    pub command: String,
    /// `global` (default), `list`, `tree`, `addressBar`, `palette`, `filter` or `quickView`.
    pub when: String,
    pub args: BTreeMap<String, String>,
    /// Line in the file, for messages about this binding (FR-KEY-05).
    pub line: usize,
}

#[derive(Serialize, Clone, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct KeyBindings {
    pub file: String,
    pub bindings: Vec<Binding>,
    pub warnings: Vec<String>,
}

const HEADER: &str = "# keybindings.toml — your key bindings. These override the defaults.
# Help › Keyboard Shortcuts shows every command and writes this file for you.
#
# [[bind]]
# key = \"Ctrl+E\"                 # a chord: \"Ctrl+K Ctrl+B\"
# command = \"find.open\"
# when = \"list\"                  # optional: global, list, tree, addressBar, palette, filter
#
# Use key = \"\" to remove a command's default keys.
";

pub fn load(file: &Path) -> KeyBindings {
    let file_name = file.to_string_lossy().into_owned();
    match fs::read_to_string(file) {
        Ok(text) => {
            let (bindings, warnings) = parse(&text);
            KeyBindings { file: file_name, bindings, warnings }
        }
        Err(e) if e.kind() == io::ErrorKind::NotFound => KeyBindings { file: file_name, ..KeyBindings::default() },
        Err(e) => KeyBindings {
            file: file_name,
            warnings: vec![format!("Could not read keybindings.toml ({e}). The default keys are used.")],
            ..KeyBindings::default()
        },
    }
}

/// Reads the `[[bind]]` entries. Entries with mistakes are skipped and
/// reported; a syntax error skips the whole file (FR-KEY-05).
pub fn parse(text: &str) -> (Vec<Binding>, Vec<String>) {
    let doc = match toml_edit::Document::parse(text) {
        Ok(doc) => doc,
        Err(e) => {
            let line = e.span().map_or(1, |s| line_of(text, s.start));
            return (
                Vec::new(),
                vec![format!(
                    "keybindings.toml line {line}: {} The default keys are used until this is fixed.",
                    e.message()
                )],
            );
        }
    };
    let mut bindings = Vec::new();
    let mut warnings = Vec::new();
    let Some(item) = doc.get("bind") else { return (bindings, warnings) };
    let Some(tables) = item.as_array_of_tables() else {
        let line = item.span().map_or(1, |s| line_of(text, s.start));
        warnings.push(format!("keybindings.toml line {line}: write each binding as a [[bind]] section."));
        return (bindings, warnings);
    };
    for table in tables.iter() {
        let line = table.span().map_or(1, |s| line_of(text, s.start));
        let string = |name: &str| table.get(name).map(|v| v.as_str().map(str::to_string));
        let (key, command) = match (string("key"), string("command")) {
            (Some(Some(key)), Some(Some(command))) if !command.trim().is_empty() => (key, command),
            _ => {
                warnings
                    .push(format!("keybindings.toml line {line}: a binding needs key = \"…\" and command = \"…\"."));
                continue;
            }
        };
        let when = match string("when") {
            None => "global".to_string(),
            Some(Some(when)) => when,
            Some(None) => {
                warnings.push(format!("keybindings.toml line {line}: when must be text, such as \"list\"."));
                continue;
            }
        };
        let mut args = BTreeMap::new();
        if let Some(value) = table.get("args") {
            match value.as_table_like() {
                Some(t) => {
                    for (k, v) in t.iter() {
                        let text = v.as_str().map(str::to_string).or_else(|| v.as_value().map(|v| v.to_string()));
                        args.insert(k.to_string(), text.unwrap_or_default().trim().to_string());
                    }
                }
                None => {
                    warnings.push(format!(
                        "keybindings.toml line {line}: args must be a table, such as {{ name = \"Acme\" }}."
                    ));
                    continue;
                }
            }
        }
        bindings.push(Binding { key: key.trim().to_string(), command: command.trim().to_string(), when, args, line });
    }
    (bindings, warnings)
}

fn line_of(text: &str, offset: usize) -> usize {
    text[..offset.min(text.len())].matches('\n').count() + 1
}

/// Creates the file with an explanatory header, if it does not exist yet.
pub fn ensure_file(file: &Path) -> io::Result<()> {
    if file.exists() {
        return Ok(());
    }
    write_atomic(file, HEADER.as_bytes())
}

/// Sets the keys of one command (FR-KEY-04), keeping the user's comments and
/// other bindings. With no keys, `remove_defaults` writes `key = ""` so the
/// default keys are removed too; otherwise the command goes back to its defaults.
pub fn set(file: &Path, command: &str, when: &str, keys: &[String], remove_defaults: bool) -> Result<(), String> {
    let text = match fs::read_to_string(file) {
        Ok(text) => text,
        Err(e) if e.kind() == io::ErrorKind::NotFound => HEADER.to_string(),
        Err(e) => return Err(e.to_string()),
    };
    // The comments at the top belong to the file, not to the first binding,
    // so they stay even when that binding is replaced.
    let (header, body) = paths::split_header(&text);
    let mut doc = body
        .parse::<toml_edit::DocumentMut>()
        .map_err(|e| format!("keybindings.toml has an error, so the change was not saved. {e}"))?;
    if !doc.contains_key("bind") {
        doc.insert("bind", toml_edit::Item::ArrayOfTables(toml_edit::ArrayOfTables::new()));
    }
    let tables =
        doc["bind"].as_array_of_tables_mut().ok_or("keybindings.toml: bind must be a list of [[bind]] sections.")?;
    let same = |t: &toml_edit::Table| {
        t.get("command").and_then(|v| v.as_str()) == Some(command)
            && t.get("when").and_then(|v| v.as_str()).unwrap_or("global") == when
            && !t.contains_key("args")
    };
    tables.retain(|t| !same(t));
    let mut add = |key: &str| {
        let mut table = toml_edit::Table::new();
        table["key"] = toml_edit::value(key);
        table["command"] = toml_edit::value(command);
        if when != "global" {
            table["when"] = toml_edit::value(when);
        }
        tables.push(table);
    };
    if keys.is_empty() {
        if remove_defaults {
            add("");
        }
    } else {
        for key in keys {
            add(key);
        }
    }
    if file.exists() {
        let _ = fs::write(file.with_extension("toml.bak"), &text);
    }
    write_atomic(file, paths::join_header(header, &doc.to_string()).as_bytes()).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_bindings_and_reports_mistakes_with_line_numbers() {
        let text = "# mine\n[[bind]]\nkey = \"Ctrl+E\"\ncommand = \"find.open\"\n\n[[bind]]\nkey = \"Space\"\n\n[[bind]]\nkey = \"Alt+1\"\ncommand = \"bookmark.open\"\nwhen = \"list\"\nargs = { name = \"Acme\" }\n";
        let (bindings, warnings) = parse(text);
        assert_eq!(bindings.len(), 2);
        assert_eq!(bindings[0].key, "Ctrl+E");
        assert_eq!(bindings[0].when, "global");
        assert_eq!(bindings[0].line, 2);
        assert_eq!(bindings[1].args.get("name").map(String::as_str), Some("Acme"));
        assert_eq!(warnings.len(), 1);
        assert!(warnings[0].contains("line 6"), "{warnings:?}");
    }

    #[test]
    fn a_syntax_error_reports_its_line() {
        let (bindings, warnings) = parse("[[bind]]\nkey = \"Ctrl+E\ncommand = \"x\"\n");
        assert!(bindings.is_empty());
        assert!(warnings[0].contains("line 2"), "{warnings:?}");
    }

    #[test]
    fn set_replaces_one_commands_keys_and_keeps_the_rest() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("keybindings.toml");
        fs::write(&file, "# my comment\n[[bind]]\nkey = \"Ctrl+E\"\ncommand = \"find.open\"\n\n[[bind]]\nkey = \"Ctrl+J\"\ncommand = \"nav.up\"\n").unwrap();
        set(&file, "find.open", "global", &["Ctrl+Alt+F".into(), "Ctrl+K Ctrl+F".into()], false).unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.starts_with("# my comment"), "{text}");
        let (bindings, warnings) = parse(&text);
        assert!(warnings.is_empty());
        let keys: Vec<(&str, &str)> = bindings.iter().map(|b| (b.key.as_str(), b.command.as_str())).collect();
        assert_eq!(keys, [("Ctrl+J", "nav.up"), ("Ctrl+Alt+F", "find.open"), ("Ctrl+K Ctrl+F", "find.open")]);

        set(&file, "nav.up", "global", &[], true).unwrap();
        set(&file, "find.open", "global", &[], false).unwrap();
        let (bindings, _) = parse(&fs::read_to_string(&file).unwrap());
        assert_eq!(bindings.len(), 1);
        assert_eq!((bindings[0].key.as_str(), bindings[0].command.as_str()), ("", "nav.up"));
    }

    #[test]
    fn set_creates_the_file_with_its_header() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("keybindings.toml");
        set(&file, "quickView.toggle", "list", &["Q".into()], false).unwrap();
        let text = fs::read_to_string(&file).unwrap();
        assert!(text.starts_with("# keybindings.toml"));
        let (bindings, _) = parse(&text);
        assert_eq!(bindings[0].when, "list");
    }
}
