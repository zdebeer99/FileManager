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


contextModeLater : String
contextModeLater =
    "Context view: coming in a later version"


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
