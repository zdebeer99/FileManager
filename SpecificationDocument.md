# File Catalog Specification Document

| | |
|---|---|
| Version | 0.3 (Draft) |
| Date | 2026-10-31 |
| Source | [RequirementsDocument.md](RequirementsDocument.md) (2026-10-31) |
| Status | For review |
| Changes | 0.4: Scope reduced (decision log 13.1, 2026-11-01): project folders, cloud sync status and pinned tabs moved out of v1.0; ZIP moved to a later version; Compare dropped. |
| | 0.2: Platforms decided: Windows primary, Linux supported, macOS deferred. |
| | 0.3: Review decisions merged: Rust confirmed, Elm 0.19.3, separate I/O threads, folder settings only in the app settings folder, minimal Context view, standard Explorer columns, Duplicate / ZIP / Compare added, e-mails handled as files. |

---

## 1. Introduction

### 1.1 Purpose

This document turns the File Catalog Requirements Document into a specification that can be designed, built and tested against. It defines the architecture, the user interface, every user-facing function, the configuration files, and the performance targets. Each requirement has an ID (`FR-…` for functional, `NFR-…` for non-functional) so it can be traced, implemented and tested on its own.

### 1.2 Product summary

File Catalog is an ultra-fast, keyboard-driven desktop file manager for information workers, such as project managers and people who manage many folders, online and offline. It does everything a normal file explorer does, but its main focus is **organising** files and making large numbers of files **easy to navigate and reach**.

Its guiding principle is **no lock-in**: everything File Catalog creates (folders, shortcuts, web links, templates, settings) is a plain file or folder that still works in Windows Explorer, any Linux file manager, or any other file manager, without File Catalog installed.

### 1.3 Scope

**In scope (v1.0):** the application layout, navigation, tabs, bookmarks, favourites, sorting/filtering, per-folder view persistence, quick filter, quick find (file and folder names), creating files, folders, shortcuts and items from templates, file operations, the command palette, customisable shortcuts and toolbar, and human-readable configuration.

**Out of scope (v1.0):** see Section 12.

### 1.4 Definitions

| Term | Meaning |
|---|---|
| **Item** | A file, folder, shortcut or web link shown in the content list. |
| **Shortcut** | An OS-native link to a file or folder: `.lnk` on Windows, a symbolic link on Linux. |
| **Web link** | A `.url` file (Internet Shortcut format) that points to a web address. |
| **Favourite** | A pinned folder in the sidebar Favourites view (like Explorer's *Quick access*). |
| **Bookmark** | A named, grouped pointer to a folder, file or URL, shown in the Bookmark Bar and the sidebar Bookmarks view. |
| **Context bookmark** | A bookmark linked to a folder tree, shown in the sidebar Context view when you are in that tree (Section 6.4.4). |
| **Folder settings** | The saved view of one folder, stored only in the app settings folder (Section 8.4). |
| **Project folder** | A normal folder used to gather links and working documents for a short-lived task (Section 6.14). |
| **Command** | A named application action with an ID, e.g. `file.rename`. Every menu item, toolbar button, shortcut and palette entry calls a command. |
| **Job** | A long-running background task, such as a copy, move, delete or search, that reports progress. |

### 1.5 Conventions

- **Must** = required for v1.0. **Should** = planned for v1.0, may be postponed if needed. **May** = optional or future.
- Default key bindings are the same on Windows and Linux.

---

## 2. Target platforms

| Platform | Support level | Notes |
|---|---|---|
| Windows 10 (22H2) / Windows 11, x64 and ARM64 | **Primary** | Full feature set, including cloud sync status and `.lnk` shortcuts. Designed, tuned and tested first on Windows. Installer: MSI and NSIS `.exe`. |
| Linux x64 (Ubuntu 22.04 LTS+, Debian 12+, Fedora 38+; WebKitGTK 4.1) | **Supported** | Full feature set except the sync status column (no standard sync API on Linux). Shortcuts are symbolic links; Delete uses the freedesktop.org Trash. Packages: AppImage, `.deb`, `.rpm`. |
| macOS | **Not in v1.0** — planned for later | Not built or tested in v1.0, but the design must not block it (Section 2.1). |

> Decided: Windows is the primary platform, Linux is supported, macOS is deferred (Decision log, 13.1).

### 2.1 Keeping macOS possible later

- All OS-specific code (shortcuts, sync status, Open With, Trash, fast copy, terminal, native context menu) lives behind one **platform layer** in the Rust core: a set of traits with a Windows and a Linux implementation. Adding macOS later means adding a third implementation, not changing the rest of the app.
- The Elm UI never checks which OS it runs on. It asks the backend which features are available (e.g. `capabilities.syncStatus = false`) and shows or hides them.
- Only cross-platform crates are used outside the platform layer. Paths are always handled as `PathBuf`/`OsString` in Rust, never as Windows-style strings.
- Key bindings are stored as `Ctrl+…`; a later macOS version can map `Ctrl` to `Cmd` when loading them.
- Settings, cache and log locations come from the `directories` crate, which already knows the macOS locations.

---

## 3. Technology decisions

### 3.1 Backend and UI container: **Rust** (chosen over Zig)

| Criterion | Rust | Zig |
|---|---|---|
| Desktop web-view shell | **Tauri 2**: mature, small binaries, fast start, uses the system web view (WebView2 on Windows, WebKitGTK on Linux; WKWebView for a later macOS version) | No mature equivalent; would need a custom web-view binding |
| File system ecosystem | `notify` (watching), `ignore`/`walkdir` (parallel walking), `trash`, `windows` crate (Shell, Cloud Files API), `toml_edit` | Few libraries; most would need to be written from scratch |
| Language stability | Stable (1.x) | Pre-1.0; breaking changes between releases |
| Safe multithreading | Checked by the compiler; `tokio` + `rayon` | Manual |

**Decision (confirmed):** Rust (stable toolchain, edition 2021+) with **Tauri 2.x** as the window and web-view container.

### 3.2 Frontend: **Elm 0.19.3**

- Elm **0.19.3** (released 2026-10-02) is used. It has no language changes from 0.19.1, so all 0.19.x packages work. `elm.json` sets `"elm-version": "0.19.3"`, and the compiler is pinned as a project dev dependency (npm `elm@0.19.3-0`) so every developer and CI build uses the same version.
- All UI is written in Elm, using The Elm Architecture (Model / Update / View).
- Elm talks to the Rust backend only through **ports**. A small, hand-written JavaScript bridge (`bridge.js`, kept under ~150 lines) connects Elm ports to Tauri's `invoke` and event APIs. No other JavaScript application logic is allowed.
- Styling uses plain CSS with CSS custom properties for theming (light/dark). No CSS framework.
- Build: `elm make --optimize`, then minify with `esbuild` (or `uglify-js`). Target bundle size: ≤ 250 KB minified, ≤ 80 KB gzipped.

### 3.3 Main Rust crates (indicative)

| Area | Crate |
|---|---|
| App shell / IPC | `tauri` 2.x |
| Async runtime | `tokio` |
| CPU-parallel work | `rayon` |
| Directory walking / search | `ignore` (WalkParallel), `walkdir` |
| File system watching | `notify` (+ `notify-debouncer-full`) |
| Recycle Bin / Trash | `trash` |
| Settings | `serde`, `toml_edit` (keeps user comments and formatting) |
| Config paths | `directories` |
| Fuzzy matching | `nucleo-matcher` |
| Windows Shell, `.lnk`, Cloud Files | `windows` |
| Logging | `tracing`, `tracing-appender` |

---

## 4. Architecture

### 4.1 Overview

```
┌──────────────────────────── Tauri window (system web view) ────────────────────────────┐
│  Elm application                                                                        │
│   Model ── Update ── View          Virtualised list, palette, dialogs, layout           │
│        │  ports (out: requests)  ▲ ports (in: responses, events)                        │
│  bridge.js  ──── invoke(cmd, {reqId, ...}) ────►  ◄──── emit(event, payload) ──────     │
└───────────────────────────────────────┬─────────────────────────────────────────────────┘
                                        │ Tauri IPC
┌───────────────────────────────────────▼─────────────────────────────────────────────────┐
│  Rust core                                                                              │
│  ┌────────────┐ ┌──────────────┐ ┌───────────┐ ┌────────────┐ ┌───────────────────────┐ │
│  │ Commands   │ │ Directory    │ │ Watcher   │ │ Job queue  │ │ Settings service      │ │
│  │ (IPC API)  │ │ service +    │ │ (notify)  │ │ copy/move/ │ │ (TOML load/save,      │ │
│  │            │ │ cache        │ │           │ │ delete/    │ │  hot reload, folder   │ │
│  │            │ │              │ │           │ │ search     │ │  settings resolution) │ │
│  └────────────┘ └──────────────┘ └───────────┘ └────────────┘ └───────────────────────┘ │
│  ┌────────────┐ ┌──────────────┐ ┌───────────┐ ┌─────────────────────────────────────┐  │
│  │ Bookmarks  │ │ Templates    │ │ Preview   │ │ Platform layer (Windows Shell,      │  │
│  │ service    │ │ service      │ │ service   │ │ Cloud Files, .lnk, Trash, open-with)│  │
│  └────────────┘ └──────────────┘ └───────────┘ └─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Responsibilities

| Layer | Owns | Does not own |
|---|---|---|
| **Elm UI** | Layout, focus, selection, client-side sort and quick filter of the loaded list, palette fuzzy display, key handling, dialogs | Any file system access |
| **Rust core** | All file system access, directory caching, watching, search, file operations, settings files, platform integrations | UI state (except persisted session and settings) |

### 4.3 Threading model

**Rule: the UI never waits for the file system.** All file system work runs on threads that are separate from both the UI (web view) thread and the main window thread. The UI only sends requests and receives messages; it never blocks on a reply.

| Thread(s) | Runs | Never runs |
|---|---|---|
| **UI thread** (web view) | Elm: drawing, input, sorting and filtering of the already-loaded list | Any call that waits for Rust; all calls are asynchronous and answered by messages |
| **Main thread** (Tauri) | The window and event loop only | Any file system call |
| **Tokio worker threads** | IPC handlers, the job queue, watcher events. Handlers hand work to the pools below and return at once. | Long blocking calls |
| **Local I/O pool** (`spawn_blocking`) | Listing and reading local disks | Network or cloud paths |
| **Slow-path I/O pool** (separate, small) | Listing and reading network shares, removable drives and cloud placeholders | Local disks |
| **Rayon pool** | CPU-heavy work: parallel search, metadata for large folders, recursive size | — |

- Network and cloud paths get their **own threads**, so a share that hangs can never hold up local folders or the UI. Calls to such paths time out after 5 s (configurable) and show a clear *"not reachable"* state.
- Every job can be **cancelled** with a `CancellationToken`. Cancelling must stop work within 100 ms.

### 4.4 IPC contract

All requests are asynchronous and carry a client-generated `reqId`. Responses and streamed events echo the `reqId`, so Elm can drop stale responses (for example, a listing for a folder the user has already left).

**Requests (Elm → Rust)** — indicative list:

| Command | Payload | Response |
|---|---|---|
| `dir.list` | `{ reqId, path }` | Streamed `dir.chunk` events, then `dir.done` |
| `dir.watch` / `dir.unwatch` | `{ path }` | — (changes arrive as `dir.changed`) |
| `fs.createFolder` / `fs.createFile` / `fs.createShortcut` / `fs.createWebLink` | `{ parent, name, target? }` | `{ ok, path } \| { error }` |
| `fs.createFromTemplate` | `{ parent, templateId, name }` | `{ ok, path } \| { error }` |
| `fs.rename` | `{ path, newName }` | `{ ok } \| { error }` |
| `job.copy` / `job.move` / `job.delete` | `{ sources[], dest?, permanent? }` | `{ jobId }`, then `job.progress` / `job.conflict` / `job.done` |
| `job.resolveConflict` | `{ jobId, conflictId, action, applyToAll }` | — |
| `job.cancel` | `{ jobId }` | — |
| `search.start` | `{ reqId, root, query, options }` | Streamed `search.results`, then `search.done` |
| `open.item` / `open.with` / `open.terminal` / `reveal.inOs` | `{ path, app? }` | — |
| `settings.get` / `settings.set` | `{ scope, key, value? }` | value |
| `folderSettings.get` / `folderSettings.save` / `folderSettings.reset` | `{ path, settings? }` | resolved settings |
| `bookmarks.*`, `favourites.*`, `templates.list` | … | … |
| `preview.get` | `{ path, maxBytes }` | `{ kind, content \| url }` |
| `job.duplicate` / `job.compress` / `job.extract` | `{ sources[], dest? }` | `{ jobId }`, then job events |
| `fs.compare` | `{ a, b }` | `{ identical, reason }` |
| `settings_set` | `{ key, value }` (dotted key, e.g. `layout.sidebar.width`) | — |
| `folder_view_get` / `folder_view_save` / `folder_view_reset` / `folder_view_file` | `{ path, view?, applyToSubfolders? }` | resolved view / file path |
| `bookmarks_get` / `bookmarks_edit` | `{ edit: { op, … } }` | favourites, bookmarks, warnings |
| `job_start` / `job_cancel` / `job_pause` / `job_resolve` | `{ request: { kind, sources, dest?, permanent } }` / `{ jobId, … }` | job id; then `job-progress` and `job-conflict` events |
| `fs_rename` / `fs_create` | `{ path, newName }` / `{ parent, item: { kind, … } }` | new path |
| `clipboard_write_text` / `open_terminal` / `reveal_item` | `{ text }` / `{ path }` | — |
| `templates_list` / `templates_folder` / `fs_create_from_template` | `{ parent, template, name, today }` | templates / folder / new path |
| `fs_create_shortcuts` / `clipboard_set_files` / `clipboard_get_files` / `drag_out` | `{ parent, targets }` / `{ paths, cut }` / — / `{ paths }` | — |
| `undo_last` | — | `{ ok } \| { error }` |

**Events (Rust → Elm):** `dir.chunk`, `dir.done`, `dir.changed`, `dir.error`, `job.progress`, `job.conflict`, `job.done`, `search.results`, `search.done`, `settings.changed`, `bookmarks.changed`, `syncStatus.changed`.

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
| Directory cache | Memory, LRU, default 200 folders / 64 MB | Item records per folder | Watcher events; manual refresh (F5); 30 s age for unwatched network paths |
| Session snapshot | Disk: `<cache dir>/session.bin` | Listings of the folders open in tabs when the app last closed | Shown immediately at start-up, then refreshed in the background |
| Icon cache | Memory + disk: `<cache dir>/icons/` | Icons per extension (and per file for `.exe`/`.lnk`) | App version change |
| Folder settings cache | Memory | Resolved folder settings | Settings file watcher |

The cache directory is the OS cache location (`%LOCALAPPDATA%\FileCatalog\cache` on Windows, `$XDG_CACHE_HOME/filecatalog` (default `~/.cache/filecatalog`) on Linux). Cache files are **not** settings: they may be binary and can be deleted at any time without losing anything.

### 4.6 Directory listing pipeline

1. Elm sends `dir.list`. If the folder is cached, Rust sends the cached items straight away (`dir.chunk` with `fromCache: true`).
2. Rust reads the folder on the blocking pool and streams items in chunks of 500 (the first chunk is sent as soon as it is ready, at most 50 ms after the request).
3. Metadata that is slow to read (sync status, shortcut targets, document properties such as Authors or Title) is filled in afterwards with `dir.changed` patch events, so the list is usable immediately.
4. The folder is watched while it is shown in any tab. Changes are debounced (100 ms) and sent as patches (added/removed/changed), not full reloads.

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
├───────────────┬────────────────────────────────────────────┬─────────────────────┤
│ [🌳][★][🔖][◎] │ Name ▾           Modified     Size  Sync  │                     │
│ Sidebar        │ 📁 Archive       2026-10-02         ☁    │   Quick View        │
│ (tree /        │ 📄 Contract.docx 2026-10-30  48 KB  ✔    │   (preview of the   │
│  favourites /  │ 🔗 Old contract  2026-09-01   1 KB       │    selected item)   │
│  bookmarks /   │ 🌐 Supplier site 2026-10-29   1 KB       │                     │
│  context)      │        (Content container)                 │                     │
├───────────────┴────────────────────────────────────────────┴─────────────────────┤
│ 24 items (3 folders, 21 files) · 2 selected (96 KB) · Copying 3/12 ████░░ 40% (Status Bar)│
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **FR-UI-01 (Must)** Every bar and panel above, except the content container, can be shown or hidden from the **View** menu and the command palette. Visibility is saved in `settings.toml`.
- **FR-UI-02 (Must)** The sidebar and the Quick View panel are **dockable**: each can be placed on the left or right edge, resized by dragging its splitter, or collapsed. Position and width are saved.
- **FR-UI-03 (Must)** The layout must work at window widths down to 640 px. Below 900 px the Quick View panel collapses automatically.
- **FR-UI-04 (Must)** Light and dark themes, following the OS by default, with a manual override.
- **FR-UI-05 (Must)** Every function can be reached with the keyboard alone. Focus is always visible. `F6` / `Shift+F6` moves focus between regions (Address Bar → Sidebar → Content → Quick View).

### 5.2 Menu Bar

**FR-MENU-01 (Must)** All commands are grouped in a standard menu layout. Each menu item shows its current key binding.

| Menu | Items |
|---|---|
| **File** | New Tab, New Window, New Folder, New File, New Shortcut, New Web Link, New from Template ▸, Open, Open With ▸, Compress to ZIP, Extract ▸, Compare, Open in Terminal, Reveal in Explorer / System File Manager, Properties, Close Tab, Exit |
| **Edit** | Undo, Cut, Copy, Paste, Paste as Shortcut, Duplicate, Copy Path, Rename, Delete, Delete Permanently, Select All, Invert Selection, Select None |
| **View** | Menu Bar / Toolbar / Bookmark Bar / Tab Bar / Address Bar / Sidebar / Quick View / Status Bar (toggles), Sidebar Mode ▸, View Mode ▸ (Details, List), Columns ▸, Sort By ▸, Show Hidden Files, Show File Extensions, Save View for This Folder, Reset View for This Folder, Theme ▸, Refresh |
| **Go** | Back, Forward, Up, Home, Go to Address, Recent Folders ▸, Favourites ▸ |
| **Bookmarks** | Bookmark This Folder, Bookmark Selected Item, Add Context Bookmark, Manage Bookmarks, bookmark list ▸ |
| **Tools** | Quick Find, Quick Filter, Command Palette, Project ▸ (New Project Folder, Link Selected into Project, File Project…), Edit Templates Folder, Open Settings File, Open Key Bindings File, Open Toolbar File, Reload Settings |
| **Window** | Next Tab, Previous Tab, Tab 1–9, Duplicate Tab, Reopen Closed Tab |
| **Help** | Keyboard Shortcuts, Documentation, Open Log Folder, About |

### 5.3 Toolbar

- **FR-TB-01 (Must)** The toolbar holds buttons that call commands. Its contents, order, separators and button style (icon, icon + text, text) are set in `toolbar.toml` (Section 8.5).
- **FR-TB-02 (Should)** *Customise Toolbar* (right-click on the toolbar) lets the user add, remove and reorder buttons by dragging. Changes are written back to `toolbar.toml`.
- **FR-TB-03 (Must)** Buttons whose command cannot run right now (e.g. *Paste* with an empty clipboard) are shown disabled.
- **FR-TB-04 (Must)** The default toolbar includes the **Save View** button (FR-VIEW-05).

### 5.4 Bookmark Bar

- **FR-BB-01 (Must)** Shows the bookmarks in the `bar` group as buttons. Folder groups appear as drop-down menus.
- **FR-BB-02 (Must)** Clicking opens the target (folder: navigate; file: open with its default app; URL: open in the default browser). Middle-click or `Ctrl+click` on a folder opens it in a new tab.
- **FR-BB-03 (Must)** Dragging a folder, file or URL onto the bar creates a bookmark. Bookmarks can be reordered by dragging.
- **FR-BB-04 (Must)** Right-click menu: Open, Open in New Tab, Edit, Delete, New Group.
- **FR-BB-05 (Should)** Overflowing bookmarks go into a `»` menu.

### 5.5 Tab Bar

- **FR-TAB-01 (Must)** Each tab has its own location, back/forward history, selection, scroll position, quick filter and sort.
- **FR-TAB-02 (Must)** New tab (`Ctrl+T`) opens the current folder; close (`Ctrl+W`, middle-click); reopen closed tab (`Ctrl+Shift+T`, last 20 kept); switch (`Ctrl+Tab`, `Ctrl+Shift+Tab`, `Ctrl+1…9`); reorder by dragging.
- **FR-TAB-03 (Later)** Pinned tabs: small, cannot be closed by accident, always kept.
- **FR-TAB-04 (Must)** Open tabs and their locations are restored on start-up (configurable).
- **FR-TAB-05 (Should)** Dropping files onto a tab copies/moves them into that tab's folder.

### 5.6 Address Bar

- **FR-ADDR-01 (Must)** Shows the current path in **breadcrumb mode**. Each segment can be clicked to navigate. The `›` separator between segments opens a drop-down of that folder's sub-folders.
- **FR-ADDR-02 (Must)** Clicking empty space in the bar, or pressing `Ctrl+L` / `Alt+D`, switches to **edit mode**: a text box with the full path selected. It autocompletes folder names with `Tab`; `Enter` navigates; `Esc` cancels.
- **FR-ADDR-03 (Must)** Accepts drive paths, UNC paths (`\\server\share`), `~`, and environment variables (`%USERPROFILE%`, `$HOME`). Typing a file path opens that file's folder with the file selected.
- **FR-ADDR-04 (Must)** Long paths shrink from the left: the first segment and the last segments stay visible, and hidden middle segments go into a `…` drop-down.
- **FR-ADDR-05 (Must)** The Quick Filter box (FR-QF) sits at the right end of the Address Bar.

### 5.7 Sidebar

**FR-SB-01 (Must)** The sidebar has four modes, switched with buttons at its top or with `Ctrl+Shift+1…4`:

| Mode | Content |
|---|---|
| **Tree** | Folder tree, starting from: Favourites, Home, drives/volumes, network locations and cloud roots (OneDrive, etc.). It loads lazily, expands to follow the current folder (configurable), and supports keyboard navigation (arrows, `→` expand, `←` collapse, type-ahead). |
| **Favourites** | A flat, user-ordered list of pinned folders. *Pin to Favourites* is available from the right-click menu and the palette. |
| **Bookmarks** | All bookmarks in their groups, as a tree, with search at the top. Supports edit, delete, drag to reorder and drag between groups. |
| **Context** *(experimental)* | Links to folders, documents and web addresses that may be related to the folder you are looking at. v1.0 keeps this minimal (Section 6.4.4) so the idea can take shape with use. Updates every time the user navigates. Shows *"No context links for this folder"* plus an *Add* button when empty. |

- **FR-SB-02 (Must)** Dropping items onto a folder in the Tree or Favourites copies/moves them there (FR-COPY-06).

### 5.8 Content container

- **FR-CC-01 (Must)** **Details view** (default): one row per item, with sortable, resizable and reorderable columns. The standard File Explorer columns are available (Section 5.8.2). Any column can be shown or hidden by right-clicking a column header or with **View › Columns ▸**, and the choice is part of the folder view (Section 6.5). Visible by default: **Name**, **Date modified**, **Date created**, **Size**, **Sync status** (Sync status only where the platform supports it).
- **FR-CC-02 (Should)** **List view**: compact, multi-column names only.
- **FR-CC-03 (Must)** The list is **virtualised**: only visible rows (plus a buffer) are rendered, so folders with 100,000 items scroll smoothly (NFR-PERF-05).
- **FR-CC-04 (Must)** Selection: click, `Ctrl+click`, `Shift+click`, rubber-band drag selection, `Ctrl+A`, keyboard (arrows, `Home`/`End`, `PgUp`/`PgDn`, with `Shift` to extend and `Ctrl` + `Space` to toggle).
- **FR-CC-05 (Must)** Type-ahead: typing letters when the list has focus jumps to the next item starting with those letters (reset after 1 s). If the setting `typingStartsFilter = true`, typing starts the Quick Filter instead.
- **FR-CC-06 (Must)** `Enter` / double-click opens the item. Folders open in the current tab; `Ctrl+Enter` opens a folder in a new tab. `Backspace` / `Alt+Up` goes to the parent folder.
- **FR-CC-07 (Must)** Right-click menu with the commands that apply to the selection. On Windows, a **"Show more options"** item opens the native Explorer context menu (so other installed apps' menu items stay reachable).
- **FR-CC-08 (Must)** Drag and drop: inside the app, to/from other apps and the desktop.
- **FR-CC-09 (Must)** Items being changed by a running job are marked (for example, a progress hint on the row).
- **FR-CC-10 (Must)** Empty and error states: *"This folder is empty"*, *"Access denied"*, *"Location not available"* (with a *Retry* button).

#### 5.8.1 Sync status column

> **Not in v1.0** (decision 2026-11-01). The basic Windows column built in M1 (read from file attributes only, so it never downloads anything) stays available, but the requirements below are not developed further in v1.0.

**FR-SYNC-01 (Must, Windows)** Shows the cloud state of items in folders managed by a cloud sync provider (OneDrive, SharePoint, Dropbox, Google Drive and others that use the Windows Cloud Files API):

| State | Icon | Detected from |
|---|---|---|
| Online-only | ☁ | `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` or `FILE_ATTRIBUTE_OFFLINE` |
| Available locally | ✔ (outline) | Placeholder, in sync, not pinned |
| Always keep on this device | ✔ (filled) | `FILE_ATTRIBUTE_PINNED` |
| Syncing | ⟳ | Placeholder state not in sync |
| Error / conflict | ⚠ | Provider error state, when available |
| (blank) | | Not in a sync root |

- **FR-SYNC-02 (Should)** The right-click menu offers *Always keep on this device* and *Free up space* for items in a sync root.
- **FR-SYNC-03 (Must)** Reading sync status must never trigger a file download (a "hydration").
- **FR-SYNC-04 (Must)** Linux: the Sync status column is hidden and not offered in the column list.

#### 5.8.2 Available columns

**FR-COL-01 (Must)** These columns can be chosen. Columns marked *lazy* are filled in after the list is shown (Section 4.6), and reading them never downloads online-only cloud files.

| Column | Windows | Linux | Lazy |
|---|---|---|---|
| Name | ✔ | ✔ | |
| Date modified | ✔ | ✔ | |
| Date created | ✔ | ✔ (where the file system records it) | |
| Date accessed | ✔ | ✔ | |
| Size | ✔ | ✔ | |
| Type (e.g. *Microsoft Word Document*) | ✔ registered type name | ✔ MIME type description | ✔ |
| Extension | ✔ | ✔ | |
| Attributes | ✔ `R H S A` … | ✔ permissions (`rwxr-xr-x`) | |
| Owner | ✔ | ✔ | ✔ |
| Link target (shortcuts, web links) | ✔ | ✔ | ✔ |
| Sync status | ✔ | — | ✔ |
| Title, Authors, Tags, Categories, Comments | ✔ Windows Property System | — | ✔ |
| Dimensions (images) | ✔ | ✔ (read from image header) | ✔ |
| Folder (search results only) | ✔ | ✔ | |

- **FR-COL-02 (Should)** *More columns…* on Windows lists any other property the Windows Property System offers for the files in view.

### 5.9 Quick View panel (right)

- **FR-QV-01 (Must)** Shows a preview of the single selected item; toggled with `Space` (while the list has focus) or `Ctrl+Q`.
- **FR-QV-02 (Must)** Built-in previews: plain text and code (first 256 KB, monospaced), Markdown (rendered), images (PNG, JPEG, GIF, WebP, SVG, BMP), PDF (rendered by the web view), web links (target URL and title), shortcuts (target path and its preview), folders (item count, total size calculated in the background, and the first 50 items).
- **FR-QV-03 (Should)** Other file types: Windows Preview Handlers where available (Office documents, etc.); otherwise file properties (size, dates, type, path).
- **FR-QV-04 (Must)** Preview never blocks the UI and never downloads online-only cloud files unless the user clicks *Download and preview*.

### 5.10 Status bar

**FR-STAT-01 (Must)** Shows, from left to right:
- Item counts: `N items (F folders, D files)`. When filtered: `showing M of N`.
- Selection: `S selected (total size)`.
- Running jobs: the active job's name, progress bar and percentage, plus `+n more`. Clicking it opens the **Jobs panel** (all jobs, with pause/cancel, details and errors).
- Free space on the current volume.
- A temporary message area for results (e.g. *"3 items copied"*), which fades after 4 s.

---

## 6. Functional specification

### 6.1 Navigation

- **FR-NAV-01 (Must)** Back (`Alt+Left`, mouse button 4), Forward (`Alt+Right`, mouse button 5), Up (`Alt+Up`, `Backspace`), Home (`Alt+Home`, goes to the configured home folder), Refresh (`F5`).
- **FR-NAV-02 (Must)** Each tab keeps its own history (at least 100 entries). Long-pressing or right-clicking Back/Forward shows the history list.
- **FR-NAV-03 (Must)** When going back or up, the folder you came from is selected and scrolled into view.
- **FR-NAV-04 (Must)** Recent folders (last 50 visited, across all tabs) are kept in the session and shown in **Go › Recent Folders** and the command palette.

### 6.2 Sorting

- **FR-SORT-01 (Must)** Sort by any visible column, by clicking its header (click again to reverse) or with **View › Sort By**.
- **FR-SORT-02 (Must)** Name sorting is *natural* (`File 2` before `File 10`), case-insensitive and follows the locale.
- **FR-SORT-03 (Must)** Folders are listed before files by default (setting `foldersFirst`).
- **FR-SORT-04 (Should)** Secondary sort: `Shift+click` on a second column header.
- **FR-SORT-05 (Must)** Re-sorting 100,000 items must finish in under 150 ms (NFR-PERF-06).

### 6.3 Filtering and Quick Filter

#### 6.3.1 Quick Filter (by name)

- **FR-QF-01 (Must)** `Ctrl+F` (or `/`) moves focus to the Quick Filter box. Typing filters the current list **as you type**, without touching the disk.
- **FR-QF-02 (Must)** Matching rules:
  - Plain text: case-insensitive *contains* match on the name.
  - Words separated by spaces: every word must match (AND).
  - `*` and `?` wildcards: glob match on the whole name (e.g. `*.pdf`).
  - A leading `!` negates a word (e.g. `contract !draft`).
  - `ext:pdf,docx` limits by extension.
- **FR-QF-03 (Must)** Matching parts of names are highlighted. The status bar shows `showing M of N`.
- **FR-QF-04 (Must)** `Esc` clears the filter and returns focus to the list. `Down` / `Enter` moves focus into the filtered list.
- **FR-QF-05 (Must)** The filter belongs to the tab and is cleared on navigation (setting `keepFilterOnNavigate = false`).
- **FR-QF-06 (Must)** A filter icon is shown on the tab and in the Address Bar while a filter is active, so the user always knows the list is filtered.

#### 6.3.2 Column filters (Excel-style)

- **FR-CF-01 (Must)** Each column header in Details view has a filter button that opens a drop-down, like Excel's filter on a table:
  - A search box.
  - A checklist of distinct values, with *(Select All)*. For **Type/Extension** and **Sync status**: one entry per value. For **Date** columns: grouped by year › month › day, plus quick choices (*Today*, *Yesterday*, *This week*, *Last 7 days*, *This month*, *This year*). For **Size**: buckets (*Empty*, *< 16 KB*, *16 KB–1 MB*, *1–16 MB*, *16–128 MB*, *> 128 MB*) and a custom *between* range.
  - *Clear filter*.
- **FR-CF-02 (Must)** Column filters combine with each other and with the Quick Filter (AND).
- **FR-CF-03 (Must)** A column with an active filter shows a filled filter icon. **View › Clear All Filters** (`Ctrl+Shift+L`) removes them all.
- **FR-CF-04 (Should)** Column filters can be saved as part of the folder view (FR-VIEW-05). By default they are not saved.

### 6.4 Bookmarks and Favourites

#### 6.4.1 Bookmark data

Each bookmark has: `id`, `name`, `target` (path or URL), `kind` (`folder | file | url`), `group` (path of group names, e.g. `["bar", "Vendors"]`), optional `icon`, optional `shortcutKey`, optional `scope` (Section 6.4.4).

#### 6.4.2 Functions

- **FR-BM-01 (Must)** *Bookmark This Folder* (`Ctrl+D`) and *Bookmark Selected Item* open a small dialog (name, group) that can be confirmed with `Enter`.
- **FR-BM-02 (Must)** Bookmarks are stored in `bookmarks.toml` (Section 8.6) and can be edited by hand. External edits are picked up live.
- **FR-BM-03 (Must)** A bookmark whose target no longer exists is shown greyed out with a warning icon, and offers *Locate…* and *Delete*.
- **FR-BM-04 (Should)** A bookmark can have its own key binding (e.g. `Alt+1`).
- **FR-BM-05 (Should)** Import bookmarks from Explorer *Quick access* (Windows) on first run, if the user agrees.

#### 6.4.3 Favourites

- **FR-FAV-01 (Must)** Pin/unpin a folder to Favourites from the right-click menu, the palette, or by dragging it into the Favourites view.
- **FR-FAV-02 (Must)** Stored as an ordered list in `bookmarks.toml` under `[favourites]`.

#### 6.4.4 Context view and context bookmarks

The idea: when you look at a folder, the sidebar shows links to other folders, documents and web addresses that are related to it (for a vendor folder: the contracts register, the procurement process, the vendor's portal). The idea will evolve as the project takes shape, so v1.0 builds only the **smallest useful version**:

- **FR-CTX-01 (Must)** A bookmark can be linked to one or more folders with `scope`. It shows in the Context view when the current folder is one of those folders or inside one.
- **FR-CTX-02 (Must)** Context bookmarks are stored only in `bookmarks.toml` (Section 8.6). Nothing is written into the folders themselves.
- **FR-CTX-03 (Must)** The Context view lists the context bookmarks for the current folder, nearest scope first.
- **FR-CTX-04 (Must)** *Add Context Bookmark* (`Ctrl+Shift+D`, or dragging an item into the Context view) asks for a name; the target is the dragged or selected item, and the scope is the current folder.
- **FR-CTX-05 (May, future)** Suggest related items automatically (for example, files often opened from this folder, or links used in its project folders). Not built in v1.0.

### 6.5 Per-folder view persistence ("Quick persist")

- **FR-VIEW-01 (Must)** A folder's **view** is: view mode, visible columns (order and widths), sort columns and direction, folders-first, show hidden, and (optionally) column filters.
- **FR-VIEW-02 (Must)** Without saved settings, a folder uses the **default view** from `settings.toml`.
- **FR-VIEW-03 (Must)** Changes to the view affect only the current tab and are **not** saved automatically. A dot appears on the *Save View* button when the current view differs from the saved one.
- **FR-VIEW-04 (Must)** View settings are resolved in this order (first match wins, field by field):
  1. Saved settings for this exact folder (Section 8.4).
  2. Saved settings of the nearest parent folder that has `applyToSubfolders = true`.
  3. The default view in `settings.toml`.
- **FR-VIEW-05 (Must)** The **Save View** toolbar button (`Ctrl+S`) saves the current view for the current folder with one click, with no dialog, in the app settings folder. The status bar confirms *"View saved for <folder>"*.
- **FR-VIEW-06 (Must)** The drop-down arrow next to *Save View* offers: *Save for this folder and subfolders*, *Reset to default view*, *Open folder settings file*.
- **FR-VIEW-07 (Must)** Saving a view never writes anything into the folder itself, so it works the same for read-only, shared and cloud folders.

### 6.6 Quick Find (search in folder and sub-folders)

- **FR-FIND-01 (Must)** `Ctrl+Shift+F` (or `F3`) opens Quick Find for the current folder. Results are shown in a **search results tab** that works like a normal list: it can be sorted, filtered and acted on, and has an extra **Folder** column (path relative to the search root).
- **FR-FIND-02 (Must)** It searches **file and folder names**, recursively, using the same match syntax as the Quick Filter (FR-QF-02), plus:
  - `size:>10mb`, `size:<1kb`
  - `modified:today`, `modified:>2026-01-01`, `modified:7d`
  - `type:folder`, `type:file`
  - `in:subfolder-name`
- **FR-FIND-03 (Must)** Results stream in while the search runs (batched every 50 ms). The status bar shows the number of folders scanned and items found, and the search can be cancelled (`Esc`).
- **FR-FIND-04 (Must)** Search options: include hidden files (default off), follow symbolic links/junctions (default off, with loop protection), maximum depth (default unlimited), maximum results (default 10,000), and skip online-only cloud *folders* that are not yet loaded (default on, to avoid downloading).
- **FR-FIND-05 (Must)** The search runs in parallel across folders using all CPU cores (`ignore::WalkParallel`), without reading file contents.
- **FR-FIND-06 (Should)** The last 20 searches are saved and offered in the find box and the palette.
- **FR-FIND-07 (May, future)** Content search inside files and a background index for instant search across favourite locations.

### 6.7 Create items

- **FR-NEW-01 (Must)** **New Folder** (`Ctrl+Shift+N`) creates `New folder` (with `(2)`, `(3)` … if the name is taken) and starts renaming it at once.
- **FR-NEW-02 (Must)** **New File** (`Ctrl+N`) asks for a name, including the extension, and creates an empty file. The 10 most used extensions are suggested.
- **FR-NEW-03 (Must)** **New Shortcut** asks for a target (path box with autocomplete and a *Browse* button) and a name. It creates a `.lnk` (Windows) or a symbolic link (Linux). **Paste as Shortcut** (`Ctrl+Shift+V`) creates shortcuts to the items on the clipboard.
- **FR-NEW-04 (Must)** **New Web Link** asks for a URL and a name (the name is filled in from the page title if the URL can be reached within 2 s; otherwise from the domain). It creates a `.url` file, which works on all platforms.
- **FR-NEW-05 (Must)** All new items are selected and scrolled into view after they are created.

### 6.8 Create from template

- **FR-TPL-01 (Must)** Templates are ordinary files and folders inside the **templates folder** (default `<app config dir>/templates/`; more folders can be added in `settings.toml`, e.g. a shared team templates folder).
- **FR-TPL-02 (Must)** **New from Template** (`Ctrl+Alt+N`, **File › New from Template ▸**, and the toolbar drop-down) lists templates in a menu that follows the templates folder's structure. Sub-folders whose name starts with `_` are menu groups, not templates.
- **FR-TPL-03 (Must)** A **file** template is copied into the current folder. A **folder** template is copied with all its content (recursively).
- **FR-TPL-04 (Must)** Placeholders in file and folder names are replaced when copying:

  | Placeholder | Replaced with |
  |---|---|
  | `{name}` | The name the user enters |
  | `{date}` | Today's date, `YYYY-MM-DD` (format configurable) |
  | `{year}`, `{month}`, `{day}` | Parts of today's date |
  | `{user}` | The OS user name |
  | `{parent}` | The name of the destination folder |

  Example: template folder `{date} {name}` containing `Notes - {name}.docx` → `2026-10-31 Acme renewal/Notes - Acme renewal.docx`.
- **FR-TPL-05 (Should)** Placeholders in the **content** of plain text files (`.txt`, `.md`, `.csv`, `.html`, `.json`, `.toml`, `.ini`, `.xml`) are replaced too. Binary and Office files are copied unchanged.
- **FR-TPL-06 (Must)** *Save Selection as Template* copies the selected file or folder into the templates folder.

### 6.9 Command palette

- **FR-CMD-01 (Must)** `Ctrl+P` opens the command palette: a centred input with a list of results below, similar to VS Code's *Quick Open*. It must open in under 50 ms.
- **FR-CMD-02 (Must)** Modes, chosen by the first character:

  | Prefix | Mode | Searches |
  |---|---|---|
  | (none) | Go to | Recent folders, favourites, bookmarks, items in the current folder |
  | `>` | Commands | All commands, by name, with their key binding shown (`Ctrl+Shift+P` opens straight into this mode) |
  | `@` | Bookmarks | All bookmarks, including context bookmarks |
  | `/` | Path | Path entry with autocomplete (like the Address Bar) |
  | `?` | Find | Starts Quick Find in the current folder with the rest of the text |
  | `#` | Tabs | Open tabs |

- **FR-CMD-03 (Must)** Fuzzy matching (`nucleo`), with matched letters highlighted. Results are ranked by match quality, then by how often and how recently they were used.
- **FR-CMD-04 (Must)** `Up`/`Down` choose, `Enter` runs, `Ctrl+Enter` opens a folder result in a new tab, `Esc` closes.
- **FR-CMD-05 (Must)** Every command in the application (Appendix A) is available in the palette, including ones that are not in a menu.

### 6.10 Key bindings

- **FR-KEY-01 (Must)** Every command can be bound to one or more keys. Key bindings are defined in `keybindings.toml` (Section 8.3). User bindings override the defaults.
- **FR-KEY-02 (Must)** Chords are supported (e.g. `Ctrl+K Ctrl+B`). A hint shows in the status bar after the first key.
- **FR-KEY-03 (Must)** A binding may have a `when` context: `list`, `tree`, `addressBar`, `palette`, `filter`, `quickView`, or `global` (default).
- **FR-KEY-04 (Must)** **Help › Keyboard Shortcuts** shows a searchable list of all commands and their bindings, and lets the user record a new binding by pressing keys. Conflicts are shown before saving. Changes are written to `keybindings.toml`.
- **FR-KEY-05 (Must)** Invalid entries in `keybindings.toml` are skipped and reported (with line number) in a notification, never a crash.

### 6.11 Opening items

- **FR-OPEN-01 (Must)** Files open with the OS default app. Shortcuts open their target. Web links open in the default browser.
- **FR-OPEN-02 (Must)** **Open With ▸** lists apps registered for the file type (Windows: the registered handlers; Linux: `.desktop` MIME associations) and *Choose another app…*.
- **FR-OPEN-03 (Must)** **Open in Terminal** opens the configured terminal (default on Windows: Windows Terminal, else PowerShell; on Linux: `$TERMINAL`, else `x-terminal-emulator`, else `gnome-terminal` / `konsole`) in the current folder.
- **FR-OPEN-04 (Must)** **Copy Path** (`Ctrl+Shift+C`) copies the full path(s) of the selection, one per line. **Copy Name** copies names only.

### 6.12 File operations

#### 6.12.1 General

- **FR-OP-01 (Must)** Copy (`Ctrl+C`), Cut (`Ctrl+X`), Paste (`Ctrl+V`), Rename (`F2`), Delete (`Del`), Delete Permanently (`Shift+Del`). These use the OS clipboard, so files can be copied to and from other file managers.
- **FR-OP-02 (Must)** Copy, move and delete run as background **jobs** (Section 4.3). The UI stays usable. Several jobs can run at once; jobs on the same physical drive are run one after another by default to avoid disk thrashing.
- **FR-OP-03 (Must)** Each job shows progress (bytes and items, speed, time left) in the status bar and the Jobs panel, and can be paused or cancelled.
- **FR-OP-04 (Must)** Errors on single items (access denied, file in use, path too long) do not stop the job. They are collected and shown at the end with *Retry*, *Skip* and *Show in folder*.

#### 6.12.2 Copy and move

- **FR-COPY-01 (Must)** Moving within the same volume is a rename (instant). Moving between volumes is copy, verify size, then delete the source.
- **FR-COPY-02 (Must)** Files are copied with the OS fast-copy function where available (Windows `CopyFileEx`, Linux `copy_file_range`, with reflink on file systems that support it), keeping timestamps and, where possible, attributes.
- **FR-COPY-03 (Must)** Files are first written to a temporary name in the destination folder and renamed when complete, so a cancelled or failed copy never leaves a half-written file under the real name.
- **FR-COPY-04 (Must)** **Name conflicts** open a dialog showing both files (size, date, preview icon) with: *Replace*, *Skip*, *Keep both* (adds ` (2)`), *Replace if newer*, *Compare* (open both), plus *Apply to all remaining conflicts*.
- **FR-COPY-05 (Must)** Copying or moving a folder into itself or one of its own sub-folders is refused with a clear message.
- **FR-COPY-06 (Must)** Drag and drop: same volume = move, other volume = copy (like Explorer). Holding `Ctrl` forces copy, `Shift` forces move, `Alt` creates shortcuts. The cursor shows which will happen.
- **FR-COPY-07 (Must)** Copying from online-only cloud locations is allowed (it downloads the file), and the progress shows *"Downloading…"*.

#### 6.12.3 Rename

- **FR-REN-01 (Must)** `F2` renames in place. The name without the extension is selected first; pressing `F2` again cycles through: whole name → extension only → name only.
- **FR-REN-02 (Must)** Names are checked as you type (characters not allowed on the platform, reserved names such as `CON`/`NUL` on Windows, names that already exist, path length). An error is shown next to the edit box and `Enter` is blocked until it is fixed.
- **FR-REN-03 (Must)** Changing the extension asks for confirmation (setting `confirmExtensionChange`).
- **FR-REN-04 (Should)** **Batch rename** (when more than one item is selected): find/replace (with optional regex), add prefix/suffix, numbering (`{n:3}` → `001`), change case. A live preview of old → new names is shown before applying.

#### 6.12.4 Delete

- **FR-DEL-01 (Must)** `Del` moves items to the Recycle Bin / Trash. A confirmation is shown only when the setting `confirmDelete` is on (default: off for the Recycle Bin, since it can be undone).
- **FR-DEL-02 (Must)** `Shift+Del` deletes permanently, always after a confirmation that names the items (or the count, and the first 10 names).
- **FR-DEL-03 (Must)** If the item cannot go to the Recycle Bin (e.g. network drives), the user is told it will be deleted permanently and must confirm.

#### 6.12.5 Undo

- **FR-UNDO-01 (Should)** `Ctrl+Z` undoes the last operation from this session: rename (rename back), move (move back), copy (send the copies to the Recycle Bin), create (send to the Recycle Bin), delete to Recycle Bin (restore). Permanent deletes cannot be undone. Undo history: the last 50 operations.
- **FR-UNDO-02 (Should)** Before undoing, the app checks that the files have not changed since. If they have, it asks first.

#### 6.12.6 Duplicate, ZIP and Compare

- **FR-DUP-01 (Must)** **Duplicate** makes a copy of each selected item next to the original, named like Explorer does: `Report - Copy.docx`, then `Report - Copy (2).docx`. Runs as a job.
- **FR-ZIP-01 (Later)** **Compress to ZIP** packs the selected items into one `.zip` file in the current folder (named after the single item, or after the folder for several items) and starts renaming it. Runs as a job with progress.
- **FR-ZIP-02 (Later)** **Extract ▸** for `.zip` files: *Extract here* and *Extract to "<zip name>"*. Runs as a job; name conflicts use the conflict dialog (FR-COPY-04). Entries that would land outside the destination folder (`../` paths) are refused.
- **FR-CMP-01 (Excluded)** **Compare** (exactly two files selected) checks whether they are identical (size first, then content) and shows the result in the status bar. If a compare tool is set (`compare.tool` in `settings.toml`, e.g. WinMerge or Meld), it opens the two files in that tool instead. The conflict dialog's *Compare* button (FR-COPY-04) uses the same function.

### 6.13 Properties

- **FR-PROP-01 (Must)** **Properties** (`Alt+Enter`) shows the path, size (folder size calculated in the background), created/modified/accessed dates, attributes, link target, and sync status.
- **FR-PROP-02 (Should)** On Windows, a button opens the native Explorer Properties dialog.

### 6.14 Project folders

> **Not in v1.0** (decision 2026-11-01). Kept here for a later version.

This section supports the main workflow in the requirements: open a project folder for a short task, gather links to documents and websites from other folders, work in it, and when the project is done, file it under the main subject folder (for example, a vendor folder). Everything stays plain files and folders, so the project folder still works without File Catalog.

- **FR-PRJ-01 (Must)** **New Project Folder** creates a folder from a chosen folder template (default template `_Projects/{date} {name}`, editable) in the configured projects location (`projects.root` in `settings.toml`; default: the current folder), and opens it in a new tab.
- **FR-PRJ-02 (Must)** **Link Selected into Project…** (and dragging with `Alt` onto a project tab or folder) creates **shortcuts** to the selected files and folders inside a chosen project folder. A palette list of open and recent project folders makes this quick. Web addresses are added as web links (`.url`).
- **FR-PRJ-03 (Must)** Shortcuts in a project folder behave like their targets: `Enter` opens the target, Quick View previews the target, and the **Link target** column shows where it points.
- **FR-PRJ-04 (Must)** **File Project…** moves the project folder into a chosen destination (with a folder picker that suggests the most-used bookmarks, favourites and context bookmarks). Before moving, a dialog lists the shortcuts in the project and asks, for each one or for all:
  - **Keep as link** (default): the shortcut stays and still points to the original.
  - **Copy target in**: replace the shortcut with a copy of the target file/folder.
  - **Move target in**: move the target into the project and leave nothing at the old place. (Warns that other links to it may break.)
  - **Remove link**.
- **FR-PRJ-05 (Should)** After filing, the app offers to add a context bookmark to the destination folder pointing at the filed project.
- **FR-PRJ-06 (Must)** Broken shortcuts (target missing) are marked in the list and offer *Locate…* (search for a file with the same name and size) and *Delete*.
- **FR-PRJ-07 (Must)** E-mails are added to a project folder as saved files (`.eml`, `.msg`) and then work like any other file. Direct integration with e-mail clients is not part of v1.0.

---

## 7. Non-functional requirements

### 7.1 Performance

Reference hardware: 4-core CPU (2020 or newer), 8 GB RAM, NVMe SSD. Targets apply to both **Windows 11** (WebView2 already installed) and **Ubuntu 24.04 LTS**. Times are 95th percentile.

> Risk: WebKitGTK usually starts more slowly than WebView2. The Linux start-up time must be measured in M1; if 500 ms can't be met on Linux, the gap and options are brought back for a decision rather than quietly relaxing the target.

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

**How the 500 ms start is reached:**
1. Rust starts the window at once with a minimal, inline-styled HTML shell, while reading settings and the session snapshot in parallel.
2. The Elm bundle is small (≤ 80 KB gzipped) and embedded in the binary.
3. The first listing comes from the session snapshot (Section 4.5) and is then refreshed in the background.
4. Anything not needed for the first view (icon extraction, sync status, the tree, bookmarks validation, templates scan) is loaded after the first paint.
5. Start-up time is measured in CI on every build; a build fails if it is more than 10% over budget.

### 7.2 Reliability and data safety

- **NFR-REL-01** No operation may lose user data. File operations use temp-then-rename (FR-COPY-03); moves between volumes delete the source only after the copy is verified.
- **NFR-REL-02** Settings files are written atomically (write to a temp file, then rename). The previous version is kept as `<name>.bak`.
- **NFR-REL-03** A settings file with errors never stops the app from starting. The app uses defaults for the broken part, shows a notification with the file name, line and error, and does **not** overwrite the broken file.
- **NFR-REL-04** A crash in a background job must not crash the UI. Panics are caught per job and logged.
- **NFR-REL-05** Network or cloud locations that become unavailable are shown as *unavailable*, not as empty folders.

### 7.3 Usability and accessibility

- **NFR-UX-01** All functions can be reached by keyboard (FR-UI-05).
- **NFR-UX-02** WCAG 2.1 AA colour contrast in both themes. Screen reader support through correct ARIA roles (`tree`, `grid`, `listbox`, `dialog`).
- **NFR-UX-03** Supports display scaling 100–300% and per-monitor DPI.
- **NFR-UX-04** UI text is in English for v1.0, with all strings kept in one Elm module so they can be translated later. Dates and numbers follow the OS locale.

### 7.4 Security and privacy

- **NFR-SEC-01** No telemetry, no accounts, no network access except: fetching a web page title for *New Web Link* (FR-NEW-04) and opening URLs in the user's browser.
- **NFR-SEC-02** Tauri capabilities are limited to the defined IPC commands. The web view cannot load remote content. A strict Content Security Policy is set.
- **NFR-SEC-03** Paths from the UI are always checked by the Rust core; the UI is never trusted to decide what is safe.
- **NFR-SEC-04** Settings are read only from the app settings folder. File Catalog never reads or acts on configuration files found inside the folders it shows.

### 7.5 Maintainability

- **NFR-MNT-01** Rust: `cargo clippy -D warnings` and `cargo fmt` pass. Elm: `elm-format` and `elm-review` pass.
- **NFR-MNT-02** Test coverage: Rust core ≥ 80% lines for file operations, settings and search. Elm: `elm-test` for update logic, filter/sort and key binding parsing.
- **NFR-MNT-03** Logs (`tracing`) go to `<app data dir>/logs/`, rotated daily, kept for 7 days. The default level is `info`.

---

## 8. Configuration and settings files

### 8.1 Principles

- All settings are **TOML** files, easy for people to read and edit (chosen over INI because TOML supports lists and nested tables without inventing a syntax).
- Files are written with `toml_edit`, so the user's **comments, order and formatting are kept** when the app saves changes.
- Files are **watched**: when edited outside the app they are reloaded at once (`settings.changed` event).
- Each file starts with a comment that explains what it is and links to the documentation.
- Only values that differ from the default need to be in the file. The app writes defaults only when it first creates the file, and leaves them commented out (`# key = default`), so users can see what is possible.

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
├── bookmarks.toml       # Bookmarks, favourites, personal context bookmarks (8.6)
├── session.toml         # Open tabs, recent folders, recent searches (written by the app)
├── folders/             # Per-folder view settings (8.4)
│   └── <name>-<hash>.toml
├── templates/           # Templates (6.8)
└── logs/
```

### 8.3 `settings.toml` and `keybindings.toml`

```toml
# File Catalog settings — https://<docs>/settings
# Only values that differ from the defaults are needed.

[general]
startupFolder   = "last"          # "last" | "home" | a path
restoreTabs     = true
homeFolder      = "~"
theme           = "system"        # "system" | "light" | "dark"
confirmDelete   = false
confirmExtensionChange = true
typingStartsFilter = false
terminal        = "wt"            # command used by Open in Terminal

[layout]
menuBar = true
toolbar = true
bookmarkBar = true
tabBar = true
addressBar = true
statusBar = true
sidebar = { visible = true, side = "left",  width = 260, mode = "tree" }
quickView = { visible = false, side = "right", width = 360 }

[view.default]
mode        = "details"           # "details" | "list"
columns     = ["name", "modified", "created", "size", "sync"]
sort        = [{ column = "name", direction = "asc" }]
foldersFirst = true
showHidden  = false
showExtensions = true
dateFormat  = "yyyy-MM-dd HH:mm"

[search]
includeHidden   = false
followLinks     = false
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
# Use "" to remove a default binding.

[[bind]]
key = "Ctrl+E"
command = "find.open"

[[bind]]
key = "Ctrl+K Ctrl+B"
command = "view.toggleSidebar"

[[bind]]
key = "Space"
command = "quickView.toggle"
when = "list"

[[bind]]
key = "Alt+1"
command = "bookmark.open"
args = { name = "Acme" }
```

### 8.4 Folder settings

Folder settings hold a folder's saved **view** (Section 6.5). They are stored **only in the app settings folder**, one file per folder:

`<app settings>/folders/<folder name>-<8-char hash of full path>.toml`

File Catalog never writes settings into the folders it shows, so shared, read-only and cloud folders are never changed. Context bookmarks are kept in `bookmarks.toml` (Section 8.6).

- **FR-FS-01 (Must)** Each file stores the full `path` of the folder it belongs to, so it is easy to find and edit by hand.
- **FR-FS-02 (Should)** When File Catalog renames or moves a folder, the folder's settings file is updated to follow it. **Tools › Clean Up Folder Settings** lists settings files whose folder no longer exists.
- **FR-FS-03 (Must)** Deleting a folder settings file resets that folder to the default view.

```toml
# Acme-3f9a12c0.toml — saved view for one folder.
# Safe to delete; the folder then uses the default view.

path = 'C:\Vendors\Acme'
applyToSubfolders = false

[view]
mode    = "details"
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
  "view.saveForFolder", "view.toggleQuickView",
  "->",                         # push the rest to the right
  "palette.open",
]
```

`"|"` is a separator and `"->"` is flexible space.

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

[[bookmark]]
name   = "Procurement process"
target = 'S:\Procurement\Process'
scope  = ['C:\Vendors']          # personal context bookmark
```

---

## 9. Error handling and messages

| Situation | Behaviour |
|---|---|
| Folder not found / no access | Content area shows the error with *Retry* and *Go up*. The tab keeps its history. |
| Network path slow or offline | Spinner for up to `timeoutSeconds`, then *"Location not available"* with *Retry*. Other tabs keep working. |
| File in use during an operation | Collected in the job's error list; *Retry* / *Skip*. Windows shows which app holds it, when the Restart Manager can tell. |
| Not enough space | The job pauses and asks *Retry* / *Cancel*. Checked before starting when the total size is known. |
| Path too long (Windows) | Long paths (`\\?\`) are used internally. Paths over 260 characters are allowed, with a warning that some apps may not open them. |
| Settings file has errors | NFR-REL-03. |

Messages say what happened, why (if known), and what the user can do next. Notifications appear in the bottom-right corner, stack, and do not take focus.

---

## 10. Testing and acceptance

- **Unit tests** for each `FR-` with logic (filter syntax, sort order, placeholders, settings merge, key binding parsing, name checks).
- **Integration tests** (Rust) against temporary directory trees for all file operations, including conflicts, cancellation, errors and undo.
- **End-to-end tests** with `tauri-driver` (WebDriver) for the main user flows: navigate, filter, find, create from template, copy with conflict, save view, create project and file it.
- **Performance tests** (NFR-PERF) run in CI on fixed Windows and Linux runners with generated folders of 1k / 10k / 100k / 500k items.
- **Acceptance:** v1.0 is accepted when all *Must* requirements pass their tests and all NFR-PERF targets are met on the reference hardware.

---

## 11. Delivery plan

| Milestone | Content | Status |
|---|---|---|
| **M1 — Core shell** | Tauri + Elm skeleton, IPC bridge, directory listing with cache and watcher, Details view (virtualised), navigation, Address Bar, tabs, status bar, `settings.toml`. | Done (2026-10-31). Start-up still to be measured on Windows. |
| **M2 — Organise** | See 11.1. | Done (2026-10-31), with the deferrals listed in 11.1. |
| **M3a — Operate: core** | See 11.2. | Done (2026-10-31), with the deferrals listed in 11.2. |
| **M3b — Operate: integration** | Clipboard exchange with Explorer and other file managers (including *Paste as Shortcut*), drag and drop (including onto the sidebar, Bookmark Bar and tabs), templates (6.8). ZIP moved to a later version and Compare dropped (decision 2026-11-01). See 11.3. | Done (2026-11-01), with the deferrals listed in 11.3. |
| **M4 — Speed** | Command palette, key bindings file and editor (menus then show custom keys), customisable toolbar, Quick Find. | Next |
| **M5 — Projects and polish** | Context bookmarks and Context view, Quick View, lazy metadata columns (Owner, Windows document properties, registered type names), accessibility, themes, installer. | |

### 11.1 M2 — Organise

| # | Part | Requirements |
|---|---|---|
| 1 | **Menu Bar**: all menus from 5.2; items not built yet are shown disabled; opens with `Alt` / `F10` and `Alt+<letter>` | FR-MENU-01, FR-UI-01 |
| 2 | **Sorting**: header click, natural name sort, folders first, `Shift+click` secondary sort, **View › Sort By** | FR-SORT-01 to 05 |
| 3 | **Quick Filter**: `Ctrl+F` / `/`, filter as you type, wildcards, `!` exclusion, `ext:`, highlighted matches, "showing M of N" | FR-QF-01 to 06 |
| 4 | **Column filters (Excel-style)**: value checklist with search, date groups and quick choices, size buckets | FR-CF-01 to 04 |
| 5 | **Columns**: show/hide (header right-click, **View › Columns**), resize and reorder by dragging; Date accessed, Attributes and Link target added | FR-CC-01, FR-COL-01 |
| 6 | **Save View** (`Ctrl+S`) and per-folder settings in the app settings folder, *apply to subfolders*, Reset | FR-VIEW-01 to 07, FR-FS-01, FR-FS-03 |
| 7 | **Sidebar**: dockable and resizable; Tree view and Favourites view (pin/unpin) | FR-SB-01, FR-FAV-01 to 02, FR-UI-02 |
| 8 | **Bookmarks**: Bookmark Bar with groups, `Ctrl+D`, sidebar Bookmarks view, `bookmarks.toml` with live reload | FR-BB-01, 02, 04, FR-BM-01 to 03 |

Also: find the 200–350 ms delay between UI start and first listing seen in M1. *Found: at start-up the folder tree sent its requests at the same time as the first listing, and they queued ahead of it. The tree now loads after the first listing; the UI shows the first folder 11–16 ms after it starts.*

**Deferred from M2** (not built yet):

| Item | Requirement | Moved to |
|---|---|---|
| Custom "between" range in the Size column filter (the size buckets work) | FR-CF-01 | M4 |
| Saving column filters as part of a folder view | FR-CF-04 (Should) | M4 |
| Dragging items onto the Bookmark Bar, sidebar or tabs | FR-BB-03, FR-TAB-05 | Done in M3b |
| `»` overflow menu on a full Bookmark Bar | FR-BB-05 (Should) | M5 |
| Reordering tabs and favourites by dragging (favourites can be moved with *Move Up/Down*) | FR-TAB-02, FR-SB-01 | M4 |
| *Locate…* for a bookmark whose target is missing (*Delete* works) | FR-BM-03 | M4 (needs Quick Find) |
| Type-ahead in the folder tree (it works in the file list) | FR-SB-01 | M4 |
| A folder's saved view follows it when File Catalog renames or moves it | FR-FS-02 | M3 (with rename and move) |

### 11.2 M3a — Operate: core

Built: background job queue with progress, speed, time left, pause and cancel, and a Jobs panel (FR-OP-02, 03, 04); copy and move with conflict dialog, *Keep both*, *Replace if newer* and *apply to all*, temporary-name copies, kept timestamps, folders never copied into themselves, cross-volume moves (FR-COPY-01 to 05); in-place rename with live name checks, F2 selection cycle and extension warning (FR-REN-01 to 03); Delete to the Recycle Bin / Trash, Shift+Del with confirmation, permanent-delete offer when the Recycle Bin refuses (FR-DEL-01 to 03); Undo of rename, move, copy, create and delete (FR-UNDO-01); New Folder / File / Shortcut / Web Link (FR-NEW-01 to 05); Duplicate (FR-DUP-01); Copy Path (FR-OPEN-04); Open in Terminal (FR-OPEN-03); Show in File Manager; right-click menus on items and on empty space (FR-CC-07); cut and paste inside File Catalog.

**Deferred from M3a:**

| Item | Requirement | Moved to |
|---|---|---|
| Several jobs at once on different drives (jobs now run one after another) | FR-OP-02 | M4 |
| *Retry* and *Skip* buttons for failed items (*Show in folder* works) | FR-OP-04 | M4 |
| Progress inside one very large file (progress now moves per file) | FR-OP-03 | M4 |
| *Compare* button in the conflict dialog | FR-COPY-04 | Dropped with Compare (FR-CMP-01) |
| *"Downloading…"* label when copying online-only cloud files | FR-COPY-07 | Later version (with sync status) |
| Batch rename | FR-REN-04 (Should) | M4 |
| Checking that files changed since the operation before undoing a copy or create | FR-UNDO-02 (Should) | M4 |
| Filling in a web link's name from the page title (the domain is used) | FR-NEW-04 | M5 |
| *Open With* and *Properties* | FR-OPEN-02, FR-PROP-01 | M5 |
| Windows "Show more options" (native Explorer menu) | FR-CC-07 | M5 |

### 11.3 M3b — Operate: integration

Built: files exchanged through the system clipboard with Explorer and other file managers, both ways (FR-OP-01), with Explorer's *cut* marker on Windows; *Paste as Shortcut* (Ctrl+Shift+V); drag and drop inside File Catalog onto folders, the folder tree, Favourites, tabs and the Bookmark Bar, with Ctrl = copy, Shift = move, Alt = shortcuts and otherwise move on the same drive / copy across drives (FR-COPY-06, FR-BB-03, FR-TAB-05); files dropped in from other apps; dragging items out of the window to other apps (FR-CC-08); templates with `_Group` menus, placeholders in names and in text-file contents, *Save Selection as Template* and *Edit Templates Folder* (FR-TPL-01 to 06); `[templates]` in settings.toml.

**Deferred from M3b:**

| Item | Requirement | Moved to |
|---|---|---|
| On Linux, a *cut* in File Catalog pastes as a copy in other file managers (the clipboard library can't mark a cut there) | FR-OP-01 | Later version |
| Highlighting the target folder while files from another app are dragged over the window | FR-CC-08 | M5 |
| A drag cursor that shows copy / move / shortcut | FR-COPY-06 | M5 |
| Checked by hand only inside File Catalog: dropping onto Explorer / another app and dropping in from them still need a test on Windows and Linux | FR-CC-08 | Windows test |

---

## 12. Out of scope for v1.0

- Project folders (6.14), cloud sync status beyond the basic Windows column (5.8.1), and pinned tabs (FR-TAB-03); decision 2026-11-01.
- Compress/Extract ZIP (FR-ZIP-01, FR-ZIP-02): a later version. Compare (FR-CMP-01): dropped.
- Searching inside file contents, and a background search index (FR-FIND-07).
- Built-in cloud storage clients (the app uses the OS sync clients' folders).
- E-mail client integration (e-mails are handled as saved files; FR-PRJ-07).
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
| 2026-10-31 | E-mails handled as saved files; no e-mail client integration in v1.0 | FR-PRJ-07 |
| 2026-10-31 | Context view kept minimal in v1.0, to evolve with use | 6.4.4 |
| 2026-10-31 | Standard File Explorer columns available; Name, dates, Size, Sync status shown by default | 5.8.2 |
| 2026-10-31 | *File Project* with link options kept | FR-PRJ-04 |
| 2026-10-31 | Duplicate, Compress/Extract ZIP and Compare added | 6.12.6 |
| 2026-11-01 | Project folders, cloud sync status (beyond the basic Windows column) and pinned tabs moved out of v1.0; this replaces the 2026-10-31 *File Project* decision | 1.3, 5.8.1, 6.14, 12 |
| 2026-11-01 | Compress/Extract ZIP moved to a later version; Compare dropped | 6.12.6, 12 |

---

## 14. Requirements traceability

| Requirement (from Requirements Document) | Specified in |
|---|---|
| File explorer: find/open documents, basic file operations | 6.1, 6.11, 6.12 |
| Focus on organising and navigating many files | 6.4, 6.5, 6.14 |
| Link documents from several folders into a project, then move it back | 6.14 (later version) |
| Use standard files/folders; works without the app | 1.2, 6.7, 6.14 |
| Ultra-fast, keyboard-driven | 6.9, 6.10, 7.1, FR-UI-05 |
| Full Menu Bar | 5.2 |
| Customisable Toolbar | 5.3, 8.5 |
| Bookmark Bar | 5.4, 6.4 |
| Tab Bar | 5.5 |
| Address Bar — breadcrumb mode | 5.6 |
| Dockable sidebar, content container, right quick view | 5.1 (FR-UI-02), 5.7, 5.8, 5.9 |
| Sidebar: tree, favourites, full bookmarks, content-aware bookmarks | 5.7, 6.4.3, 6.4.4 |
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
| Copy, move, rename, delete, plus duplicate, ZIP and compare | 6.12 |
| Open within 500 ms, caching, multithreading | 4.3, 4.5, 4.6, 7.1 |
| Rust or Zig backend and UI container | 3.1 (Rust + Tauri) |
| Elm front end | 3.2 |
| Settings in user app folder, INI or TOML, human-readable | 8.1–8.3, 8.5, 8.6 |
| Folder settings saved in the app settings folder | 6.5, 8.4 |
| Platforms: Windows primary, Linux supported | 2 |
| File system work must not affect the UI | 4.3 |

---

## Appendix A — Commands and default key bindings

| Command ID | Name | Default key |
|---|---|---|
| `nav.back` / `nav.forward` | Back / Forward | `Alt+Left` / `Alt+Right` |
| `nav.up` | Up | `Alt+Up`, `Backspace` |
| `nav.home` | Home | `Alt+Home` |
| `nav.refresh` | Refresh | `F5` |
| `nav.focusAddress` | Go to Address | `Ctrl+L`, `Alt+D` |
| `tab.new` / `tab.close` / `tab.reopen` | New / Close / Reopen Closed Tab | `Ctrl+T` / `Ctrl+W` / `Ctrl+Shift+T` |
| `tab.next` / `tab.prev` | Next / Previous Tab | `Ctrl+Tab` / `Ctrl+Shift+Tab` |
| `tab.goto1…9` | Go to Tab 1–9 | `Ctrl+1…9` |
| `window.new` | New Window | `Ctrl+Shift+W` |
| `palette.open` | Command Palette (Go to) | `Ctrl+P` |
| `palette.commands` | Command Palette (Commands) | `Ctrl+Shift+P` |
| `filter.focus` | Quick Filter | `Ctrl+F`, `/` |
| `filter.clearAll` | Clear All Filters | `Ctrl+Shift+L` |
| `find.open` | Quick Find | `Ctrl+Shift+F`, `F3` |
| `new.file` | New File | `Ctrl+N` |
| `new.folder` | New Folder | `Ctrl+Shift+N` |
| `new.fromTemplate` | New from Template | `Ctrl+Alt+N` |
| `new.shortcut` / `new.webLink` | New Shortcut / New Web Link | — |
| `edit.cut` / `edit.copy` / `edit.paste` | Cut / Copy / Paste | `Ctrl+X` / `Ctrl+C` / `Ctrl+V` |
| `edit.pasteShortcut` | Paste as Shortcut | `Ctrl+Shift+V` |
| `edit.copyPath` | Copy Path | `Ctrl+Shift+C` |
| `edit.duplicate` | Duplicate | — |
| `file.compressZip` / `file.extractHere` / `file.extractTo` | Compress to ZIP / Extract Here / Extract To | — |
| `file.compare` | Compare | — |
| `edit.rename` | Rename | `F2` |
| `edit.delete` / `edit.deletePermanent` | Delete / Delete Permanently | `Del` / `Shift+Del` |
| `edit.undo` | Undo | `Ctrl+Z` |
| `edit.selectAll` / `edit.invertSelection` | Select All / Invert Selection | `Ctrl+A` / `Ctrl+I` |
| `item.open` / `item.openNewTab` | Open / Open in New Tab | `Enter` / `Ctrl+Enter` |
| `item.properties` | Properties | `Alt+Enter` |
| `item.openTerminal` | Open in Terminal | `` Ctrl+` `` |
| `view.saveForFolder` | Save View for This Folder | `Ctrl+S` |
| `view.resetForFolder` | Reset View for This Folder | — |
| `view.toggleSidebar` | Toggle Sidebar | `Ctrl+B` |
| `view.sidebarMode.tree/favourites/bookmarks/context` | Sidebar Mode | `Ctrl+Shift+1…4` |
| `quickView.toggle` | Toggle Quick View | `Space` (list), `Ctrl+Q` |
| `view.toggleHidden` | Show Hidden Files | `Ctrl+H` |
| `focus.nextRegion` / `focus.prevRegion` | Next / Previous Region | `F6` / `Shift+F6` |
| `bookmark.addFolder` | Bookmark This Folder | `Ctrl+D` |
| `bookmark.addContext` | Add Context Bookmark | `Ctrl+Shift+D` |
| `favourite.toggle` | Pin / Unpin Favourite | — |
| `project.new` / `project.link` / `project.file` | New Project / Link into Project / File Project | — |
| `settings.open` / `keybindings.open` | Open Settings / Key Bindings File | `Ctrl+,` / `Ctrl+K Ctrl+S` |
| `help.shortcuts` | Keyboard Shortcuts | `Ctrl+/` |
