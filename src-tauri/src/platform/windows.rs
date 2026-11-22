use std::fs::Metadata;
use std::os::windows::ffi::OsStrExt;
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

/// Home, the online drives (REQ-028), and every drive letter (FR-SB-01).
pub fn roots(home: &Path) -> Vec<Root> {
    let mut roots = vec![Root::new("Home", home.to_string_lossy(), "home")];
    let cloud = super::cloud_roots();
    // SAFETY: GetLogicalDrives takes no arguments and only returns a bit mask.
    let mask = unsafe { GetLogicalDrives() };
    let mut drives = Vec::new();
    for i in 0..26u32 {
        if mask & (1 << i) == 0 {
            continue;
        }
        let letter = (b'A' + i as u8) as char;
        let path = format!("{letter}:\\");
        // Google Drive's own drive letter is listed once, as an online drive.
        if cloud.iter().any(|c| c.path.eq_ignore_ascii_case(&path)) {
            continue;
        }
        let kind = match drive_type(&path) {
            DRIVE_REMOTE => "network",
            DRIVE_REMOVABLE | DRIVE_CDROM => "removable",
            _ => "drive",
        };
        drives.push(Root::new(format!("{letter}:"), path, kind));
    }
    roots.extend(cloud);
    roots.extend(drives);
    roots
}

fn drive_type(root: &str) -> u32 {
    let wide: Vec<u16> = root.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: `wide` is a valid, NUL-terminated UTF-16 string that outlives the call.
    unsafe { GetDriveTypeW(wide.as_ptr()) }
}

/// Online drives Windows knows about (REQ-028): OneDrive's own settings,
/// the cloud sync roots registered with Windows (OneDrive, Dropbox, Proton
/// Drive and others that use the Cloud Files API), and Google Drive's drive.
pub fn cloud_candidates(_home: &Path) -> Vec<crate::cloud::Candidate> {
    use crate::cloud::Candidate;
    let mut found = Vec::new();
    for var in ["OneDriveCommercial", "OneDriveConsumer", "OneDrive"] {
        if let Some(path) = std::env::var_os(var) {
            found.push(Candidate { path: path.into(), provider: "onedrive", name: String::new() });
        }
    }
    for (key, path) in sync_roots() {
        if let Some(provider) = provider_from_key(&key) {
            found.push(Candidate { path: path.into(), provider, name: String::new() });
        }
    }
    // Google Drive for desktop shows as a drive labelled "Google Drive".
    // SAFETY: GetLogicalDrives takes no arguments and only returns a bit mask.
    let mask = unsafe { GetLogicalDrives() };
    for i in 0..26u32 {
        let root = format!("{}:\\", (b'A' + i as u8) as char);
        if mask & (1 << i) != 0
            && drive_type(&root) == DRIVE_FIXED
            && volume_label(&root).as_deref() == Some("Google Drive")
        {
            found.push(Candidate { path: root.into(), provider: "gdrive", name: "Google Drive".into() });
        }
    }
    found
}

const DRIVE_FIXED: u32 = 3;

/// The provider named by a SyncRootManager key such as `OneDrive!S-1-5-…!Personal`.
fn provider_from_key(key: &str) -> Option<&'static str> {
    let name = key.split('!').next().unwrap_or(key).to_lowercase();
    if name.contains("onedrive") {
        Some("onedrive")
    } else if name.contains("dropbox") {
        Some("dropbox")
    } else if name.contains("google") {
        Some("gdrive")
    } else if name.contains("proton") {
        Some("proton")
    } else {
        None
    }
}

fn volume_label(root: &str) -> Option<String> {
    use windows_sys::Win32::Storage::FileSystem::GetVolumeInformationW;
    let wide: Vec<u16> = root.encode_utf16().chain(std::iter::once(0)).collect();
    let mut label = [0u16; 261];
    // SAFETY: `wide` is NUL-terminated and `label` is a writable buffer of the size given.
    let ok = unsafe {
        GetVolumeInformationW(
            wide.as_ptr(),
            label.as_mut_ptr(),
            label.len() as u32,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            0,
        )
    };
    (ok != 0).then(|| String::from_utf16_lossy(&label[..label.iter().position(|&c| c == 0).unwrap_or(0)]))
}

/// (key name, folder) for every cloud sync root registered for this computer:
/// `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager\<key>\UserSyncRoots`.
fn sync_roots() -> Vec<(String, String)> {
    use windows_sys::Win32::System::Registry::{
        RegCloseKey, RegEnumKeyExW, RegEnumValueW, RegOpenKeyExW, HKEY, HKEY_LOCAL_MACHINE, KEY_READ, REG_SZ,
    };
    let wide = |s: &str| s.encode_utf16().chain(std::iter::once(0)).collect::<Vec<u16>>();
    let open = |parent: HKEY, name: &str| -> Option<HKEY> {
        let name = wide(name);
        let mut key: HKEY = std::ptr::null_mut();
        // SAFETY: `name` is NUL-terminated and `key` receives the opened handle.
        (unsafe { RegOpenKeyExW(parent, name.as_ptr(), 0, KEY_READ, &mut key) } == 0).then_some(key)
    };
    let mut found = Vec::new();
    let Some(manager) = open(HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SyncRootManager")
    else {
        return found;
    };
    for index in 0.. {
        let mut name = [0u16; 512];
        let mut len = name.len() as u32;
        // SAFETY: `name` is writable for `len` UTF-16 units; the other outputs are optional.
        let status = unsafe {
            RegEnumKeyExW(
                manager,
                index,
                name.as_mut_ptr(),
                &mut len,
                std::ptr::null(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                std::ptr::null_mut(),
            )
        };
        if status != 0 {
            break;
        }
        let key_name = String::from_utf16_lossy(&name[..len as usize]);
        let Some(user_roots) = open(manager, &format!("{key_name}\\UserSyncRoots")) else { continue };
        for value_index in 0.. {
            let mut value_name = [0u16; 256];
            let mut value_len = value_name.len() as u32;
            let mut data = [0u16; 1024];
            let mut data_len = (data.len() * 2) as u32;
            let mut kind = 0u32;
            // SAFETY: the name and data buffers are writable for the sizes given (data in bytes).
            let status = unsafe {
                RegEnumValueW(
                    user_roots,
                    value_index,
                    value_name.as_mut_ptr(),
                    &mut value_len,
                    std::ptr::null(),
                    &mut kind,
                    data.as_mut_ptr().cast(),
                    &mut data_len,
                )
            };
            if status != 0 {
                break;
            }
            if kind == REG_SZ {
                let units = &data[..(data_len as usize / 2).min(data.len())];
                let text =
                    String::from_utf16_lossy(&units[..units.iter().position(|&c| c == 0).unwrap_or(units.len())]);
                if !text.is_empty() {
                    found.push((key_name.clone(), text));
                }
            }
        }
        // SAFETY: the key was opened above.
        unsafe { RegCloseKey(user_roots) };
    }
    // SAFETY: the key was opened above.
    unsafe { RegCloseKey(manager) };
    found
}

/// Whether a folder can have an icon of its own (REQ-025). Windows only uses
/// a folder's `desktop.ini` when the folder is read-only or a system folder,
/// which is also how Downloads, Pictures and online drives are marked.
pub fn may_have_own_icon(_path: &Path, meta: &Metadata) -> bool {
    meta.is_dir() && meta.file_attributes() & (FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_SYSTEM) != 0
}

/// True for network shares and removable or optical drives (spec 4.3).
pub fn is_slow_device(path: &Path) -> bool {
    let root = match path.components().next() {
        Some(Component::Prefix(prefix)) => match prefix.kind() {
            Prefix::Disk(letter) | Prefix::VerbatimDisk(letter) => format!("{}:\\", letter as char),
            Prefix::UNC(..) | Prefix::VerbatimUNC(..) => return true,
            _ => return false,
        },
        _ => return false,
    };
    matches!(drive_type(&root), DRIVE_REMOVABLE | DRIVE_REMOTE | DRIVE_CDROM)
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

/// The system icon for a folder, a file type or one file, as a 32×32 PNG
/// (FR-ICON-02). File types are asked for with SHGFI_USEFILEATTRIBUTES, so no
/// file is touched. The caller makes sure a single file is local and not
/// online-only, so reading its icon never downloads it (FR-SYNC-03).
pub fn icon(target: &super::IconTarget) -> Option<super::Icon> {
    use windows_sys::Win32::Storage::FileSystem::{FILE_ATTRIBUTE_DIRECTORY, FILE_ATTRIBUTE_NORMAL};
    use windows_sys::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED};
    use windows_sys::Win32::UI::Shell::{
        SHGetFileInfoW, SHFILEINFOW, SHGFI_ICON, SHGFI_LARGEICON, SHGFI_USEFILEATTRIBUTES,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::DestroyIcon;

    let (path, attributes, flags) = match target {
        super::IconTarget::Folder => ("folder".to_string(), FILE_ATTRIBUTE_DIRECTORY, SHGFI_USEFILEATTRIBUTES),
        super::IconTarget::Extension(ext) if ext.is_empty() => {
            ("file".to_string(), FILE_ATTRIBUTE_NORMAL, SHGFI_USEFILEATTRIBUTES)
        }
        super::IconTarget::Extension(ext) => (format!("file.{ext}"), FILE_ATTRIBUTE_NORMAL, SHGFI_USEFILEATTRIBUTES),
        super::IconTarget::File(path) | super::IconTarget::Dir(path) => (path.to_string_lossy().into_owned(), 0, 0),
    };
    let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
    let mut info = SHFILEINFOW::default();
    // SAFETY: COM is set up for this thread (a repeat call only returns S_FALSE),
    // `wide` is NUL-terminated and `info` is a properly sized, writable struct.
    let found = unsafe {
        CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32);
        SHGetFileInfoW(
            wide.as_ptr(),
            attributes,
            &mut info,
            std::mem::size_of::<SHFILEINFOW>() as u32,
            SHGFI_ICON | SHGFI_LARGEICON | flags,
        )
    };
    if found == 0 || info.hIcon.is_null() {
        return None;
    }
    let png = icon_to_png(info.hIcon);
    // SAFETY: the icon came from SHGetFileInfoW with SHGFI_ICON, so it is ours to destroy.
    unsafe { DestroyIcon(info.hIcon) };
    png.map(|bytes| super::Icon { bytes, mime: "image/png" })
}

/// Reads an icon's pixels and encodes them as PNG.
fn icon_to_png(icon: windows_sys::Win32::UI::WindowsAndMessaging::HICON) -> Option<Vec<u8>> {
    use windows_sys::Win32::Graphics::Gdi::{
        CreateCompatibleDC, DeleteDC, DeleteObject, GetDIBits, GetObjectW, BITMAP, BITMAPINFO, BITMAPINFOHEADER,
        BI_RGB, DIB_RGB_COLORS, HBITMAP,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::{GetIconInfo, ICONINFO};

    let mut info = ICONINFO::default();
    // SAFETY: `icon` is a valid icon handle and `info` is writable.
    if unsafe { GetIconInfo(icon, &mut info) } == 0 {
        return None;
    }
    let (colour, mask) = (info.hbmColor, info.hbmMask);

    // 32-bit, top-down pixels of a bitmap.
    let read = |bitmap: HBITMAP, width: i32, height: i32| -> Option<Vec<u8>> {
        let mut header = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: width,
                biHeight: -height,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut pixels = vec![0u8; (width * height * 4) as usize];
        // SAFETY: a memory DC is created and deleted here; `pixels` holds exactly
        // `height` rows of `width` 32-bit pixels, as `header` describes.
        let lines = unsafe {
            let dc = CreateCompatibleDC(std::ptr::null_mut());
            let lines =
                GetDIBits(dc, bitmap, 0, height as u32, pixels.as_mut_ptr().cast(), &mut header, DIB_RGB_COLORS);
            DeleteDC(dc);
            lines
        };
        (lines == height).then_some(pixels)
    };

    let result = (|| {
        if colour.is_null() {
            return None; // A black-and-white icon: rare, and the built-in icon is better.
        }
        let mut bitmap: BITMAP = unsafe { std::mem::zeroed() };
        // SAFETY: `colour` is a bitmap handle and `bitmap` has the size passed.
        if unsafe { GetObjectW(colour, std::mem::size_of::<BITMAP>() as i32, (&mut bitmap as *mut BITMAP).cast()) } == 0
        {
            return None;
        }
        let (width, height) = (bitmap.bmWidth, bitmap.bmHeight);
        if width <= 0 || height <= 0 || width > 256 || height > 256 {
            return None;
        }
        let mut pixels = read(colour, width, height)?;
        // Old icons have no alpha channel: take transparency from the mask.
        if pixels.chunks_exact(4).all(|p| p[3] == 0) {
            let mask_pixels = read(mask, width, height)?;
            for (pixel, m) in pixels.chunks_exact_mut(4).zip(mask_pixels.chunks_exact(4)) {
                pixel[3] = if m[0] == 0 { 255 } else { 0 };
            }
        }
        // BGRA -> RGBA
        for pixel in pixels.chunks_exact_mut(4) {
            pixel.swap(0, 2);
        }
        encode_png(&pixels, width as u32, height as u32)
    })();

    // SAFETY: GetIconInfo created these bitmaps for us to delete.
    unsafe {
        if !colour.is_null() {
            DeleteObject(colour);
        }
        if !mask.is_null() {
            DeleteObject(mask);
        }
    }
    result
}

fn encode_png(rgba: &[u8], width: u32, height: u32) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    let mut encoder = png::Encoder::new(&mut out, width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(png::BitDepth::Eight);
    let mut writer = encoder.write_header().ok()?;
    writer.write_image_data(rgba).ok()?;
    writer.finish().ok()?;
    Some(out)
}

/// Open With (FR-OPEN-02): the system's own "How do you want to open this
/// file?" dialog, which also opens the file with the app picked. `parent` is
/// the main window, so the dialog stays in front of it. Blocks until it closes.
pub fn open_with_dialog(path: &Path, parent: isize) -> Result<(), String> {
    use windows_sys::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED};
    use windows_sys::Win32::UI::Shell::{
        SHOpenWithDialog, OAIF_ALLOW_REGISTRATION, OAIF_EXEC, OAIF_REGISTER_EXT, OPENASINFO,
    };
    /// HRESULT_FROM_WIN32(ERROR_CANCELLED): the dialog was closed without a choice.
    const CANCELLED: i32 = 0x8007_04C7_u32 as i32;
    let wide: Vec<u16> = path.as_os_str().encode_wide().chain(std::iter::once(0)).collect();
    let info = OPENASINFO {
        pcszFile: wide.as_ptr(),
        pcszClass: std::ptr::null(),
        oaifInFlags: OAIF_ALLOW_REGISTRATION | OAIF_REGISTER_EXT | OAIF_EXEC,
    };
    // SAFETY: COM is set up for this thread; `wide` and `info` outlive the call.
    let result = unsafe {
        CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32);
        SHOpenWithDialog(parent as _, &info)
    };
    if result >= 0 || result == CANCELLED {
        Ok(())
    } else {
        Err(format!("Could not show Open With (error 0x{:08X}).", result as u32))
    }
}

/// Explorer's Quick access folders (REQ-029): the pinned and frequent folders,
/// in Explorer's order. Recent files in the list are left out. Read only;
/// pinning stays in Explorer.
pub fn quick_access(_home: &Path) -> Vec<super::Place> {
    use windows::core::w;
    use windows::Win32::System::Com::{CoInitializeEx, CoTaskMemFree, COINIT_APARTMENTTHREADED};
    use windows::Win32::UI::Shell::{
        BHID_EnumItems, IEnumShellItems, IShellItem, SHCreateItemFromParsingName, SIGDN, SIGDN_FILESYSPATH,
        SIGDN_NORMALDISPLAY,
    };

    fn name_of(item: &IShellItem, kind: SIGDN) -> Option<String> {
        // SAFETY: GetDisplayName returns a string we own and must free with CoTaskMemFree.
        unsafe {
            let text = item.GetDisplayName(kind).ok()?;
            let value = text.to_string().ok();
            CoTaskMemFree(Some(text.0 as *const _));
            value
        }
    }

    let mut places = Vec::new();
    // SAFETY: COM is set up for this thread; every interface is released when dropped.
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
        let Ok(folder) =
            SHCreateItemFromParsingName::<_, _, IShellItem>(w!("shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}"), None)
        else {
            return places;
        };
        let Ok(items) = folder.BindToHandler::<_, IEnumShellItems>(None, &BHID_EnumItems) else { return places };
        loop {
            let mut batch = [None];
            let mut fetched = 0u32;
            if items.Next(&mut batch, Some(&mut fetched)).is_err() || fetched == 0 {
                break;
            }
            let Some(item) = batch[0].take() else { break };
            let Some(path) = name_of(&item, SIGDN_FILESYSPATH) else { continue };
            // Only folders; a network folder is listed without checking it.
            if !(is_slow_device(Path::new(&path)) || Path::new(&path).is_dir()) {
                continue;
            }
            let name = name_of(&item, SIGDN_NORMALDISPLAY).unwrap_or_else(|| path.clone());
            places.push(super::Place { name, path });
            if places.len() >= 50 {
                break;
            }
        }
    }
    places
}
