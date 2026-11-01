//! Where File Catalog keeps its files, and helpers for working with user-typed paths.

use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

/// Locations of the app's own files (spec 8.2).
#[derive(Clone, Debug)]
pub struct AppPaths {
    /// Settings folder: settings.toml, session.toml, folders/, templates/.
    pub config: PathBuf,
    /// Cache folder: can be deleted at any time.
    pub cache: PathBuf,
    pub logs: PathBuf,
}

impl AppPaths {
    pub fn detect() -> Self {
        // Portable mode: a portable.toml next to the program keeps everything beside it.
        if let Some(exe_dir) = std::env::current_exe().ok().and_then(|exe| exe.parent().map(Path::to_path_buf)) {
            if exe_dir.join("portable.toml").exists() {
                let config = exe_dir.join("settings");
                return Self { cache: config.join("cache"), logs: config.join("logs"), config };
            }
        }

        let (config_root, cache_root) = directories::BaseDirs::new()
            .map(|base| (base.config_dir().to_path_buf(), base.cache_dir().to_path_buf()))
            .unwrap_or_else(|| (PathBuf::from("."), PathBuf::from(".")));

        #[cfg(windows)]
        let (config, cache) = (config_root.join("FileCatalog"), cache_root.join("FileCatalog").join("cache"));
        #[cfg(not(windows))]
        let (config, cache) = (config_root.join("filecatalog"), cache_root.join("filecatalog"));

        Self { logs: config.join("logs"), config, cache }
    }

    pub fn settings_file(&self) -> PathBuf {
        self.config.join("settings.toml")
    }

    pub fn session_file(&self) -> PathBuf {
        self.config.join("session.toml")
    }

    pub fn bookmarks_file(&self) -> PathBuf {
        self.config.join("bookmarks.toml")
    }

    pub fn keybindings_file(&self) -> PathBuf {
        self.config.join("keybindings.toml")
    }

    pub fn toolbar_file(&self) -> PathBuf {
        self.config.join("toolbar.toml")
    }

    pub fn snapshot_file(&self) -> PathBuf {
        self.cache.join("session-snapshot.json")
    }
}

pub fn home_dir() -> PathBuf {
    directories::BaseDirs::new()
        .map(|base| base.home_dir().to_path_buf())
        .unwrap_or_else(|| PathBuf::from(if cfg!(windows) { "C:\\" } else { "/" }))
}

/// Writes a file so that it is either fully replaced or left untouched (NFR-REL-02).
pub fn write_atomic(path: &Path, contents: &[u8]) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, contents)?;
    fs::rename(&tmp, path)
}

/// Splits a TOML file into its leading comment block and the rest. The
/// comments belong to the file, not to its first entry, so they are kept
/// at the top when that entry is replaced (toml_edit would move them).
pub fn split_header(text: &str) -> (&str, &str) {
    let mut end = 0;
    for line in text.split_inclusive('\n') {
        let trimmed = line.trim();
        if !(trimmed.is_empty() || trimmed.starts_with('#')) {
            break;
        }
        end += line.len();
    }
    text.split_at(end)
}

/// Joins a header from `split_header` and an edited document.
pub fn join_header(header: &str, doc: &str) -> String {
    let gap = if header.is_empty() || header.ends_with("\n\n") { "" } else { "\n" };
    format!("{header}{gap}{}", doc.trim_start())
}

/// The form of a folder path used everywhere as its key: no trailing separator
/// (except for roots such as `C:\` or `/`), and backslashes on Windows.
pub fn normalize(path: &str) -> String {
    let mut s = if cfg!(windows) { path.replace('/', "\\") } else { path.to_string() };
    let sep = if cfg!(windows) { '\\' } else { '/' };
    if cfg!(windows) && s.len() == 2 && s.ends_with(':') {
        s.push('\\');
        return s;
    }
    while s.len() > 1 && s.ends_with(sep) {
        if cfg!(windows) && s.len() == 3 && s.as_bytes()[1] == b':' {
            break;
        }
        s.pop();
    }
    s
}

/// Removes `.` and `..` parts without touching the file system.
pub fn clean(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    out.push(component);
                }
            }
            other => out.push(other),
        }
    }
    out
}

/// Expands `~`, `%VAR%`, `$VAR` and `${VAR}` in a typed path (FR-ADDR-03).
/// Unknown variables are left as typed.
pub fn expand(input: &str, home: &Path) -> String {
    let trimmed = input.trim().trim_matches('"');
    let with_home = if trimmed == "~" {
        home.to_string_lossy().into_owned()
    } else if let Some(rest) = trimmed.strip_prefix("~/").or_else(|| trimmed.strip_prefix("~\\")) {
        home.join(rest).to_string_lossy().into_owned()
    } else {
        trimmed.to_string()
    };
    expand_vars(&with_home)
}

fn expand_vars(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let found = match c {
            '%' => chars[i + 1..].iter().position(|&x| x == '%').map(|len| {
                let name: String = chars[i + 1..i + 1 + len].iter().collect();
                (name, len + 2)
            }),
            '$' if chars.get(i + 1) == Some(&'{') => chars[i + 2..].iter().position(|&x| x == '}').map(|len| {
                let name: String = chars[i + 2..i + 2 + len].iter().collect();
                (name, len + 3)
            }),
            '$' => {
                let len = chars[i + 1..].iter().take_while(|x| x.is_ascii_alphanumeric() || **x == '_').count();
                (len > 0).then(|| (chars[i + 1..i + 1 + len].iter().collect(), len + 1))
            }
            _ => None,
        };
        match found.and_then(|(name, used): (String, usize)| std::env::var(&name).ok().map(|value| (value, used))) {
            Some((value, used)) => {
                out.push_str(&value);
                i += used;
            }
            None => {
                out.push(c);
                i += 1;
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_trims_trailing_separators_but_keeps_roots() {
        if cfg!(windows) {
            assert_eq!(normalize("C:\\Vendors\\"), "C:\\Vendors");
            assert_eq!(normalize("C:\\"), "C:\\");
            assert_eq!(normalize("C:"), "C:\\");
            assert_eq!(normalize("C:/Vendors/Acme"), "C:\\Vendors\\Acme");
        } else {
            assert_eq!(normalize("/home/user/"), "/home/user");
            assert_eq!(normalize("/"), "/");
        }
    }

    #[test]
    fn clean_resolves_dot_parts() {
        assert_eq!(clean(Path::new("/a/b/../c/./d")), PathBuf::from("/a/c/d"));
    }

    #[test]
    fn expand_handles_home_and_variables() {
        let home = Path::new("/home/test");
        assert_eq!(expand("~", home), "/home/test");
        assert_eq!(expand("~/docs", home), "/home/test/docs");
        std::env::set_var("FC_TEST_VAR", "value");
        assert_eq!(expand("/x/$FC_TEST_VAR/y", home), "/x/value/y");
        assert_eq!(expand("/x/${FC_TEST_VAR}y", home), "/x/valuey");
        assert_eq!(expand("%FC_TEST_VAR%\\y", home), "value\\y");
        assert_eq!(expand("/x/$FC_UNKNOWN_VAR", home), "/x/$FC_UNKNOWN_VAR");
        assert_eq!(expand("50% off", home), "50% off");
    }
}
