//! Open With on Linux and other freedesktop.org desktops (FR-OPEN-02): the apps
//! that can open a file type, from the `.desktop` files and `mimeapps.list`
//! (Desktop Entry and MIME Applications Associations specifications), and
//! starting one of them with the file.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use super::freedesktop::{data_dirs, home, ini_sections, mime_db};
use super::{App, OpenWithChoices};

/// The apps for `path`'s file type, the default one first, and every other app
/// that opens files (for *Show all apps*).
pub fn choices(path: &Path) -> OpenWithChoices {
    let mime = mime_for(path);
    let (apps, others) = apps_for(&mime, &desktop_files(&data_dirs()), &associations(&config_files()));
    OpenWithChoices { shown: false, apps, others }
}

/// Starts the app with the file id `id` (e.g. `org.gnome.TextEditor.desktop`) on `path`.
pub fn launch(id: &str, path: &Path) -> Result<(), String> {
    let entries = desktop_files(&data_dirs());
    let entry = entries.get(id).ok_or("That app is no longer installed.")?;
    let args = exec_args(&entry.exec, path);
    let (program, rest) = args.split_first().ok_or("That app can't be started (it has no command).")?;
    let mut command = std::process::Command::new(program);
    command.args(rest);
    if let Some(dir) = path.parent() {
        command.current_dir(dir);
    }
    command.spawn().map(|_| ()).map_err(|e| format!("Could not start {}: {e}", entry.name))
}

fn mime_for(path: &Path) -> String {
    let ext = path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    mime_db()
        .mime_type(&ext)
        .unwrap_or(if ext.is_empty() { "application/octet-stream" } else { "text/plain" })
        .to_string()
}

#[derive(Debug, Clone, PartialEq)]
struct Entry {
    name: String,
    exec: String,
    mime_types: Vec<String>,
}

/// Every app that can be shown, by desktop file id. Earlier data folders win.
fn desktop_files(data_dirs: &[PathBuf]) -> HashMap<String, Entry> {
    let mut found = HashMap::new();
    let mut hidden = HashSet::new();
    for dir in data_dirs.iter().map(|d| d.join("applications")) {
        let mut files = Vec::new();
        collect(&dir, &dir, &mut files, 0);
        for (id, file) in files {
            if found.contains_key(&id) || hidden.contains(&id) {
                continue;
            }
            let Ok(text) = fs::read_to_string(&file) else { continue };
            let sections = ini_sections(&text);
            let Some(entry) = sections.get("Desktop Entry") else { continue };
            let get = |key: &str| entry.get(key).map(String::as_str).unwrap_or_default();
            // A Hidden or NoDisplay entry in an earlier folder hides the app everywhere.
            if get("Hidden") == "true" || get("NoDisplay") == "true" || get("Type") != "Application" {
                hidden.insert(id);
                continue;
            }
            if get("Exec").is_empty() || get("Name").is_empty() {
                continue;
            }
            let mime_types = get("MimeType").split(';').filter(|m| !m.is_empty()).map(String::from).collect();
            found.insert(id, Entry { name: get("Name").to_string(), exec: get("Exec").to_string(), mime_types });
        }
    }
    found
}

/// `.desktop` files under `dir`; the id of `a/b.desktop` is `a-b.desktop`.
fn collect(base: &Path, dir: &Path, out: &mut Vec<(String, PathBuf)>, depth: usize) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() && depth < 4 {
            collect(base, &path, out, depth + 1);
        } else if path.extension().is_some_and(|e| e == "desktop") {
            if let Ok(rel) = path.strip_prefix(base) {
                out.push((rel.to_string_lossy().replace('/', "-"), path));
            }
        }
    }
}

/// `mimeapps.list` files, most important first.
fn config_files() -> Vec<PathBuf> {
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".config"));
    let system = std::env::var("XDG_CONFIG_DIRS").unwrap_or_else(|_| "/etc/xdg".into());
    std::iter::once(config.join("mimeapps.list"))
        .chain(system.split(':').filter(|d| !d.is_empty()).map(|d| PathBuf::from(d).join("mimeapps.list")))
        .chain(data_dirs().into_iter().map(|d| d.join("applications/mimeapps.list")))
        .collect()
}

#[derive(Default, Debug)]
struct Associations {
    /// MIME type → default app ids, in order.
    defaults: HashMap<String, Vec<String>>,
    added: HashMap<String, Vec<String>>,
    removed: HashMap<String, HashSet<String>>,
}

fn associations(files: &[PathBuf]) -> Associations {
    let mut result = Associations::default();
    let list = |v: &str| v.split(';').filter(|s| !s.is_empty()).map(String::from).collect::<Vec<_>>();
    for file in files {
        let Ok(text) = fs::read_to_string(file) else { continue };
        let sections = ini_sections(&text);
        for (mime, ids) in sections.get("Default Applications").into_iter().flatten() {
            result.defaults.entry(mime.clone()).or_default().extend(list(ids));
        }
        for (mime, ids) in sections.get("Added Associations").into_iter().flatten() {
            result.added.entry(mime.clone()).or_default().extend(list(ids));
        }
        for (mime, ids) in sections.get("Removed Associations").into_iter().flatten() {
            result.removed.entry(mime.clone()).or_default().extend(list(ids));
        }
    }
    result
}

/// The apps for `mime` (the default first, then by name), and the other apps that take files.
fn apps_for(mime: &str, entries: &HashMap<String, Entry>, assoc: &Associations) -> (Vec<App>, Vec<App>) {
    let removed = assoc.removed.get(mime).cloned().unwrap_or_default();
    let default = assoc.defaults.get(mime).and_then(|ids| ids.iter().find(|id| entries.contains_key(*id))).cloned();
    let mut ids: Vec<String> = assoc.added.get(mime).cloned().unwrap_or_default();
    let mut listed: Vec<&String> =
        entries.iter().filter(|(_, e)| e.mime_types.iter().any(|m| m == mime)).map(|(id, _)| id).collect();
    listed.sort();
    ids.extend(listed.into_iter().cloned());
    ids.extend(default.clone());

    let app =
        |id: &String| App { id: id.clone(), name: entries[id].name.clone(), default: Some(id) == default.as_ref() };
    let mut seen = HashSet::new();
    let mut apps: Vec<App> = ids
        .iter()
        .filter(|id| entries.contains_key(*id) && !removed.contains(*id) && seen.insert((*id).clone()))
        .map(app)
        .collect();
    apps.sort_by(|a, b| b.default.cmp(&a.default).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())));

    let mut others: Vec<App> =
        entries.iter().filter(|(id, e)| !seen.contains(*id) && takes_files(&e.exec)).map(|(id, _)| app(id)).collect();
    others.sort_by_key(|a| a.name.to_lowercase());
    (apps, others)
}

fn takes_files(exec: &str) -> bool {
    ["%f", "%F", "%u", "%U"].iter().any(|code| exec.contains(code))
}

/// The command line from an `Exec` value with the file put in (Desktop Entry
/// specification): quoting is honoured, `%f %F %u %U` become the file, `%%`
/// a percent sign, and other field codes are dropped. Without a field code the
/// file goes at the end.
fn exec_args(exec: &str, path: &Path) -> Vec<String> {
    let file = path.to_string_lossy().into_owned();
    let mut args = Vec::new();
    let mut placed = false;
    for word in split_words(exec) {
        match word.as_str() {
            "%f" | "%F" | "%u" | "%U" => {
                args.push(file.clone());
                placed = true;
            }
            "%i" | "%c" | "%k" | "%d" | "%D" | "%n" | "%N" | "%v" | "%m" => {}
            _ => {
                let mut out = String::new();
                let mut chars = word.chars().peekable();
                while let Some(c) = chars.next() {
                    if c == '%' {
                        match chars.next() {
                            Some('%') => out.push('%'),
                            Some('f' | 'F' | 'u' | 'U') => {
                                out.push_str(&file);
                                placed = true;
                            }
                            _ => {}
                        }
                    } else {
                        out.push(c);
                    }
                }
                if !out.is_empty() {
                    args.push(out);
                }
            }
        }
    }
    if !placed {
        args.push(file);
    }
    args
}

/// Splits on spaces outside double quotes; `\` escapes inside quotes.
fn split_words(text: &str) -> Vec<String> {
    let mut words = Vec::new();
    let mut current = String::new();
    let (mut quoted, mut any) = (false, false);
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                quoted = !quoted;
                any = true;
            }
            '\\' if quoted => current.extend(chars.next()),
            ' ' | '\t' if !quoted => {
                if any || !current.is_empty() {
                    words.push(std::mem::take(&mut current));
                }
                any = false;
            }
            _ => current.push(c),
        }
    }
    if any || !current.is_empty() {
        words.push(current);
    }
    words
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_lines_get_the_file() {
        let file = Path::new("/home/me/My notes.txt");
        assert_eq!(exec_args("gedit %U", file), ["gedit", "/home/me/My notes.txt"]);
        assert_eq!(exec_args("code --new-window %F", file), ["code", "--new-window", "/home/me/My notes.txt"]);
        assert_eq!(exec_args("\"/opt/My App/run\" --x %i", file), ["/opt/My App/run", "--x", "/home/me/My notes.txt"]);
        assert_eq!(
            exec_args("app --ratio=50%% --file=%f", file),
            ["app", "--ratio=50%", "--file=/home/me/My notes.txt"]
        );
    }

    #[test]
    fn apps_come_from_desktop_files_and_mimeapps_lists() {
        let dir = tempfile::tempdir().unwrap();
        let apps = dir.path().join("share/applications");
        fs::create_dir_all(apps.join("kde")).unwrap();
        let write = |name: &str, text: &str| fs::write(apps.join(name), text).unwrap();
        write("gedit.desktop", "[Desktop Entry]\nType=Application\nName=gedit\nExec=gedit %U\nMimeType=text/plain;\n");
        write("kde/kate.desktop", "[Desktop Entry]\nType=Application\nName=Kate\nExec=kate %F\nMimeType=text/plain;\n");
        write("vim.desktop", "[Desktop Entry]\nType=Application\nName=Vim\nExec=vim %F\nMimeType=text/x-c;\n");
        write(
            "hidden.desktop",
            "[Desktop Entry]\nType=Application\nName=Old\nExec=old %f\nNoDisplay=true\nMimeType=text/plain;\n",
        );
        write("settings.desktop", "[Desktop Entry]\nType=Application\nName=Settings\nExec=settings\n");
        let list = dir.path().join("mimeapps.list");
        fs::write(&list, "[Default Applications]\ntext/plain=kde-kate.desktop;\n[Added Associations]\ntext/plain=vim.desktop;\n[Removed Associations]\ntext/plain=gedit.desktop;\n").unwrap();

        let entries = desktop_files(&[dir.path().join("share")]);
        assert!(entries.contains_key("kde-kate.desktop") && !entries.contains_key("hidden.desktop"));
        let (apps, others) = apps_for("text/plain", &entries, &associations(&[list]));
        let names: Vec<(&str, bool)> = apps.iter().map(|a| (a.name.as_str(), a.default)).collect();
        assert_eq!(names, [("Kate", true), ("Vim", false)]);
        // gedit was removed for text files but can still be picked from all apps; Settings takes no files.
        assert_eq!(others.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(), ["gedit"]);
    }
}
