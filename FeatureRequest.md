---
feature: file:C:/Users/zdebe/Documents/CodeProjects/FileCatalog/md-FeatureRequest/image-20261121210836923.png
thumbnail: thumbnails/resized/3589ee70fe80b9df38e2a72752d794f8_86cf658e.webp
---
# File Catalog Feature Requests
2026-11-02

 Update Cycle: c6

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



**Quick Requests**







- 

**Request table**

| ID      | Name                | Area            | Description     | Priority | Status | Update Cycle | Comment       |
| ------- | ------------------- | --------------- | --------------- | -------- | ------ | ------------ | ------------- |

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
| REQ-007 | Bookmark Reordering | Bookmarks | Allow drag and drop bookmarks to reorder them quickly, also allow moving bookmarks between groups. | Normal | c3 | 02Nov26 new. 21Nov26 Built: FR-BM-07: drag in the sidebar and on the Bookmark Bar; drop on a bookmark (before it) or a group (end of it). |
| REQ-021 | Topic View | Left Side View | Add a Topic view that links folders to the current visible folder. See "REQ-021 Topic View" below. | Normal | c3 | 14Nov26 Added. 21Nov26 Built: spec 6.4.6 (FR-TOP-01 to 05), topics.toml (8.8): fourth sidebar view, Add to Topic in folder menus, drag folders onto a topic. |
| REQ-022 | Export file names | File View | Export current folder file list as a text file containing all the folder and file names in the folder. | Normal | c3 | 21Nov26 added. 21Nov26 Built: FR-OPEN-07: Export File List… (right-click on empty space, File menu, palette); the names shown, one per line, in a .txt you choose. |
| REQ-032 | Google Drive sync status | File List | The sync status for Google Drive files is not showing in the Sync status column. | Normal | c6 | 22Nov26 added from the quick requests. 22Nov26 Checked: Google Drive gives every file `Normal` (0x80) and Explorer shows no status. Built: FR-SYNC-01: files in an online drive with no state of their own show ☁ *In online drive*. |
| REQ-030 | Favourites: open in the active tab | Side Bar | In the Favourites view, open a folder directly in the active tab: the ↗ button next to each folder, and Ctrl+Click. | Normal | c6 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-FAV-05. |
| REQ-031 | Topic switcher | Topics Side Bar | In an open topic, the title is a drop-down with the top 7 topics, to switch quickly. | Normal | c6 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-TOP-08. |
| REQ-033 | No autocomplete | General | No autocomplete when editing folder names, labels, paths and descriptions. | Normal | c6 | 22Nov26 added from the quick requests. 22Nov26 Built: NFR-UX-05: autocomplete="off" on every text box, and WebView2 autofill off on Windows. |
| REQ-024 | Open With | File List | Add an "Open With" action to open a file with an app other than the default one. | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-OPEN-02: Open With… in the file's right-click menu and the File menu; Windows' own dialog, an app list on Linux. |
| REQ-025 | OS folder icons | File List | Show the OS folder icons for folders like Downloads and Pictures, and for folders with a custom icon set. | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-ICON-03: folders' own icons (Downloads, Pictures, custom icons, online drives) in the list, tree, Favourites and Topics. |
| REQ-026 | Bookmark folder icons | Bookmarks | Bookmarked folders show their folder icon, e.g. the Downloads icon for a Downloads bookmark. | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-ICON-03, FR-BB-01: bookmarked folders show the folder's own icon, in the sidebar and on the Bookmark Bar. |
| REQ-027 | Tab folder icons | Tabs | A tab shows the icon of the nearest folder above it with its own icon, and shows when the folder is in an online drive (Dropbox, OneDrive, Google Drive). | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-TAB-07: the nearest own folder icon, and a cloud badge inside an online drive. |
| REQ-028 | Online drives | General | Support the online drives Dropbox, OneDrive, Google Drive and Proton Drive. | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: Spec 6.4.7 (FR-CLOUD-01 to 03): found from the providers' settings, the Windows sync-root registry and the default folders; shown in the tree and Favourites; slow-path pool. |
| REQ-029 | Favourites groups | Side Bar | Show the OS file explorer's pinned folders at the top of the Favourites view (on Windows: Home and Quick access), then groups for your pinned folders, drives, network drives and so on. Groups can be folded and reordered. | Normal | c5 | 22Nov26 added from the quick requests. 22Nov26 Built: FR-FAV-04: Quick access (Explorer's on Windows, standard folders and GTK bookmarks on Linux), Pinned, Online drives, Drives, Network; fold and drag to reorder. |
| REQ-023 | Topics Improvements | Topics Side Bar | See "REQ-023 Topics Improvements" below. | Normal | c4 | 21Nov26 added. 21Nov26 Built: FR-TOP-02 (Archive and Delete in the ✎ topic dialog), FR-TOP-06 (✎ per folder: name shown and path, Remove from Topic; drag folders to reorder), FR-TOP-07 (opening a folder opens its topic). |
| — | Quick requests | General | Show the Type column by default; remove the Save View button; larger toolbar buttons. | Normal | c3 | 21Nov26 Built: FR-CC-01 (Type column), FR-TB-04 (Save View out of the default toolbar, 36 × 34 px buttons). |
| REQ-018 | UI Style (visual refresh) | Look and Feel | Use Tailwind css style sheets to style the application components | Normal | c3 | 14Nov26 Added. 14Nov26 Decided: a visual refresh, not Tailwind. Built in the "Studio" direction: dark frame and flat tabs, blue accent, 28 px rows, redrawn icons (see details below). |

## Details

### REQ-023 Topics Improvements

- The three button at the bottom of the folders ![image-20261121210836923](./md-FeatureRequest/image-20261121210836923.png) can be removed and added into the dialog window when clicked on the pen icon to edit the topic name and description.
- The folder name must be editable, you can use the edit icon next to each folder name to open a similiar dialog for changing the folder path, folder name, delete. you can reuse the dialog and functionaltiyt from the bookmarks.
- reordering the folders in the topic is not working, please fix.
- when a folder is open thats added in a topic, also open that topic, currently the topic is only selected.

21Nov26 built. The folder name is a label shown in the topic only; the folder on disk is not renamed (spec FR-TOP-06).

### REQ-021 Topic View

2026-11-14 (built 21Nov26, see the Done table)

This is very similar behavior than grouped tab supported in chrome.



- The topic view is a tap on the left side panel, next to bookmark tab.
- a Topics is a title and short description and a list of folders that is related to each other. The list is build up by the user by adding a folder to a topic. when any of the folders in a topic is opened.
- The main or start view show the topics title defined, and a `+` to add a new topic.
- when you click on the topic the topic is opened showing the title at the top, description below and the list of folders, be default the top folder is open in the active tab.
- in the topic open view you can jump between different folders, delete folders from the topic, delete the topic, change the topic name, and description or navigate back to the main topic view.
- topic should be searchable and the order can be changed by dragiing them up or down.
- you can archive or delete a topic, archiving will whow them in a archiving group below all the normal topics. that is hidden by default.



Great enjoy developing.

### REQ-018 UI Style (visual refresh)

14Nov26: the aim is a more modern look; Tailwind itself is not needed. Three directions were mocked up (Fluent, Studio, Soft) and **Studio** was chosen:

- A dark frame (menus, toolbar, Bookmark Bar, address bar, sidebar) around the file list, light or dark with the theme.
- Flat tabs with an accent line on the active tab.
- Blue accent: the bright blue from the Fluent dark mock-up on dark surfaces, a deeper blue on light ones; blue status bar.
- Comfortable 28 px rows.
- Redrawn icons: two-tone file and folder icons, line icons for the toolbar.

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
- **14Nov26 REQ-018 built** (c3) on branch `dev`: Studio look, 28 px rows, new icons. See spec 3.2.
- **22Nov26 c6 built** on branch `dev`: REQ-030, REQ-031, REQ-033. See spec section 11.8. REQ-032 followed after a check on your Google Drive: every file reports `Normal` (0x80) and Explorer shows no status, so files in an online drive with no state of their own now show ☁ *In online drive*.
- **22Nov26 c5 built** on branch `dev`: REQ-024 Open With, REQ-025 OS folder icons, REQ-026 bookmark folder icons, REQ-027 tab folder icons, REQ-028 online drives, REQ-029 Favourites groups (logged from the quick requests). See spec section 11.7. The Windows parts were checked by compiling for Windows and need a test in the app.
- **22Nov26 Fixed (REQ-023)**: saving a folder's name or path in a topic did nothing. The backend expected the field `new_path` while the UI sends `newPath`, so every save failed; a test now reads each topic change exactly as the UI sends it.
- **21Nov26 c4 built** on branch `dev`: REQ-023 Topics improvements. Reordering folders had not been built in REQ-021; it is now. See spec section 11.6.
- **21Nov26 c3 second part built** on branch `dev`: quick requests (Type column by default, Save View out of the default toolbar, larger toolbar buttons), REQ-007 bookmark dragging, REQ-021 Topics, REQ-022 Export File List. See spec section 11.5. Choices made for REQ-021: topics live in `topics.toml` in the app settings folder; opening a topic opens its first folder in the active tab; topics with the open folder in them are marked.
