# Feature Requests
2026-11-02

 Update Cycle: c1

## Feature List 

| Name | Area | Description | Priority | Status | Update Cycle | Comment |
| ---- | ---- | ----------- | -------- | ------ | ------- | ---- |
| File Icons | File List | Add support for showing file icons. | Normal | done | c1 | 02Nov26 Added. 03Nov26 Built: icons by file type (spec FR-ICON-01). |
| Folder Colors | File List | Add Support for colored folders | Normal | done | c1 | 02Nov26 new. 03Nov26 Built: right-click › Folder Colour, saved in colours.toml (spec 6.4.5). |
| Folded Bookmarks in  sidebar | Bookmarks | Allow groups to be folded to hide the sub content. | Normal | done | c1 | 02Nov26 new. 03Nov26 Built (spec FR-BM-06). |
| Favorite Sidebar view update | Side Bar | Update the Favorite sidebar as specified in section 1.1 | Normal | done | c1 | 03Nov26 Added. 03Nov26 Built (spec FR-FAV-03). |
| Sidebar view update | Side Bar | Remove the Context View in the sidebar. | Normal | done | c1 | 03Nov26 Added. 03Nov26 Removed (spec 5.7, decision log 13.1). |
| Bookmark Groups | Bookmarks | When adding a new bookmark add dropdown on the group field that also allow free text. The user can select an existing group, type to search existing groups or if the typed group does not exist create it as a new group. | Low | done | c1 | 02Nov26 new. 03Nov26 Built (spec FR-BM-01). |
| Bookmark Reordering | Bookmarks | Allow drag and drop bookmarks to reorder them quickly, also allow moving bookmarks between groups. | Low | new | c9 | 02Nov26 new |
| Catchy name | General | Get a better name for my file explorer | Low | proposed | c1 | 02Nov26 new. 03Nov26 Ideas in the log below; waiting for your choice. |
| Open Text Editor | Feature | Setup your favorite text editor default vscode, and always show on the context menu to open any file or quickly open the current folder with the application. | Normal | new | c2 | 03Nov26 added |

### 1.1 Favorite Sidebar view update

Update the favorite sidebar view to work as follow. When the view it's initial state will show folders pinned. Example "Downloads", when the user clicks on the this folder, the files and folders in the actual folder will show in favorite. the user must be able to drill back up to the the initial favorites list. This view especially help full when savings downloads from email and you want to move the files quickly to the active tab folder.



## Log

- **03Nov26 c1 built** on branch `feature/c1`: File Icons, Folder Colors, Folded Bookmarks in sidebar, Favorite Sidebar view update, Sidebar view update, Bookmark Groups. See spec section 11.2.
- **03Nov26 Catchy name ideas** (check that the name is free before using it):
  - **Wayfile**: find your way through many folders.
  - **Foldwise**: folders, organised wisely.
  - **Filewise**: a short, plain name for a file manager.
  - **Corral**: gather files from many places into one spot.
  - **Hopper**: drop things in and move them on quickly.
