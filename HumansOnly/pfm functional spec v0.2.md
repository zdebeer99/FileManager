# Functional Specification & AI Prompt Directive: PowerFileManager (PFM)
**Project Codename:** PowerFileManager (PFM)  
**Target Operating Systems:** Windows 10/11 (x64, ARM64) | macOS 12+ (Apple Silicon, Intel) | Linux (x86_64, aarch64)  
**Core Technologies:** Zig (v0.13.0+) + Elm (v0.19.1) via Embedded Native OS WebView  
**Document Purpose:** Master Functional Specification & Self-Contained AI Implementation Prompt  

---

```
========================================================================================
                          AI IMPLEMENTATION DIRECTIVE
========================================================================================
You are an expert systems engineer and frontend architect. You are tasked with developing
a high-performance, responsive, cross-platform desktop file manager called PowerFileManager.

PRIMARY DIRECTIVES:
1. Systems Core: Implement all native file I/O, multithreading, background transfer queues,
   filesystem watching, search crawlers, and OS windowing in Zig (0.13.0+).
2. UI & Interaction Layer: Implement all layout, state machines, dual-pane logic, virtualized
   DOM grids, dialogs, and user interaction in Elm (0.19.1) compiled to HTML/JS.
3. Host Window: Embed the platform-native WebView (WebView2 on Windows, WKWebView on macOS,
   WebKitGTK on Linux) via Zig without bundling Chromium or Electron.
4. IPC Communication: Use asynchronous JSON-RPC style message passing across Elm Ports.
5. Code Completeness: Produce fully working, production-grade code. Do not emit stubs,
   placeholders, or truncated "// TODO: implement later" blocks.
6. Paragraph ending with '- [Ignore]', must be ignored as a requirement. This statement will be used to comment out requirements.
========================================================================================
```

---







## 1. Product Vision & Non-Negotiable Performance Goals

PowerFileManager is designed as an ultra-fast, keyboard-driven, dual-pane desktop file manager combining the bare-metal performance of **Zig** with the guaranteed runtime stability and predictability of **Elm**.

### Performance Benchmarks (Hard Criteria)
- **Cold Boot Time:** `< 500 ms` from executable launch to interactive UI.
- **Directory Listing Latency:** `< 300 ms` to enumerate, categorize, sort, and display 1,000 files.
- **RAM Footprint:** `< 40 MB` at idle; `< 90 MB` under heavy transfer and search workloads. - [Ignore]
- **Binary Footprint:** `< 8 MB` standalone executable (excluding the OS-bundled WebView runtime). - [Ignore]
- **Runtime Error Rate:** `0` uncaught UI runtime exceptions (enforced by Elm's type system).

---

## 2. Functional Requirements & Feature Specification

### 2.1 Window & Pane Management

#### 2.1.1 Dual-Pane Layout Modes

The application must support two primary viewing configurations:
1. **Single Pane:** Standard full-width file view.
2. **Dual-Pane Vertical Split (Default Commander Mode):** Two independent file panes displayed side-by-side with an adjustable divider.



#### 2.1.2 Active Pane Semantics

- At any moment, exactly one pane is marked as the **Active Pane** (`PaneId: Left | Right`).
- The Active Pane is visually emphasized with an accent border and elevated title styling.
- All global keyboard shortcuts (navigation, selection, new folder, delete, search) apply strictly to the Active Pane.
- The inactive pane acts as the **Target Pane** for quick transfer operations (e.g., pressing `F5` copies selection to the Target Pane; `F6` moves selection).
- Pressing `Tab` or `F6` toggles focus between the panes instantly.



#### 2.1.3 Tabbed Browsing
- 
- Each pane maintains its own independent collection of tabs.
- Features per tab:
  - New tab (`Ctrl+T`), close current tab (`Ctrl+W`), duplicate tab, close other tabs.
  - Independent browsing history stack (Back `Alt+Left`, Forward `Alt+Right`, Up to Parent `Backspace` or `Alt+Up`).
  - Independent scroll offset memory, column sort configuration, and selection cache.
  - Tab titles display the folder name with path tooltip on hover.

---

### 2.2 Navigation, Path Bar & Sidebar

#### 2.2.1 Interactive Breadcrumb & Path Input Bar
- Located at the top of each pane.
- **Breadcrumb Mode:** Displays clickable directory path tokens (e.g., `C: > Users > Developer > Projects`). Clicking any segment navigates directly to it.
- **Inline Text Input Mode (`Ctrl+L`):** Clicking the background or pressing `Ctrl+L` transforms the breadcrumbs into a standard text input field:
  - Supports manual path typing, pasting, and Windows/POSIX path normalization.
  - Auto-completion suggestions matching subdirectories as the user types.
  - Pressing `Enter` commits navigation; pressing `Escape` cancels and restores breadcrumbs.

#### 2.2.2 Sidebar & Quick Access
The collapsible left sidebar contains:
1. **Drives & Volumes:** Enumerate all mounted drives (e.g., `C:\`, `D:\`, `/`, `/Volumes/Data`) with storage capacity bars (Total, Free, Used percentage) and removable drive indicators.
2. **Standard Folders:** Quick links to Home, Desktop, Documents, Downloads, Pictures, Music, Videos.
3. **Favorites / Bookmarks:** User-pinned custom directory shortcuts (add via drag-and-drop or context menu; remove via right-click).
4. **Trash / Recycle Bin:** One-click navigation to system trash.

---

### 2.3 File Listing & Virtualized Grid Engine

#### 2.3.1 View Modes
- **Details Table View (Default):** Multi-column grid displaying Name, Extension, Size, Date Modified, Date Created, and Attributes/Permissions.
- **Compact List View:** Multi-column layout optimized for high density.
- **Tiles / Grid View:** Card-based view with large file type icons and metadata badges.

#### 2.3.2 DOM Virtualization Algorithm
Because directories can contain over 100,000 files, the Elm frontend must **never** instantiate DOM elements for the full list:
- The container measures viewport height (`viewportHeight`) and row height (fixed `32px` in Details View).
- Calculate `startIndex = max(0, floor(scrollTop / rowHeight) - 3)`.
- Calculate `visibleCount = ceil(viewportHeight / rowHeight) + 6`.
- Slice `entries` from `startIndex` to `startIndex + visibleCount`.
- Render a virtual spacer `div` with total height `totalEntries * rowHeight`.
- Position visible rows with CSS `transform: translateY(topPx)`.
- Guarantees `< 50` total active DOM nodes regardless of directory size.

#### 2.3.3 Sorting & Filtering
- Clicking column headers toggles sort: Alphabetical Name, Size (bytes), Date Modified, Extension.
- **Directory Grouping:** Folders are always grouped at the top, sorted alphabetically, followed by files.
- **Live In-Directory Filter (`/` or `Ctrl+I`):** Typing in the filter box instantaneously filters the visible rows using substring or fuzzy matching without re-querying the disk.

---

### 2.4 Selection, Keyboard Ergonomics & Context Menu

#### 2.4.1 Selection Model
- Single click / Arrow keys: Select single item, clear previous selections.
- `Ctrl + Click` / `Space`: Toggle selection of individual items without clearing others.
- `Shift + Click` / `Shift + Up/Down`: Range selection from anchor to cursor.
- `Ctrl + A`: Select all items in active tab.
- `Ctrl + Shift + A`: Invert current selection.
- Lasso Marquee: Click and drag empty space to rubber-band select files.

#### 2.4.2 Comprehensive Keyboard Shortcuts Map
| Keybinding | Scope | Operation |
| :--- | :--- | :--- |
| `Tab` / `F6` | Global | Switch focus between Left and Right panes |
| `Up` / `Down` | Pane | Move cursor up / down |
| `Enter` | Pane | Open folder or launch file with OS default handler |
| `Backspace` / `Alt+Up` | Pane | Navigate to parent directory |
| `Alt + Left / Right` | Pane | History back / forward |
| `Space` | Pane | Open Quick Look Preview modal |
| `F2` | Pane | Rename focused item (inline or modal) |
| `F5` | Global | Copy selected items to opposing pane |
| `F6` | Global | Move selected items to opposing pane |
| `F7` | Pane | Create new folder prompt |
| `Delete` | Pane | Move selection to OS Recycle Bin / Trash |
| `Shift + Delete` | Pane | Permanent delete (with confirmation dialog) |
| `Ctrl + C` / `Ctrl + X` | Pane | Copy / Cut selection to internal clipboard |
| `Ctrl + V` | Pane | Paste clipboard items into active directory |
| `Ctrl + D` | Pane | Duplicate selected item(s) in place |
| `Ctrl + T` | Pane | Open new tab |
| `Ctrl + W` | Pane | Close current tab |
| `Ctrl + L` | Pane | Focus path input bar |
| `Ctrl + F` | Global | Open recursive search modal |
| `Ctrl + H` | Global | Toggle hidden files visibility |
| `Ctrl + P` / `Ctrl + K` | Global | Open Quick Command Palette |

#### 2.4.3 Context Menu (Right Click)
Context menus must render custom Elm overlays matching the app theme:
- On File/Folder: Open, Open With, Open in Terminal, Show in OS Explorer, Cut, Copy, Rename, Batch Rename, Duplicate, Delete (Trash), Permanent Delete, Calculate Checksum, Properties.
- On Empty Viewport Space: New Folder, New File, Paste, Select All, Open in Terminal, Refresh, Properties.

---

### 2.5 File Operations & Background Transfer Manager

#### 2.5.1 Asynchronous Transfer Queue
File copying and moving must never block the UI thread:
- All copy/move jobs are submitted to a Zig worker thread pool.
- Large files are transferred in **64 KB to 256 KB chunks**.
- Worker periodically inspects an atomic cancellation flag (`cancel_token.load(.monotonic)`).
- Progress telemetry is throttled to `100 ms` intervals and emitted over IPC:
  - `job_id`, `current_file_name`, `bytes_copied`, `total_bytes`, `files_completed`, `total_files`, `speed_bytes_sec`, `eta_seconds`.

#### 2.5.2 Collision & Conflict Resolution Policies
When a destination file already exists, the transfer engine applies one of four policies:
1. `Overwrite`: Overwrite existing files unconditionally.
2. `Skip`: Skip existing files and proceed to next.
3. `Keep Both (Auto-Rename)`: Append counter ` (copy)` or ` (copy 2)` to target name.
4. `Overwrite if Newer`: Replace destination only if source timestamp is more recent.

#### 2.5.3 Transfer Drawer UI
- A floating or bottom drawer displaying all active, queued, paused, and finished jobs.
- Visual elements: Overall progress bar, current file name, transfer rate (e.g., `45.2 MB/s`), remaining time estimate (e.g., `00:42`), Pause/Resume button, and Cancel button.

---

### 2.6 Live Directory Watcher
- When navigating to any folder, Zig registers an OS-level filesystem watcher:
  - Windows: `ReadDirectoryChangesW`.
  - Linux: `inotify`.
  - macOS: `FSEvents`.
- File creations, deletions, renames, and modifications trigger a debounced (`150 ms`) event to Elm.
- The active view re-queries or updates visible state without requiring manual `F5` refreshes.
- When navigating away, the previous directory watch handle is immediately closed to conserve OS descriptors.

---

### 2.7 Power Tools & Modal Subsystems

#### 2.7.1 Multithreaded Search Modal (`Ctrl+F`)
- Recursive background directory traversal using a parallel walker.
- Filter criteria:
  - Name query (substring or regular expression).
  - Case sensitivity toggle.
  - File extension filters (e.g., `.zig, .elm, .json`).
  - Size boundaries (Min Size, Max Size in KB/MB/GB).
  - Date modified range.
- Search results stream dynamically into the UI as they are discovered.
- Double-clicking any result opens its containing folder and highlights the file.

#### 2.7.2 Quick Look Preview Modal (`Spacebar`)
- Instant inspection overlay:
  - **Text / Code:** Displays syntax-detected head content (first 64 KB) with line numbers.
  - **Images (`png, jpg, svg, webp, gif`):** Displays image scaled to viewport with dimensions and color depth.
  - **Audio / Video:** In-window playback with standard controls.
  - **Binary / Executables:** Structured 16-column hex dump with byte offsets and ASCII column.

#### 2.7.3 Batch / Bulk Renamer Modal
- Select multiple files → Open Batch Renamer (`Ctrl+M` or Context Menu).
- Transformation features:
  - Text find and replace (plain text or Regex).
  - Prefix and suffix insertion.
  - Sequential numbering / padding (e.g., `photo_001.jpg`, `photo_002.jpg`).
  - Case conversions: `lowercase`, `UPPERCASE`, `Title Case`, `camelCase`.
- **Live Diff Preview:** Side-by-side table displaying `Original Name` vs `New Name` with collision/overwrite warning indicators before committing renames to disk.

#### 2.7.4 Properties & Permissions Inspector
- Shows: Full path, parent directory, size on disk, contained file/folder counts (for directories, computed asynchronously), created/modified/accessed timestamps, read-only status, POSIX mode / Windows attributes.

---

## 3. Technology Architecture & Implementation Blueprint

```
+----------------------------------------------------------------------------------+
|                            NATIVE PLATFORM RUNTIME                               |
|   Windows (Edge WebView2)   |   macOS (WKWebView)   |   Linux (WebKitGTK-4.1)    |
+----------------------------------------------------------------------------------+
                                        ▲
                                        │ JavaScript Window PostMessage / Ports
                                        ▼
+----------------------------------------------------------------------------------+
|                              ELM 0.19.1 FRONTEND                                 |
|                                                                                  |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   |       Model.elm       |  |       Update.elm      |  |      View.elm      |   |
|   | DualPane, Tabs, Queue |  | Pure State Transition |  | Virtualized Grid   |   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   |       Ports.elm       |  |      KeyMap.elm       |  |     Modals/*.elm   |   |
|   | Typed In/Out Envelopes|  | Commander Shortcuts   |  | Preview, Rename    |   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
+----------------------------------------------------------------------------------+
                                        ▲
                                        │ Native JSON IPC Bridge
                                        ▼
+----------------------------------------------------------------------------------+
|                               ZIG 0.13.0+ CORE                                   |
|                                                                                  |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   |   ipc/dispatcher.zig  |  |   vfs/list.zig        |  |  transfer/queue.zig|   |
|   | Request/Response RPC  |  | Scoped Arena Scans    |  | Chunked Worker Pool|   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
|   |   vfs/watcher.zig     |  |   search/crawler.zig  |  |  preview/engine.zig|   |
|   | inotify/FSEvents/Win  |  | Parallel Walker       |  | Text / Hex Preview |   |
|   +-----------------------+  +-----------------------+  +--------------------+   |
+----------------------------------------------------------------------------------+
```

---

## 4. Zig Core Specifications & Memory Rules

### 4.1 Memory Management Rules for Zig
1. **Zero Unbounded Allocations:** Every allocation must be tied to an explicit allocator lifetime.
2. **Directory List Lifecycle:**
   - Always instantiate a `std.heap.ArenaAllocator` scoped exclusively to the duration of the `list_directory` invocation.
   - Allocate all entry structs, paths, and strings in this arena.
   - Serialize the final struct slice to JSON.
   - Free the entire arena immediately (`arena.deinit()`) before returning.
3. **Debug vs Release Allocator:**
   - In debug builds, use `std.heap.GeneralPurposeAllocator(.{})` to catch memory leaks or double frees.
   - In release builds, use `std.heap.c_allocator` or `std.heap.smp_allocator`.

### 4.2 Core Zig Filesystem Structures (`src/vfs/types.zig`)
```zig
pub const FileCategory = enum {
    folder,
    code,
    image,
    audio,
    video,
    archive,
    document,
    data,
    binary,
};

pub const FileEntry = struct {
    name: []const u8,
    path: []const u8,
    is_dir: bool,
    is_symlink: bool,
    is_hidden: bool,
    is_readonly: bool,
    size: u64,
    modified_ms: i64,
    created_ms: i64,
    extension: ?[]const u8,
    category: FileCategory,
};

pub const DriveInfo = struct {
    name: []const u8,
    mount_point: []const u8,
    total_bytes: u64,
    available_bytes: u64,
    fs_type: []const u8,
    is_removable: bool,
};
```

---

## 5. Elm Frontend Specifications & Port Schema

### 5.1 Elm Ports Contract (`ui/src/Ports.elm`)
```elm
port module Ports exposing (sendToZig, receiveFromZig)

import Json.Encode as E
import Json.Decode as D

-- Outgoing commands to Zig host
port sendToZig : E.Value -> Cmd msg

-- Incoming responses & stream events from Zig host
port receiveFromZig : (E.Value -> msg) -> Sub msg
```

### 5.2 Elm State Hierarchy (`ui/src/Model.elm`)
```elm
module Model exposing (..)

import Dict exposing (Dict)
import Set exposing (Set)

type PaneId = LeftPane | RightPane

type SplitMode
    = Single
    | DualHorizontal
    | DualVertical

type SortColumn = SortName | SortSize | SortDate | SortExt
type SortOrder = Ascending | Descending

type alias Tab =
    { id : String
    , path : String
    , history : List String
    , historyIndex : Int
    , entries : List FileEntry
    , selectedPaths : Set String
    , cursorIndex : Int
    , sortCol : SortColumn
    , sortOrd : SortOrder
    , filterText : String
    , scrollOffset : Float
    }

type alias Model =
    { splitMode : SplitMode
    , activePane : PaneId
    , leftTabs : List Tab
    , leftTabId : String
    , rightTabs : List Tab
    , rightTabId : String
    , drives : List DriveInfo
    , favorites : List String
    , transfers : Dict String TransferJob
    , preview : Maybe PreviewData
    , renameModal : Maybe BulkRenameState
    , searchModal : Maybe SearchState
    , contextMenu : Maybe ContextMenuState
    , showHidden : Bool
    }
```

---

## 6. IPC Protocol Specification (JSON-RPC Wire Format)

### 6.1 Elm → Zig (Commands)
```json
{
  "id": "cmd-1001",
  "command": "list_directory",
  "payload": {
    "path": "C:\\Users\\Developer",
    "show_hidden": false
  }
}
```

#### Complete Command Index:
| Command | Arguments | Expected Result |
| :--- | :--- | :--- |
| `list_directory` | `path: String, show_hidden: Bool` | `List FileEntry` |
| `get_drives` | None | `List DriveInfo` |
| `get_standard_locations` | None | Standard user paths record |
| `create_folder` | `path: String` | `Success` or `Error` |
| `create_file` | `path: String` | `Success` or `Error` |
| `delete_items` | `paths: List String, permanent: Bool` | `Success` or `Error` |
| `rename_item` | `old_path: String, new_name: String` | `new_path: String` |
| `batch_rename_preview` | `paths: List String, rule: RenameRule` | `List RenamePreviewItem` |
| `batch_rename_execute` | `items: List RenameExecutionItem` | `count: Int` |
| `start_transfer` | `id: String, sources: List String, dest: String, is_move: Bool, policy: String` | Background Job Started |
| `cancel_transfer` | `id: String` | `Success` |
| `watch_directory` | `path: String` | Active watcher assigned |
| `unwatch_directory` | `path: String` | Watcher removed |
| `search_files` | `query: SearchQueryRecord` | Streaming search results |
| `get_preview` | `path: String` | `PreviewData` |
| `open_default` | `path: String` | Launches file in OS |
| `open_terminal` | `path: String` | Launches terminal at path |
| `show_in_explorer` | `path: String` | Highlights item in OS explorer |

### 6.2 Zig → Elm (Responses & Streaming Events)
```json
// Command Response
{
  "reply_to": "cmd-1001",
  "status": "ok",
  "payload": [ /* entries array */ ]
}

// Live FS Watcher Notification
{
  "event": "fs_change",
  "payload": {
    "path": "C:\\Users\\Developer"
  }
}

// Transfer Progress Notification (every 100ms)
{
  "event": "transfer_progress",
  "payload": {
    "job_id": "job-501",
    "current_file": "backup.tar.gz",
    "bytes_copied": 134217728,
    "total_bytes": 1073741824,
    "files_copied": 3,
    "total_files": 12,
    "speed_bps": 45000000,
    "status": "running"
  }
}
```

---

## 7. Directory Tree & Codebase Organization

```
power-file-manager/
├── build.zig                   # Root build script orchestrating Elm & Zig
├── build.zig.zon               # Dependencies manifest
├── src/                        # Zig Core Engine
│   ├── main.zig                # Native window host & WebView lifecycle
│   ├── vfs/
│   │   ├── types.zig           # FileEntry, DriveInfo, Category models
│   │   ├── list.zig            # Directory scanner with scoped Arena
│   │   ├── ops.zig             # File operations (trash, permanent delete, rename)
│   │   ├── drives.zig          # Drive and mount enumeration
│   │   └── watcher.zig         # OS directory watcher (inotify/FSEvents/Win32)
│   ├── transfer/
│   │   ├── worker.zig          # Chunked streaming copy/move worker
│   │   ├── queue.zig           # Multithreaded transfer queue manager
│   │   └── conflict.zig        # Overwrite / skip / unique copy naming logic
│   ├── search/
│   │   ├── crawler.zig         # Parallel recursive crawler
│   │   └── matcher.zig         # Regex and substring matcher
│   ├── preview/
│   │   ├── engine.zig          # Text slice, image detector, and hex generator
│   │   └── hex.zig             # Formatted 16-column hex dump generator
│   ├── ipc/
│   │   ├── protocol.zig        # JSON envelope deserializer & serializer
│   │   └── dispatcher.zig      # Command router invoking VFS commands
│   └── platform/
│       ├── windows.zig         # Win32 + Edge WebView2 initialization
│       ├── macos.zig           # Cocoa + WKWebView initialization
│       └── linux.zig           # GTK3 + WebKitGTK initialization
├── ui/                         # Elm Frontend Application
│   ├── elm.json                # Elm compiler manifest
│   ├── index.html              # HTML host shell
│   ├── src/
│   │   ├── Main.elm            # TEA Application entrypoint
│   │   ├── Model.elm           # State, Tab, Viewport data records
│   │   ├── Msg.elm             # Action union type (Keyboard, Mouse, IPC)
│   │   ├── Update.elm          # State transition machine
│   │   ├── Ports.elm           # Outgoing/Incoming ports
│   │   ├── Decoders.elm        # Strict JSON decoders for IPC payloads
│   │   ├── Encoders.elm        # JSON encoders for outgoing commands
│   │   ├── Components/
│   │   │   ├── DualPane.elm    # Split layout container
│   │   │   ├── PaneView.elm    # Pane container (Tabs, Path Bar, Grid)
│   │   │   ├── VirtualGrid.elm # 60fps virtualized file grid
│   │   │   ├── Breadcrumb.elm  # Clickable breadcrumbs + input toggle
│   │   │   ├── Sidebar.elm     # Drives and favorites list
│   │   │   ├── ContextMenu.elm # Custom right-click menu
│   │   │   ├── TransferBar.elm # Transfer queue progress bar
│   │   │   ├── PreviewModal.elm# Quick Look overlay
│   │   │   ├── RenameModal.elm # Batch rename dialog with live diff
│   │   │   └── SearchModal.elm # Recursive search modal
│   │   └── Theme.elm           # Color palette and acrylic styles
│   └── styles/
│       ├── app.css             # Base styles, resets, animations
│       └── virtual_grid.css    # High-performance positioning styles
└── tests/
    ├── vfs_test.zig            # Zig filesystem tests
    └── transfer_test.zig       # Cancellation & conflict resolution tests
```

---

## 8. Step-by-Step AI Implementation Instructions

When building this application, the AI must proceed according to the following 7 execution phases:

### Phase 1: Toolchain & Native WebView Shell
1. Create `build.zig` and `build.zig.zon`.
2. Configure `build.zig` to execute `elm make ui/src/Main.elm --optimize --output=ui/dist/elm.js`.
3. Implement `src/platform/{windows,macos,linux}.zig` embedding the native WebView.
4. Establish bidirectional JavaScript message posting between the native WebView and the Elm runtime.

### Phase 2: Zig VFS Layer & Scoped Allocators
1. Implement `src/vfs/types.zig` and `src/vfs/list.zig`.
2. Ensure directory scans run inside a scoped `std.heap.ArenaAllocator` that is freed upon command completion.
3. Add directory-first alphabetical sorting.
4. Implement `src/vfs/drives.zig` querying drives and volume space across all three platforms.

### Phase 3: Elm Architecture & Virtualized Grid
1. Build `ui/src/Model.elm`, `Msg.elm`, and `Update.elm`.
2. Implement `ui/src/Components/VirtualGrid.elm` utilizing container scroll calculations to render only visible items.
3. Implement dual-pane split rendering and independent tab history.
4. Verify smooth 60 FPS scrolling with dummy datasets of 100,000 entries.

### Phase 4: Threaded Transfer Engine & Live Telemetry
1. Implement `src/transfer/worker.zig` reading/writing in 64 KB chunks.
2. Add cancellation check after each chunk using `cancel_token.load(.monotonic)`.
3. Dispatch `transfer_progress` events every 100 ms to Elm ports.
4. Render real-time progress, speed (MB/s), and ETA in Elm `TransferBar.elm`.

### Phase 5: Live Directory Watcher
1. Implement `src/vfs/watcher.zig` using native OS APIs.
2. Add a 150 ms debounce buffer in Zig.
3. Send `fs_change` events over IPC to trigger active pane refreshes.

### Phase 6: Power Tools & Modal Overlays
1. Implement parallel recursive search in `src/search/crawler.zig` with regex support.
2. Implement Quick Look text/hex preview in `src/preview/engine.zig`.
3. Implement Batch Renamer in `ui/src/Components/RenameModal.elm` with live before/after diffs.
4. Wire system trash deletion (`delete_items`).

### Phase 7: Verification, Benchmarking & Release Build
1. Verify leak-free execution using Zig GPA.
2. Verify zero uncaught exceptions in Elm.
3. Validate cross-compilation across Windows, Linux, and macOS targets.
