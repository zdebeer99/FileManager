# File Catalog Specification Document

| | |
|---|---|
| Version | 0.1.0 (Stable release) |
| Date | 2026-11-03 |
| Source | [RequirementsDocument.md](RequirementsDocument.md) (2026-10-31) |
| Status | Released. This document describes File Catalog **0.1.0** as built. |
| Changes | 0.1.0: First stable release. M5 cancelled (decision log 13.1, 2026-11-03). The document now describes only what 0.1.0 does; everything planned but not built is listed in Section 12. Document versions restart at the application version. |
| | Earlier drafts 0.2 to 0.5 (2026-10-31 to 2026-11-01): platforms decided, review decisions merged, scope reduced, M1 to M4 built. See the decision log (13.1). |

---

## 1. Introduction

### 1.1 Purpose

This document describes File Catalog 0.1.0: its architecture, user interface, user-facing functions, configuration files and performance targets. Each requirement has an ID (`FR-…` for functional, `NFR-…` for non-functional), so it can be traced to the code and tested on its own. IDs are kept from the earlier drafts; the IDs of requirements that are not built are listed in Section 12.

### 1.2 Product summary

File Catalog is an ultra-fast, keyboard-driven desktop file manager for information workers, such as project managers and people who manage many folders, online and offline. It does everything a normal file explorer does, but its main focus is **organising** files and making large numbers of files **easy to navigate and reach**.

Its guiding principle is **no lock-in**: everything File Catalog creates (folders, shortcuts, web links, templates, settings) is a plain file or folder that still works in Windows Explorer, any Linux file manager, or any other file manager, without File Catalog installed.

### 1.3 Scope

**In 0.1.0:** the application layout, navigation, tabs, bookmarks, favourites, sorting and filtering, per-folder view persistence, Quick Filter, Quick Find (file and folder names), creating files, folders, shortcuts, web links and items from templates, file operations with a background job queue and undo, clipboard exchange and drag and drop with other apps, the command palette, customisable key bindings and toolbar, light and dark themes, and human-readable configuration.

**Not in 0.1.0:** see Section 12.

### 1.4 Definitions

| Term | Meaning |
|---|---|
| **Item** | A file, folder, shortcut or web link shown in the content list. |
| **Shortcut** | An OS-native link to a file or folder: `.lnk` on Windows, a symbolic link on Linux. |
| **Web link** | A `.url` file (Internet Shortcut format) that points to a web address. |
| **Favourite** | A pinned folder in the sidebar Favourites view (like Explorer's *Quick access*). |
| **Bookmark** | A named, grouped pointer to a folder, file or URL, shown in the Bookmark Bar and the sidebar Bookmarks view. |
| **Folder settings** | The saved view of one folder, stored only in the app settings folder (Section 8.4). |
| **Command** | A named application action with an ID, e.g. `edit.rename`. Every menu item, toolbar button, key binding and palette entry calls a command. |
| **Job** | A long-running background task, such as a copy, move, duplicate or delete, that reports progress. |

### 1.5 Conventions

- Every requirement in Sections 2 to 10 is built in 0.1.0. The words **Must** and **Should** from the drafts are no longer used for them.
- Requirements that are planned but not built are in Section 12, with their original IDs.
- Default key bindings are the same on Windows and Linux.

---

## 2. Target platforms

| Platform | Support level | Notes |
|---|---|---|
| Windows 10 (22H2) / Windows 11, x64 and ARM64 | **Primary** | Full feature set, including `.lnk` shortcuts and a basic Sync status column. Installers: MSI and NSIS `.exe`. |
| Linux x64 (Ubuntu 22.04 LTS+, Debian 12+, Fedora 38+; WebKitGTK 4.1) | **Supported** | Full feature set except the Sync status column. Shortcuts are symbolic links; Delete uses the freedesktop.org Trash. Packages: AppImage, `.deb`, `.rpm`. |
| macOS | **Not supported** | Not built or tested, but the design must not block it (Section 2.1). |

### 2.1 Keeping macOS possible later

- All OS-specific code (hidden files, attributes, sync state, roots, slow-path detection, shortcuts, Trash, terminal) lives behind the **platform layer** in the Rust core (`src-tauri/src/platform/`), with a Windows and a Unix implementation. Adding macOS later means adding to that layer, not changing the rest of the app.
- The Elm UI never checks which OS it runs on. It asks the backend which features are available (for example whether the Sync status column is supported) and shows or hides them.
- Only cross-platform crates are used outside the platform layer. Paths are always handled as `PathBuf`/`OsString` in Rust, never as Windows-style strings.
- Key bindings are stored as `Ctrl+…`; a later macOS version can map `Ctrl` to `Cmd` when loading them.
- Settings, cache and log locations come from the `directories` crate, which already knows the macOS locations.

---

## 3. Technology decisions

### 3.1 Backend and UI container: **Rust** (chosen over Zig)

| Criterion | Rust | Zig |
|---|---|---|
| Desktop web-view shell | **Tauri 2**: mature, small binaries, fast start, uses the system web view (WebView2 on Windows, WebKitGTK on Linux; WKWebView for a later macOS version) | No mature equivalent; would need a custom web-view binding |
| File system ecosystem | `notify` (watching), `ignore`/`walkdir` (parallel walking), `trash`, `windows-sys`, `toml_edit` | Few libraries; most would need to be written from scratch |
| Language stability | Stable (1.x) | Pre-1.0; breaking changes between releases |
| Safe multithreading | Checked by the compiler; `tokio` + `rayon` | Manual |

**Decision:** Rust (stable toolchain, edition 2021, minimum 1.85) with **Tauri 2.x** as the window and web-view container.

### 3.2 Frontend: **Elm 0.19.3**

- Elm **0.19.3** is used. `elm.json` sets `"elm-version": "0.19.3"`, and the compiler is pinned as a project dev dependency (npm `elm@0.19.3-0`) so every build uses the same version.
- All UI is written in Elm, using The Elm Architecture (Model / Update / View).
- Elm talks to the Rust backend only through **ports**. A small, hand-written JavaScript bridge (`ui/static/bridge.js`) connects Elm ports to Tauri's `invoke`, channel and event APIs. No other JavaScript application logic is allowed.
- Styling uses plain CSS with CSS custom properties for the light and dark themes. No CSS framework.
- Build: `elm make --optimize`, then minify with `esbuild` (`ui/build.mjs`). Target bundle size: ≤ 250 KB minified, ≤ 80 KB gzipped.

### 3.3 Main Rust crates

| Area | Crate |
|---|---|
| App shell / IPC | `tauri` 2.x |
| Async runtime | `tokio` |
| CPU-parallel work | `rayon` |
| Directory walking / search | `ignore` (WalkParallel), `walkdir` |
| File system watching | `notify` |
| Recycle Bin / Trash | `trash` |
| Settings | `serde`, `toml_edit` (keeps user comments and formatting) |
| Config paths | `directories` |
| Fuzzy matching | Done in the UI (Elm), so the palette needs no backend call |
| Windows APIs | `windows-sys` |
| Logging | `tracing`, `tracing-appender` |

---

## 4. Architecture

### 4.1 Overview

```
┌──────────────────────────── Tauri window (system web view) ────────────────────────────┐
│  Elm application                                                                        │
│   Model ── Update ── View          Virtualised list, palette, dialogs, layout           │
│        │  ports (out: requests)  ▲ ports (in: responses, events)                        │
│  bridge.js  ──── invoke(cmd, args) / Channel ───►  ◄──── emit(event, payload) ─────     │
└───────────────────────────────────────┬─────────────────────────────────────────────────┘
                                        │ Tauri IPC
┌───────────────────────────────────────▼─────────────────────────────────────────────────┐
│  Rust core                                                                              │
│  ┌────────────┐ ┌──────────────┐ ┌───────────┐ ┌────────────┐ ┌───────────────────────┐ │
│  │ Commands   │ │ Listing +    │ │ Watcher   │ │ Job queue  │ │ Settings              │ │
│  │ (IPC API)  │ │ DirCache     │ │ (notify)  │ │ copy/move/ │ │ (TOML load/save,      │ │
│  │            │ │              │ │           │ │ duplicate/ │ │  live reload, folder  │ │
│  │            │ │              │ │           │ │ delete     │ │  views)               │ │
│  └────────────┘ └──────────────┘ └───────────┘ └────────────┘ └───────────────────────┘ │
│  ┌────────────┐ ┌──────────────┐ ┌───────────┐ ┌─────────────────────────────────────┐  │
│  │ Bookmarks, │ │ Templates    │ │ Quick     │ │ Platform layer (hidden files,       │  │
│  │ session    │ │              │ │ Find      │ │ attributes, sync state, roots, …)   │  │
│  └────────────┘ └──────────────┘ └───────────┘ └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Responsibilities

| Layer | Owns | Does not own |
|---|---|---|
| **Elm UI** | Layout, focus, selection, sorting and filtering of the loaded list, palette fuzzy matching, key handling, dialogs | Any file system access |
| **Rust core** | All file system access, directory caching, watching, search, file operations, settings files, platform integrations | UI state (except the saved session and settings) |

### 4.3 Threading model

**Rule: the UI never waits for the file system.** All file system work runs on threads that are separate from both the UI (web view) thread and the main window thread. The UI only sends requests and receives messages; it never blocks on a reply.

| Thread(s) | Runs | Never runs |
|---|---|---|
| **UI thread** (web view) | Elm: drawing, input, sorting and filtering of the already-loaded list | Any call that waits for Rust; all calls are asynchronous and answered by messages |
| **Main thread** (Tauri) | The window and event loop only | Any file system call |
| **Tokio worker threads** | IPC handlers. Every command is `async` and hands its work to the pools below. | Long blocking calls |
| **Local I/O pool** | Listing and reading local disks | Network, removable or cloud paths |
| **Slow-path I/O pool** (separate, small) | Listing and reading network shares, removable drives and cloud folders (chosen by `platform::is_slow_path`) | Local disks |
| **Job thread** | The job queue: copy, move, duplicate, delete | — |
| **Find thread** + rayon | Quick Find's parallel walk | — |

- Slow paths get their **own threads**, so a share that hangs can never hold up local folders or the UI. Calls to such paths time out after `network.timeoutSeconds` (default 5 s) and show a clear *"not reachable"* state.
- A failing task never takes the app down: the pools catch and log panics, and commands return user-readable error messages.
- Jobs and searches can be **cancelled** at any time.

### 4.4 IPC contract

Elm sends every request with a new id and stores what it is waiting for under that id. Replies and streamed events carry the id, so Elm drops stale replies (for example, a listing for a folder the user has already left). Command names are snake_case; JSON uses camelCase.

**Commands (Elm → Rust):**

| Command | Payload | Response |
|---|---|---|
| `app_init` | — | settings, session, start-up snapshot, platform capabilities |
| `dir_list` | `{ path }` (streamed) | `Cached`, then `Chunk`s or a `Patch`, then `Done` or `Error` |
| `watch_set` | `{ paths }` | — (changes arrive as `dir-changed`) |
| `resolve_path` / `list_subfolders` / `nearest_folder` | `{ path }` | resolved path / sub-folders / the closest existing folder above it |
| `free_space` | `{ path }` | free bytes on the volume |
| `open_item` / `open_terminal` / `reveal_item` | `{ path }` | — |
| `settings_set` | `{ key, value }` (dotted key, e.g. `layout.sidebar.width`) | — |
| `session_save` | session state | — |
| `folder_view_get` / `folder_view_save` / `folder_view_reset` / `folder_view_file` | `{ path, view?, applyToSubfolders? }` | resolved view / file path |
| `bookmarks_get` / `bookmarks_edit` | `{ edit: { op, … } }` | favourites, bookmarks, warnings |
| `job_start` / `job_cancel` / `job_pause` / `job_resolve` | `{ request: { kind, sources, dest?, permanent } }` / `{ jobId, … }` | job id; then `job-progress` and `job-conflict` events |
| `undo_last` | — | `{ ok } \| { error }` |
| `fs_rename` / `fs_create` | `{ path, newName }` / `{ parent, item: { kind, … } }` | new path |
| `fs_create_shortcuts` | `{ parent, targets }` | new paths |
| `templates_list` / `templates_folder` / `fs_create_from_template` | `{ parent, template, name, today }` | templates / folder / new path |
| `clipboard_write_text` / `clipboard_set_files` / `clipboard_get_files` | `{ text }` / `{ paths, cut }` / — | — / — / files and cut flag |
| `drag_out` | `{ paths }` | — |
| `find_start` / `find_cancel` | `{ searchId, root, query, clock: { nowMs, utcOffsetMinutes } }` / `{ searchId }` | streamed `batch` (items with `folder`, scanned, found) every 50 ms, then `done` |
| `keybindings_get` / `keybindings_set` / `keybindings_file` | — / `{ changes: [{ command, when, keys, removeDefaults }] }` / — | bindings with line numbers and warnings / file path |
| `toolbar_get` / `toolbar_save` / `toolbar_file` | — / `{ style, items }` / — | style, items, defaults, warnings / file path |
| `perf_mark` / `app_exit` | — | — |

**Events (Rust → Elm):** `dir-changed`, `settings-changed`, `bookmarks-changed`, `keybindings-changed`, `toolbar-changed`, `job-progress`, `job-conflict`, `file-drop`. Every event must also be in the `listen` list in `bridge.js`.

**Item record (shared shape):**

```json
{
  "name": "Contract 2026.docx",
  "path": "C:\\Vendors\\Acme\\Contract 2026.docx",
  "kind": "file | folder | shortcut | weblink | symlink",
  "size": 48213,
  "created": "2026-09-14T08:12:44Z",
  "modified": "2026-10-30T16:05:02Z",
  "ext": "docx",
  "hidden": false,
  "readonly": false,
  "sync": "none | local | pinned | onlineOnly | syncing | error",
  "target": null
}
```

### 4.5 Caching

| Cache | Location | Contents | Invalidation |
|---|---|---|---|
| Directory cache | Memory, LRU | Item records per folder | Watcher events; Refresh (`F5`) |
| Start-up snapshot | Disk, in the cache folder | Listings of the folders open in tabs when the app last closed | Shown immediately at start-up, then refreshed in the background |

The cache folder is the OS cache location (`%LOCALAPPDATA%\FileCatalog\cache` on Windows, `$XDG_CACHE_HOME/filecatalog` (default `~/.cache/filecatalog`) on Linux). Cache files are **not** settings: they may be binary and can be deleted at any time without losing anything.

### 4.6 Directory listing pipeline

1. Elm sends `dir_list`. If the folder is cached, Rust sends the cached items straight away (`Cached`).
2. Rust reads the folder on the right I/O pool and streams items in chunks, so the first rows appear before the whole folder is read.
3. A cached listing is checked against the disk and corrected with a `Patch`, not reloaded.
4. Folders open in any tab are watched. Changes are debounced (100 ms) and sent as patches (added / removed / changed), not full reloads.

---

## 5. User interface

### 5.1 Layout

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ File  Edit  View  Go  Bookmarks  Tools  Window  Help                 (Menu Bar) │
├──────────────────────────────────────────────────────────────────────────────────┤
│ [◀][▶][▲][⟳] │ [+Folder][+File][Template▾] │ [Cut][Copy][Paste][Del] │ [💾 View] (Toolbar)│
├──────────────────────────────────────────────────────────────────────────────────┤
│ ★ Acme  ★ Contracts  ★ Weekly notes  📁 Projects ▾  🌐 Intranet      (Bookmark Bar)│
├──────────────────────────────────────────────────────────────────────────────────┤
│ [ Vendors × ] [ Acme renewal × ] [ Downloads × ] [+]                    (Tab Bar)│
├──────────────────────────────────────────────────────────────────────────────────┤
│ 🖴 C: › Vendors › Acme › 2026                 [ Filter…        ] (Address Bar)   │
├───────────────┬──────────────────────────────────────────────────────────────────┤
│ [🌳][★][🔖]    │ Name ▾           Date modified     Size   Sync                   │
│ Sidebar        │ 📁 Archive       2026-10-02               ☁                      │
│ (tree /        │ 📄 Contract.docx 2026-10-30        48 KB  ✔                      │
│  favourites /  │ 🔗 Old contract  2026-09-01         1 KB                         │
│  bookmarks)    │ 🌐 Supplier site 2026-10-29         1 KB    (Content container)  │
├───────────────┴──────────────────────────────────────────────────────────────────┤
│ 24 items (3 folders, 21 files) · 2 selected (96 KB) · Copying 3/12 ████░░ 40% (Status Bar)│
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **FR-UI-01** Every bar and panel above, except the content container, can be shown or hidden from the **View** menu and the command palette. Visibility is saved in `settings.toml`.
- **FR-UI-02** The sidebar can be placed on the left or right edge, resized by dragging its splitter, or hidden. Position and width are saved.
- **FR-UI-04** Light and dark themes, following the OS by default, with a manual choice in **View › Theme**.
- **FR-UI-05** Every function can be reached with the keyboard alone. Focus is always visible. `F6` / `Shift+F6` moves focus between regions.

### 5.2 Menu Bar

**FR-MENU-01** All commands are grouped in a standard menu layout. Each menu item shows its current key binding. The Menu Bar opens with `Alt` / `F10` and `Alt+<letter>`. Items planned for a later version are shown disabled.

| Menu | Items |
|---|---|
| **File** | New Tab, New Folder, New File…, New Shortcut…, New Web Link…, New from Template ▸, Open, Open in Terminal, Show in File Manager, Close Tab, Exit |
| **Edit** | Undo, Cut, Copy, Paste, Paste as Shortcut, Duplicate, Copy Path, Copy Name, Rename, Delete, Delete Permanently, Select All, Invert Selection, Select None |
| **View** | Menu Bar / Toolbar / Bookmark Bar / Tab Bar / Address Bar / Sidebar / Status Bar (toggles), Customise Toolbar…, Sidebar ▸ (Folder Tree, Favourites, Bookmarks, On the Left, On the Right), View Mode ▸ (Details), Columns ▸, Sort By ▸, Show Hidden Files, Show File Extensions, Quick Filter, Clear All Filters, Save View for This Folder, Save View for This Folder and Subfolders, Reset View for This Folder, Open Folder Settings File, Theme ▸, Refresh |
| **Go** | Back, Forward, Up, Home, Go to Address, Recent Folders ▸, Favourites ▸, Pin This Folder to Favourites |
| **Bookmarks** | Bookmark This Folder, Bookmark Selected Item, Manage Bookmarks, Open Bookmarks File, All Bookmarks ▸ |
| **Tools** | Quick Find, Quick Filter, Command Palette, Commands…, Save Selection as Template, Edit Templates Folder, Open Settings File, Open Key Bindings File, Open Toolbar File |
| **Window** | Jobs, Next Tab, Previous Tab, Tabs ▸, Duplicate Tab, Reopen Closed Tab |
| **Help** | Keyboard Shortcuts, Open Log Folder, About File Catalog |

### 5.3 Toolbar

- **FR-TB-01** The toolbar holds buttons that call commands. Its contents, order, separators, flexible space and button style (icon, icon and text, text) are set in `toolbar.toml` (Section 8.5).
- **FR-TB-02** *Customise Toolbar* (right-click on the toolbar, or **View › Customise Toolbar…**) adds, removes and reorders buttons with *Move Up* / *Move Down*. Changes are written back to `toolbar.toml`.
- **FR-TB-03** Buttons whose command cannot run right now (e.g. *Paste* with an empty clipboard) are shown disabled.
- **FR-TB-04** The default toolbar includes the **Save View** button (FR-VIEW-05).

### 5.4 Bookmark Bar

- **FR-BB-01** Shows the bookmarks in the `bar` group as buttons. Groups appear as drop-down menus.
- **FR-BB-02** Clicking opens the target (folder: navigate; file: open with its default app; URL: open in the default browser). Middle-click or `Ctrl+click` on a folder opens it in a new tab.
- **FR-BB-03** Dragging a folder, file or URL onto the bar creates a bookmark.
- **FR-BB-04** Right-click menu: Open, Open in New Tab, Edit, Delete, New Group.

### 5.5 Tab Bar

- **FR-TAB-01** Each tab has its own location, back/forward history, selection, scroll position, Quick Filter and sort.
- **FR-TAB-02** New tab (`Ctrl+T`) opens the current folder; close (`Ctrl+W`, middle-click); reopen closed tab (`Ctrl+Shift+T`, last 20 kept); switch (`Ctrl+Tab`, `Ctrl+Shift+Tab`, `Ctrl+1…9`); reorder by dragging; duplicate.
- **FR-TAB-04** Open tabs and their locations are restored on start-up (setting `restoreTabs`).
- **FR-TAB-05** Dropping files onto a tab copies or moves them into that tab's folder.

### 5.6 Address Bar

- **FR-ADDR-01** Shows the current path in **breadcrumb mode**. Each segment can be clicked to navigate. The `›` separator between segments opens a drop-down of that folder's sub-folders.
- **FR-ADDR-02** Clicking empty space in the bar, or pressing `Ctrl+L` / `Alt+D`, switches to **edit mode**: a text box with the full path selected. It completes folder names with `Tab`; `Enter` navigates; `Esc` cancels.
- **FR-ADDR-03** Accepts drive paths, UNC paths (`\\server\share`), `~`, and environment variables (`%USERPROFILE%`, `$HOME`). Typing a file path opens that file's folder with the file selected.
- **FR-ADDR-04** Long paths shrink from the left: the first segment and the last segments stay visible, and hidden middle segments go into a `…` drop-down.
- **FR-ADDR-05** The Quick Filter box (FR-QF) sits at the right end of the Address Bar.

### 5.7 Sidebar

**FR-SB-01** The sidebar has three modes, switched with buttons at its top or with `Ctrl+Shift+1…3`:

| Mode | Content |
|---|---|
| **Tree** | Folder tree, starting from Favourites, Home, drives/volumes, network locations and cloud roots. It loads lazily, expands to follow the current folder, and supports keyboard navigation (arrows, `→` expand, `←` collapse, type-ahead). |
| **Favourites** | A user-ordered list of pinned folders, reordered with *Move Up* / *Move Down*. *Pin to Favourites* is available from the right-click menu, the Go menu and the palette. |
| **Bookmarks** | All bookmarks in their groups, as a tree, with edit and delete. |

- **FR-SB-02** Dropping items onto a folder in the Tree or Favourites copies or moves them there (FR-COPY-06).

### 5.8 Content container

- **FR-CC-01** **Details view**: one row per item, with sortable, resizable and reorderable columns (Section 5.8.2). Any column can be shown or hidden by right-clicking a column header or with **View › Columns ▸**, and the choice is part of the folder view (Section 6.5). Visible by default: **Name**, **Date modified**, **Date created**, **Size**, **Sync status** (Sync status only on Windows).
- **FR-CC-03** The list is **virtualised**: only visible rows (plus a buffer) are drawn, so folders with 100,000 items scroll smoothly (NFR-PERF-05).
- **FR-CC-04** Selection: click, `Ctrl+click`, `Shift+click`, `Ctrl+A`, keyboard (arrows, `Home`/`End`, `PgUp`/`PgDn`, with `Shift` to extend and `Ctrl` + `Space` to toggle).
- **FR-CC-05** Type-ahead: typing letters when the list has focus jumps to the next item starting with those letters (reset after 1 s).
- **FR-CC-06** `Enter` / double-click opens the item. Folders open in the current tab; `Ctrl+Enter` opens a folder in a new tab. `Backspace` / `Alt+Up` goes to the parent folder.
- **FR-CC-07** Right-click menus (also `Shift+F10` and the Menu key) on items and on empty space, with the commands that apply.
- **FR-CC-08** Drag and drop: inside the app, out of the window to other apps, and files dropped in from other apps.
- **FR-CC-10** Empty and error states: *"This folder is empty"*, *"Access denied"*, *"Location not available"* (with a *Retry* button).

#### 5.8.1 Sync status column

**FR-SYNC-01 (basic, Windows only)** The Sync status column shows the cloud state of items in folders managed by a cloud sync provider (OneDrive, SharePoint, Dropbox and others that use the Windows Cloud Files API). It is read from file attributes only:

| State | Icon | Detected from |
|---|---|---|
| Online-only | ☁ | `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` or `FILE_ATTRIBUTE_OFFLINE` |
| Always keep on this device | ✔ (filled) | `FILE_ATTRIBUTE_PINNED` |
| Available locally | ✔ (outline) | Other items in a sync folder |
| (blank) | | Not in a sync root |

- **FR-SYNC-03** Reading sync status never triggers a file download (a "hydration").
- **FR-SYNC-04** Linux: the Sync status column is hidden and not offered in the column list.

#### 5.8.2 Available columns

**FR-COL-01** These columns can be chosen:

| Column | Windows | Linux |
|---|---|---|
| Name | ✔ | ✔ |
| Date modified | ✔ | ✔ |
| Date created | ✔ | ✔ (where the file system records it) |
| Date accessed | ✔ | ✔ |
| Size | ✔ | ✔ |
| Type (from the item kind and extension, e.g. *DOCX file*) | ✔ | ✔ |
| Extension | ✔ | ✔ |
| Attributes | ✔ `R H S A` … | ✔ permissions (`rwxr-xr-x`) |
| Link target (shortcuts, web links) | ✔ | ✔ |
| Sync status | ✔ | — |
| Folder (search results only) | ✔ | ✔ |

### 5.10 Status bar

**FR-STAT-01** Shows, from left to right:
- Item counts: `N items (F folders, D files)`. When filtered: `showing M of N`.
- Selection: `S selected (total size)`.
- Running jobs: the active job's name, progress bar and percentage. Clicking it opens the **Jobs panel** (all jobs, with pause, cancel, details and errors).
- Search progress while Quick Find runs, and the hint for the next key of a chord.
- Free space on the current volume.
- A temporary message area for results (e.g. *"3 items copied"*), which fades after a few seconds.

---

## 6. Functional specification

### 6.1 Navigation

- **FR-NAV-01** Back (`Alt+Left`, mouse back button), Forward (`Alt+Right`, mouse forward button), Up (`Alt+Up`, `Backspace`), Home (`Alt+Home`, goes to the configured home folder), Refresh (`F5`).
- **FR-NAV-02** Each tab keeps its own back/forward history.
- **FR-NAV-03** When going back or up, the folder you came from is selected and scrolled into view.
- **FR-NAV-04** Recent folders (across all tabs) are kept in the session and shown in **Go › Recent Folders** and the command palette.

### 6.2 Sorting

- **FR-SORT-01** Sort by any visible column, by clicking its header (click again to reverse) or with **View › Sort By**.
- **FR-SORT-02** Name sorting is *natural* (`File 2` before `File 10`) and case-insensitive.
- **FR-SORT-03** Folders are listed before files by default (`foldersFirst`).
- **FR-SORT-04** Secondary sort: `Shift+click` on a second column header.
- **FR-SORT-05** Re-sorting 100,000 items must finish in under 150 ms (NFR-PERF-06).

### 6.3 Filtering and Quick Filter

#### 6.3.1 Quick Filter (by name)

- **FR-QF-01** `Ctrl+F` (or `/`) moves focus to the Quick Filter box. Typing filters the current list **as you type**, without touching the disk.
- **FR-QF-02** Matching rules:
  - Plain text: case-insensitive *contains* match on the name.
  - Words separated by spaces: every word must match (AND).
  - `*` and `?` wildcards: glob match on the whole name (e.g. `*.pdf`).
  - A leading `!` negates a word (e.g. `contract !draft`).
  - `ext:pdf,docx` limits by extension.
- **FR-QF-03** Matching parts of names are highlighted. The status bar shows `showing M of N`.
- **FR-QF-04** `Esc` clears the filter and returns focus to the list. `Down` / `Enter` moves focus into the filtered list.
- **FR-QF-05** The filter belongs to the tab and is cleared on navigation (setting `keepFilterOnNavigate = false`).
- **FR-QF-06** A filter icon is shown on the tab and in the Address Bar while a filter is active, so the user always knows the list is filtered.

#### 6.3.2 Column filters (Excel-style)

- **FR-CF-01** Each column header in Details view has a filter button that opens a drop-down, like Excel's filter on a table:
  - A search box.
  - A checklist of distinct values, with *(Select All)*. For **Type/Extension** and **Sync status**: one entry per value. For **Date** columns: grouped by year › month › day, plus quick choices (*Today*, *Yesterday*, *This week*, *Last 7 days*, *This month*, *This year*). For **Size**: buckets (*Empty*, *< 16 KB*, *16 KB–1 MB*, *1–16 MB*, *16–128 MB*, *> 128 MB*) and a custom *between* range.
  - *Clear filter*.
- **FR-CF-02** Column filters combine with each other and with the Quick Filter (AND).
- **FR-CF-03** A column with an active filter shows a filled filter icon. **View › Clear All Filters** (`Ctrl+Shift+L`) removes them all.

### 6.4 Bookmarks and Favourites

#### 6.4.1 Bookmark data

Each bookmark has a `name`, a `target` (path or URL) and a `group` (path of group names, e.g. `["bar", "Vendors"]`). The kind (folder, file or URL) follows from the target.

#### 6.4.2 Functions

- **FR-BM-01** *Bookmark This Folder* (`Ctrl+D`) and *Bookmark Selected Item* open a small dialog (name, group) that can be confirmed with `Enter`.
- **FR-BM-02** Bookmarks are stored in `bookmarks.toml` (Section 8.6) and can be edited by hand. Outside edits are picked up live.
- **FR-BM-03** A bookmark whose target no longer exists is shown greyed out with a warning icon, and offers *Locate…* and *Delete*.
- **FR-BM-04** A bookmark can be opened with its own key binding: the `bookmark.open` command with `args = { name = "…" }` in `keybindings.toml`.

#### 6.4.3 Favourites

- **FR-FAV-01** Pin or unpin a folder to Favourites from the right-click menu, the Go menu, the palette, or by dragging it into the Favourites view.
- **FR-FAV-02** Stored as an ordered list in `bookmarks.toml` under `[favourites]`.

### 6.5 Per-folder view persistence ("Quick persist")

- **FR-VIEW-01** A folder's **view** is: visible columns (order and widths), sort columns and direction, folders-first and show hidden.
- **FR-VIEW-02** Without saved settings, a folder uses the **default view** from `settings.toml`.
- **FR-VIEW-03** Changes to the view affect only the current tab and are **not** saved automatically. A dot appears on the *Save View* button when the current view differs from the saved one.
- **FR-VIEW-04** View settings are resolved in this order (first match wins, field by field):
  1. Saved settings for this exact folder (Section 8.4).
  2. Saved settings of the nearest parent folder that has `applyToSubfolders = true`.
  3. The default view in `settings.toml`.
- **FR-VIEW-05** The **Save View** toolbar button (`Ctrl+S`) saves the current view for the current folder with one click, with no dialog, in the app settings folder. The status bar confirms *"View saved for <folder>"*.
- **FR-VIEW-06** The drop-down arrow next to *Save View* offers: *Save for this folder and subfolders*, *Reset to default view*, *Open folder settings file*.
- **FR-VIEW-07** Saving a view never writes anything into the folder itself, so it works the same for read-only, shared and cloud folders.

### 6.6 Quick Find (search in folder and sub-folders)

- **FR-FIND-01** `Ctrl+Shift+F` (or `F3`, or `?` in the palette) opens Quick Find for the current folder. Results are shown in a **search results tab** that works like a normal list: it can be sorted, filtered and acted on, and has an extra **Folder** column (path relative to the search root). *Refresh* runs the search again. A folder opened from the results opens in a new tab, so the results stay.
- **FR-FIND-02** It searches **file and folder names**, recursively, using the same match syntax as the Quick Filter (FR-QF-02), plus:
  - `size:>10mb`, `size:<1kb`
  - `modified:today`, `modified:>2026-01-01`, `modified:7d`
  - `type:folder`, `type:file`
  - `in:subfolder-name`
- **FR-FIND-03** Results stream in while the search runs (batched every 50 ms). The status bar shows the number of folders scanned and items found, and the search can be cancelled (`Esc`).
- **FR-FIND-04** Search options (`[search]` in `settings.toml`): include hidden files (default off), follow symbolic links/junctions (default off, with loop protection), maximum depth (default unlimited), maximum results (default 10,000), and skip online-only cloud *folders* (default on, to avoid downloading).
- **FR-FIND-05** The search runs in parallel across folders using all CPU cores (`ignore::WalkParallel`), without reading file contents.
- **FR-FIND-06** The last 20 searches are saved and offered in the palette.

### 6.7 Create items

- **FR-NEW-01** **New Folder** (`Ctrl+Shift+N`) creates `New folder` (with `(2)`, `(3)` … if the name is taken) and starts renaming it at once.
- **FR-NEW-02** **New File** (`Ctrl+N`) asks for a name, including the extension, and creates an empty file.
- **FR-NEW-03** **New Shortcut** asks for a target and a name. It creates a `.lnk` (Windows) or a symbolic link (Linux). **Paste as Shortcut** (`Ctrl+Shift+V`) creates shortcuts to the items on the clipboard.
- **FR-NEW-04** **New Web Link** asks for a URL and a name (filled in from the domain). It creates a `.url` file, which works on all platforms.
- **FR-NEW-05** All new items are selected and scrolled into view after they are created.

### 6.8 Create from template

- **FR-TPL-01** Templates are ordinary files and folders inside the **templates folders** (default `<app settings>/templates/`; more folders can be added in `[templates]` in `settings.toml`, e.g. a shared team templates folder).
- **FR-TPL-02** **New from Template** (`Ctrl+Alt+N`, **File › New from Template ▸**, and the toolbar drop-down) lists templates in a menu that follows the templates folder's structure. Sub-folders whose name starts with `_` are menu groups, not templates.
- **FR-TPL-03** A **file** template is copied into the current folder. A **folder** template is copied with all its content (recursively).
- **FR-TPL-04** Placeholders in file and folder names are replaced when copying:

  | Placeholder | Replaced with |
  |---|---|
  | `{name}` | The name the user enters |
  | `{date}` | Today's date, `YYYY-MM-DD` (format set by `templates.dateFormat`) |
  | `{year}`, `{month}`, `{day}` | Parts of today's date |
  | `{user}` | The OS user name |
  | `{parent}` | The name of the destination folder |

  Example: template folder `{date} {name}` containing `Notes - {name}.docx` → `2026-10-31 Acme renewal/Notes - Acme renewal.docx`. Dates use the user's time zone.
- **FR-TPL-05** Placeholders in the **content** of plain text files (`.txt`, `.md`, `.csv`, `.html`, `.json`, `.toml`, `.ini`, `.xml`) are replaced too. Binary and Office files are copied unchanged.
- **FR-TPL-06** *Save Selection as Template* copies the selected file or folder into the templates folder. *Edit Templates Folder* opens it.

### 6.9 Command palette

- **FR-CMD-01** `Ctrl+P` opens the command palette: a centred input with a list of results below, similar to VS Code's *Quick Open*.
- **FR-CMD-02** Modes, chosen by the first character:

  | Prefix | Mode | Searches |
  |---|---|---|
  | (none) | Go to | Recent folders, favourites, bookmarks, items in the current folder (first 5,000) |
  | `>` | Commands | All commands, by name, with their key binding shown (`Ctrl+Shift+P` opens straight into this mode) |
  | `@` | Bookmarks | All bookmarks |
  | `/` | Path | Path entry with sub-folder completion and `Tab` |
  | `?` | Find | Starts Quick Find in the current folder with the rest of the text |
  | `#` | Tabs | Open tabs |

- **FR-CMD-03** Fuzzy matching in the UI, with matched letters highlighted. Results are ranked by match quality, then by how often and how recently they were picked.
- **FR-CMD-04** `Up`/`Down` choose, `Enter` runs, `Ctrl+Enter` opens a folder result in a new tab, `Esc` closes.
- **FR-CMD-05** Every command in the application (Appendix A) is available in the palette, including ones that are not in a menu.

### 6.10 Key bindings

- **FR-KEY-01** Every command can be bound to one or more keys. Key bindings are defined in `keybindings.toml` (Section 8.3). User bindings override the defaults, and menus, the toolbar and the palette show the current keys.
- **FR-KEY-02** Chords are supported (e.g. `Ctrl+K Ctrl+B`). A hint shows in the status bar after the first key.
- **FR-KEY-03** A binding may have a `when` context: `list`, `tree`, `addressBar`, `palette`, `filter`, or `global` (default).
- **FR-KEY-04** **Help › Keyboard Shortcuts** (`Ctrl+/`) shows a searchable list of all commands and their bindings, and lets the user record a new key or chord, remove a binding or reset it. Conflicts are shown before saving. Changes are written to `keybindings.toml`.
- **FR-KEY-05** Invalid entries in `keybindings.toml` are skipped and reported with their line number, never a crash. The file is reloaded live when it changes.

### 6.11 Opening items

- **FR-OPEN-01** Files open with the OS default app. Shortcuts open their target. Web links open in the default browser.
- **FR-OPEN-03** **Open in Terminal** opens the configured terminal (`general.terminal`; default on Windows: Windows Terminal, else PowerShell; on Linux: `$TERMINAL`, else `x-terminal-emulator`, else `gnome-terminal` / `konsole`) in the current folder.
- **FR-OPEN-04** **Copy Path** (`Ctrl+Shift+C`) copies the full path(s) of the selection, one per line. **Copy Name** copies names only.
- **FR-OPEN-05** **Show in File Manager** shows the item in Explorer or the system file manager.

### 6.12 File operations

#### 6.12.1 General

- **FR-OP-01** Copy (`Ctrl+C`), Cut (`Ctrl+X`), Paste (`Ctrl+V`), Rename (`F2`), Delete (`Del`), Delete Permanently (`Shift+Del`). These use the OS clipboard, so files can be copied to and from Explorer and other file managers, both ways. On Windows a cut sets Explorer's *cut* marker.
- **FR-OP-02** Copy, move, duplicate and delete run as background **jobs** on their own thread (Section 4.3). The UI stays usable. Jobs run one after another.
- **FR-OP-03** Each job shows progress (bytes and items, speed, time left) in the status bar and the Jobs panel, and can be paused or cancelled. Large files are copied in pieces, so progress moves inside a file and pause and cancel work part way.
- **FR-OP-04** Errors on single items (access denied, file in use, path too long) do not stop the job. They are collected and shown with *Retry*, *Skip* and *Show in folder*.

#### 6.12.2 Copy and move

- **FR-COPY-01** Moving within the same volume is a rename (instant). Moving between volumes is copy, then delete the source.
- **FR-COPY-02** Copies keep timestamps.
- **FR-COPY-03** Files are first written to a temporary name in the destination folder and renamed when complete, so a cancelled or failed copy never leaves a half-written file under the real name.
- **FR-COPY-04** **Name conflicts** open a dialog showing both files (size, date) with: *Replace*, *Skip*, *Keep both* (adds ` (2)`), *Replace if newer*, plus *Apply to all remaining conflicts*.
- **FR-COPY-05** Copying or moving a folder into itself or one of its own sub-folders is refused with a clear message.
- **FR-COPY-06** Drag and drop onto folders, the folder tree, Favourites, tabs and the Bookmark Bar: same drive = move, other drive = copy (like Explorer). Holding `Ctrl` forces copy, `Shift` forces move, `Alt` creates shortcuts.

#### 6.12.3 Rename

- **FR-REN-01** `F2` renames in place. The name without the extension is selected first; pressing `F2` again cycles through: whole name → extension only → name only.
- **FR-REN-02** Names are checked as you type (characters not allowed on the platform, reserved names such as `CON`/`NUL` on Windows, names that already exist, path length). An error is shown next to the edit box and `Enter` is blocked until it is fixed.
- **FR-REN-03** Changing the extension asks for confirmation (setting `confirmExtensionChange`).

#### 6.12.4 Delete

- **FR-DEL-01** `Del` moves items to the Recycle Bin / Trash. A confirmation is shown only when the setting `confirmDelete` is on (default: off, since it can be undone).
- **FR-DEL-02** `Shift+Del` deletes permanently, always after a confirmation that names the items (or the count, and the first names).
- **FR-DEL-03** If the item cannot go to the Recycle Bin (e.g. network drives), the user is told it will be deleted permanently and must confirm.

#### 6.12.5 Undo

- **FR-UNDO-01** `Ctrl+Z` undoes the last operation from this session: rename (rename back), move (move back), copy and duplicate (send the copies to the Recycle Bin), create (send to the Recycle Bin), delete to Recycle Bin (restore). Permanent deletes cannot be undone.

#### 6.12.6 Duplicate

- **FR-DUP-01** **Duplicate** makes a copy of each selected item next to the original, named like Explorer does: `Report - Copy.docx`, then `Report - Copy (2).docx`. Runs as a job.

---

## 7. Non-functional requirements

### 7.1 Performance

Reference hardware: 4-core CPU (2020 or newer), 8 GB RAM, NVMe SSD. Targets apply to both **Windows 11** (WebView2 already installed) and **Ubuntu 24.04 LTS**. Times are 95th percentile. In 0.1.0 they are checked by hand; measurement in CI is planned (Section 12). Start-up on Windows is still to be measured.

| ID | Measure | Target |
|---|---|---|
| **NFR-PERF-01** | Cold start: process launch → window shown with the last folder listed and usable | **≤ 500 ms** |
| NFR-PERF-02 | Warm start (app recently run) | ≤ 300 ms |
| NFR-PERF-03 | Navigate to a local folder with 1,000 items → list shown | ≤ 50 ms |
| NFR-PERF-04 | Navigate to a local folder with 10,000 items → first rows shown / all loaded | ≤ 50 ms / ≤ 300 ms |
| NFR-PERF-05 | Scrolling a 100,000-item list | 60 fps, no frame over 32 ms |
| NFR-PERF-06 | Sort or Quick Filter keystroke on 100,000 items | ≤ 150 ms (≤ 16 ms for 5,000 items) |
| NFR-PERF-07 | Command palette open / first results | ≤ 50 ms / ≤ 30 ms per keystroke |
| NFR-PERF-08 | Quick Find, 500,000 local items | First results ≤ 200 ms; full scan ≤ 3 s |
| NFR-PERF-09 | Key press → visible response, any UI action | ≤ 50 ms |
| NFR-PERF-10 | Memory use: idle with 5 tabs | ≤ 150 MB total (including the web view) |
| NFR-PERF-11 | Installer / app size | ≤ 15 MB |

**How a fast start is reached:**
1. Rust opens the window at once, while reading settings and the start-up snapshot.
2. The Elm bundle is small and built into the app.
3. The first listing comes from the start-up snapshot (Section 4.5) and is then refreshed in the background.
4. Anything not needed for the first view (the folder tree, bookmarks, templates) loads after the first listing. The UI shows the first folder 11–16 ms after it starts (measured on Linux).

### 7.2 Reliability and data safety

- **NFR-REL-01** No operation may lose user data. File copies use temp-then-rename (FR-COPY-03); moves between volumes delete the source only after the copy has finished.
- **NFR-REL-02** Settings files are written atomically (write to a temp file, then rename). The previous version is kept as `<name>.bak`.
- **NFR-REL-03** A settings file with errors never stops the app from starting. Each section is read on its own: the app uses defaults for the broken section, shows a warning with the file name and error, and does **not** overwrite the broken file.
- **NFR-REL-04** A crash in a background task must not crash the UI. Panics are caught and logged.
- **NFR-REL-05** Network or cloud locations that become unavailable are shown as *not available*, not as empty folders.

### 7.3 Usability

- **NFR-UX-01** All functions can be reached by keyboard (FR-UI-05).
- **NFR-UX-04** UI text is in English, with all strings kept in one Elm module (`Text.elm`) so they can be translated later.

### 7.4 Security and privacy

- **NFR-SEC-01** No telemetry, no accounts and no network access, except opening URLs in the user's browser.
- **NFR-SEC-02** Tauri capabilities are limited to the defined IPC commands. The web view cannot load remote content. A strict Content Security Policy allows only the app's own scripts.
- **NFR-SEC-03** Paths from the UI are always checked by the Rust core; the UI is never trusted to decide what is safe.
- **NFR-SEC-04** Settings are read only from the app settings folder. File Catalog never reads or acts on configuration files found inside the folders it shows.

### 7.5 Maintainability

- **NFR-MNT-01** Rust: `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` pass. Elm: `elm-format` is used on changed files.
- **NFR-MNT-02** Rust unit and integration tests cover file operations, jobs, settings, key bindings, toolbar, templates and search (`cargo test`).
- **NFR-MNT-03** Logs (`tracing`) go to `<app settings>/logs/`, one file per day, kept for 7 days. The default level is `info`.

---

## 8. Configuration and settings files

### 8.1 Principles

- All settings are **TOML** files, easy for people to read and edit (chosen over INI because TOML supports lists and nested tables without inventing a syntax).
- Files are written with `toml_edit`, so the user's **comments, order and formatting are kept** when the app saves changes.
- Files are **watched**: when edited outside the app they are reloaded at once (`settings-changed`, `bookmarks-changed`, `keybindings-changed`, `toolbar-changed`).
- Only values that differ from the default need to be in the file.

### 8.2 Locations

| OS | App settings folder |
|---|---|
| Windows | `%APPDATA%\FileCatalog\` |
| Linux | `$XDG_CONFIG_HOME/filecatalog/` (default `~/.config/filecatalog/`) |

A **portable mode** is used when a file `portable.toml` sits next to the program: all settings are then stored in a `settings/` folder next to the program.

```
FileCatalog/
├── settings.toml        # General settings (8.3)
├── keybindings.toml     # Key binding overrides (8.3)
├── toolbar.toml         # Toolbar layout (8.5)
├── bookmarks.toml       # Bookmarks and favourites (8.6)
├── session.toml         # Open tabs, recent folders, palette and search history (written by the app)
├── folders/             # Per-folder view settings (8.4)
│   └── <name>-<hash>.toml
├── templates/           # Templates (6.8)
└── logs/
```

### 8.3 `settings.toml` and `keybindings.toml`

```toml
# File Catalog settings
# Only values that differ from the defaults are needed.

[general]
startupFolder   = "last"          # "last" | "home" | a path
restoreTabs     = true
homeFolder      = "~"
theme           = "system"        # "system" | "light" | "dark"
confirmDelete   = false
confirmExtensionChange = true
keepFilterOnNavigate = false
terminal        = "wt"            # command used by Open in Terminal

[layout]
menuBar = true
toolbar = true
bookmarkBar = true
tabBar = true
addressBar = true
statusBar = true
sidebar = { visible = true, side = "left",  width = 260, mode = "tree" }

[view.default]
mode        = "details"
columns     = ["name", "modified", "created", "size", "sync"]
sort        = [{ column = "name", direction = "asc" }]
foldersFirst = true
showHidden  = false
showExtensions = true
dateFormat  = "yyyy-MM-dd HH:mm"

[search]
includeHidden   = false
followLinks     = false
maxDepth        = 0               # 0 = no limit
maxResults      = 10000
skipOnlineOnlyFolders = true

[templates]
folders    = ["templates"]        # relative to the settings folder, or full paths
dateFormat = "yyyy-MM-dd"

[network]
timeoutSeconds = 5
```

```toml
# keybindings.toml — your key bindings. These override the defaults.
# Use key = "" to remove a command's default keys.

[[bind]]
key = "Ctrl+E"
command = "find.open"

[[bind]]
key = "Ctrl+K Ctrl+B"
command = "view.toggleSidebar"

[[bind]]
key = "Alt+1"
command = "bookmark.open"
args = { name = "Acme" }
```

### 8.4 Folder settings

Folder settings hold a folder's saved **view** (Section 6.5). They are stored **only in the app settings folder**, one file per folder:

`<app settings>/folders/<folder name>-<8-char hash of full path>.toml`

File Catalog never writes settings into the folders it shows, so shared, read-only and cloud folders are never changed.

- **FR-FS-01** Each file stores the full `path` of the folder it belongs to, so it is easy to find and edit by hand.
- **FR-FS-03** Deleting a folder settings file resets that folder to the default view.

```toml
# Acme-3f9a12c0.toml — saved view for one folder.
# Safe to delete; the folder then uses the default view.

path = 'C:\Vendors\Acme'
applyToSubfolders = false

[view]
columns = ["name", "modified", "size", "sync", "linkTarget"]
sort    = [{ column = "modified", direction = "desc" }]
foldersFirst = true
```

### 8.5 `toolbar.toml`

```toml
style = "icon"                  # "icon" | "iconText" | "text"

items = [
  "nav.back", "nav.forward", "nav.up", "nav.refresh",
  "|",
  "new.folder", "new.file", "new.fromTemplate",
  "|",
  "edit.cut", "edit.copy", "edit.paste", "edit.delete",
  "|",
  "view.saveForFolder",
  "->",                         # push the rest to the right
  "palette.open",
]
```

`"|"` is a separator and `"->"` is flexible space. Unknown command ids are skipped and reported.

### 8.6 `bookmarks.toml`

```toml
[favourites]
paths = ['C:\Vendors', 'C:\Projects', '~\Documents\Meetings']

[[bookmark]]
name   = "Acme"
target = 'C:\Vendors\Acme'
group  = ["bar"]

[[bookmark]]
name   = "Contracts register"
target = 'S:\Legal\Contracts register.xlsx'
group  = ["bar", "Legal"]
```

---

## 9. Error handling and messages

| Situation | Behaviour |
|---|---|
| Folder not found / no access | Content area shows the error with *Retry*. The tab keeps its history. |
| Network path slow or offline | Waits for up to `timeoutSeconds`, then *"Location not available"* with *Retry*. Other tabs keep working. |
| Error on one item during a job | Collected in the job's error list, with *Retry*, *Skip* and *Show in folder*. |
| Settings, key bindings or toolbar file has errors | NFR-REL-03; FR-KEY-05. |

Messages say what happened, why (if known), and what the user can do next.

---

## 10. Testing and acceptance

- **Unit tests** (Rust) for logic: name checks and free names, settings merge and editing, key binding parsing, toolbar parsing, template placeholders, the Quick Find query syntax.
- **Integration tests** (Rust) against temporary folders for file operations and the job queue, including conflicts, cancellation, errors and undo.
- **Manual checks** for the UI and for the performance targets (NFR-PERF).
- **Acceptance:** 0.1.0 is accepted when `cargo test`, `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` pass, and the functions in Sections 5 and 6 work on Windows and Linux.

---

## 11. Release history

### 11.1 0.1.0 — first stable release (2026-11-03)

0.1.0 was built in four milestones. The fifth milestone (M5 — Projects and polish) was cancelled on 2026-11-03, and its work moved to Section 12.

| Milestone | Content | Status |
|---|---|---|
| **M1 — Core shell** | Tauri + Elm skeleton, IPC bridge, directory listing with cache and watcher, Details view (virtualised), navigation, Address Bar, tabs, status bar, `settings.toml`. | Done (2026-10-31) |
| **M2 — Organise** | Menu Bar, sorting, Quick Filter, column filters, columns, Save View and folder settings, sidebar (Tree, Favourites, Bookmarks), Bookmark Bar and `bookmarks.toml`. | Done (2026-10-31) |
| **M3a — Operate: core** | Background job queue with Jobs panel; copy and move with conflict dialog; rename; delete to the Recycle Bin / Trash; undo; New Folder / File / Shortcut / Web Link; Duplicate; Copy Path; Open in Terminal; Show in File Manager; right-click menus. | Done (2026-10-31) |
| **M3b — Operate: integration** | Clipboard exchange with Explorer and other file managers (including *Paste as Shortcut*), drag and drop (including onto the sidebar, Bookmark Bar and tabs, and to and from other apps), templates. | Done (2026-11-01) |
| **M4 — Speed** | Command palette, key bindings file and editor, customisable toolbar, Quick Find; plus the Size filter range, *Locate…* for bookmarks, tree type-ahead, tab reordering, *Retry*/*Skip*, progress inside large files and *Copy Name*. | Done (2026-11-01) |
| ~~**M5 — Projects and polish**~~ | — | **Cancelled** (2026-11-03). See Section 12. |

**Known limits in 0.1.0:**
- On Linux, a *cut* in File Catalog pastes as a copy in other file managers (the clipboard library can't mark a cut there).
- Dropping onto Explorer or other apps, and dropping in from them, has been checked by hand only inside File Catalog; it still needs a test on Windows and Linux.
- Start-up time (NFR-PERF-01) is still to be measured on Windows.
- Search results are not updated by the folder watcher; *Refresh* runs the search again.

---

## 12. Not in 0.1.0 (later versions)

These were specified in the drafts but are not built. Each keeps its ID so it can be picked up again. None is scheduled; a later version will choose from this list.

**From the cancelled M5:**

| Item | IDs |
|---|---|
| Context view and context bookmarks (bookmarks linked to a folder tree, shown in a fourth sidebar mode; *Add Context Bookmark* `Ctrl+Shift+D`; automatic suggestions) | FR-CTX-01 to 05, FR-SB-01 (Context mode) |
| Quick View panel (`Space` / `Ctrl+Q`): previews of text, Markdown, images, PDF, links, folders; Windows Preview Handlers; dockable left or right; collapse below 900 px | FR-QV-01 to 04, FR-UI-02, FR-UI-03 |
| Lazy metadata columns: Owner, Windows document properties (Title, Authors, Tags, Categories, Comments), image Dimensions, registered type names (Windows) / MIME descriptions (Linux), *More columns…* | FR-COL-01, FR-COL-02 |
| Accessibility: WCAG 2.1 AA contrast checked in both themes, full ARIA roles for screen readers, display scaling 100–300% and per-monitor DPI checked | NFR-UX-02, NFR-UX-03 |
| Installer polish (signing, upgrade checks) beyond the standard Tauri bundles | NFR-PERF-11 |
| Saving column filters as part of a folder view | FR-CF-04, FR-VIEW-01 |
| `»` overflow menu on a full Bookmark Bar; reordering bookmarks by dragging | FR-BB-05, FR-BB-03 |
| Reordering favourites, and toolbar buttons in *Customise Toolbar*, by dragging | FR-SB-01, FR-TB-02 |
| Several jobs at once on different drives | FR-OP-02 |
| Batch rename with live preview | FR-REN-04 |
| Checking that files changed since the operation before undoing; undo history limit | FR-UNDO-01, FR-UNDO-02 |
| Filling in a web link's name from the page title | FR-NEW-04, NFR-SEC-01 |
| *Open With ▸* and *Properties* (`Alt+Enter`), including the native Windows Properties dialog | FR-OPEN-02, FR-PROP-01, FR-PROP-02 |
| Windows *Show more options* (the native Explorer menu) | FR-CC-07 |
| Highlighting the target folder while files from another app are dragged over the window; a drag cursor that shows copy / move / shortcut | FR-CC-08, FR-COPY-06 |
| Hints that name a key (status-bar hints, Bookmark Bar tooltips) showing a changed key | FR-KEY-01 |
| Updating search results from the folder watcher | FR-FIND-01 |

**Found missing while cleaning up the specification:**

| Item | IDs |
|---|---|
| New Window (`Ctrl+Shift+W`) | Appendix A |
| List view (compact, multi-column names) | FR-CC-02 |
| Rubber-band (drag) selection | FR-CC-04 |
| `typingStartsFilter` setting (typing starts the Quick Filter instead of type-ahead); it is read but has no effect | FR-CC-05 |
| Marking rows that a running job is changing | FR-CC-09 |
| Back/Forward history list on right-click or long-press | FR-NAV-02 |
| Suggesting the 10 most used extensions in *New File*; *Browse* button in *New Shortcut* | FR-NEW-02, FR-NEW-03 |
| Bookmark import from Explorer *Quick access* | FR-BM-05 |
| A folder's saved view following it when File Catalog renames or moves it; *Tools › Clean Up Folder Settings* | FR-FS-02 |
| OS fast-copy functions (`CopyFileEx`, `copy_file_range`, reflink) and keeping attributes; verifying size before a cross-volume move deletes the source | FR-COPY-01, FR-COPY-02 |
| Icon cache with per-file icons for `.exe` and `.lnk` | 4.5 |
| Showing which app holds a file in use (Windows Restart Manager); pausing a job when the disk is full; long-path (`\\?\`) handling | 9 |
| Help › Documentation | 5.2 |
| `elm-test` and `elm-review`, end-to-end tests with `tauri-driver`, and performance tests in CI | NFR-MNT-01, NFR-MNT-02, 10 |

**Moved out earlier (decisions 2026-11-01):**

- Project folders: *New Project Folder*, *Link Selected into Project…*, *File Project…* with link options, e-mails as saved files in projects (FR-PRJ-01 to 07).
- Cloud sync status beyond the basic Windows column: the *Syncing* and *Error* states, *Always keep on this device* and *Free up space*, the *"Downloading…"* label when copying online-only files (FR-SYNC-01, FR-SYNC-02, FR-COPY-07).
- Pinned tabs (FR-TAB-03).
- Compress to ZIP and Extract (FR-ZIP-01, FR-ZIP-02).
- Compare (FR-CMP-01): dropped, including the *Compare* button in the conflict dialog.

**Not planned:**

- Searching inside file contents, and a background search index (FR-FIND-07).
- Built-in cloud storage clients (the app uses the OS sync clients' folders).
- E-mail client integration (e-mails are handled as saved files).
- File tags or metadata stored outside the file system (would break the no lock-in principle).
- Browsing inside archives, archive formats other than ZIP, FTP/SFTP, dual-pane mode, a built-in side-by-side diff view.
- Plugins and scripting.
- macOS version (the design keeps it possible; Section 2.1).

---

## 13. Open questions

None at the moment. New questions are added here as they come up.

### 13.1 Decision log

| Date | Decision | Where |
|---|---|---|
| 2026-10-31 | Windows primary, Linux supported, macOS deferred but kept possible | 2 |
| 2026-10-31 | Rust + Tauri confirmed; Elm 0.19.3 | 3.1, 3.2 |
| 2026-10-31 | File system work always on separate threads; network paths on their own threads | 4.3 |
| 2026-10-31 | Folder settings stored only in the app settings folder | 6.5, 8.4 |
| 2026-10-31 | E-mails handled as saved files; no e-mail client integration | 12 |
| 2026-10-31 | Context view kept minimal, to evolve with use | 12 |
| 2026-10-31 | Standard File Explorer columns available; Name, dates, Size, Sync status shown by default | 5.8.2 |
| 2026-10-31 | *File Project* with link options kept | 12 |
| 2026-10-31 | Duplicate, Compress/Extract ZIP and Compare added | 6.12.6 |
| 2026-11-01 | Project folders, cloud sync status (beyond the basic Windows column) and pinned tabs moved out of v1.0; this replaces the 2026-10-31 *File Project* decision | 12 |
| 2026-11-01 | Compress/Extract ZIP moved to a later version; Compare dropped | 12 |
| 2026-11-03 | M5 cancelled. M1 to M4 released as **0.1.0**, the first stable release. The specification now describes only what 0.1.0 does; all M5 work, the M5 deferrals and the parts found not built are listed in Section 12 for a later version. | 1, 11, 12 |

---

## 14. Requirements traceability

| Requirement (from Requirements Document) | Specified in |
|---|---|
| File explorer: find/open documents, basic file operations | 6.1, 6.11, 6.12 |
| Focus on organising and navigating many files | 6.4, 6.5 |
| Link documents from several folders into a project, then move it back | 12 (later version) |
| Use standard files/folders; works without the app | 1.2, 6.7, 6.8 |
| Ultra-fast, keyboard-driven | 6.9, 6.10, 7.1, FR-UI-05 |
| Full Menu Bar | 5.2 |
| Customisable Toolbar | 5.3, 8.5 |
| Bookmark Bar | 5.4, 6.4 |
| Tab Bar | 5.5 |
| Address Bar — breadcrumb mode | 5.6 |
| Dockable sidebar, content container, right quick view | 5.1 (FR-UI-02), 5.7, 5.8; Quick View: 12 |
| Sidebar: tree, favourites, full bookmarks, content-aware bookmarks | 5.7, 6.4.3; content-aware view: 12 |
| Content: name, created, modified, sync status | 5.8, 5.8.1, 5.8.2 |
| Status bar: file/folder count, selection count, progress | 5.10 |
| Sorting and filtering by name, size, date | 6.2, 6.3 |
| Quick persist button for sorting and view per folder | 6.5 |
| Quick file filter, Excel-like | 6.3.1, 6.3.2 |
| Quick file find in files and sub-folders | 6.6 |
| Create new folder, shortcut and file | 6.7 |
| Create from a template file or folder | 6.8 |
| Customisable shortcuts for all actions | 6.10, 8.3 |
| Quick command bar like Ctrl+P | 6.9 |
| Copy, move, rename, delete, duplicate | 6.12 |
| Compress to ZIP and extract ZIP | 12 (later version) |
| Open within 500 ms, caching, multithreading | 4.3, 4.5, 4.6, 7.1 |
| Rust or Zig backend and UI container | 3.1 (Rust + Tauri) |
| Elm front end | 3.2 |
| Settings in user app folder, INI or TOML, human-readable | 8.1–8.3, 8.5, 8.6 |
| Folder settings saved in the app settings folder | 6.5, 8.4 |
| Platforms: Windows primary, Linux supported | 2 |
| File system work must not affect the UI | 4.3 |

---

## Appendix A — Commands and default key bindings

The application has more commands than this table lists (for example `view.toggleStatusBar`, `toolbar.customise`, `help.about`). **Help › Keyboard Shortcuts** shows every command with its id, and those ids are what `keybindings.toml` and `toolbar.toml` use.

| Command ID | Name | Default key |
|---|---|---|
| `nav.back` / `nav.forward` | Back / Forward | `Alt+Left` / `Alt+Right` (and the mouse back/forward buttons) |
| `nav.up` | Up | `Alt+Up`, `Backspace` |
| `nav.home` | Home | `Alt+Home` |
| `nav.refresh` | Refresh | `F5` |
| `nav.focusAddress` | Go to Address | `Ctrl+L`, `Alt+D` |
| `tab.new` / `tab.close` / `tab.reopen` | New / Close / Reopen Closed Tab | `Ctrl+T` / `Ctrl+W` / `Ctrl+Shift+T` |
| `tab.next` / `tab.prev` | Next / Previous Tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| `tab.goto1…9` | Go to Tab 1–9 | `Ctrl+1…9` |
| `tab.duplicate` | Duplicate Tab | — |
| `palette.open` | Command Palette (Go to) | `Ctrl+P` |
| `palette.commands` | Command Palette (Commands) | `Ctrl+Shift+P` |
| `palette.bookmarks` / `palette.tabs` | Command Palette (Bookmarks / Tabs) | — |
| `filter.focus` | Quick Filter | `Ctrl+F`, `/` |
| `filter.clearAll` | Clear All Filters | `Ctrl+Shift+L` |
| `find.open` | Quick Find | `Ctrl+Shift+F`, `F3` |
| `new.file` | New File | `Ctrl+N` |
| `new.folder` | New Folder | `Ctrl+Shift+N` |
| `new.fromTemplate` | New from Template | `Ctrl+Alt+N` |
| `new.shortcut` / `new.webLink` | New Shortcut / New Web Link | — |
| `template.saveSelection` / `template.editFolder` | Save Selection as Template / Edit Templates Folder | — |
| `edit.cut` / `edit.copy` / `edit.paste` | Cut / Copy / Paste | `Ctrl+X` / `Ctrl+C` / `Ctrl+V` |
| `edit.pasteShortcut` | Paste as Shortcut | `Ctrl+Shift+V` |
| `edit.copyPath` / `edit.copyName` | Copy Path / Copy Name | `Ctrl+Shift+C` / — |
| `edit.duplicate` | Duplicate | — |
| `edit.rename` | Rename | `F2` |
| `edit.delete` / `edit.deletePermanent` | Delete / Delete Permanently | `Del` / `Shift+Del` |
| `edit.undo` | Undo | `Ctrl+Z` |
| `edit.selectAll` / `edit.invertSelection` / `edit.selectNone` | Select All / Invert Selection / Select None | `Ctrl+A` / `Ctrl+I` / — |
| `item.open` / `item.openNewTab` | Open / Open in New Tab | `Enter` / `Ctrl+Enter` |
| `item.openTerminal` | Open in Terminal | `` Ctrl+` `` |
| `item.reveal` | Show in File Manager | — |
| `item.contextMenu` | Right-click Menu | `Shift+F10`, Menu key |
| `view.saveForFolder` | Save View for This Folder | `Ctrl+S` |
| `view.saveForSubfolders` / `view.resetForFolder` / `view.openFolderSettings` | Save for Subfolders / Reset View / Open Folder Settings File | — |
| `view.toggleSidebar` | Toggle Sidebar | `Ctrl+B` |
| `view.sidebarMode.tree/favourites/bookmarks` | Sidebar Mode | `Ctrl+Shift+1…3` |
| `view.toggleHidden` | Show Hidden Files | `Ctrl+H` |
| `view.theme.system/light/dark` | Theme | — |
| `focus.nextRegion` / `focus.prevRegion` | Next / Previous Region | `F6` / `Shift+F6` |
| `menu.open` | Menu Bar | `F10` |
| `bookmark.addFolder` / `bookmark.addItem` | Bookmark This Folder / Selected Item | `Ctrl+D` / — |
| `bookmark.open` | Open a bookmark (`args = { name = "…" }`) | — |
| `favourite.toggle` | Pin / Unpin Favourite | — |
| `jobs.toggle` | Jobs panel | — |
| `settings.open` / `keybindings.open` / `toolbar.open` | Open Settings / Key Bindings / Toolbar File | `Ctrl+,` / `Ctrl+K Ctrl+S` / — |
| `help.shortcuts` | Keyboard Shortcuts | `Ctrl+/` |
| `app.exit` | Exit | — |
