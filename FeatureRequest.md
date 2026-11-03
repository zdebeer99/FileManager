# Feature Requests
2026-11-02

 Update Cycle: c1

## How to use this file

- Add a new request as a row in **Open requests** with the next free ID, status `new`, and the update cycle it belongs to (`c2`, `c3`…).
- Longer descriptions go in a section below the tables, named after the request ID (for example *REQ-004 Favorite Sidebar view update*).
- When a request is built, move its row to **Done**, with the spec IDs it became in the Comment column, and add a line to the **Log**.
- IDs are `REQ-001`, `REQ-002`…, never reused. (They are not `FR-…`, so they can't be mixed up with the requirement IDs in the specification.)

| Status | Meaning |
| ------ | ------- |
| `new` | Logged, not looked at yet. |
| `planned` | Agreed, waiting for its update cycle. |
| `proposed` | An answer or design is ready and waits for your decision. |
| `done` | Built; see the Done table. |
| `rejected` | Not going to be built; the reason is in the Comment column. |

## Open requests

| ID | Name | Area | Description | Priority | Status | Update Cycle | Comment |
| -- | ---- | ---- | ----------- | -------- | ------ | ------------ | ------- |
| REQ-007 | Bookmark Reordering | Bookmarks | Allow drag and drop bookmarks to reorder them quickly, also allow moving bookmarks between groups. | Low | new | c9 | 02Nov26 new |
| REQ-008 | Catchy name | General | Get a better name for my file explorer | Low | proposed | c1 | 02Nov26 new. 03Nov26 Ideas in the log below; waiting for your choice. |
| REQ-009 | Open Text Editor | Feature | Setup your favorite text editor default vscode, and always show on the context menu to open any file or quickly open the current folder with the application. | Normal | new | c2 | 03Nov26 added |

## Done

| ID | Name | Area | Description | Priority | Update Cycle | Comment |
| -- | ---- | ---- | ----------- | -------- | ------------ | ------- |
| REQ-001 | File Icons | File List | Add support for showing file icons. | Normal | c1 | 02Nov26 Added. 03Nov26 Built: icons by file type (spec FR-ICON-01). |
| REQ-002 | Folder Colors | File List | Add Support for colored folders | Normal | c1 | 02Nov26 new. 03Nov26 Built: right-click › Folder Colour, saved in colours.toml (spec 6.4.5). |
| REQ-003 | Folded Bookmarks in sidebar | Bookmarks | Allow groups to be folded to hide the sub content. | Normal | c1 | 02Nov26 new. 03Nov26 Built (spec FR-BM-06). |
| REQ-004 | Favorite Sidebar view update | Side Bar | Update the Favorite sidebar as specified in REQ-004 below. | Normal | c1 | 03Nov26 Added. 03Nov26 Built (spec FR-FAV-03). |
| REQ-005 | Sidebar view update | Side Bar | Remove the Context View in the sidebar. | Normal | c1 | 03Nov26 Added. 03Nov26 Removed (spec 5.7, decision log 13.1). |
| REQ-006 | Bookmark Groups | Bookmarks | When adding a new bookmark add dropdown on the group field that also allow free text. The user can select an existing group, type to search existing groups or if the typed group does not exist create it as a new group. | Low | c1 | 02Nov26 new. 03Nov26 Built (spec FR-BM-01). |
| REQ-010 | System file icons | File List | Show the icons the operating system shows: Windows shell icons (programs and shortcuts with their own icon), Linux icon theme icons. Load them in the background, cache them, never download cloud files for an icon, keep the built-in icons as the fallback, and add a setting to choose. | Normal | c2 | 03Nov26 Added and built: View › Icons, setting view.default.icons (spec FR-ICON-02). Needs a test on Windows. |

## Details

### REQ-004 Favorite Sidebar view update

Update the favorite sidebar view to work as follow. When the view it's initial state will show folders pinned. Example "Downloads", when the user clicks on the this folder, the files and folders in the actual folder will show in favorite. the user must be able to drill back up to the the initial favorites list. This view especially help full when savings downloads from email and you want to move the files quickly to the active tab folder.

## Log

- **03Nov26 c1 built** on branch `feature/c1`: File Icons, Folder Colors, Folded Bookmarks in sidebar, Favorite Sidebar view update, Sidebar view update, Bookmark Groups (REQ-001 to REQ-006). See spec section 11.2.
- **03Nov26 Catchy name ideas** for REQ-008 (check that the name is free before using it):
  - **Wayfile**: find your way through many folders.
  - **Foldwise**: folders, organised wisely.
  - **Filewise**: a short, plain name for a file manager.
  - **Corral**: gather files from many places into one spot.
  - **Hopper**: drop things in and move them on quickly.
- **03Nov26** Request IDs, a Done table and the status list added.
- **03Nov26 REQ-010 built** (c2) on branch `feature/system-icons`: system file icons with the built-in icons as fallback. See spec section 11.3.
