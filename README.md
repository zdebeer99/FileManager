# Info File Catalog
2026-10-31

Info File Catalog is a file manager similar to windows explorer but with core focus for a information worker, like a project manager working accross projects, or manager required access over multiple folders, online and offline.



> [!IMPORTANT] 
>
> **AI Agents and GPT Model Rules!!**
>
> The "**HumansOnly**" folder is for human reference purposes only, AI models must ignore and exclude the content of this folder. The content of this folder is not relevant to the production version of the project. The purpose of this folder is to store document versions, drafts and ideas for reference only and is not relevant  to the production version of the project outcome.

## Building and running

The specification is [SpecificationDocument.md](SpecificationDocument.md). The current release is **0.1.0**, the first stable release (spec section 11). Features planned for later versions are listed in spec section 12.

| Folder | Contents |
|---|---|
| `src-tauri/` | Rust backend and Tauri window (file system, cache, watcher, settings) |
| `ui/` | Elm 0.19.3 front end (`ui/src`), static files and bridge (`ui/static`), build script (`ui/build.mjs`) |

Requirements: Node.js 20+, Rust (stable), and on Linux the WebKitGTK libraries:

```bash
sudo apt install pkg-config libwebkit2gtk-4.1-dev libgtk-3-dev libssl-dev librsvg2-dev libxdo-dev libayatana-appindicator3-dev
```

```bash
npm install          # Elm compiler, Tauri CLI, esbuild
npm run dev          # build the UI and start the app
npm run build        # optimised build and installers (MSI/NSIS on Windows; deb/rpm/AppImage on Linux)
```

Tests and checks:

```bash
cd src-tauri && cargo test && cargo clippy --all-targets -- -D warnings && cargo fmt --check
```

Tip: put an empty `portable.toml` next to the program to keep its settings in a `settings/` folder beside it instead of your user settings folder (handy for testing).
