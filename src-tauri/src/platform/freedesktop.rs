//! System icons on Linux and other freedesktop.org desktops (FR-ICON-02):
//! a file type's MIME type from the shared-mime-info database, then its icon
//! from the user's icon theme, following the Icon Theme Specification
//! (inherited themes, then hicolor). Nothing here reads the user's files.

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::OnceLock;

use super::{Icon, IconTarget};

/// The size asked for. Icons are drawn at 16 px, so 32 px stays sharp on
/// high-DPI screens.
const SIZE: u32 = 32;

pub fn icon(target: &IconTarget) -> Option<Icon> {
    let names = match target {
        IconTarget::Folder => vec!["folder".to_string()],
        IconTarget::Extension(ext) => mime_db().icon_names(ext),
        IconTarget::File(_) => return None,
    };
    let themes = themes();
    names.iter().find_map(|name| themes.find(name)).and_then(|path| {
        let mime = if path.extension().is_some_and(|e| e == "svg") { "image/svg+xml" } else { "image/png" };
        fs::read(&path).ok().map(|bytes| Icon { bytes, mime })
    })
}

fn mime_db() -> &'static MimeDb {
    static DB: OnceLock<MimeDb> = OnceLock::new();
    DB.get_or_init(|| MimeDb::load(&data_dirs()))
}

fn themes() -> &'static Themes {
    static THEMES: OnceLock<Themes> = OnceLock::new();
    THEMES.get_or_init(|| Themes::load(icon_dirs(), &theme_name()))
}

// DIRECTORIES

fn home() -> PathBuf {
    crate::paths::home_dir()
}

/// $XDG_DATA_HOME, then $XDG_DATA_DIRS.
fn data_dirs() -> Vec<PathBuf> {
    let mut dirs =
        vec![std::env::var_os("XDG_DATA_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".local/share"))];
    let system = std::env::var("XDG_DATA_DIRS").unwrap_or_default();
    let system = if system.trim().is_empty() { "/usr/local/share:/usr/share".to_string() } else { system };
    dirs.extend(system.split(':').filter(|d| !d.is_empty()).map(PathBuf::from));
    dirs
}

/// Where icon themes live: ~/.icons, then `icons` in every data folder.
fn icon_dirs() -> Vec<PathBuf> {
    std::iter::once(home().join(".icons")).chain(data_dirs().into_iter().map(|d| d.join("icons"))).collect()
}

/// The icon theme the desktop uses: GTK's settings, GNOME's setting, or KDE's; else Adwaita.
fn theme_name() -> String {
    let config = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home().join(".config"));
    let from_ini = |file: PathBuf, section: &str, key: &str| -> Option<String> {
        let text = fs::read_to_string(file).ok()?;
        ini_sections(&text).get(section)?.get(key).cloned().filter(|v| !v.is_empty())
    };
    from_ini(config.join("gtk-4.0/settings.ini"), "Settings", "gtk-icon-theme-name")
        .or_else(|| from_ini(config.join("gtk-3.0/settings.ini"), "Settings", "gtk-icon-theme-name"))
        .or_else(|| {
            let out = std::process::Command::new("gsettings")
                .args(["get", "org.gnome.desktop.interface", "icon-theme"])
                .output()
                .ok()?;
            let name = String::from_utf8_lossy(&out.stdout).trim().trim_matches('\'').to_string();
            (out.status.success() && !name.is_empty()).then_some(name)
        })
        .or_else(|| from_ini(config.join("kdeglobals"), "Icons", "Theme"))
        .unwrap_or_else(|| "Adwaita".to_string())
}

/// A minimal INI reader: section → key → value.
fn ini_sections(text: &str) -> HashMap<String, HashMap<String, String>> {
    let mut sections: HashMap<String, HashMap<String, String>> = HashMap::new();
    let mut current = String::new();
    for line in text.lines().map(str::trim) {
        if line.starts_with('#') || line.starts_with(';') || line.is_empty() {
            continue;
        }
        if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
            current = name.to_string();
        } else if let Some((key, value)) = line.split_once('=') {
            sections.entry(current.clone()).or_default().insert(key.trim().to_string(), value.trim().to_string());
        }
    }
    sections
}

// MIME TYPES

#[derive(Default)]
struct MimeDb {
    /// Extension → (weight, MIME type).
    by_ext: HashMap<String, (u32, String)>,
    /// MIME type → icon name, from mime/icons.
    icons: HashMap<String, String>,
    /// MIME type → generic icon name, from mime/generic-icons.
    generic: HashMap<String, String>,
}

impl MimeDb {
    fn load(data_dirs: &[PathBuf]) -> Self {
        let mut db = MimeDb::default();
        // Earlier folders take precedence, so read them last.
        for dir in data_dirs.iter().rev().map(|d| d.join("mime")) {
            if let Ok(text) = fs::read_to_string(dir.join("globs2")) {
                db.add_globs(&text);
            }
            for (file, map) in [("icons", &mut db.icons), ("generic-icons", &mut db.generic)] {
                if let Ok(text) = fs::read_to_string(dir.join(file)) {
                    for (mime, icon) in text.lines().filter_map(|l| l.split_once(':')) {
                        map.insert(mime.to_string(), icon.trim().to_string());
                    }
                }
            }
        }
        db
    }

    /// globs2 lines are `weight:type:pattern[:flags]`; only `*.ext` patterns are used.
    fn add_globs(&mut self, text: &str) {
        for line in text.lines().filter(|l| !l.starts_with('#')) {
            let mut parts = line.split(':');
            let (Some(weight), Some(mime), Some(pattern)) = (parts.next(), parts.next(), parts.next()) else {
                continue;
            };
            let Some(ext) = pattern.strip_prefix("*.") else { continue };
            if ext.contains(['*', '?', '[', '.']) {
                continue;
            }
            let weight: u32 = weight.parse().unwrap_or(50);
            let ext = ext.to_lowercase();
            if self.by_ext.get(&ext).is_none_or(|(w, _)| weight > *w) {
                self.by_ext.insert(ext, (weight, mime.to_string()));
            }
        }
    }

    /// Icon names to try for a file type, most specific first.
    fn icon_names(&self, ext: &str) -> Vec<String> {
        let mut names = Vec::new();
        if let Some((_, mime)) = self.by_ext.get(ext) {
            names.extend(self.icons.get(mime).cloned());
            names.push(mime.replace('/', "-"));
            names.extend(self.generic.get(mime).cloned());
            if let Some((media, _)) = mime.split_once('/') {
                names.push(format!("{media}-x-generic"));
            }
        }
        names.push("text-x-generic".to_string());
        let mut seen = std::collections::HashSet::new();
        names.retain(|n| seen.insert(n.clone()));
        names
    }
}

// ICON THEMES

#[derive(Debug, Clone)]
struct ThemeDir {
    path: String,
    size: u32,
    scale: u32,
    kind: String,
    min: u32,
    max: u32,
    threshold: u32,
}

impl ThemeDir {
    /// How far this folder's icons are from the wanted size (0 = a match).
    fn distance(&self, size: u32) -> u32 {
        match self.kind.as_str() {
            "Scalable" if size < self.min => self.min - size,
            "Scalable" if size > self.max => size - self.max,
            "Scalable" => 0,
            "Threshold" if size.abs_diff(self.size) <= self.threshold => 0,
            _ => size.abs_diff(self.size),
        }
    }
}

struct Theme {
    dirs: Vec<ThemeDir>,
    inherits: Vec<String>,
}

struct Themes {
    bases: Vec<PathBuf>,
    /// The themes to search, in order: the user's, those it inherits, then hicolor.
    order: Vec<(String, Theme)>,
}

impl Themes {
    fn load(bases: Vec<PathBuf>, name: &str) -> Self {
        let mut order: Vec<(String, Theme)> = Vec::new();
        let mut queue = vec![name.to_string()];
        while let Some(next) = queue.first().cloned() {
            queue.remove(0);
            if order.iter().any(|(n, _)| *n == next) || order.len() > 16 {
                continue;
            }
            if let Some(theme) = read_theme(&bases, &next) {
                queue.extend(theme.inherits.iter().cloned());
                order.push((next, theme));
            }
            if queue.is_empty() && !order.iter().any(|(n, _)| n == "hicolor") {
                queue.push("hicolor".to_string());
            }
        }
        Themes { bases, order }
    }

    /// The best file for an icon name in the first theme that has it.
    fn find(&self, name: &str) -> Option<PathBuf> {
        for (theme_name, theme) in &self.order {
            let mut best: Option<(u32, PathBuf)> = None;
            for dir in theme.dirs.iter().filter(|d| d.scale == 1) {
                let distance = dir.distance(SIZE);
                if best.as_ref().is_some_and(|(d, _)| *d <= distance) {
                    continue;
                }
                for base in &self.bases {
                    let folder = base.join(theme_name).join(&dir.path);
                    if let Some(file) =
                        ["png", "svg"].iter().map(|ext| folder.join(format!("{name}.{ext}"))).find(|f| f.is_file())
                    {
                        best = Some((distance, file));
                        break;
                    }
                }
            }
            if let Some((_, file)) = best {
                return Some(file);
            }
        }
        None
    }
}

fn read_theme(bases: &[PathBuf], name: &str) -> Option<Theme> {
    let text = bases.iter().find_map(|base| fs::read_to_string(base.join(name).join("index.theme")).ok())?;
    let sections = ini_sections(&text);
    let main = sections.get("Icon Theme")?;
    let list = |key: &str| -> Vec<String> {
        main.get(key)
            .map(|v| v.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect())
            .unwrap_or_default()
    };
    let dirs = list("Directories")
        .into_iter()
        .filter_map(|path| {
            let section = sections.get(&path)?;
            let number = |key: &str| section.get(key).and_then(|v| v.parse::<u32>().ok());
            let size = number("Size")?;
            Some(ThemeDir {
                size,
                scale: number("Scale").unwrap_or(1),
                kind: section.get("Type").cloned().unwrap_or_else(|| "Threshold".to_string()),
                min: number("MinSize").unwrap_or(size),
                max: number("MaxSize").unwrap_or(size),
                threshold: number("Threshold").unwrap_or(2),
                path,
            })
        })
        .collect();
    Some(Theme { dirs, inherits: list("Inherits") })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn write(path: &Path, text: &str) {
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, text).unwrap();
    }

    #[test]
    fn mime_types_and_icon_names_come_from_the_database() {
        let dir = tempfile::tempdir().unwrap();
        write(
            &dir.path().join("mime/globs2"),
            "# comment\n50:application/pdf:*.pdf\n50:text/plain:*.txt\n10:text/x-weak:*.txt\n50:text/x-readme:README*\n",
        );
        write(&dir.path().join("mime/generic-icons"), "application/pdf:x-office-document\n");
        let db = MimeDb::load(&[dir.path().to_path_buf()]);
        assert_eq!(
            db.icon_names("pdf"),
            ["application-pdf", "x-office-document", "application-x-generic", "text-x-generic"]
        );
        assert_eq!(db.icon_names("txt"), ["text-plain", "text-x-generic"]);
        assert_eq!(db.icon_names("unknownext"), ["text-x-generic"]);
    }

    #[test]
    fn icons_are_found_in_the_theme_then_inherited_themes_then_hicolor() {
        let dir = tempfile::tempdir().unwrap();
        let base = dir.path().join("icons");
        write(
            &base.join("Mine/index.theme"),
            "[Icon Theme]\nName=Mine\nInherits=Parent\nDirectories=16x16/mimetypes,scalable/mimetypes\n\n\
             [16x16/mimetypes]\nSize=16\nType=Fixed\n\n[scalable/mimetypes]\nSize=16\nMinSize=8\nMaxSize=512\nType=Scalable\n",
        );
        write(&base.join("Mine/16x16/mimetypes/application-pdf.png"), "small");
        write(&base.join("Mine/scalable/mimetypes/application-pdf.svg"), "<svg/>");
        write(&base.join("Parent/index.theme"), "[Icon Theme]\nDirectories=32x32/places\n\n[32x32/places]\nSize=32\n");
        write(&base.join("Parent/32x32/places/folder.png"), "folder");
        write(&base.join("hicolor/index.theme"), "[Icon Theme]\nDirectories=48x48/apps\n\n[48x48/apps]\nSize=48\n");
        write(&base.join("hicolor/48x48/apps/text-x-generic.png"), "generic");

        let themes = Themes::load(vec![base.clone()], "Mine");
        // The scalable icon fits 32 px better than the 16 px one.
        assert_eq!(themes.find("application-pdf"), Some(base.join("Mine/scalable/mimetypes/application-pdf.svg")));
        assert_eq!(themes.find("folder"), Some(base.join("Parent/32x32/places/folder.png")));
        assert_eq!(themes.find("text-x-generic"), Some(base.join("hicolor/48x48/apps/text-x-generic.png")));
        assert_eq!(themes.find("missing"), None);
    }

    #[test]
    fn a_missing_theme_falls_back_to_hicolor() {
        let dir = tempfile::tempdir().unwrap();
        write(&dir.path().join("hicolor/index.theme"), "[Icon Theme]\nDirectories=32x32\n\n[32x32]\nSize=32\n");
        write(&dir.path().join("hicolor/32x32/folder.png"), "x");
        let themes = Themes::load(vec![dir.path().to_path_buf()], "NotInstalled");
        assert!(themes.find("folder").is_some());
    }
}
