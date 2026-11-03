module Commands exposing
    ( Def
    , all
    , buildKeymap
    , enabled
    , find
    , fromBinding
    , icon
    , idOf
    , keyLabel
    , name
    )

{-| Every command in the application with its id (spec Appendix A), and the
default key bindings. The command palette, the menus, keybindings.toml and
toolbar.toml all name commands by these ids (FR-CMD-05, FR-KEY-01, FR-TB-01).
-}

import Array
import Dict exposing (Dict)
import Keys exposing (Keymap, UserBinding)
import Path
import Text
import Types exposing (..)


type alias Def =
    { id : String
    , command : Command

    -- Shown on toolbar buttons: a symbol, or `.name` for the `icon name` style.
    , icon : String
    }


all : List Def
all =
    [ Def "nav.back" CmdBack "←"
    , Def "nav.forward" CmdForward "→"
    , Def "nav.up" CmdUp "↑"
    , Def "nav.home" CmdHome "⌂"
    , Def "nav.refresh" CmdRefresh "⟳"
    , Def "nav.focusAddress" CmdEditAddress "⌨"
    , Def "tab.new" CmdNewTab "+"
    , Def "tab.close" CmdCloseTab "×"
    , Def "tab.reopen" CmdReopenTab "↺"
    , Def "tab.duplicate" CmdDuplicateTab "⧉"
    , Def "tab.next" CmdNextTab "»"
    , Def "tab.prev" CmdPrevTab "«"
    , Def "palette.open" (CmdPalette "") ".command"
    , Def "palette.commands" (CmdPalette ">") "›"
    , Def "palette.bookmarks" (CmdPalette "@") "@"
    , Def "palette.tabs" (CmdPalette "#") "#"
    , Def "filter.focus" CmdFocusFilter "⏷"
    , Def "filter.clearAll" CmdClearFilters "⊘"
    , Def "find.open" (CmdPalette "?") ".find"
    , Def "new.file" (CmdNewItem NewFile) ".new-file"
    , Def "new.folder" CmdNewFolder ".new-folder"
    , Def "new.fromTemplate" CmdNewFromTemplate "✚"
    , Def "new.shortcut" (CmdNewItem NewShortcut) "↗"
    , Def "new.webLink" (CmdNewItem NewWebLink) ".weblink"
    , Def "template.saveSelection" CmdSaveAsTemplate ".copy"
    , Def "template.editFolder" CmdEditTemplates "✎"
    , Def "edit.undo" CmdUndo "↶"
    , Def "edit.cut" CmdCut "✂"
    , Def "edit.copy" CmdCopy ".copy"
    , Def "edit.paste" CmdPaste ".paste"
    , Def "edit.pasteShortcut" CmdPasteShortcut "⤤"
    , Def "edit.duplicate" CmdDuplicate "⧉"
    , Def "edit.copyPath" CmdCopyPath "⋯"
    , Def "edit.copyName" CmdCopyName "Aa"
    , Def "edit.rename" CmdRename "✎"
    , Def "edit.delete" (CmdDelete False) ".trash"
    , Def "edit.deletePermanent" (CmdDelete True) "⨯"
    , Def "edit.selectAll" CmdSelectAll "☰"
    , Def "edit.invertSelection" CmdInvertSelection "◑"
    , Def "edit.selectNone" CmdSelectNone "○"
    , Def "item.open" CmdOpen "▶"
    , Def "item.openNewTab" CmdOpenNewTab "⧉"
    , Def "item.openTerminal" CmdOpenTerminal ".terminal"
    , Def "item.reveal" CmdReveal "⌕"
    , Def "item.contextMenu" CmdItemMenu "≡"
    , Def "view.saveForFolder" (CmdSaveView False) ".save"
    , Def "view.saveForSubfolders" (CmdSaveView True) ".save"
    , Def "view.resetForFolder" CmdResetView "⟲"
    , Def "view.openFolderSettings" CmdOpenViewFile "⚙"
    , Def "view.toggleSidebar" CmdToggleSidebar "◧"
    , Def "view.sidebarMode.tree" (CmdSidebarMode TreeMode) ".tree"
    , Def "view.sidebarMode.favourites" (CmdSidebarMode FavouritesMode) ".star"
    , Def "view.sidebarMode.bookmarks" (CmdSidebarMode BookmarksMode) ".bookmark"
    , Def "view.sidebarLeft" (CmdSidebarSide "left") "◧"
    , Def "view.sidebarRight" (CmdSidebarSide "right") "◨"
    , Def "view.toggleMenuBar" (CmdToggleSetting "layout.menuBar") "☰"
    , Def "view.toggleToolbar" (CmdToggleSetting "layout.toolbar") "▭"
    , Def "view.toggleBookmarkBar" (CmdToggleSetting "layout.bookmarkBar") ".bookmark"
    , Def "view.toggleTabBar" (CmdToggleSetting "layout.tabBar") "▭"
    , Def "view.toggleAddressBar" (CmdToggleSetting "layout.addressBar") "▭"
    , Def "view.toggleStatusBar" (CmdToggleSetting "layout.statusBar") "▁"
    , Def "view.toggleExtensions" (CmdToggleSetting "view.default.showExtensions") ".x"
    , Def "view.toggleHidden" CmdToggleHidden ".eye"
    , Def "view.foldersFirst" CmdToggleFoldersFirst ".folder"
    , Def "view.theme.system" (CmdSetTheme "system") "◐"
    , Def "view.theme.light" (CmdSetTheme "light") "☀"
    , Def "view.theme.dark" (CmdSetTheme "dark") "☾"
    , Def "view.icons.system" (CmdSetIcons "system") "▣"
    , Def "view.icons.builtin" (CmdSetIcons "builtin") "□"
    , Def "focus.nextRegion" (CmdFocusRegion True) "⇥"
    , Def "focus.prevRegion" (CmdFocusRegion False) "⇤"
    , Def "menu.open" CmdMenuBar "☰"
    , Def "bookmark.addFolder" CmdBookmarkFolder "☆"
    , Def "bookmark.addItem" CmdBookmarkItem "☆"
    , Def "bookmark.manage" (CmdSidebarMode BookmarksMode) ".bookmark"
    , Def "bookmark.openFile" CmdOpenBookmarksFile "⚙"
    , Def "favourite.toggle" CmdTogglePin "★"
    , Def "jobs.toggle" CmdToggleJobs "≡"
    , Def "settings.open" CmdOpenSettingsFile "⚙"
    , Def "keybindings.open" CmdOpenKeybindingsFile "⌨"
    , Def "toolbar.open" CmdOpenToolbarFile "⚙"
    , Def "toolbar.customise" CmdCustomiseToolbar "✎"
    , Def "help.shortcuts" CmdShortcuts "⌨"
    , Def "help.logFolder" CmdOpenLogFolder ".file"
    , Def "help.about" CmdAbout "ℹ"
    , Def "app.exit" CmdExit "✕"
    ]
        ++ List.map (\n -> Def ("tab.goto" ++ String.fromInt n) (CmdGotoTab n) (String.fromInt n)) (List.range 1 9)


byId : Dict String Def
byId =
    Dict.fromList (List.map (\d -> ( d.id, d )) all)


find : String -> Maybe Def
find id =
    Dict.get id byId


{-| The id of a command, when it has one (cursor keys and typing do not).
`bookmark.manage` shares its command with the Bookmarks sidebar mode.
-}
idOf : Command -> Maybe String
idOf command =
    List.filter (\d -> d.command == command) all |> List.head |> Maybe.map .id


name : String -> String
name id =
    Text.commandName id


icon : String -> String
icon id =
    find id |> Maybe.map .icon |> Maybe.withDefault "?"


{-| The command a binding runs. `bookmark.open` takes the bookmark's name
(spec 8.3: `args = { name = "Acme" }`).
-}
fromBinding : String -> Dict String String -> Maybe Command
fromBinding id args =
    if id == "bookmark.open" then
        Dict.get "name" args |> Maybe.map CmdOpenBookmarkNamed

    else if id == "nav.goto" then
        Dict.get "path" args |> Maybe.map CmdGoto

    else
        find id |> Maybe.map .command



-- KEY BINDINGS


{-| The default key bindings (spec Appendix A): key, command, context.
-}
defaults : List ( String, String, String )
defaults =
    [ ( "Alt+Left", "nav.back", "global" )
    , ( "BrowserBack", "nav.back", "global" )
    , ( "Alt+Right", "nav.forward", "global" )
    , ( "BrowserForward", "nav.forward", "global" )
    , ( "Alt+Up", "nav.up", "global" )
    , ( "Backspace", "nav.up", "global" )
    , ( "Alt+Home", "nav.home", "global" )
    , ( "F5", "nav.refresh", "global" )
    , ( "Ctrl+L", "nav.focusAddress", "global" )
    , ( "Alt+D", "nav.focusAddress", "global" )
    , ( "Ctrl+T", "tab.new", "global" )
    , ( "Ctrl+W", "tab.close", "global" )
    , ( "Ctrl+Shift+T", "tab.reopen", "global" )
    , ( "Ctrl+Tab", "tab.next", "global" )
    , ( "Ctrl+Shift+Tab", "tab.prev", "global" )
    , ( "Ctrl+P", "palette.open", "global" )
    , ( "Ctrl+Shift+P", "palette.commands", "global" )
    , ( "Ctrl+F", "filter.focus", "global" )
    , ( "/", "filter.focus", "global" )
    , ( "Ctrl+Shift+L", "filter.clearAll", "global" )
    , ( "Ctrl+Shift+F", "find.open", "global" )
    , ( "F3", "find.open", "global" )
    , ( "Ctrl+N", "new.file", "global" )
    , ( "Ctrl+Shift+N", "new.folder", "global" )
    , ( "Ctrl+Alt+N", "new.fromTemplate", "global" )
    , ( "Ctrl+Z", "edit.undo", "global" )
    , ( "Ctrl+X", "edit.cut", "global" )
    , ( "Ctrl+C", "edit.copy", "global" )
    , ( "Ctrl+V", "edit.paste", "global" )
    , ( "Ctrl+Shift+V", "edit.pasteShortcut", "global" )
    , ( "Ctrl+Shift+C", "edit.copyPath", "global" )
    , ( "F2", "edit.rename", "global" )
    , ( "Del", "edit.delete", "global" )
    , ( "Shift+Del", "edit.deletePermanent", "global" )
    , ( "Ctrl+A", "edit.selectAll", "global" )
    , ( "Ctrl+I", "edit.invertSelection", "global" )
    , ( "Enter", "item.open", "global" )
    , ( "Ctrl+Enter", "item.openNewTab", "global" )
    , ( "Ctrl+`", "item.openTerminal", "global" )
    , ( "Shift+F10", "item.contextMenu", "global" )
    , ( "ContextMenu", "item.contextMenu", "global" )
    , ( "Ctrl+S", "view.saveForFolder", "global" )
    , ( "Ctrl+B", "view.toggleSidebar", "global" )
    , ( "Ctrl+Shift+1", "view.sidebarMode.tree", "global" )
    , ( "Ctrl+Shift+2", "view.sidebarMode.favourites", "global" )
    , ( "Ctrl+Shift+3", "view.sidebarMode.bookmarks", "global" )
    , ( "Ctrl+H", "view.toggleHidden", "global" )
    , ( "F6", "focus.nextRegion", "global" )
    , ( "Shift+F6", "focus.prevRegion", "global" )
    , ( "F10", "menu.open", "global" )
    , ( "Ctrl+D", "bookmark.addFolder", "global" )
    , ( "Ctrl+,", "settings.open", "global" )
    , ( "Ctrl+K Ctrl+S", "keybindings.open", "global" )
    , ( "Ctrl+/", "help.shortcuts", "global" )
    ]
        ++ List.map (\n -> ( "Ctrl+" ++ String.fromInt n, "tab.goto" ++ String.fromInt n, "global" )) (List.range 1 9)


contexts : List String
contexts =
    [ "global", "list", "tree", "addressBar", "palette", "filter", "quickView" ]


{-| The defaults with the user's bindings applied (FR-KEY-01). A command the
user binds loses its default keys, a key the user binds is taken from its
default command, and `key = ""` removes a command's default keys. Mistakes
are skipped and reported with their line (FR-KEY-05).
-}
buildKeymap : List UserBinding -> ( Keymap, List String )
buildKeymap user =
    let
        check b =
            if b.command /= "bookmark.open" && b.command /= "nav.goto" && find b.command == Nothing then
                Err (Text.keyLine b.line (Text.unknownCommand b.command))

            else if not (List.member b.when contexts) then
                Err (Text.keyLine b.line (Text.unknownContext b.when))

            else if fromBinding b.command b.args == Nothing then
                Err (Text.keyLine b.line Text.missingArgs)

            else if String.trim b.key == "" then
                Ok { b | key = "" }

            else
                case Keys.parse b.key of
                    Ok key ->
                        Ok { b | key = key }

                    Err problem ->
                        Err (Text.keyLine b.line problem)

        checked =
            List.map check user

        valid =
            List.filterMap Result.toMaybe checked

        warnings =
            List.filterMap
                (\r ->
                    case r of
                        Err w ->
                            Just w

                        Ok _ ->
                            Nothing
                )
                checked

        overridden =
            List.map .command valid

        taken =
            List.map (\b -> ( b.key, b.when )) valid

        kept =
            defaults
                |> List.filter (\( key, id, when ) -> not (List.member id overridden) && not (List.member ( key, when ) taken))
                |> List.map (\( key, id, when ) -> { key = key, command = id, when = when, args = Dict.empty })

        chosen =
            kept ++ List.map (\b -> { key = b.key, command = b.command, when = b.when, args = b.args }) (List.filter (\b -> b.key /= "") valid)

        add b keymap =
            { byKey = Dict.update b.key (\list -> Just (Maybe.withDefault [] list ++ [ { command = b.command, when = b.when, args = b.args } ])) keymap.byKey
            , byCommand =
                if Dict.isEmpty b.args then
                    Dict.update b.command (\list -> Just (Maybe.withDefault [] list ++ [ b.key ])) keymap.byCommand

                else
                    keymap.byCommand
            }
    in
    ( List.foldl add Keys.empty chosen, warnings )


{-| The key shown next to a command in menus and the palette: its first binding.
-}
keyLabel : Keymap -> String -> String
keyLabel keymap id =
    Keys.keysFor id keymap |> List.head |> Maybe.withDefault ""



-- STATE


{-| False when the command can't run right now, so its toolbar button is
shown disabled (FR-TB-03).
-}
enabled : Model -> Tab -> Command -> Bool
enabled model tab command =
    case command of
        CmdBack ->
            not (List.isEmpty tab.back)

        CmdForward ->
            not (List.isEmpty tab.forward)

        CmdUp ->
            Path.parent model.sep tab.path /= Nothing && tab.search == Nothing

        CmdPaste ->
            True

        CmdReopenTab ->
            not (List.isEmpty model.closedTabs)

        CmdCut ->
            hasTargets tab

        CmdCopy ->
            hasTargets tab

        CmdDelete _ ->
            hasTargets tab

        CmdRename ->
            hasTargets tab

        CmdDuplicate ->
            hasTargets tab

        CmdCopyPath ->
            hasTargets tab

        CmdCopyName ->
            hasTargets tab

        CmdNewFolder ->
            tab.search == Nothing

        CmdNewItem _ ->
            tab.search == Nothing

        CmdNewFromTemplate ->
            tab.search == Nothing

        CmdSaveView _ ->
            tab.search == Nothing

        _ ->
            True


hasTargets : Tab -> Bool
hasTargets tab =
    not (Array.isEmpty tab.visible)
