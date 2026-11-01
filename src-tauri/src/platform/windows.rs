use std::fs::Metadata;
use std::os::windows::fs::MetadataExt;
use std::path::{Component, Path, Prefix};

use windows_sys::Win32::Storage::FileSystem::{GetDriveTypeW, GetLogicalDrives};

use super::Root;
use crate::model::SyncState;

const FILE_ATTRIBUTE_READONLY: u32 = 0x1;
const FILE_ATTRIBUTE_HIDDEN: u32 = 0x2;
const FILE_ATTRIBUTE_SYSTEM: u32 = 0x4;
const FILE_ATTRIBUTE_ARCHIVE: u32 = 0x20;
const FILE_ATTRIBUTE_COMPRESSED: u32 = 0x800;
const FILE_ATTRIBUTE_ENCRYPTED: u32 = 0x4000;
const FILE_ATTRIBUTE_OFFLINE: u32 = 0x1000;
const FILE_ATTRIBUTE_RECALL_ON_OPEN: u32 = 0x4_0000;
const FILE_ATTRIBUTE_PINNED: u32 = 0x8_0000;
const FILE_ATTRIBUTE_UNPINNED: u32 = 0x10_0000;
const FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS: u32 = 0x40_0000;

const DRIVE_REMOVABLE: u32 = 2;
const DRIVE_REMOTE: u32 = 4;
const DRIVE_CDROM: u32 = 5;

pub fn is_hidden(_name: &str, meta: &Metadata) -> bool {
    meta.file_attributes() & FILE_ATTRIBUTE_HIDDEN != 0
}

/// Explorer-style attribute letters, e.g. `RHA`.
pub fn attributes(meta: &Metadata) -> String {
    let attributes = meta.file_attributes();
    [
        (FILE_ATTRIBUTE_READONLY, 'R'),
        (FILE_ATTRIBUTE_HIDDEN, 'H'),
        (FILE_ATTRIBUTE_SYSTEM, 'S'),
        (FILE_ATTRIBUTE_ARCHIVE, 'A'),
        (FILE_ATTRIBUTE_COMPRESSED, 'C'),
        (FILE_ATTRIBUTE_ENCRYPTED, 'E'),
        (FILE_ATTRIBUTE_OFFLINE, 'O'),
    ]
    .iter()
    .filter(|(flag, _)| attributes & flag != 0)
    .map(|(_, letter)| *letter)
    .collect()
}

/// Sync state from file attributes only, so reading it never downloads
/// the file (FR-SYNC-03). "Syncing" and "Error" need the Cloud Files API
/// and are added in milestone M5.
pub fn sync_state(meta: &Metadata) -> SyncState {
    let attributes = meta.file_attributes();
    if attributes & (FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS | FILE_ATTRIBUTE_RECALL_ON_OPEN | FILE_ATTRIBUTE_OFFLINE) != 0
    {
        SyncState::OnlineOnly
    } else if attributes & FILE_ATTRIBUTE_PINNED != 0 {
        SyncState::Pinned
    } else if attributes & FILE_ATTRIBUTE_UNPINNED != 0 {
        SyncState::Local
    } else {
        SyncState::None
    }
}

/// Home, OneDrive folders, and every drive letter (FR-SB-01).
pub fn roots(home: &Path) -> Vec<Root> {
    let mut roots = vec![Root { name: "Home".into(), path: home.to_string_lossy().into_owned(), kind: "home" }];
    let mut seen = std::collections::HashSet::new();
    for var in ["OneDriveCommercial", "OneDriveConsumer", "OneDrive"] {
        if let Ok(path) = std::env::var(var) {
            if Path::new(&path).is_dir() && seen.insert(path.to_lowercase()) {
                let name =
                    Path::new(&path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or(path.clone());
                roots.push(Root { name, path, kind: "cloud" });
            }
        }
    }
    // SAFETY: GetLogicalDrives takes no arguments and only returns a bit mask.
    let mask = unsafe { GetLogicalDrives() };
    for i in 0..26u32 {
        if mask & (1 << i) == 0 {
            continue;
        }
        let letter = (b'A' + i as u8) as char;
        let path = format!("{letter}:\\");
        let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
        // SAFETY: `wide` is a valid, NUL-terminated UTF-16 string that outlives the call.
        let kind = match unsafe { GetDriveTypeW(wide.as_ptr()) } {
            DRIVE_REMOTE => "network",
            DRIVE_REMOVABLE | DRIVE_CDROM => "removable",
            _ => "drive",
        };
        roots.push(Root { name: format!("{letter}:"), path, kind });
    }
    roots
}

/// True for network shares and removable or optical drives, so their I/O
/// runs on the separate slow-path threads (spec 4.3).
pub fn is_slow_path(path: &Path) -> bool {
    let root = match path.components().next() {
        Some(Component::Prefix(prefix)) => match prefix.kind() {
            Prefix::Disk(letter) | Prefix::VerbatimDisk(letter) => format!("{}:\\", letter as char),
            Prefix::UNC(..) | Prefix::VerbatimUNC(..) => return true,
            _ => return false,
        },
        _ => return false,
    };
    let wide: Vec<u16> = root.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: `wide` is a valid, NUL-terminated UTF-16 string that outlives the call.
    let drive_type = unsafe { GetDriveTypeW(wide.as_ptr()) };
    matches!(drive_type, DRIVE_REMOVABLE | DRIVE_REMOTE | DRIVE_CDROM)
}

/// Opens a terminal in `dir`: the configured command, else Windows Terminal,
/// else PowerShell (FR-OPEN-03).
pub fn open_terminal(dir: &Path, configured: &str) -> Result<(), String> {
    use std::process::Command;
    let spawned = if !configured.is_empty() {
        Command::new(configured).current_dir(dir).spawn()
    } else {
        Command::new("wt").arg("-d").arg(dir).spawn().or_else(|_| Command::new("powershell").current_dir(dir).spawn())
    };
    spawned.map(|_| ()).map_err(|e| format!("Could not open a terminal: {e}"))
}

/// Shows the item selected in Explorer.
pub fn reveal(path: &Path) -> Result<(), String> {
    let mut select = std::ffi::OsString::from("/select,");
    select.push(path.as_os_str());
    std::process::Command::new("explorer")
        .arg(select)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("Could not open Explorer: {e}"))
}

const DROPEFFECT_MOVE: u32 = 2;

fn drop_effect_format() -> u32 {
    let name: Vec<u16> = "Preferred DropEffect".encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: `name` is a valid, NUL-terminated UTF-16 string that outlives the call.
    unsafe { windows_sys::Win32::System::DataExchange::RegisterClipboardFormatW(name.as_ptr()) }
}

/// Marks the files on the clipboard as cut or copied, so Explorer moves or
/// copies them when it pastes (FR-OP-01).
pub fn set_clipboard_cut(cut: bool) {
    use windows_sys::Win32::System::DataExchange::{CloseClipboard, OpenClipboard, SetClipboardData};
    use windows_sys::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
    let effect: u32 = if cut { DROPEFFECT_MOVE } else { 5 }; // 5 = copy | link
                                                             // SAFETY: standard clipboard protocol; the memory handle is handed to the
                                                             // clipboard, which owns it after SetClipboardData succeeds.
    unsafe {
        if OpenClipboard(std::ptr::null_mut()) == 0 {
            return;
        }
        let memory = GlobalAlloc(GMEM_MOVEABLE, std::mem::size_of::<u32>());
        if !memory.is_null() {
            let target = GlobalLock(memory) as *mut u32;
            if !target.is_null() {
                *target = effect;
                GlobalUnlock(memory);
                SetClipboardData(drop_effect_format(), memory);
            }
        }
        CloseClipboard();
    }
}

/// Whether the files on the clipboard were cut (Some(true)) or copied.
pub fn clipboard_cut() -> Option<bool> {
    use windows_sys::Win32::System::DataExchange::{
        CloseClipboard, GetClipboardData, IsClipboardFormatAvailable, OpenClipboard,
    };
    use windows_sys::Win32::System::Memory::{GlobalLock, GlobalUnlock};
    let format = drop_effect_format();
    // SAFETY: standard clipboard protocol; the data is only read while locked.
    unsafe {
        if IsClipboardFormatAvailable(format) == 0 || OpenClipboard(std::ptr::null_mut()) == 0 {
            return None;
        }
        let handle = GetClipboardData(format);
        let mut result = None;
        if !handle.is_null() {
            let value = GlobalLock(handle) as *const u32;
            if !value.is_null() {
                result = Some(*value & DROPEFFECT_MOVE != 0);
                GlobalUnlock(handle);
            }
        }
        CloseClipboard();
        result
    }
}
