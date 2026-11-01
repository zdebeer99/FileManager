//! Templates (spec 6.8): ordinary files and folders in the templates folders,
//! copied into place with `{name}`, `{date}` and other placeholders filled in.

use std::fs;
use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::fileops::{self, Naming};
use crate::paths::AppPaths;

/// Text files whose contents get placeholders replaced too (FR-TPL-05).
const TEXT_EXTENSIONS: &[&str] = &["txt", "md", "csv", "html", "htm", "json", "toml", "ini", "xml"];

#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Template {
    /// Shown in menus: the file or folder name.
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    /// Menu groups from `_Group` folders, outermost first (FR-TPL-02).
    pub group: Vec<String>,
    /// True when the name contains `{name}`, so the user is asked for one.
    pub needs_name: bool,
}

#[derive(Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Templates {
    /// The first templates folder: where *Save as Template* puts things.
    pub folder: String,
    pub templates: Vec<Template>,
}

/// The templates folders from settings; relative ones are inside the settings folder.
pub fn folders(paths: &AppPaths, configured: &[String]) -> Vec<PathBuf> {
    let list: Vec<PathBuf> = configured
        .iter()
        .filter(|f| !f.trim().is_empty())
        .map(|f| {
            let p = PathBuf::from(crate::paths::expand(f, &crate::paths::home_dir()));
            if p.is_absolute() {
                p
            } else {
                paths.config.join(p)
            }
        })
        .collect();
    if list.is_empty() {
        vec![paths.config.join("templates")]
    } else {
        list
    }
}

pub fn list(folders: &[PathBuf]) -> Templates {
    let mut templates = Vec::new();
    for folder in folders {
        collect(folder, &[], &mut templates);
    }
    Templates { folder: folders.first().map(|f| f.to_string_lossy().into_owned()).unwrap_or_default(), templates }
}

fn collect(dir: &Path, group: &[String], out: &mut Vec<Template>) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut entries: Vec<PathBuf> = entries.filter_map(Result::ok).map(|e| e.path()).collect();
    entries.sort_by_key(|p| p.file_name().map(|n| n.to_string_lossy().to_lowercase()));
    for path in entries {
        let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if name.starts_with('.') {
            continue;
        }
        let is_dir = path.is_dir();
        if is_dir && name.starts_with('_') && name.len() > 1 {
            let mut inner = group.to_vec();
            inner.push(name[1..].to_string());
            collect(&path, &inner, out);
        } else {
            out.push(Template {
                needs_name: name.contains("{name}"),
                name,
                path: path.to_string_lossy().into_owned(),
                is_dir,
                group: group.to_vec(),
            });
        }
    }
}

/// Values for the placeholders (FR-TPL-04).
pub struct Values {
    pub name: String,
    pub date: String,
    pub year: String,
    pub month: String,
    pub day: String,
    pub user: String,
    pub parent: String,
}

impl Values {
    /// `date` is today as (year, month, day); `date_format` uses yyyy, MM and dd.
    pub fn new(name: &str, parent: &Path, (year, month, day): (i32, u32, u32), date_format: &str) -> Self {
        let (year, month, day) = (year.to_string(), format!("{month:02}"), format!("{day:02}"));
        let format = if date_format.trim().is_empty() { "yyyy-MM-dd" } else { date_format };
        Self {
            name: name.to_string(),
            date: format.replace("yyyy", &year).replace("MM", &month).replace("dd", &day),
            year,
            month,
            day,
            user: std::env::var("USERNAME").or_else(|_| std::env::var("USER")).unwrap_or_default(),
            parent: parent.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        }
    }

    pub fn fill(&self, text: &str) -> String {
        text.replace("{name}", &self.name)
            .replace("{date}", &self.date)
            .replace("{year}", &self.year)
            .replace("{month}", &self.month)
            .replace("{day}", &self.day)
            .replace("{user}", &self.user)
            .replace("{parent}", &self.parent)
    }
}

/// Copies a template into `parent`, filling in placeholders in names and in
/// the contents of text files. Returns the new item's path (FR-TPL-03 to 05).
pub fn create(template: &Path, parent: &Path, values: &Values) -> Result<PathBuf, String> {
    let name = template.file_name().map(|n| n.to_string_lossy().into_owned()).ok_or("This template has no name.")?;
    let target_name = values.fill(&name);
    fileops::validate_name(&target_name)?;
    let target = fileops::free_name(parent, &target_name, Naming::Numbered);
    copy_filled(template, &target, values).map_err(|e| fileops::describe(&e, &target))?;
    Ok(target)
}

fn copy_filled(source: &Path, target: &Path, values: &Values) -> std::io::Result<()> {
    if source.is_dir() {
        fs::create_dir(target)?;
        for entry in fs::read_dir(source)? {
            let entry = entry?;
            let name = values.fill(&entry.file_name().to_string_lossy());
            copy_filled(&entry.path(), &target.join(name), values)?;
        }
        return Ok(());
    }
    let ext = source.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    if TEXT_EXTENSIONS.contains(&ext.as_str()) {
        if let Ok(text) = fs::read_to_string(source) {
            return fs::write(target, values.fill(&text));
        }
    }
    fileops::copy_file(source, target).map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(name: &str, parent: &Path) -> Values {
        Values::new(name, parent, (2026, 10, 31), "yyyy-MM-dd")
    }

    #[test]
    fn lists_templates_with_groups_and_name_flags() {
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("Memo.docx"), "").unwrap();
        fs::create_dir_all(dir.path().join("_Projects/{date} {name}")).unwrap();
        fs::write(dir.path().join(".hidden"), "").unwrap();
        let found = list(&[dir.path().to_path_buf()]).templates;
        assert_eq!(found.len(), 2, "hidden files are left out");
        let memo = found.iter().find(|t| t.name == "Memo.docx").unwrap();
        assert!(!memo.needs_name && memo.group.is_empty());
        let project = found.iter().find(|t| t.name == "{date} {name}").unwrap();
        assert_eq!(project.group, ["Projects"]);
        assert!(project.is_dir && project.needs_name);
    }

    #[test]
    fn creates_a_folder_template_with_placeholders_in_names_and_text() {
        let dir = tempfile::tempdir().unwrap();
        let template = dir.path().join("tpl/{date} {name}");
        fs::create_dir_all(&template).unwrap();
        fs::write(template.join("Notes - {name}.md"), "# {name}\nBy {user} on {date} in {parent}").unwrap();
        fs::write(template.join("logo.png"), [0u8, 1, 2]).unwrap();
        let parent = dir.path().join("Vendors");
        fs::create_dir(&parent).unwrap();

        let created = create(&template, &parent, &values("Acme renewal", &parent)).unwrap();
        assert_eq!(created, parent.join("2026-10-31 Acme renewal"));
        let notes = fs::read_to_string(created.join("Notes - Acme renewal.md")).unwrap();
        assert!(notes.starts_with("# Acme renewal\nBy "));
        assert!(notes.ends_with("on 2026-10-31 in Vendors"));
        assert_eq!(fs::read(created.join("logo.png")).unwrap(), [0, 1, 2]);

        let again = create(&template, &parent, &values("Acme renewal", &parent)).unwrap();
        assert_eq!(again, parent.join("2026-10-31 Acme renewal (2)"));
    }

    #[test]
    fn a_name_with_bad_characters_is_refused() {
        let dir = tempfile::tempdir().unwrap();
        let template = dir.path().join("{name}.txt");
        fs::write(&template, "").unwrap();
        assert!(create(&template, dir.path(), &values("a/b", dir.path())).is_err());
    }
}
