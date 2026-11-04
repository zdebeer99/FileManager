//! Opening files and folders in a text editor or IDE (FR-OPEN-06): the one set
//! in `[editor]` in settings.toml, else the first known editor that is
//! installed (VS Code, VSCodium, Zed, Sublime Text, …).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

/// `[editor]` in settings.toml.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(default, rename_all = "camelCase")]
pub struct EditorSettings {
    /// The program: a name found on PATH (`code`, `zed`, `subl`) or a full path.
    /// Empty: use the first known editor that is installed.
    pub command: String,
    /// The name shown in menus ("Open with …"). Empty: worked out from the program.
    pub name: String,
    /// Extra arguments put before the file or folder (for example `["--new-window"]`).
    pub args: Vec<String>,
}

/// What the UI needs to show the menu items.
#[derive(Serialize, Clone, Debug, Default, PartialEq)]
pub struct EditorInfo {
    /// The editor's name, or empty when no editor was found.
    pub name: String,
}

/// Editors tried when none is set, in this order, with their names.
const KNOWN: &[(&str, &str)] = &[
    ("code", "VS Code"),
    ("codium", "VSCodium"),
    ("zed", "Zed"),
    ("zeditor", "Zed"),
    ("subl", "Sublime Text"),
    ("notepad++", "Notepad++"),
    ("kate", "Kate"),
    ("gnome-text-editor", "Text Editor"),
    ("gedit", "gedit"),
];

pub fn info(settings: &EditorSettings) -> EditorInfo {
    EditorInfo { name: resolve(settings, &search_path()).map(|(_, name)| name).unwrap_or_default() }
}

/// Opens the paths in the editor, all in one call (editors open each one).
pub fn open(settings: &EditorSettings, paths: &[String]) -> Result<(), String> {
    let (program, name) = resolve(settings, &search_path()).ok_or_else(|| {
        if settings.command.trim().is_empty() {
            "No text editor was found. Set one with [editor] command = \"…\" in settings.toml.".to_string()
        } else {
            format!(
                "The editor \"{}\" was not found. Check [editor] command in settings.toml.",
                settings.command.trim()
            )
        }
    })?;
    let mut command = std::process::Command::new(&program);
    command.args(&settings.args).args(paths);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }
    command.spawn().map(|_| ()).map_err(|e| format!("Could not open {name}: {e}"))
}

/// The editor program and its name.
fn resolve(settings: &EditorSettings, dirs: &[PathBuf]) -> Option<(PathBuf, String)> {
    let configured = settings.command.trim();
    let (program, name) = if configured.is_empty() {
        KNOWN
            .iter()
            .find_map(|(program, name)| find_program(program, dirs).map(|p| (p, name.to_string())))
            .or_else(installed_vs_code)?
    } else {
        let program = find_program(configured, dirs)?;
        let stem = program.file_stem().map(|s| s.to_string_lossy().to_lowercase()).unwrap_or_default();
        let known = KNOWN.iter().find(|(p, _)| *p == stem).map(|(_, n)| n.to_string());
        (program, known.unwrap_or(stem))
    };
    let name = if settings.name.trim().is_empty() { name } else { settings.name.trim().to_string() };
    Some((prefer_gui(program), name))
}

/// VS Code puts `bin\code.cmd` on PATH on Windows; starting the `Code.exe` next to
/// it opens the same window without a console flashing up.
fn prefer_gui(program: PathBuf) -> PathBuf {
    let is_cmd = program.extension().is_some_and(|e| e.eq_ignore_ascii_case("cmd"));
    let in_bin = program.parent().and_then(Path::file_name).is_some_and(|d| d.eq_ignore_ascii_case("bin"));
    if is_cmd && in_bin {
        let stem = program.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default();
        let exe = if stem.eq_ignore_ascii_case("codium") { "VSCodium.exe" } else { "Code.exe" };
        if let Some(gui) = program.parent().and_then(Path::parent).map(|d| d.join(exe)).filter(|p| p.is_file()) {
            return gui;
        }
    }
    program
}

/// VS Code installed without being added to PATH (Windows).
fn installed_vs_code() -> Option<(PathBuf, String)> {
    if !cfg!(windows) {
        return None;
    }
    let local = std::env::var_os("LOCALAPPDATA").map(|d| PathBuf::from(d).join("Programs"));
    let machine = std::env::var_os("ProgramFiles").map(PathBuf::from);
    [local, machine]
        .into_iter()
        .flatten()
        .map(|base| base.join("Microsoft VS Code").join("Code.exe"))
        .find(|p| p.is_file())
        .map(|p| (p, "VS Code".to_string()))
}

fn search_path() -> Vec<PathBuf> {
    std::env::var_os("PATH").map(|p| std::env::split_paths(&p).collect()).unwrap_or_default()
}

/// A program by full path, or by name in `dirs` (on Windows also with the
/// PATHEXT extensions, such as `code.cmd`).
fn find_program(program: &str, dirs: &[PathBuf]) -> Option<PathBuf> {
    let given = Path::new(program);
    if given.components().count() > 1 || given.is_absolute() {
        return is_program(given).then(|| given.to_path_buf());
    }
    let extensions: Vec<String> = if cfg!(windows) {
        std::iter::once(String::new())
            .chain(
                std::env::var("PATHEXT")
                    .unwrap_or_else(|_| ".COM;.EXE;.BAT;.CMD".into())
                    .split(';')
                    .filter(|e| !e.is_empty())
                    .map(str::to_lowercase),
            )
            .collect()
    } else {
        vec![String::new()]
    };
    dirs.iter()
        .flat_map(|dir| extensions.iter().map(move |ext| dir.join(format!("{program}{ext}"))))
        .find(|p| is_program(p))
}

fn is_program(path: &Path) -> bool {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        path.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        path.is_file()
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    fn program(dir: &Path, name: &str) -> PathBuf {
        let path = dir.join(name);
        fs::write(&path, "#!/bin/sh\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    #[test]
    fn the_first_known_installed_editor_is_used_when_none_is_set() {
        let dir = tempfile::tempdir().unwrap();
        let dirs = vec![dir.path().to_path_buf()];
        assert_eq!(resolve(&EditorSettings::default(), &dirs), None);

        let subl = program(dir.path(), "subl");
        assert_eq!(resolve(&EditorSettings::default(), &dirs), Some((subl, "Sublime Text".into())));
        let code = program(dir.path(), "code");
        assert_eq!(resolve(&EditorSettings::default(), &dirs), Some((code, "VS Code".into())));
    }

    #[test]
    fn a_configured_editor_wins_and_can_be_named() {
        let dir = tempfile::tempdir().unwrap();
        let dirs = vec![dir.path().to_path_buf()];
        program(dir.path(), "code");
        let zed = program(dir.path(), "zed");
        let set =
            |command: &str, name: &str| EditorSettings { command: command.into(), name: name.into(), args: vec![] };

        assert_eq!(resolve(&set("zed", ""), &dirs), Some((zed.clone(), "Zed".into())));
        assert_eq!(resolve(&set(&zed.to_string_lossy(), "My Zed"), &dirs), Some((zed, "My Zed".into())));
        let mine = program(dir.path(), "myedit");
        assert_eq!(resolve(&set("myedit", ""), &dirs), Some((mine, "myedit".into())));
        // A configured editor that isn't there is not replaced by another one.
        assert_eq!(resolve(&set("missing", ""), &dirs), None);
    }

    #[test]
    fn files_that_are_not_programs_are_skipped() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("code"), "not executable").unwrap();
        assert_eq!(find_program("code", &[dir.path().to_path_buf()]), None);
    }
}
