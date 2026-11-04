module Text exposing (..)

{-| All user-facing text in one place, so it can be translated later (NFR-UX-04).
-}


appName : String
appName =
    "File Catalog"


back : String
back =
    "Back (Alt+Left)"


forward : String
forward =
    "Forward (Alt+Right)"


up : String
up =
    "Up (Alt+Up)"


refresh : String
refresh =
    "Refresh (F5)"


home : String
home =
    "Home (Alt+Home)"


newTab : String
newTab =
    "New tab (Ctrl+T)"


closeTab : String
closeTab =
    "Close tab (Ctrl+W)"


columnTitle : String -> String
columnTitle column =
    case column of
        "name" ->
            "Name"

        "modified" ->
            "Date modified"

        "created" ->
            "Date created"

        "size" ->
            "Size"

        "type" ->
            "Type"

        "ext" ->
            "Extension"

        "sync" ->
            "Sync"

        other ->
            other


emptyFolder : String
emptyFolder =
    "This folder is empty."


loading : String
loading =
    "Loading…"


errorText : String -> String -> String
errorText kind message =
    case kind of
        "notFound" ->
            "This folder doesn't exist any more."

        "denied" ->
            "Access denied. You don't have permission to open this folder."

        "unavailable" ->
            "Location not available. " ++ message

        "notADirectory" ->
            "This is not a folder."

        _ ->
            message


retry : String
retry =
    "Retry"


goUp : String
goUp =
    "Go up"


noSubfolders : String
noSubfolders =
    "No sub-folders"


itemCount : Int -> Int -> Int -> String
itemCount total folders files =
    plural total "item" "items" ++ " (" ++ plural folders "folder" "folders" ++ ", " ++ plural files "file" "files" ++ ")"


hiddenCount : Int -> String
hiddenCount n =
    if n == 0 then
        ""

    else
        plural n "hidden item" "hidden items" ++ " not shown (Ctrl+H)"


selected : Int -> String -> String
selected n totalSize =
    if n == 0 then
        ""

    else if totalSize == "" then
        String.fromInt n ++ " selected"

    else
        String.fromInt n ++ " selected (" ++ totalSize ++ ")"


free : String -> String
free amount =
    amount ++ " free"


plural : Int -> String -> String -> String
plural n one many =
    String.fromInt n
        ++ " "
        ++ (if n == 1 then
                one

            else
                many
           )


toggleSidebar : String
toggleSidebar =
    "Show or hide the sidebar (Ctrl+B)"


saveViewLabel : String
saveViewLabel =
    "Save view"


saveView : String
saveView =
    "Save this view for the folder (Ctrl+S)"


saveViewChanged : String
saveViewChanged =
    "The view has unsaved changes. Save it for this folder (Ctrl+S)"


saveViewOptions : String
saveViewOptions =
    "More view options"


viewSaved : String -> String
viewSaved folder =
    "View saved for " ++ folder


viewReset : String -> String
viewReset folder =
    "View reset to default for " ++ folder


noSavedView : String
noSavedView =
    "This folder uses the default view. Save a view first (Ctrl+S)."


filterPlaceholder : String
filterPlaceholder =
    "Filter (Ctrl+F)"


filtered : String
filtered =
    "Filtered"


showing : Int -> Int -> String
showing shown total =
    "Showing " ++ String.fromInt shown ++ " of " ++ String.fromInt total


noMatches : String
noMatches =
    "No items match the filter."


clearFilters : String
clearFilters =
    "Clear filters"


columnFilter : String
columnFilter =
    "Filter this column"


searchColumn : String -> String
searchColumn column =
    "Search " ++ String.toLower column


selectAll : String
selectAll =
    "(Select all)"


clearFilter : String
clearFilter =
    "Clear filter"


cancel : String
cancel =
    "Cancel"


ok : String
ok =
    "OK"


save : String
save =
    "Save"


today : String
today =
    "Today"


yesterday : String
yesterday =
    "Yesterday"


thisWeek : String
thisWeek =
    "This week"


last7Days : String
last7Days =
    "Last 7 days"


thisMonth : String
thisMonth =
    "This month"


thisYear : String
thisYear =
    "This year"


treeMode : String
treeMode =
    "Folder tree (Ctrl+Shift+1)"


favouritesMode : String
favouritesMode =
    "Favourites (Ctrl+Shift+2)"


bookmarksMode : String
bookmarksMode =
    "Bookmarks (Ctrl+Shift+3)"


noFavourites : String
noFavourites =
    "No favourites yet."


pinThis : String
pinThis =
    "+ Pin this folder"


unpinThis : String
unpinThis =
    "− Unpin this folder"


pin : String
pin =
    "Pin to Favourites"


unpin : String
unpin =
    "Unpin from Favourites"


open : String
open =
    "Open"


openInNewTab : String
openInNewTab =
    "Open in New Tab"


edit : String
edit =
    "Edit…"


moveUp : String
moveUp =
    "Move Up"


moveDown : String
moveDown =
    "Move Down"


delete : String
delete =
    "Delete"


bookmarkBar : String
bookmarkBar =
    "Bookmark Bar"


bookmarkBarHint : String
bookmarkBarHint =
    "Press Ctrl+D to bookmark this folder."


otherBookmarks : String
otherBookmarks =
    "Other bookmarks"


searchBookmarks : String
searchBookmarks =
    "Search bookmarks"


noBookmarks : String
noBookmarks =
    "No bookmarks yet. Press Ctrl+D to bookmark this folder."


noBookmarksFile : String
noBookmarksFile =
    "There is no bookmarks file yet. Add a bookmark or favourite first."


addBookmark : String
addBookmark =
    "Add bookmark"


editBookmark : String
editBookmark =
    "Edit bookmark"


name : String
name =
    "Name"


target : String
target =
    "Folder, file or web address"


group : String
group =
    "Group"


newGroup : String -> String
newGroup typed =
    "Create new group \"" ++ typed ++ "\""


favUp : String
favUp =
    "Back"


showInList : String
showInList =
    "Show this folder in the file list"


folderGone : String
folderGone =
    "This folder is no longer there."


foldGroup : String
foldGroup =
    "Fold this group"


unfoldGroup : String
unfoldGroup =
    "Unfold this group"


icons : String
icons =
    "Icons"


systemIcons : String
systemIcons =
    "System Icons"


builtinIcons : String
builtinIcons =
    "Built-in Icons"


folderColour : String
folderColour =
    "Folder Colour"


noColour : String
noColour =
    "No Colour"


colourName : String -> String
colourName colour =
    case colour of
        "red" ->
            "Red"

        "orange" ->
            "Orange"

        "yellow" ->
            "Yellow"

        "green" ->
            "Green"

        "teal" ->
            "Teal"

        "blue" ->
            "Blue"

        "purple" ->
            "Purple"

        "pink" ->
            "Pink"

        "grey" ->
            "Grey"

        _ ->
            colour


groupHint : String
groupHint =
    "\"bar\" puts it on the Bookmark Bar; \"bar/Legal\" adds it to a Legal drop-down on the bar. Leave empty to keep it in the Bookmarks list only."


nameAndTargetNeeded : String
nameAndTargetNeeded =
    "Enter a name and a target."


missingTarget : String -> String
missingTarget path =
    "Can't find " ++ path


nothingSelected : String
nothingSelected =
    "Select an item first."


about : String -> String
about version =
    appName ++ " " ++ version


clipboardEmpty : String
clipboardEmpty =
    "Nothing to paste. Cut or copy items first."


renameOne : String
renameOne =
    "Select one item to rename."


newFileName : String
newFileName =
    "New file.txt"


deletePermanently : String
deletePermanently =
    "Delete Permanently"


pasteInto : String
pasteInto =
    "Paste into Folder"


cut : String
cut =
    "Cut"


copy : String
copy =
    "Copy"


paste : String
paste =
    "Paste"


duplicate : String
duplicate =
    "Duplicate"


copyPath : String
copyPath =
    "Copy Path"


rename : String
rename =
    "Rename"


undo : String
undo =
    "Undo"


openWith : String -> String
openWith editor =
    "Open with " ++ editor


openFolderWith : String -> String
openFolderWith editor =
    "Open Folder with " ++ editor


openFolderWithEditor : String
openFolderWithEditor =
    "Open Folder with Text Editor"


openTerminalHere : String
openTerminalHere =
    "Open in Terminal"


bookmarkItem : String
bookmarkItem =
    "Bookmark…"


reveal : String
reveal =
    "Show in File Manager"


newFolder : String
newFolder =
    "New Folder"


newFile : String
newFile =
    "New File…"


newShortcut : String
newShortcut =
    "New Shortcut…"


newWebLink : String
newWebLink =
    "New Web Link…"


selectAllItems : String
selectAllItems =
    "Select All"


refreshFolder : String
refreshFolder =
    "Refresh"


changeExtensionTitle : String
changeExtensionTitle =
    "Change the extension?"


changeIt : String
changeIt =
    "Change It"


targetNeeded : String
targetNeeded =
    "Enter a target."


nameEmpty : String
nameEmpty =
    "Enter a name."


nameReserved : String
nameReserved =
    "This name is reserved."


nameTooLong : String
nameTooLong =
    "The name is too long."


nameTrailing : String
nameTrailing =
    "A name can't end with a dot or a space on Windows."


conflictTitle : String
conflictTitle =
    "An item with this name already exists"


conflictNew : String
conflictNew =
    "Item being copied or moved"


conflictExisting : String
conflictExisting =
    "Item already there"


replace : String
replace =
    "Replace"


skip : String
skip =
    "Skip"


keepBoth : String
keepBoth =
    "Keep Both"


replaceIfNewer : String
replaceIfNewer =
    "Replace if Newer"


applyToAll : String
applyToAll =
    "Do this for all remaining conflicts"


jobs : String
jobs =
    "Jobs"


noJobs : String
noJobs =
    "No jobs yet."


clearFinished : String
clearFinished =
    "Clear finished"


pause : String
pause =
    "Pause"


resume : String
resume =
    "Resume"


cancelJob : String
cancelJob =
    "Cancel"


showInFolder : String
showInFolder =
    "Show in folder"


close : String
close =
    "Close"


create : String
create =
    "Create"


fileName : String
fileName =
    "File name (with extension)"


shortcutTarget : String
shortcutTarget =
    "Folder or file the shortcut opens"


shortcutNameHint : String
shortcutNameHint =
    "Name (leave empty to use the target's name)"


webAddress : String
webAddress =
    "Web address"


webNameHint : String
webNameHint =
    "Name (leave empty to use the site name)"


newFileTitle : String
newFileTitle =
    "New file"


newShortcutTitle : String
newShortcutTitle =
    "New shortcut"


newWebLinkTitle : String
newWebLinkTitle =
    "New web link"


pathsCopied : Int -> String
pathsCopied n =
    if n == 1 then
        "Path copied to the clipboard"

    else
        String.fromInt n ++ " paths copied to the clipboard"


itemsCut : Int -> String
itemsCut n =
    plural n "item" "items" ++ " cut. Paste them with Ctrl+V."


itemsCopied : Int -> String
itemsCopied n =
    plural n "item" "items" ++ " copied. Paste them with Ctrl+V."


deletePermanentlyTitle : Int -> String
deletePermanentlyTitle n =
    "Delete " ++ plural n "item" "items" ++ " permanently? This can't be undone."


recycleTitle : Int -> String
recycleTitle n =
    "Move " ++ plural n "item" "items" ++ " to the Recycle Bin?"


noRecycleTitle : Int -> String
noRecycleTitle n =
    plural n "item" "items" ++ " can't go to the Recycle Bin. Delete permanently instead?"


{-| Up to 10 names, then "and N more" (FR-DEL-02).
-}
nameList : List String -> List String
nameList names =
    List.take 10 names
        ++ (if List.length names > 10 then
                [ "… and " ++ String.fromInt (List.length names - 10) ++ " more" ]

            else
                []
           )


jobProblems : Int -> String
jobProblems n =
    "Finished with " ++ plural n "problem" "problems" ++ ". See Jobs."


subject : Int -> String -> String
subject count first =
    if count == 1 then
        "\"" ++ first ++ "\""

    else
        String.fromInt count ++ " items"


{-| "Copying 3 items to Acme" while running; "Copied …" when done.
-}
jobLabel : String -> Bool -> Int -> String -> Maybe String -> Bool -> String
jobLabel kind finished count first dest permanent =
    let
        verb =
            case ( kind, finished ) of
                ( "copy", False ) ->
                    "Copying"

                ( "copy", True ) ->
                    "Copied"

                ( "move", False ) ->
                    "Moving"

                ( "move", True ) ->
                    "Moved"

                ( "duplicate", False ) ->
                    "Duplicating"

                ( "duplicate", True ) ->
                    "Duplicated"

                ( _, False ) ->
                    "Deleting"

                ( _, True ) ->
                    "Deleted"

        whereTo =
            case ( kind, dest ) of
                ( "delete", _ ) ->
                    if permanent then
                        ""

                    else
                        " to the Recycle Bin"

                ( _, Just d ) ->
                    " to " ++ d

                _ ->
                    ""
    in
    verb ++ " " ++ subject count first ++ whereTo


jobFinished : String -> String -> Int -> String -> Bool -> String
jobFinished kind state count first permanent =
    if state == "cancelled" then
        "Cancelled"

    else
        jobLabel kind True count first Nothing permanent


jobState : String -> String
jobState state =
    case state of
        "queued" ->
            "Waiting"

        "paused" ->
            "Paused"

        "waiting" ->
            "Waiting for your answer"

        "done" ->
            "Done"

        "cancelled" ->
            "Cancelled"

        _ ->
            ""


{-| "12.5 MB/s, about 20 s left" (FR-OP-03).
-}
speed : String -> Int -> String
speed perSecond secondsLeft =
    perSecond
        ++ "/s"
        ++ (if secondsLeft > 0 then
                ", about " ++ duration secondsLeft ++ " left"

            else
                ""
           )


duration : Int -> String
duration seconds =
    if seconds < 60 then
        String.fromInt seconds ++ " s"

    else if seconds < 3600 then
        String.fromInt (seconds // 60) ++ " min"

    else
        String.fromInt (seconds // 3600) ++ " h " ++ String.fromInt (modBy 60 (seconds // 60)) ++ " min"


moreJobs : Int -> String
moreJobs n =
    "+" ++ String.fromInt n ++ " more"


changeExtension : String -> String -> String
changeExtension old new =
    "Changing the extension from \""
        ++ old
        ++ "\" to \""
        ++ new
        ++ "\" may make the file unusable."


nameBadChar : String -> String
nameBadChar c =
    "A name can't contain \"" ++ c ++ "\"."


nameReservedWindows : String -> String
nameReservedWindows stem =
    "\"" ++ stem ++ "\" is reserved by Windows."


nameTaken : String -> String
nameTaken n =
    "\"" ++ n ++ "\" already exists."


editTemplates : String
editTemplates =
    "Open Templates Folder"


noTemplates : String
noTemplates =
    "No templates yet. Put files or folders in the templates folder."


dragHint : String
dragHint =
    "Ctrl copies · Shift moves · Alt makes shortcuts"


templateName : String
templateName =
    "Name (fills {name} in the template)"


newFromTemplateTitle : String
newFromTemplateTitle =
    "New from template"



-- COMMANDS (spec Appendix A)


{-| The name of a command, shown in menus, the palette, tooltips and
Help › Keyboard Shortcuts.
-}
commandName : String -> String
commandName id =
    case id of
        "nav.back" ->
            "Back"

        "nav.forward" ->
            "Forward"

        "nav.up" ->
            "Up"

        "nav.home" ->
            "Home"

        "nav.refresh" ->
            "Refresh"

        "nav.focusAddress" ->
            "Go to Address"

        "tab.new" ->
            "New Tab"

        "tab.close" ->
            "Close Tab"

        "tab.reopen" ->
            "Reopen Closed Tab"

        "tab.duplicate" ->
            "Duplicate Tab"

        "tab.next" ->
            "Next Tab"

        "tab.prev" ->
            "Previous Tab"

        "palette.open" ->
            "Command Palette"

        "palette.commands" ->
            "Command Palette: Commands"

        "palette.bookmarks" ->
            "Command Palette: Bookmarks"

        "palette.tabs" ->
            "Command Palette: Tabs"

        "filter.focus" ->
            "Quick Filter"

        "filter.clearAll" ->
            "Clear All Filters"

        "find.open" ->
            "Quick Find"

        "new.file" ->
            "New File…"

        "new.folder" ->
            "New Folder"

        "new.fromTemplate" ->
            "New from Template"

        "new.shortcut" ->
            "New Shortcut…"

        "new.webLink" ->
            "New Web Link…"

        "template.saveSelection" ->
            "Save Selection as Template"

        "template.editFolder" ->
            "Edit Templates Folder"

        "edit.undo" ->
            "Undo"

        "edit.cut" ->
            "Cut"

        "edit.copy" ->
            "Copy"

        "edit.paste" ->
            "Paste"

        "edit.pasteShortcut" ->
            "Paste as Shortcut"

        "edit.duplicate" ->
            "Duplicate"

        "edit.copyPath" ->
            "Copy Path"

        "edit.copyName" ->
            "Copy Name"

        "edit.rename" ->
            "Rename"

        "edit.delete" ->
            "Delete"

        "edit.deletePermanent" ->
            "Delete Permanently"

        "edit.selectAll" ->
            "Select All"

        "edit.invertSelection" ->
            "Invert Selection"

        "edit.selectNone" ->
            "Select None"

        "item.open" ->
            "Open"

        "item.openNewTab" ->
            "Open in New Tab"

        "item.openTerminal" ->
            "Open in Terminal"

        "item.openInEditor" ->
            "Open with Text Editor"

        "folder.openInEditor" ->
            "Open Folder with Text Editor"

        "item.reveal" ->
            "Show in File Manager"

        "item.contextMenu" ->
            "Show Item Menu"

        "view.saveForFolder" ->
            "Save View for This Folder"

        "view.saveForSubfolders" ->
            "Save View for This Folder and Subfolders"

        "view.resetForFolder" ->
            "Reset View for This Folder"

        "view.openFolderSettings" ->
            "Open Folder Settings File"

        "view.toggleSidebar" ->
            "Toggle Sidebar"

        "view.sidebarMode.tree" ->
            "Sidebar: Folder Tree"

        "view.sidebarMode.favourites" ->
            "Sidebar: Favourites"

        "view.sidebarMode.bookmarks" ->
            "Sidebar: Bookmarks"

        "view.sidebarLeft" ->
            "Sidebar on the Left"

        "view.sidebarRight" ->
            "Sidebar on the Right"

        "view.toggleMenuBar" ->
            "Toggle Menu Bar"

        "view.toggleToolbar" ->
            "Toggle Toolbar"

        "view.toggleBookmarkBar" ->
            "Toggle Bookmark Bar"

        "view.toggleTabBar" ->
            "Toggle Tab Bar"

        "view.toggleAddressBar" ->
            "Toggle Address Bar"

        "view.toggleStatusBar" ->
            "Toggle Status Bar"

        "view.toggleExtensions" ->
            "Show File Extensions"

        "view.toggleHidden" ->
            "Show Hidden Files"

        "view.foldersFirst" ->
            "Folders First"

        "view.theme.system" ->
            "Theme: Follow System"

        "view.theme.light" ->
            "Theme: Light"

        "view.theme.dark" ->
            "Theme: Dark"

        "view.icons.system" ->
            "Icons: System"

        "view.icons.builtin" ->
            "Icons: Built-in"

        "focus.nextRegion" ->
            "Next Region"

        "focus.prevRegion" ->
            "Previous Region"

        "menu.open" ->
            "Open Menu Bar"

        "bookmark.addFolder" ->
            "Bookmark This Folder"

        "bookmark.addItem" ->
            "Bookmark Selected Item"

        "bookmark.manage" ->
            "Manage Bookmarks"

        "bookmark.openFile" ->
            "Open Bookmarks File"

        "bookmark.open" ->
            "Open Bookmark"

        "nav.goto" ->
            "Go to Folder"

        "favourite.toggle" ->
            "Pin / Unpin Favourite"

        "jobs.toggle" ->
            "Jobs"

        "settings.open" ->
            "Open Settings File"

        "keybindings.open" ->
            "Open Key Bindings File"

        "toolbar.open" ->
            "Open Toolbar File"

        "toolbar.customise" ->
            "Customise Toolbar…"

        "help.shortcuts" ->
            "Keyboard Shortcuts"

        "help.logFolder" ->
            "Open Log Folder"

        "help.about" ->
            "About File Catalog"

        "app.exit" ->
            "Exit"

        _ ->
            if String.startsWith "tab.goto" id then
                "Go to Tab " ++ String.dropLeft 8 id

            else
                id



-- KEY BINDINGS (spec 6.10)


keyLine : Int -> String -> String
keyLine line problem =
    "keybindings.toml line " ++ String.fromInt line ++ ": " ++ problem ++ ". This binding is skipped."


unknownCommand : String -> String
unknownCommand command =
    "\"" ++ command ++ "\" is not a command (Help › Keyboard Shortcuts lists them)"


unknownContext : String -> String
unknownContext when =
    "when = \"" ++ when ++ "\" is not known (use global, list, tree, addressBar, palette or filter)"


missingArgs : String
missingArgs =
    "this command needs args, such as args = { name = \"Acme\" }"


chordWaiting : String -> String
chordWaiting key =
    key ++ " was pressed. Waiting for the second key of the chord…"


chordUnknown : String -> String
chordUnknown chord =
    chord ++ " is not a command."


shortcutsTitle : String
shortcutsTitle =
    "Keyboard Shortcuts"


shortcutsSearch : String
shortcutsSearch =
    "Search commands or keys"


shortcutsHint : String
shortcutsHint =
    "Your changes are saved in keybindings.toml."


addKey : String
addKey =
    "Add key"


resetKeys : String
resetKeys =
    "Reset"


removeKey : String
removeKey =
    "Remove this key"


pressKeys : String
pressKeys =
    "Press the keys… (Esc cancels; a second key within a moment makes a chord)"


keyConflict : String -> String -> String
keyConflict key command =
    key ++ " is used by " ++ command ++ ". Saving moves it to this command."


keyFree : String -> String
keyFree key =
    key ++ " is free."


saveKey : String
saveKey =
    "Save"


openFile : String
openFile =
    "Open File"


noBinding : String
noBinding =
    "—"


customised : String
customised =
    "changed"



-- COMMAND PALETTE (spec 6.9)


palettePlaceholder : String
palettePlaceholder =
    "Go to folder or file.  > commands   @ bookmarks   / path   ? find   # tabs"


paletteNoResults : String
paletteNoResults =
    "No matches"


paletteRecent : String
paletteRecent =
    "Recent"


paletteFavourite : String
paletteFavourite =
    "Favourite"


paletteBookmark : String
paletteBookmark =
    "Bookmark"


paletteInFolder : String
paletteInFolder =
    "In this folder"


paletteTab : String
paletteTab =
    "Tab"


paletteFolder : String
paletteFolder =
    "Folder"


paletteFindIn : String -> String -> String
paletteFindIn query folder =
    "Find \"" ++ query ++ "\" in " ++ folder


paletteFindHint : String
paletteFindHint =
    "Type what to find. Also: size:>10mb  modified:7d  type:folder  in:name  ext:pdf  !word"


paletteFindRecent : String
paletteFindRecent =
    "Recent search"



-- QUICK FIND (spec 6.6)


searchTabLabel : String -> String
searchTabLabel query =
    "Find: " ++ query


searchRunning : Int -> Int -> String
searchRunning scanned found =
    "Searching… " ++ String.fromInt scanned ++ " folders, " ++ String.fromInt found ++ " found (Esc stops)"


searchDone : Int -> Int -> Int -> String
searchDone scanned found millis =
    String.fromInt found ++ " found in " ++ String.fromInt scanned ++ " folders (" ++ String.fromFloat (toFloat (millis // 100) / 10) ++ " s)"


searchStopped : Int -> String
searchStopped found =
    "Search stopped. " ++ String.fromInt found ++ " found."


searchTruncated : Int -> String
searchTruncated limit =
    "Only the first " ++ String.fromInt limit ++ " results are shown (search.maxResults)."


searchResultsIn : String -> String -> String
searchResultsIn query folder =
    "Results for \"" ++ query ++ "\" in " ++ folder


searchNothing : String
searchNothing =
    "Nothing found."


searchAgain : String
searchAgain =
    "Search again"



-- TOOLBAR (spec 5.3)


customiseToolbar : String
customiseToolbar =
    "Customise Toolbar"


toolbarButtons : String
toolbarButtons =
    "Buttons"


toolbarAvailable : String
toolbarAvailable =
    "Add a button"


toolbarSeparator : String
toolbarSeparator =
    "Separator"


toolbarSpace : String
toolbarSpace =
    "Flexible space (pushes the rest right)"


toolbarStyle : String
toolbarStyle =
    "Show"


toolbarStyleIcon : String
toolbarStyleIcon =
    "Icons"


toolbarStyleIconText : String
toolbarStyleIconText =
    "Icons and text"


toolbarStyleText : String
toolbarStyleText =
    "Text"


toolbarDefaults : String
toolbarDefaults =
    "Restore Defaults"


toolbarUnknown : String -> String
toolbarUnknown item =
    "toolbar.toml: \"" ++ item ++ "\" is not a command, so it is not shown."


noBookmarkNamed : String -> String
noBookmarkNamed bookmarkName =
    "There is no bookmark named \"" ++ bookmarkName ++ "\"."


notInSearch : String
notInSearch =
    "Search results have no saved view. Open a folder to save its view."


namesCopied : Int -> String
namesCopied n =
    if n == 1 then
        "Name copied to the clipboard"

    else
        String.fromInt n ++ " names copied to the clipboard"


locate : String
locate =
    "Locate…"


locateHint : String -> String
locateHint bookmarkName =
    "Choose the new location of \"" ++ bookmarkName ++ "\" in the results and press Enter."


bookmarkRelinked : String -> String
bookmarkRelinked bookmarkName =
    "Bookmark \"" ++ bookmarkName ++ "\" now points to the new location."


retryAll : String
retryAll =
    "Retry All"


skipAll : String
skipAll =
    "Skip All"


sizeBetween : String
sizeBetween =
    "Between"


sizeAnd : String
sizeAnd =
    "and"


sizeFromHint : String
sizeFromHint =
    "0"


sizeToHint : String
sizeToHint =
    "e.g. 10 MB"
