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
