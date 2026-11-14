# Feature Requests
2026-11-02

 Update Cycle: c3

## How to use this file

- Add a new request as a row in **Open requests** with the next free ID, status `new`, and the update cycle it belongs to (`c2`, `c3`…).
- Longer descriptions go in a section below the tables, named after the request ID (for example *REQ-004 Favorite Sidebar view update*).
- When a request is built, move its row to **Done**, with the spec IDs it became in the Comment column, and add a line to the **Log**.
- IDs are `REQ-001`, `REQ-002`…, never reused. (They are not `FR-…`, so they can't be mixed up with the requirement IDs in the specification.)

| Status     | Meaning                                                     |
| ---------- | ----------------------------------------------------------- |
| `new`      | Logged, not looked at yet.                                  |
| `planned`  | Agreed, waiting for its update cycle.                       |
| `proposed` | An answer or design is ready and waits for your decision.   |
| `done`     | Built; see the Done table.                                  |
| `rejected` | Not going to be built; the reason is in the Comment column. |

## Open requests

| ID      | Name                                              | Area                | Description                                                  | Priority | Status   | Update Cycle | Comment       |
| ------- | ------------------------------------------------- | ------------------- | ------------------------------------------------------------ | -------- | -------- | ------------ | ------------- |
| REQ-007 | Bookmark Reordering                               | Bookmarks           | Allow drag and drop bookmarks to reorder them quickly, also allow moving bookmarks between groups. | Low      | proposal | c9           | 02Nov26 new   |
| REQ-018 | UI Style                                          | Look and Feel       | Use Tailwind css style sheets to style the application components | Normal   | New      | c3           | 14Nov26 Added |
| REQ-021 | Topic View                                        | Left Side View      | Add a Topic view that links folders to the current visible folder. See "REQ-021 Topic View" Section Below | Normal   | proposal | c9           | 14Nov26 Added |
| REQ-022 |                                                   |                     |                                                              |          |          |              |               |
| REQ-023 |                                                   |                     |                                                              |          |          |              |               |
| REQ-024 |                                                   |                     |                                                              |          |          |              |               |

### REQ-021 Topic View

2026-11-14



This section is still a work in progress.




## Done

| ID      | Name                         | Area      | Description                                                                                                                                                                                                                                                                                                  | Priority | Update Cycle | Comment                                                                                                                     |
| ------- | ---------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------------ | --------------------------------------------------------------------------------------------------------------------------- |
| REQ-001 | File Icons                   | File List | Add support for showing file icons.                                                                                                                                                                                                                                                                          | Normal   | c1           | 02Nov26 Added. 03Nov26 Built: icons by file type (spec FR-ICON-01).                                                         |
| REQ-002 | Folder Colors                | File List | Add Support for colored folders                                                                                                                                                                                                                                                                              | Normal   | c1           | 02Nov26 new. 03Nov26 Built: right-click › Folder Colour, saved in colours.toml (spec 6.4.5).                                |
| REQ-003 | Folded Bookmarks in sidebar  | Bookmarks | Allow groups to be folded to hide the sub content.                                                                                                                                                                                                                                                           | Normal   | c1           | 02Nov26 new. 03Nov26 Built (spec FR-BM-06).                                                                                 |
| REQ-004 | Favorite Sidebar view update | Side Bar  | Update the Favorite sidebar as specified in REQ-004 below.                                                                                                                                                                                                                                                   | Normal   | c1           | 03Nov26 Added. 03Nov26 Built (spec FR-FAV-03).                                                                              |
| REQ-005 | Sidebar view update          | Side Bar  | Remove the Context View in the sidebar.                                                                                                                                                                                                                                                                      | Normal   | c1           | 03Nov26 Added. 03Nov26 Removed (spec 5.7, decision log 13.1).                                                               |
| REQ-006 | Bookmark Groups              | Bookmarks | When adding a new bookmark add dropdown on the group field that also allow free text. The user can select an existing group, type to search existing groups or if the typed group does not exist create it as a new group.                                                                                   | Low      | c1           | 02Nov26 new. 03Nov26 Built (spec FR-BM-01).                                                                                 |
| REQ-010 | System file icons            | File List | Show the icons the operating system shows: Windows shell icons (programs and shortcuts with their own icon), Linux icon theme icons. Load them in the background, cache them, never download cloud files for an icon, keep the built-in icons as the fallback, and add a setting to choose.                  | Normal   | c2           | 03Nov26 Added and built: View › Icons, setting view.default.icons (spec FR-ICON-02). 03Nov26 Tested on Windows: icons load. |
| REQ-008 | Catchy name                  | General   | Get a better name for my file explorer                                                                                                                                                                                                                                                                       | Low      | c1           | 04Nov26 Rejected                                                                                                            |
| REQ-009 | Open Text Editor             | File List | Setup your favorite text editor example like vscode, zed, sublime, etc and if set always show in the file context menu to open the file or open the current folder using this ide. even when the user right click on a open space in the file context view, the "open folder with vscode" should be visible. | Normal   | c2           | 03Nov26 added. 04Nov26 Built: Open with … / Open Folder with …, [editor] in settings.toml (spec FR-OPEN-06).                |
| REQ-011 | File Content menu placement  | File List | Fix When right clicking on a file at the bottom of the view, the file content window will go off screen and you cannot select one of the bottom menu items. Fix so that the content window will always be visible even when files are located at the bottom of the window.                                   | Normal   | c2           | 04Nov26 added. 04Nov26 Fixed: menus and submenus move up to stay on screen (spec FR-MENU-02).                               |
| REQ-012 | Tab Color                    | Tabs      | If a folder has a specified colour set and the folder is open in a tab, let the tab show the same colour. the tab colour should persist even when opening subfolders in that file view.                                                                                                                      | Normal   | c2           | 04Nov26 Built (spec FR-TAB-06). Priority and cycle were empty; built with c2.                                               |
| REQ-013 | Folder Rename color issue | File View | When a folder with a color is renamed it loses its color. make it that the color stay even after renaming the folder | Normal | c3 | 04Nov26 added. 14Nov26 Built: FR-FCOL-03: colours follow renamed and moved folders (and undo). |
| REQ-014 | Quick Shortcut | Selected File | Create a new shortcut file pointing to the selected file. | Normal | c3 | 14Nov26 added. 14Nov26 Built: FR-NEW-06: Create Shortcut in the right-click and Edit menus. |
| REQ-015 | Fix Command palette sizing | 6.9 Command palette | The command pallet width is to narrow, it only show the first character or icon. correct the command pallet width. | Normal | c3 | 10Nov26 added. 14Nov26 Built: Fixed: a CSS class clash with the folder colour palette made the palette narrow. |
| REQ-016 | Issue with copying files from the favorites view. | 6.4.3 Favorites | Dragging a file from the favorites into the file view does not nothing (strangely it works when dragging the file on the file view grid header. Ex dragging the file over the name field.), it should copy the file into the active folder when droping anyware on the fileview. Also add cut/copy options on the favorites context menu. | Normal | c3 | 10Nov26 added. 14Nov26 Built: FR-FAV-03: drops anywhere on the list copy; Cut/Copy in Favourites menus. Cause: the empty-folder message covered the list. |
| REQ-017 | Bookmark icons not showing | Bookmarks Bar | In the bookmark bar groups the icons is not showing. | Normal | c3 | 14Nov26 Added. 14Nov26 Built: FR-BB-01: group drop-downs show bookmark icons. |
| REQ-019 | Open in VSCode Error | Command | Open in VSCode is not working, it gives an error.  "Could not open VS Code: %1 is not a valid Win32 application. (os error 193)" | Normal | c3 | 14Nov26 Added. 14Nov26 Built: FR-OPEN-06: on Windows only .exe/.cmd/.bat/.com are started (VS Code's bin\code script was picked). |
| REQ-020 | Logging Errors | Log File | Errors is not logged in the log file. | Normal | c3 | 14Nov26 Added. 14Nov26 Built: NFR-MNT-03: command errors, listing errors and job errors go to the log. |

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
- **03Nov26 REQ-010 tested on Windows**: system icons load.
- **04Nov26 c2 built** on branch `dev`: REQ-009 Open Text Editor, REQ-011 menu placement, REQ-012 tab colour. IDs REQ-0011 to REQ-0014 written as REQ-011 to REQ-014. See spec section 11.3.
- **14Nov26 c3 built** on branch `dev`: REQ-013, REQ-014, REQ-015, REQ-016, REQ-017, REQ-019, REQ-020. REQ-018 (Tailwind) left open. See spec section 11.4.
