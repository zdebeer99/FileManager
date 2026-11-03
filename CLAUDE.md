# CLAUDE.md

File Catalog is a fast, keyboard-driven desktop file manager for information workers. It is built with Tauri 2: a Rust backend in `src-tauri/` and an Elm 0.19.3 UI in `ui/`. Windows is the main platform, Linux is supported, and macOS is planned for later (keep it possible, but don't build it).

## Rules

- **Ignore `HumansOnly/`.** It holds drafts for people only. Do not read it, search it or use it.
- **[SpecificationDocument.md](SpecificationDocument.md) is the source of truth.** It describes File Catalog **0.1.0**, the first stable release, as built: M1 (core shell), M2 (Organise), M3a (Operate: job queue, copy/move/delete, rename, undo, create items), M3b (clipboard exchange with other file managers, drag and drop, templates) and M4 (Speed: command palette, key bindings, customisable toolbar, Quick Find). M5 was cancelled (decision log 13.1, 2026-11-03). Everything planned but not built, including the former M5 work, project folders, cloud sync status, pinned tabs and ZIP, is listed in spec section 12; nothing there is scheduled until the user picks it. Before you build or change a feature, read its spec section and `FR-…`/`NFR-…` IDs. Cite those IDs in doc comments, as the existing code does (for example `// FR-QF-02`, `(spec 4.3)`).
- When you build an item from spec section 12, move it into the section that describes it, and record the release in spec section 11.
- [RequirementsDocument.md](RequirementsDocument.md) holds the user's original requirements. The user reviews documents by adding inline `[zdb]` comments. When asked to merge them, apply each decision to **both** documents, remove the markers, and add the decision to the decision log (spec 13.1).
- **No lock-in:** everything the app creates must be a plain file or folder that still works without File Catalog. Never write anything into the user's folders. Per-folder settings go only in the app settings folder.

## Commands

```bash
npm install                 # Elm compiler, Tauri CLI, esbuild
npm run dev                 # dev UI build (no --optimize, Debug.log works) + tauri dev
npm run build               # optimised UI + release installers
npm run build:ui            # UI only -> ui/dist (build:ui:dev for the dev build)

cd src-tauri
cargo test                  # all Rust tests
cargo test settings::       # tests in one module
cargo clippy --all-targets -- -D warnings
cargo fmt --check           # rustfmt.toml: max_width 120
```

- Elm: run `elm-format` on changed `.elm` files. `elm-test` and `elm-review` are in the spec but not set up yet, and there are no Elm tests.
- To test settings without touching your real settings folder, put an empty `portable.toml` next to the binary. Settings then go to `settings/` beside it.
- `ui/dist/`, `ui/elm-stuff/`, `src-tauri/target/` and `src-tauri/gen/` are generated. Don't edit them.

## Architecture

**Rule: the UI never waits for the file system** (spec 4.3). Elm does no file system work. Every Rust command is `async`, and it sends file system work to the I/O pools in [pools.rs](src-tauri/src/pools.rs):
- `local` pool for local disks.
- `slow` pool for network shares, removable drives and cloud paths, chosen by `platform::is_slow_path`.
- Use `IoPools::run(path, timeout, work)` to wait with a timeout (`network.timeoutSeconds`), or `spawn` to stream results.

### IPC path

1. Elm calls `request cmd args stream kind model` ([Main.elm](ui/src/Main.elm), HELPERS section). It stores `kind` (a `Request` variant) in `model.requests` under a new id.
2. The message goes out through `Ports.toBackend`. [bridge.js](ui/static/bridge.js) turns it into Tauri `invoke(cmd, args)`. When `stream` is true, the bridge also passes a `Channel` as `onEvent`.
3. Replies come back through `Ports.fromBackend` as `{ id, type: ok|err|stream|event, data, name? }`. `handleEnvelope` and `handleResponse` match each reply to its stored request. Stale replies are dropped by id.
4. Push events from Rust are emitted by [watcher.rs](src-tauri/src/watcher.rs) (`dir-changed`, `settings-changed`, `bookmarks-changed`, `keybindings-changed`, `toolbar-changed`) and [jobs.rs](src-tauri/src/jobs.rs) (`job-progress`, `job-conflict`), plus `file-drop` from [main.rs](src-tauri/src/main.rs) for files dropped in from other apps (bridge.js adds the `data-drop` target under the pointer). They reach `handleEvent`. **If you add a new event, also add it to the `listen` list in bridge.js.**

**To add a backend command:**
1. Write a `#[tauri::command] pub async fn` in [commands.rs](src-tauri/src/commands.rs).
2. Register it in `generate_handler!` in [main.rs](src-tauri/src/main.rs).
3. Add a `Request` variant in [Types.elm](ui/src/Types.elm), and handle its reply in `handleResponse`.

Command names are snake_case (`dir_list`, `folder_view_save`), even where spec 4.4 uses dotted names. Serde uses `rename_all = "camelCase"` for JSON and for TOML keys.

### Rust modules (`src-tauri/src/`)

| Module | Role |
|---|---|
| `commands.rs` | All IPC commands. `AppState` holds the paths, pools, `DirCache`, settings, session and watcher. `app_init` is the first call: it loads settings, the session and the start-up snapshot, and starts the watcher. |
| `jobs.rs` | Background job queue (copy, move, duplicate, delete) on its own thread: progress events, conflict questions answered with `job_resolve`, pause and cancel, and the undo stack. Tests use `JobManager::start_with` with a recording event sink. |
| `fileops.rs` | Blocking file operations used by jobs and commands: name checks, free names (`Report (2)`, `Report - Copy`), copy through a temporary name, create, rename, `describe` for readable errors |
| `find.rs` | Quick Find: the query syntax (Quick Filter words plus `size:`, `modified:`, `type:`, `in:`) and the parallel walk with `ignore`, sending batches every 50 ms. `find_start` runs it on its own thread; `find_cancel` sets its flag. |
| `keybindings.rs` | `keybindings.toml`: reads `[[bind]]` entries with their line numbers, and `set` rewrites one command's keys. The command list and default keys live in the UI (`Commands.elm`). |
| `toolbar.rs` | `toolbar.toml`: style and items, with the defaults. |
| `templates.rs` | Templates folders (`[templates]` in settings), the `_Group` menu tree, and creating items with placeholders filled in. `today` comes from the UI, so dates use the user's time zone. |
| `listing.rs` | `read_dir_streaming` (sends items in chunks), `DirEvent` (`Cached` → `Chunk`s or `Patch` → `Done`/`Error`), `diff`, LRU `DirCache` |
| `watcher.rs` | `notify` watcher for the folders open in tabs (set with `watch_set`) and for the settings folder. Debounce is 100 ms. Sends patches, not full reloads. Reloads settings, bookmarks, key bindings and the toolbar when their files change. |
| `settings.rs` | `settings.toml`. Each section is read on its own, so an error in one section resets only that section and adds a warning. `set_value` edits a dotted key with `toml_edit`, keeps the user's comments, keeps a `.bak` copy, and never overwrites a file that has syntax errors. |
| `folder_view.rs` | Saved per-folder views in `<config>/folders/<name>-<hash>.toml`, with *apply to subfolders* |
| `bookmarks.rs` | `bookmarks.toml`: bookmarks with groups, and favourites. Changes are made through `Edit` ops. |
| `session.rs` | `session.toml` (open tabs, recent folders, palette and search history) and the start-up listing snapshot in the cache folder |
| `paths.rs` | `AppPaths` (config, cache and log folders; portable mode), `write_atomic`, path normalising and `~` expansion, and `split_header`/`join_header` to keep a TOML file's top comments when `toml_edit` rewrites it |
| `model.rs` | The `Item` record that is shared with Elm (spec 4.4), and `read_item` |
| `platform/` | Everything that differs between operating systems: hidden files, attributes, sync state, roots, slow-path detection. `windows.rs` uses `windows-sys`. `unix.rs` covers everything that is not Windows. |

Notes:
- Write files with `paths::write_atomic`.
- A failing task must never take the app down. The pools log panics instead of crashing. Return user-readable `String` errors.
- Logs go to `<config>/logs/` (daily files, kept for 7 days).

### Elm modules (`ui/src/`)

- `Main.elm`: `init`, `update`, keyboard routing, and the backend message handlers. It is about 5,500 lines, divided by `-- SECTION` comment headers.
- `View.elm`: all drawing. `Types.elm`: `Model`, `Msg`, `Request` and the tab state, shared by Main and View.
- Feature modules:
  - `Columns.elm`: column definitions and sort and filter keys.
  - `Filter.elm`: the Quick Filter syntax.
  - `Menu.elm`: the Menu Bar. Items from later milestones are shown disabled. Keys shown in menus come from the key map.
  - `Commands.elm`: every command with its id (spec Appendix A), its `Command` value and toolbar icon, the default key bindings, and `buildKeymap`, which applies `keybindings.toml`. **To add a command:** add a `Command` variant, handle it in `runCommand`, add a `Def` here, and its name to `Text.commandName`.
  - `Keys.elm`: key names (`Ctrl+Shift+N`, chords), parsing what users write, and key-map lookups. View's `keyDecoder` uses it; cursor keys and typing are built in and not bindable.
  - `Palette.elm`: the command palette's results and fuzzy matching.
  - `Item.elm`: the item decoder and natural sort.
  - `FileName.elm`: name checks while renaming or creating, and the F2 selection cycle.
  - `Path.elm`, `Format.elm` and `Settings.elm`: path helpers, size and date formatting, and the settings decoder.
- **All user-facing text lives in `Text.elm`** (NFR-UX-04). Don't put text in other modules.
- `ui/static/` holds `index.html`, `styles.css` and `bridge.js`. `ui/build.mjs` builds them into `ui/dist/`.
- The CSP (in `tauri.conf.json`) allows only `'self'` scripts. No CDNs.

## Settings locations

| | Settings | Cache |
|---|---|---|
| Windows | `%APPDATA%\FileCatalog\` | `%LOCALAPPDATA%\FileCatalog\cache` |
| Linux | `~/.config/filecatalog/` | `~/.cache/filecatalog/` |

All settings must stay readable TOML that people can edit (spec 8). Cache files may be binary and can be deleted at any time.
