module Menu exposing (Menu, colourEntries, columnEntries, menus, selectable, templateEntries, viewDropdown, viewMenuBar)

{-| The Menu Bar (FR-MENU-01): every command grouped in standard menus.
Commands that later milestones add are shown disabled, so the menus
already show the whole application.
-}

import Columns exposing (Column)
import Commands
import Dict
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, tabindex)
import Html.Events exposing (onClick, onMouseEnter, stopPropagationOn)
import Json.Decode as D
import Path
import Text
import Types exposing (..)


type alias Menu =
    { title : String
    , entries : List MenuEntry
    }


{-| Each menu item shows its command's current key, from the defaults and
keybindings.toml (FR-MENU-01, FR-KEY-01).
-}
menus : Model -> Tab -> List Menu
menus model tab =
    List.map (\m -> { m | entries = List.map (withKey model) m.entries }) (baseMenus model tab)


withKey : Model -> MenuEntry -> MenuEntry
withKey model entry =
    case entry of
        Action a ->
            case a.msg of
                Just (KeyCommand command) ->
                    case Commands.idOf command of
                        Just id ->
                            Action { a | key = Commands.keyLabel model.keymap id }

                        Nothing ->
                            entry

                _ ->
                    entry

        Submenu label children ->
            Submenu label (List.map (withKey model) children)

        Separator ->
            entry


baseMenus : Model -> Tab -> List Menu
baseMenus model tab =
    let
        s =
            model.settings

        primarySort =
            List.head tab.view.sort |> Maybe.withDefault ( Columns.Name, False )

        pinned =
            List.any (\f -> f.path == tab.path) model.favourites

        sidebarMode =
            sidebarModeFromString s.sidebarMode
    in
    [ { title = "File"
      , entries =
            [ cmd "New Tab" "Ctrl+T" CmdNewTab
            , later "New Window" "Ctrl+Shift+W"
            , Separator
            , cmd "New Folder" "Ctrl+Shift+N" CmdNewFolder
            , cmd "New File…" "Ctrl+N" (CmdNewItem NewFile)
            , cmd "New Shortcut…" "" (CmdNewItem NewShortcut)
            , cmd "New Web Link…" "" (CmdNewItem NewWebLink)
            , Submenu "New from Template" (templateEntries model)
            , Separator
            , cmd "Open" "Enter" CmdOpen
            , later "Open With" ""
            , cmd "Open in Terminal" "Ctrl+`" CmdOpenTerminal
            , cmd "Show in File Manager" "" CmdReveal
            , later "Properties" "Alt+Enter"
            , Separator
            , cmd "Close Tab" "Ctrl+W" CmdCloseTab
            , cmd "Exit" "" CmdExit
            ]
      }
    , { title = "Edit"
      , entries =
            [ cmd "Undo" "Ctrl+Z" CmdUndo
            , Separator
            , cmd "Cut" "Ctrl+X" CmdCut
            , cmd "Copy" "Ctrl+C" CmdCopy
            , Action { label = "Paste", key = "Ctrl+V", msg = Maybe.map (\_ -> KeyCommand CmdPaste) model.clipboard, checked = Nothing }
            , cmd "Paste as Shortcut" "Ctrl+Shift+V" CmdPasteShortcut
            , cmd "Duplicate" "" CmdDuplicate
            , cmd "Copy Path" "Ctrl+Shift+C" CmdCopyPath
            , cmd "Copy Name" "" CmdCopyName
            , Separator
            , cmd "Rename" "F2" CmdRename
            , cmd "Delete" "Del" (CmdDelete False)
            , cmd "Delete Permanently" "Shift+Del" (CmdDelete True)
            , Separator
            , cmd "Select All" "Ctrl+A" CmdSelectAll
            , cmd "Invert Selection" "Ctrl+I" CmdInvertSelection
            , cmd "Select None" "Esc" CmdSelectNone
            ]
      }
    , { title = "View"
      , entries =
            [ toggle "Menu Bar" "" s.menuBar (CmdToggleSetting "layout.menuBar")
            , toggle "Toolbar" "" s.toolbar (CmdToggleSetting "layout.toolbar")
            , toggle "Bookmark Bar" "" s.bookmarkBar (CmdToggleSetting "layout.bookmarkBar")
            , toggle "Tab Bar" "" s.tabBar (CmdToggleSetting "layout.tabBar")
            , toggle "Address Bar" "" s.addressBar (CmdToggleSetting "layout.addressBar")
            , toggle "Sidebar" "Ctrl+B" s.sidebarVisible CmdToggleSidebar
            , later "Quick View" "Ctrl+Q"
            , toggle "Status Bar" "" s.statusBar (CmdToggleSetting "layout.statusBar")
            , cmd "Customise Toolbar…" "" CmdCustomiseToolbar
            , Separator
            , Submenu "Sidebar"
                [ toggle "Folder Tree" "Ctrl+Shift+1" (sidebarMode == TreeMode) (CmdSidebarMode TreeMode)
                , toggle "Favourites" "Ctrl+Shift+2" (sidebarMode == FavouritesMode) (CmdSidebarMode FavouritesMode)
                , toggle "Bookmarks" "Ctrl+Shift+3" (sidebarMode == BookmarksMode) (CmdSidebarMode BookmarksMode)
                , Separator
                , toggle "On the Left" "" (s.sidebarSide /= "right") (CmdSidebarSide "left")
                , toggle "On the Right" "" (s.sidebarSide == "right") (CmdSidebarSide "right")
                ]
            , Submenu "View Mode"
                [ Action { label = "Details", key = "", msg = Just NoOp, checked = Just True }
                , later "List" ""
                ]
            , Submenu "Columns" (columnEntries model tab)
            , Submenu "Sort By"
                (List.map
                    (\( column, _ ) ->
                        toggle (Columns.title column) "" (Tuple.first primarySort == column) (CmdSortBy column)
                    )
                    tab.view.columns
                    ++ [ Separator
                       , toggle "Ascending" "" (not (Tuple.second primarySort)) (CmdSortDirection False)
                       , toggle "Descending" "" (Tuple.second primarySort) (CmdSortDirection True)
                       , Separator
                       , toggle "Folders First" "" tab.view.foldersFirst CmdToggleFoldersFirst
                       ]
                )
            , toggle "Show Hidden Files" "Ctrl+H" tab.view.showHidden CmdToggleHidden
            , toggle "Show File Extensions" "" s.showExtensions (CmdToggleSetting "view.default.showExtensions")
            , Separator
            , cmd "Quick Filter" "Ctrl+F" CmdFocusFilter
            , cmd "Clear All Filters" "Ctrl+Shift+L" CmdClearFilters
            , Separator
            , cmd "Save View for This Folder" "Ctrl+S" (CmdSaveView False)
            , cmd "Save View for This Folder and Subfolders" "" (CmdSaveView True)
            , cmd "Reset View for This Folder" "" CmdResetView
            , cmd "Open Folder Settings File" "" CmdOpenViewFile
            , Separator
            , Submenu "Theme"
                [ toggle "Follow System" "" (s.theme /= "light" && s.theme /= "dark") (CmdSetTheme "system")
                , toggle "Light" "" (s.theme == "light") (CmdSetTheme "light")
                , toggle "Dark" "" (s.theme == "dark") (CmdSetTheme "dark")
                ]
            , cmd "Refresh" "F5" CmdRefresh
            ]
      }
    , { title = "Go"
      , entries =
            [ cmd "Back" "Alt+Left" CmdBack
            , cmd "Forward" "Alt+Right" CmdForward
            , cmd "Up" "Alt+Up" CmdUp
            , cmd "Home" "Alt+Home" CmdHome
            , cmd "Go to Address" "Ctrl+L" CmdEditAddress
            , Separator
            , Submenu "Recent Folders" (folderList model (List.take 15 model.recent))
            , Submenu "Favourites" (folderList model (List.map .path model.favourites))
            , toggle "Pin This Folder to Favourites" "" pinned CmdTogglePin
            ]
      }
    , { title = "Bookmarks"
      , entries =
            [ cmd "Bookmark This Folder" "Ctrl+D" CmdBookmarkFolder
            , cmd "Bookmark Selected Item" "" CmdBookmarkItem
            , cmd "Manage Bookmarks" "" (CmdSidebarMode BookmarksMode)
            , cmd "Open Bookmarks File" "" CmdOpenBookmarksFile
            , Separator
            , Submenu "All Bookmarks"
                (if List.isEmpty model.bookmarks then
                    [ later "No bookmarks yet" "" ]

                 else
                    List.map
                        (\b -> Action { label = b.name, key = "", msg = Just (OpenBookmark b False), checked = Nothing })
                        (List.take 40 model.bookmarks)
                )
            ]
      }
    , { title = "Tools"
      , entries =
            [ cmd "Quick Find" "Ctrl+Shift+F" (CmdPalette "?")
            , cmd "Quick Filter" "Ctrl+F" CmdFocusFilter
            , cmd "Command Palette" "Ctrl+P" (CmdPalette "")
            , cmd "Commands…" "Ctrl+Shift+P" (CmdPalette ">")
            , Separator
            , cmd "Save Selection as Template" "" CmdSaveAsTemplate
            , cmd "Edit Templates Folder" "" CmdEditTemplates
            , Separator
            , cmd "Open Settings File" "Ctrl+," CmdOpenSettingsFile
            , cmd "Open Key Bindings File" "" CmdOpenKeybindingsFile
            , cmd "Open Toolbar File" "" CmdOpenToolbarFile
            ]
      }
    , { title = "Window"
      , entries =
            [ toggle "Jobs" "" model.jobsPanel CmdToggleJobs
            , Separator
            , cmd "Next Tab" "Ctrl+Tab" CmdNextTab
            , cmd "Previous Tab" "Ctrl+Shift+Tab" CmdPrevTab
            , Submenu "Tabs"
                (List.indexedMap
                    (\i t ->
                        toggle (Path.name model.sep t.path)
                            (if i < 8 then
                                "Ctrl+" ++ String.fromInt (i + 1)

                             else
                                ""
                            )
                            (t.id == model.active)
                            (CmdGotoTab (i + 1))
                    )
                    model.tabs
                )
            , cmd "Duplicate Tab" "" CmdDuplicateTab
            , cmd "Reopen Closed Tab" "Ctrl+Shift+T" CmdReopenTab
            ]
      }
    , { title = "Help"
      , entries =
            [ cmd "Keyboard Shortcuts" "Ctrl+/" CmdShortcuts
            , later "Documentation" ""
            , cmd "Open Log Folder" "" CmdOpenLogFolder
            , cmd ("About " ++ "File Catalog") "" CmdAbout
            ]
      }
    ]


{-| The Folder Colour submenu (spec 6.4.5) for one or more folders. The tick
shows the colour they share, if any.
-}
colourEntries : Model -> List String -> MenuEntry
colourEntries model paths =
    let
        current =
            case List.map (\p -> Dict.get p model.folderColours) paths of
                first :: rest ->
                    if List.all ((==) first) rest then
                        first

                    else
                        Just "mixed"

                [] ->
                    Nothing

        choice colour =
            Action
                { label = Text.colourName colour
                , key = ""
                , msg = Just (SetFolderColour paths (Just colour))
                , checked = Just (current == Just colour)
                }
    in
    Submenu Text.folderColour
        (List.map choice folderColours
            ++ [ Separator
               , Action { label = Text.noColour, key = "", msg = Just (SetFolderColour paths Nothing), checked = Just (current == Nothing) }
               ]
        )


{-| The column chooser, used by View › Columns and the header right-click menu.
-}
columnEntries : Model -> Tab -> List MenuEntry
columnEntries model tab =
    List.map
        (\column ->
            let
                shown =
                    List.any (\( c, _ ) -> c == column) tab.view.columns
            in
            Action
                { label = Columns.title column
                , key = ""
                , msg =
                    if column == Columns.Name then
                        Nothing

                    else
                        Just (ToggleColumn column)
                , checked = Just shown
                }
        )
        (Columns.available model.syncSupported)


folderList : Model -> List String -> List MenuEntry
folderList model paths =
    if List.isEmpty paths then
        [ later "(empty)" "" ]

    else
        List.map (\p -> Action { label = Path.name model.sep p, key = "", msg = Just (NavigateTo p), checked = Nothing }) paths


cmd : String -> String -> Command -> MenuEntry
cmd label key command =
    Action { label = label, key = key, msg = Just (KeyCommand command), checked = Nothing }


toggle : String -> String -> Bool -> Command -> MenuEntry
toggle label key checked command =
    Action { label = label, key = key, msg = Just (KeyCommand command), checked = Just checked }


{-| A command that a later milestone adds: shown, but disabled.
-}
later : String -> String -> MenuEntry
later label key =
    Action { label = label, key = key, msg = Nothing, checked = Nothing }


{-| Indexes of entries the keyboard can move to (not separators or disabled actions).
-}
selectable : List MenuEntry -> List Int
selectable entries =
    entries
        |> List.indexedMap Tuple.pair
        |> List.filterMap
            (\( i, entry ) ->
                case entry of
                    Action { msg } ->
                        Maybe.map (\_ -> i) msg

                    Submenu _ _ ->
                        Just i

                    Separator ->
                        Nothing
            )



-- VIEW


viewMenuBar : Model -> Tab -> Html Msg
viewMenuBar model tab =
    div [ class "menubar", attribute "role" "menubar" ]
        (List.indexedMap
            (\i menu ->
                let
                    open =
                        Maybe.map .index model.menuBar == Just i
                in
                div [ class "menubar-item" ]
                    [ button
                        [ classList [ ( "open", open ) ]
                        , stopPropagationOn "click" (D.succeed ( MenuBarClick i, True ))
                        , onMouseEnter (MenuBarHover i)
                        , tabindex -1
                        ]
                        [ text menu.title ]
                    , case ( open, model.menuBar ) of
                        ( True, Just state ) ->
                            viewDropdown state.active state.sub True menu.entries

                        _ ->
                            text ""
                    ]
            )
            (menus model tab)
        )


{-| A drop-down list of entries. `active` and `sub` mark the keyboard
position; submenus also open on mouse hover.
-}
viewDropdown : Int -> Maybe Int -> Bool -> List MenuEntry -> Html Msg
viewDropdown active sub trackHover entries =
    div [ class "menu dropdown", attribute "role" "menu", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
        (List.indexedMap
            (\i entry ->
                let
                    hover subIndex =
                        if trackHover then
                            [ onMouseEnter (MenuItemHover i subIndex) ]

                        else
                            []
                in
                case entry of
                    Action a ->
                        button
                            ([ class "menu-item"
                             , classList [ ( "active", i == active ) ]
                             , disabled (a.msg == Nothing)
                             , tabindex -1
                             , attribute "role" "menuitem"
                             ]
                                ++ hover Nothing
                                ++ (case a.msg of
                                        Just msg ->
                                            [ onClick (MenuRun msg) ]

                                        Nothing ->
                                            []
                                   )
                            )
                            [ span [ class "check" ]
                                [ text
                                    (if a.checked == Just True then
                                        "✓"

                                     else
                                        ""
                                    )
                                ]
                            , span [ class "label" ] [ text a.label ]
                            , span [ class "key" ] [ text a.key ]
                            ]

                    Submenu label children ->
                        div
                            ([ class "menu-item has-sub"
                             , classList [ ( "active", i == active ), ( "open", i == active && sub /= Nothing ) ]
                             , attribute "role" "menuitem"
                             ]
                                ++ hover Nothing
                            )
                            [ span [ class "check" ] []
                            , span [ class "label" ] [ text label ]
                            , span [ class "key" ] [ text "▸" ]
                            , div [ class "submenu" ]
                                [ viewDropdown
                                    (if i == active then
                                        Maybe.withDefault -1 sub

                                     else
                                        -1
                                    )
                                    Nothing
                                    False
                                    children
                                ]
                            ]

                    Separator ->
                        div [ class "menu-sep" ] []
            )
            entries
        )


{-| The New from Template menu: templates, grouped by their `_Group` folders (FR-TPL-02).
-}
templateEntries : Model -> List MenuEntry
templateEntries model =
    let
        entry t =
            Action { label = t.name, key = "", msg = Just (CreateFromTemplate t), checked = Nothing }

        topLevel =
            List.filter (\t -> List.isEmpty t.group) model.templates

        groups =
            List.foldl
                (\t acc ->
                    case List.head t.group of
                        Just g ->
                            if List.member g acc then
                                acc

                            else
                                acc ++ [ g ]

                        Nothing ->
                            acc
                )
                []
                model.templates

        footer =
            [ Separator, Action { label = Text.editTemplates, key = "", msg = Just (KeyCommand CmdEditTemplates), checked = Nothing } ]
    in
    if List.isEmpty model.templates then
        Action { label = Text.noTemplates, key = "", msg = Nothing, checked = Nothing } :: footer

    else
        List.map entry topLevel
            ++ List.map (\g -> Submenu g (List.map entry (List.filter (\t -> List.head t.group == Just g) model.templates))) groups
            ++ footer
