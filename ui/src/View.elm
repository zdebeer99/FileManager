module View exposing (filterPopupValues, treeRows, view)

{-| Draws the window (spec 5.1).
-}

import Array
import Columns exposing (Column)
import Commands
import Dict
import Filter
import Format
import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, placeholder, spellcheck, style, tabindex, title, value)
import Html.Events exposing (on, onBlur, onClick, onFocus, onInput, onMouseEnter, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Item exposing (Item)
import Json.Decode as D
import Json.Encode
import Keys
import Menu
import Path
import Set
import Text
import Types exposing (..)


view : Model -> Html Msg
view model =
    div
        ([ class "app"

         -- Focusable, so clicking an empty spot keeps keyboard focus inside the app.
         , tabindex -1
         , preventDefaultOn "keydown" (keyDecoder model)
         , on "mouseup" mouseNavDecoder
         , on "mouseleave" (D.succeed DragLeftWindow)
         ]
            ++ themeAttribute model.settings.theme
            ++ (if model.popup /= Nothing || model.menuBar /= Nothing then
                    [ onClick ClosePopups ]

                else
                    []
               )
            ++ (case model.drag of
                    Just (ResizeColumn _ _ _) ->
                        [ class "dragging-col" ]

                    Just (ResizeSidebar _) ->
                        [ class "dragging-col" ]

                    _ ->
                        []
               )
        )
        (if not model.booted then
            [ div [ class "placeholder" ] [ text (Maybe.withDefault "" model.bootError) ] ]

         else
            case activeTab model of
                Nothing ->
                    []

                Just tab ->
                    [ viewIf (model.settings.menuBar || model.menuBar /= Nothing) (Menu.viewMenuBar model tab)
                    , viewIf model.settings.toolbar (viewToolbar model tab)
                    , viewIf model.settings.bookmarkBar (viewBookmarkBar model)
                    , viewIf model.settings.tabBar (viewTabBar model)
                    , viewIf model.settings.addressBar (viewAddressBar model tab)
                    , viewMain model tab
                    , viewIf model.settings.statusBar (viewStatusBar model tab)
                    , viewIf model.jobsPanel (viewJobsPanel model)
                    , viewPopup model
                    , viewDragGhost model
                    , case model.conflicts of
                        conflict :: _ ->
                            viewConflict model conflict

                        [] ->
                            viewDialog model
                    , viewPalette model
                    ]
        )


themeAttribute : String -> List (Html.Attribute msg)
themeAttribute theme =
    if theme == "light" || theme == "dark" then
        [ attribute "data-theme" theme ]

    else
        []


viewIf : Bool -> Html msg -> Html msg
viewIf condition html =
    if condition then
        html

    else
        text ""



-- TOOLBAR


viewToolbar : Model -> Tab -> Html Msg
viewToolbar model tab =
    div
        [ class ("toolbar style-" ++ model.toolbar.style)
        , preventDefaultOn "contextmenu" (D.map2 (\x y -> ( ToolbarContext x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))
        ]
        (List.map (viewToolbarItem model tab) model.toolbar.items)


{-| One toolbar.toml item: a command button, `|` a separator, `->` flexible space (spec 8.5).
-}
viewToolbarItem : Model -> Tab -> String -> Html Msg
viewToolbarItem model tab item =
    case item of
        "|" ->
            span [ class "sep" ] []

        "->" ->
            span [ class "grow" ] []

        "view.saveForFolder" ->
            viewSaveViewButton model tab

        id ->
            case Commands.find id of
                Just def ->
                    let
                        name =
                            Commands.name id

                        key =
                            Commands.keyLabel model.keymap id

                        label =
                            if key == "" then
                                name

                            else
                                name ++ " (" ++ key ++ ")"
                    in
                    button
                        [ onClick (KeyCommand def.command)
                        , title label
                        , attribute "aria-label" label
                        , disabled (not (Commands.enabled model tab def.command))
                        , tabindex -1
                        ]
                        (toolbarFace model.toolbar.style def.icon name)

                Nothing ->
                    text ""


toolbarFace : String -> String -> String -> List (Html msg)
toolbarFace style icon name =
    let
        glyph =
            if String.startsWith "." icon then
                span [ class ("icon " ++ String.dropLeft 1 icon) ] []

            else
                span [ class "tb-icon" ] [ text icon ]
    in
    case style of
        "text" ->
            [ span [ class "tb-text" ] [ text name ] ]

        "iconText" ->
            [ glyph, span [ class "tb-text" ] [ text name ] ]

        _ ->
            [ glyph ]


{-| Save View, with a dot when the view has unsaved changes (FR-TB-04, FR-VIEW-05).
-}
viewSaveViewButton : Model -> Tab -> Html Msg
viewSaveViewButton model tab =
    let
        changed =
            tab.view /= tab.savedView && tab.search == Nothing
    in
    div [ class "split-button" ]
        [ button
            [ class "wide"
            , onClick (KeyCommand (CmdSaveView False))
            , title
                (if changed then
                    Text.saveViewChanged

                 else
                    Text.saveView
                )
            , disabled (tab.search /= Nothing)
            , tabindex -1
            ]
            [ text Text.saveViewLabel
            , viewIf changed (span [ class "dot" ] [])
            ]
        , button
            [ class "arrow"
            , stopPropagationOn "click" (D.map2 (\x y -> ( SaveViewMenu x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))
            , title Text.saveViewOptions
            , disabled (tab.search /= Nothing)
            , tabindex -1
            ]
            [ text "▾" ]
        ]



-- BOOKMARK BAR


type BarEntry
    = BarBookmark Bookmark
    | BarGroup String (List Bookmark)


viewBookmarkBar : Model -> Html Msg
viewBookmarkBar model =
    let
        onBar =
            List.filter (\b -> List.head b.group == Just "bar") model.bookmarks

        entries =
            List.foldl
                (\b acc ->
                    case b.group of
                        [ "bar" ] ->
                            acc ++ [ BarBookmark b ]

                        _ :: group :: _ ->
                            if List.any (isGroup group) acc then
                                acc

                            else
                                acc ++ [ BarGroup group (List.filter (\x -> List.drop 1 x.group |> List.head |> (==) (Just group)) onBar) ]

                        _ ->
                            acc
                )
                []
                onBar

        isGroup group entry =
            case entry of
                BarGroup g _ ->
                    g == group

                _ ->
                    False
    in
    div (class "bookmarkbar" :: dropTarget model DropBookmarkBar "bookmark-bar")
        (if List.isEmpty entries then
            [ span [ class "hint" ] [ text Text.bookmarkBarHint ] ]

         else
            List.map
                (\entry ->
                    case entry of
                        BarBookmark b ->
                            bookmarkButton model b

                        BarGroup group members ->
                            button
                                [ class "bm group"
                                , stopPropagationOn "click"
                                    (D.map2
                                        (\x y ->
                                            ( ItemContextMenu
                                                (List.map
                                                    (\b -> Action { label = b.name, key = "", msg = Just (OpenBookmark b False), checked = Nothing })
                                                    members
                                                )
                                                x
                                                (y + 10)
                                            , True
                                            )
                                        )
                                        (D.field "clientX" D.float)
                                        (D.field "clientY" D.float)
                                    )
                                , tabindex -1
                                ]
                                [ span [ class "icon folder" ] [], text (group ++ " ▾") ]
                )
                entries
        )


bookmarkButton : Model -> Bookmark -> Html Msg
bookmarkButton model b =
    button
        [ class "bm"
        , classList [ ( "missing", not b.exists ) ]
        , on "click" (D.map (\ctrl -> OpenBookmark b (ctrl && b.kind == "folder")) (D.field "ctrlKey" D.bool))
        , on "auxclick" (middleClick (OpenBookmark b (b.kind == "folder")))
        , contextMenu (bookmarkEntries b)
        , title b.target
        , tabindex -1
        ]
        [ viewBookmarkIcon model b, text b.name ]


bookmarkIcon : Bookmark -> String
bookmarkIcon b =
    case b.kind of
        "folder" ->
            "folder"

        "url" ->
            "weblink"

        _ ->
            Item.fileCategory (extensionOf b.target)


{-| The lower-case extension of a path, or "" when it has none.
-}
extensionOf : String -> String
extensionOf path =
    let
        name =
            path |> String.replace "\\" "/" |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault ""
    in
    case List.reverse (String.split "." name) of
        ext :: _ :: _ ->
            String.toLower ext

        _ ->
            ""


bookmarkEntries : Bookmark -> List MenuEntry
bookmarkEntries b =
    let
        action label msg =
            Action { label = label, key = "", msg = Just msg, checked = Nothing }

        edit op extra =
            BookmarkEditOp (( "op", Json.Encode.string op ) :: ( "index", Json.Encode.int b.index ) :: extra)
    in
    [ action Text.open (OpenBookmark b False) ]
        ++ (if b.kind == "folder" then
                [ action Text.openInNewTab (OpenBookmark b True) ]

            else
                []
           )
        ++ (if b.exists then
                []

            else
                [ action Text.locate (LocateBookmark b) ]
           )
        ++ [ Separator
           , action Text.edit (EditBookmark b)
           , action Text.moveUp (edit "move" [ ( "delta", Json.Encode.int -1 ) ])
           , action Text.moveDown (edit "move" [ ( "delta", Json.Encode.int 1 ) ])
           , Separator
           , action Text.delete (edit "remove" [])
           ]



-- TAB BAR


viewTabBar : Model -> Html Msg
viewTabBar model =
    div [ class "tabbar", attribute "role" "tablist" ]
        (List.map (viewTab model) model.tabs
            ++ [ button [ class "newtab", onClick NewTab, title Text.newTab, tabindex -1 ] [ text "+" ] ]
        )


viewTab : Model -> Tab -> Html Msg
viewTab model tab =
    let
        dragOver =
            case model.drag of
                Just (MoveTab d) ->
                    d.moved && d.over == Just tab.id && d.tabId /= tab.id

                _ ->
                    False
    in
    div
        ([ class "tab"
         , classList [ ( "active", tab.id == model.active ), ( "tab-drop", dragOver ) ]
         , on "mousedown"
            (D.map2 Tuple.pair (D.field "button" D.int) (D.field "clientX" D.float)
                |> D.andThen
                    (\( b, x ) ->
                        if b == 0 then
                            D.succeed (TabMouseDown tab.id x)

                        else
                            D.fail "not the left button"
                    )
            )
         , on "mouseover" (D.succeed (TabHover tab.id))
         , attribute "role" "tab"
         , onClick (ActivateTab tab.id)
         , on "auxclick" (middleClick (CloseTab tab.id))
         , title tab.path
         ]
            ++ dropTarget model (DropFolder tab.path) tab.path
        )
        [ viewIf (isFiltering tab) (span [ class "icon filter", title Text.filtered ] [])
        , case tab.search of
            Just search ->
                span [ class "label search" ] [ text (Text.searchTabLabel search.query) ]

            Nothing ->
                span [ class "label" ] [ text (Path.name model.sep tab.path) ]
        , button
            [ class "close"
            , stopPropagationOn "click" (D.succeed ( CloseTab tab.id, True ))
            , title Text.closeTab
            , tabindex -1
            ]
            [ text "×" ]
        ]



-- ADDRESS BAR


viewAddressBar : Model -> Tab -> Html Msg
viewAddressBar model tab =
    div [ class "addressbar" ]
        [ case model.address of
            Editing typed error ->
                div [ class "address-edit" ]
                    [ input
                        [ id addressInputId
                        , class "address-input"
                        , value typed
                        , onInput AddressInput
                        , onBlur AddressBlur
                        , Html.Events.custom "keydown" (inputKeys [ "Enter", "Escape", "Tab" ] AddressKey)
                        , attribute "data-select-on-focus" ""
                        , spellcheck False
                        ]
                        []
                    , case error of
                        Just message ->
                            span [ class "address-error" ] [ text message ]

                        Nothing ->
                            text ""
                    ]

            ShowCrumbs ->
                div [ class "crumbs", onClick StartEditAddress, title tab.path ]
                    (List.concatMap viewCrumb (Path.crumbs model.sep tab.path))
        , div [ class "filter-box", classList [ ( "active", tab.filter /= "" ) ] ]
            [ span [ class "icon filter" ] []
            , input
                [ id filterInputId
                , class "filter-input"
                , placeholder Text.filterPlaceholder
                , value tab.filter
                , onInput FilterInput
                , onFocus (RegionFocused RegionFilter)
                , Html.Events.custom "keydown" (inputKeys [ "Escape", "Enter", "ArrowDown", "F6" ] FilterKey)
                , spellcheck False
                , attribute "aria-label" Text.filterPlaceholder
                ]
                []
            ]
        ]


viewCrumb : Path.Crumb -> List (Html Msg)
viewCrumb crumb =
    [ button
        [ class "crumb"
        , stopPropagationOn "click" (D.succeed ( NavigateTo crumb.path, True ))
        , tabindex -1
        ]
        [ text crumb.label ]
    , button
        [ class "crumb-sep"
        , stopPropagationOn "click"
            (D.map2 (\x y -> ( OpenCrumbMenu crumb.path x y, True ))
                (D.field "clientX" D.float)
                (D.field "clientY" D.float)
            )
        , tabindex -1
        ]
        [ text "›" ]
    ]


{-| Handles the listed keys in a text box (and keeps them from the window).
-}
inputKeys : List String -> (String -> Msg) -> D.Decoder { message : Msg, stopPropagation : Bool, preventDefault : Bool }
inputKeys keys toMsg =
    D.field "key" D.string
        |> D.andThen
            (\key ->
                if List.member key keys then
                    D.succeed { message = toMsg key, stopPropagation = True, preventDefault = True }

                else
                    D.fail "other key"
            )



-- MAIN AREA: SIDEBAR AND LIST


viewMain : Model -> Tab -> Html Msg
viewMain model tab =
    let
        sidebar =
            if model.settings.sidebarVisible then
                [ viewSidebar model tab, div [ class "splitter", on "mousedown" (D.map SidebarResizeStart (D.field "clientX" D.float)) ] [] ]

            else
                []
    in
    div [ class "main" ]
        (if model.settings.sidebarSide == "right" then
            viewContent model tab :: List.reverse sidebar

         else
            sidebar ++ [ viewContent model tab ]
        )


viewSidebar : Model -> Tab -> Html Msg
viewSidebar model tab =
    let
        width =
            case model.drag of
                Just (ResizeSidebar d) ->
                    d.width

                _ ->
                    model.settings.sidebarWidth

        mode =
            sidebarModeFromString model.settings.sidebarMode

        modeButton m icon label =
            button
                [ classList [ ( "active", mode == m ) ]
                , onClick (KeyCommand (CmdSidebarMode m))
                , title label
                , attribute "aria-label" label
                , tabindex -1
                ]
                [ span [ class ("icon " ++ icon) ] [] ]
    in
    div
        [ id sidebarId
        , class "sidebar"
        , style "width" (px width)
        , tabindex 0
        , on "focusin" (D.succeed (RegionFocused RegionSidebar))
        ]
        [ div [ class "sidebar-modes" ]
            [ modeButton TreeMode "tree" Text.treeMode
            , modeButton FavouritesMode "star" Text.favouritesMode
            , modeButton BookmarksMode "bookmark" Text.bookmarksMode
            ]
        , div [ id sidebarBodyId, class "sidebar-body" ]
            (case mode of
                TreeMode ->
                    viewTree model tab

                FavouritesMode ->
                    viewFavourites model tab

                BookmarksMode ->
                    viewBookmarksPanel model
            )
        ]


type alias TreeRow =
    { path : String
    , label : String
    , depth : Int
    , kind : String
    }


{-| The visible rows of the folder tree, in order.
-}
treeRows : Model -> List TreeRow
treeRows model =
    let
        node depth path label kind =
            { path = path, label = label, depth = depth, kind = kind }
                :: (if Set.member path model.treeExpanded && depth < 64 then
                        Dict.get path model.treeChildren
                            |> Maybe.withDefault []
                            |> List.concatMap (\c -> node (depth + 1) c.path c.label "folder")

                    else
                        []
                   )
    in
    List.concatMap (\r -> node 0 r.path r.name r.kind) model.roots


viewTree : Model -> Tab -> List (Html Msg)
viewTree model tab =
    List.map
        (\row ->
            let
                expanded =
                    Set.member row.path model.treeExpanded

                twisty =
                    case Dict.get row.path model.treeChildren of
                        Just [] ->
                            ""

                        _ ->
                            if expanded then
                                "▾"

                            else
                                "▸"
            in
            div
                ([ class "tree-row"
                 , classList [ ( "current", row.path == tab.path ), ( "cursor", Just row.path == model.treeCursor ) ]
                 , id
                    (if Just row.path == model.treeCursor then
                        treeCursorId

                     else
                        ""
                    )
                 , style "padding-left" (px (toFloat row.depth * 14 + 4))
                 , onClick (TreeOpen row.path)
                 , on "auxclick" (middleClick (NavigateNewTab row.path))
                 , contextMenu (folderEntries model row.path)
                 , title row.path
                 ]
                    ++ dropTarget model (DropFolder row.path) row.path
                )
                [ span [ class "twisty", stopPropagationOn "click" (D.succeed ( TreeToggle row.path, True )) ] [ text twisty ]
                , if row.kind == "folder" then
                    viewFolderIcon model row.path

                  else
                    span [ class ("icon " ++ rootIcon row.kind) ] []
                , span [ class "label" ] [ text row.label ]
                ]
        )
        (treeRows model)


rootIcon : String -> String
rootIcon kind =
    case kind of
        "drive" ->
            "drive"

        "removable" ->
            "drive"

        "network" ->
            "network"

        "home" ->
            "home"

        _ ->
            "folder"


folderEntries : Model -> String -> List MenuEntry
folderEntries model path =
    let
        action label msg =
            Action { label = label, key = "", msg = Just msg, checked = Nothing }

        pinned =
            List.any (\f -> f.path == path) model.favourites

        fav op =
            BookmarkEditOp [ ( "op", Json.Encode.string op ), ( "path", Json.Encode.string path ) ]
    in
    [ action Text.open (NavigateTo path)
    , action Text.openInNewTab (NavigateNewTab path)
    , Separator
    , if pinned then
        action Text.unpin (fav "removeFavourite")

      else
        action Text.pin (fav "addFavourite")
    , Menu.colourEntries model [ path ]
    ]


viewFavourites : Model -> Tab -> List (Html Msg)
viewFavourites model tab =
    case model.favBrowse of
        Just browse ->
            viewFavBrowse model tab browse

        Nothing ->
            viewFavouriteList model tab


{-| Inside a favourite (spec 5.7): its files and folders, to open, browse
into, or drag onto the list, a tab or another folder. Up goes back towards
the favourite and then to the list of favourites.
-}
viewFavBrowse : Model -> Tab -> FavBrowse -> List (Html Msg)
viewFavBrowse model tab browse =
    let
        items =
            Dict.values browse.items
                |> List.filter (\i -> not i.hidden || model.settings.showHidden)
                |> List.sortWith
                    (\a b ->
                        case ( a.isDir, b.isDir ) of
                            ( True, False ) ->
                                LT

                            ( False, True ) ->
                                GT

                            _ ->
                                compare a.key b.key
                    )

        location =
            if browse.path == browse.root then
                Path.name model.sep browse.root

            else
                Path.crumbs model.sep browse.path
                    |> List.drop (List.length (Path.crumbs model.sep browse.root))
                    |> List.map .label
                    |> (::) (Path.name model.sep browse.root)
                    |> String.join " › "

        fileEntries item =
            [ Action { label = Text.open, key = "", msg = Just (OpenPath item.path), checked = Nothing }
            , Action { label = Text.reveal, key = "", msg = Just (RevealPath item.path), checked = Nothing }
            ]

        row item =
            button
                ([ class "side-item"
                 , classList [ ( "current", item.path == tab.path ), ( "selected", browse.selected == Just item.path ), ( "hidden-item", item.hidden ) ]
                 , onClick
                    (if item.isDir then
                        FavBrowseTo browse.root item.path

                     else
                        FavSelect item.path
                    )
                 , on "dblclick"
                    (D.succeed
                        (if item.isDir then
                            NavigateTo item.path

                         else
                            OpenPath item.path
                        )
                    )
                 , on "mousedown"
                    (D.field "button" D.int
                        |> D.andThen
                            (\b ->
                                if b == 0 then
                                    D.map2 (FavMouseDown item.path item.name) (D.field "clientX" D.float) (D.field "clientY" D.float)

                                else
                                    D.fail "not the left button"
                            )
                    )
                 , contextMenu
                    (if item.isDir then
                        folderEntries model item.path

                     else
                        fileEntries item
                    )
                 , title item.path
                 ]
                    ++ (if item.isDir then
                            on "auxclick" (middleClick (NavigateNewTab item.path)) :: dropTarget model (DropFolder item.path) item.path

                        else
                            []
                       )
                )
                [ viewIcon model item
                , span [ class "label" ] [ text (Item.displayName model.settings.showExtensions item) ]
                ]

        body =
            case ( browse.error, items ) of
                ( Just error, _ ) ->
                    [ div [ class "sidebar-empty" ] [ text error ] ]

                ( Nothing, [] ) ->
                    [ div [ class "sidebar-empty" ]
                        [ text
                            (if browse.loading then
                                Text.loading

                             else
                                Text.emptyFolder
                            )
                        ]
                    ]

                _ ->
                    List.map row items
    in
    div ([ class "fav-header" ] ++ dropTarget model (DropFolder browse.path) browse.path)
        [ button [ class "fav-up", onClick FavUp, title Text.favUp, attribute "aria-label" Text.favUp ] [ text "‹" ]
        , span [ class "fav-location", title browse.path ] [ text location ]
        , button [ class "fav-open", onClick (NavigateTo browse.path), title Text.showInList, attribute "aria-label" Text.showInList ] [ text "↗" ]
        ]
        :: body


viewFavouriteList : Model -> Tab -> List (Html Msg)
viewFavouriteList model tab =
    let
        pinned =
            List.any (\f -> f.path == tab.path) model.favourites

        move path delta =
            BookmarkEditOp [ ( "op", Json.Encode.string "moveFavourite" ), ( "path", Json.Encode.string path ), ( "delta", Json.Encode.int delta ) ]

        entries f =
            folderEntries model f.path
                ++ [ Action { label = Text.moveUp, key = "", msg = Just (move f.path -1), checked = Nothing }
                   , Action { label = Text.moveDown, key = "", msg = Just (move f.path 1), checked = Nothing }
                   ]
    in
    (if List.isEmpty model.favourites then
        [ div [ class "sidebar-empty" ] [ text Text.noFavourites ] ]

     else
        List.map
            (\f ->
                button
                    ([ class "side-item"
                     , classList [ ( "current", f.path == tab.path ), ( "missing", not f.exists ) ]
                     , onClick (FavBrowseTo f.path f.path)
                     , on "auxclick" (middleClick (NavigateNewTab f.path))
                     , contextMenu (entries f)
                     , title f.path
                     ]
                        ++ dropTarget model (DropFolder f.path) f.path
                    )
                    [ viewFolderIcon model f.path, span [ class "label" ] [ text (Path.name model.sep f.path) ] ]
            )
            model.favourites
    )
        ++ [ button [ class "side-add", onClick (KeyCommand CmdTogglePin) ]
                [ text
                    (if pinned then
                        Text.unpinThis

                     else
                        Text.pinThis
                    )
                ]
           ]


viewBookmarksPanel : Model -> List (Html Msg)
viewBookmarksPanel model =
    let
        search =
            String.toLower model.bookmarkSearch

        matching =
            List.filter
                (\b -> search == "" || String.contains search (String.toLower b.name) || String.contains search (String.toLower b.target))
                model.bookmarks

        -- Every group and every group above it, in the order they first appear.
        allGroups =
            List.foldl
                (\b acc ->
                    List.foldl
                        (\n acc2 ->
                            let
                                prefix =
                                    List.take n b.group
                            in
                            if List.member prefix acc2 then
                                acc2

                            else
                                acc2 ++ [ prefix ]
                        )
                        acc
                        (List.range 1 (List.length b.group))
                )
                []
                matching

        childGroups parent =
            List.filter
                (\g -> List.length g == List.length parent + 1 && List.take (List.length parent) g == parent)
                allGroups

        ungrouped =
            List.filter (\b -> List.isEmpty b.group) matching

        indent depth =
            style "padding-left" (px (toFloat depth * 14 + 4))

        viewBookmark depth b =
            button
                [ class "side-item"
                , classList [ ( "missing", not b.exists ) ]
                , indent depth
                , on "click" (D.map (\ctrl -> OpenBookmark b (ctrl && b.kind == "folder")) (D.field "ctrlKey" D.bool))
                , on "auxclick" (middleClick (OpenBookmark b (b.kind == "folder")))
                , contextMenu (bookmarkEntries b)
                , title b.target
                ]
                [ span [ class "twisty" ] [], viewBookmarkIcon model b, span [ class "label" ] [ text b.name ] ]

        -- A group heading that folds its bookmarks and sub-groups away (spec 5.7).
        -- While searching, every group is shown open so no match is hidden.
        viewGroup depth key label contents =
            let
                folded =
                    search == "" && Set.member key model.foldedGroups
            in
            button
                [ class "side-group"
                , indent depth
                , onClick (ToggleBookmarkGroup key)
                , attribute "aria-expanded"
                    (if folded then
                        "false"

                     else
                        "true"
                    )
                , title
                    (if folded then
                        Text.unfoldGroup

                     else
                        Text.foldGroup
                    )
                ]
                [ span [ class "twisty" ]
                    [ text
                        (if folded then
                            "▸"

                         else
                            "▾"
                        )
                    ]
                , span [ class "label" ] [ text label ]
                ]
                :: (if folded then
                        []

                    else
                        contents
                   )

        viewGroupTree depth group =
            viewGroup depth
                (String.join "/" group)
                (case group of
                    [ "bar" ] ->
                        Text.bookmarkBar

                    _ ->
                        List.reverse group |> List.head |> Maybe.withDefault ""
                )
                (List.map (viewBookmark (depth + 1)) (List.filter (\b -> b.group == group) matching)
                    ++ List.concatMap (viewGroupTree (depth + 1)) (childGroups group)
                )
    in
    [ input
        [ class "side-search"
        , placeholder Text.searchBookmarks
        , value model.bookmarkSearch
        , onInput BookmarkSearch
        , spellcheck False
        ]
        []
    ]
        ++ List.map (\w -> div [ class "sidebar-warning" ] [ text w ]) model.bookmarkWarnings
        ++ (if List.isEmpty model.bookmarks then
                [ div [ class "sidebar-empty" ] [ text Text.noBookmarks ] ]

            else
                List.concatMap (viewGroupTree 0) (childGroups [])
                    ++ (if List.isEmpty ungrouped then
                            []

                        else
                            viewGroup 0 "" Text.otherBookmarks (List.map (viewBookmark 1) ungrouped)
                       )
           )


viewContent : Model -> Tab -> Html Msg
viewContent model tab =
    let
        columns =
            tab.view.columns

        template =
            gridTemplate columns

        count =
            Array.length tab.visible

        first =
            max 0 (floor (tab.scrollTop / rowHeight) - 5)

        rowsShown =
            ceiling (model.viewportHeight / rowHeight) + 10

        query =
            Filter.parse tab.filter

        rows =
            Array.slice first (first + rowsShown) tab.visible
                |> Array.toIndexedList
                |> List.map (\( offset, item ) -> viewRow model tab query template (first + offset) item)
    in
    div [ class "content" ]
        [ div
            [ id listId
            , class "list"
            , tabindex 0
            , attribute "role" "grid"
            , attribute "aria-rowcount" (String.fromInt count)
            , on "scroll" (D.map2 ListScrolled (D.at [ "target", "scrollTop" ] D.float) (D.at [ "target", "clientHeight" ] D.float))
            , on "focusin" (D.succeed (RegionFocused RegionList))
            , attribute "data-drop" tab.path
            , preventDefaultOn "contextmenu" (D.map2 (\x y -> ( ListContext x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))
            ]
            [ viewHeader model tab template
            , Html.Keyed.node "div" [ class "rows", style "height" (px (toFloat count * rowHeight)) ] rows
            ]
        , viewPlaceholder tab
        ]


viewPlaceholder : Tab -> Html Msg
viewPlaceholder tab =
    case tab.status of
        Failed kind message ->
            div [ class "placeholder" ]
                [ text (Text.errorText kind message)
                , div [ class "actions" ]
                    [ button [ onClick Retry ] [ text Text.retry ]
                    , button [ onClick (KeyCommand CmdUp) ] [ text Text.goUp ]
                    ]
                ]

        Loaded ->
            if Array.isEmpty tab.visible then
                if isFiltering tab then
                    div [ class "placeholder" ]
                        [ text Text.noMatches
                        , div [ class "actions" ] [ button [ onClick (KeyCommand CmdClearFilters) ] [ text Text.clearFilters ] ]
                        ]

                else
                    div [ class "placeholder" ] [ text Text.emptyFolder ]

            else
                text ""

        _ ->
            text ""


gridTemplate : List ( Column, Float ) -> String
gridTemplate columns =
    columns
        |> List.map
            (\( c, width ) ->
                if c == Columns.Name then
                    "minmax(" ++ px width ++ ", 1fr)"

                else
                    px width
            )
        |> String.join " "


viewHeader : Model -> Tab -> String -> Html Msg
viewHeader model tab template =
    let
        sortMark column =
            case List.indexedMap (\i ( c, desc ) -> ( i, c, desc )) tab.view.sort |> List.filter (\( _, c, _ ) -> c == column) of
                ( i, _, desc ) :: _ ->
                    (if desc then
                        " ▼"

                     else
                        " ▲"
                    )
                        ++ (if List.length tab.view.sort > 1 then
                                String.fromInt (i + 1)

                            else
                                ""
                           )

                [] ->
                    ""

        target =
            case model.drag of
                Just (MoveColumn d) ->
                    if d.moved then
                        d.target

                    else
                        Nothing

                _ ->
                    Nothing
    in
    div
        [ class "list-header"
        , style "grid-template-columns" template
        , attribute "role" "row"
        , preventDefaultOn "contextmenu" (D.map2 (\x y -> ( HeaderContext x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))
        ]
        (List.map
            (\( column, _ ) ->
                let
                    filtered =
                        Dict.member (Columns.toString column) tab.columnFilters || (column == Columns.Size && Dict.member "sizeRange" tab.columnFilters)
                in
                div
                    [ class "hcell"
                    , classList [ ( "right", Columns.isRight column ), ( "drop-target", target == Just column ) ]
                    , attribute "role" "columnheader"
                    , preventDefaultOn "mousedown"
                        (D.map3 (\x shift button -> ( HeaderMouseDown column x shift, button == 0 ))
                            (D.field "clientX" D.float)
                            (D.field "shiftKey" D.bool)
                            (D.field "button" D.int)
                            |> D.andThen
                                (\( msg, isLeft ) ->
                                    if isLeft then
                                        D.succeed ( msg, True )

                                    else
                                        D.fail "not the left button"
                                )
                        )
                    , onMouseEnter (HeaderEnter column)
                    ]
                    [ span [ class "htitle" ] [ text (Columns.title column ++ sortMark column) ]
                    , button
                        [ class "filter-btn"
                        , classList [ ( "active", filtered ) ]
                        , stopPropagationOn "mousedown" (D.succeed ( NoOp, True ))
                        , stopPropagationOn "click"
                            (D.map2 (\x y -> ( OpenColumnFilter column x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))
                        , title Text.columnFilter
                        , tabindex -1
                        ]
                        [ if filtered then
                            span [ class "icon filter" ] []

                          else
                            text "▾"
                        ]
                    , span
                        [ class "resize"
                        , stopPropagationOn "mousedown" (D.map (\x -> ( HeaderResizeStart column x, True )) (D.field "clientX" D.float))
                        ]
                        []
                    ]
            )
            tab.view.columns
        )


viewRow : Model -> Tab -> Filter.Query -> String -> Int -> Item -> ( String, Html Msg )
viewRow model tab query template index item =
    ( item.id
    , div
        ([ class "row"
         , classList
            [ ( "selected", Set.member item.id tab.selected )
            , ( "cursor", index == tab.cursor )
            , ( "hidden-item", item.hidden )
            , ( "cut", isCut model item )
            ]
         , style "top" (px (toFloat index * rowHeight))
         , style "grid-template-columns" template
         , attribute "role" "row"
         , on "click"
            (D.map2 (\c s -> RowClicked index { ctrl = c, shift = s })
                (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
                (D.field "shiftKey" D.bool)
            )
         , on "dblclick" (D.succeed (RowActivated index))
         , on "auxclick" (middleClick (RowMiddleClicked index))
         , on "mousedown"
            (D.field "button" D.int
                |> D.andThen
                    (\b ->
                        if b == 0 then
                            D.map2 (ItemMouseDown index) (D.field "clientX" D.float) (D.field "clientY" D.float)

                        else
                            D.fail "not the left button"
                    )
            )
         , Html.Events.custom "contextmenu"
            (D.map2 (\x y -> { message = RowContext index x y, stopPropagation = True, preventDefault = True })
                (D.field "clientX" D.float)
                (D.field "clientY" D.float)
            )
         ]
            ++ (if item.isDir then
                    dropTarget model (DropFolder item.path) item.path

                else
                    []
               )
        )
        (List.map (\( column, _ ) -> viewCell model tab query item column) tab.view.columns)
    )


viewCell : Model -> Tab -> Filter.Query -> Item -> Column -> Html Msg
viewCell model tab query item column =
    let
        plain classes content =
            div [ class ("cell " ++ classes) ] [ text content ]

        date millis =
            plain "muted" (Maybe.map (Format.date model.settings.dateFormat model.zone) millis |> Maybe.withDefault "")
    in
    case column of
        Columns.Name ->
            case model.rename of
                Just r ->
                    if r.tabId == tab.id && r.key == item.id then
                        viewRenameCell model item r

                    else
                        viewNameCell model query item

                Nothing ->
                    viewNameCell model query item

        Columns.Modified ->
            date item.modified

        Columns.Created ->
            date item.created

        Columns.Accessed ->
            date item.accessed

        Columns.Size ->
            plain "right muted"
                (if item.isDir then
                    ""

                 else
                    Format.size item.size
                )

        Columns.Type ->
            plain "muted" (Item.typeLabel item)

        Columns.Ext ->
            plain "muted" item.ext

        Columns.Attributes ->
            plain "muted mono" item.attributes

        Columns.LinkTarget ->
            plain "muted" (Maybe.withDefault "" item.target)

        Columns.Sync ->
            div [ class "cell center muted", title (Item.syncLabel item.sync) ] [ text (syncGlyph item.sync) ]

        Columns.Folder ->
            plain "muted" item.folder


viewNameCell : Model -> Filter.Query -> Item -> Html Msg
viewNameCell model query item =
    div [ class "cell name", title (Maybe.withDefault item.name item.target) ]
        [ viewIcon model item
        , span []
            (List.map
                (\( part, marked ) ->
                    if marked then
                        Html.mark [] [ text part ]

                    else
                        text part
                )
                (Filter.highlight query (Item.displayName model.settings.showExtensions item))
            )
        ]


{-| The in-place rename box (FR-REN-01, FR-REN-02).
-}
viewRenameCell : Model -> Item -> RenameState -> Html Msg
viewRenameCell model item r =
    div [ class "cell name renaming" ]
        [ viewIcon model item
        , input
            [ id renameInputId
            , stopPropagationOn "mousedown" (D.succeed ( NoOp, True ))
            , class "rename-input"
            , classList [ ( "invalid", r.error /= Nothing ) ]
            , value r.text
            , onInput RenameInput
            , onBlur RenameBlur
            , Html.Events.custom "keydown" (inputKeys [ "Enter", "Escape", "F2" ] RenameKey)
            , stopPropagationOn "click" (D.succeed ( NoOp, True ))
            , stopPropagationOn "dblclick" (D.succeed ( NoOp, True ))
            , spellcheck False
            ]
            []
        , case r.error of
            Just error ->
                span [ class "rename-error" ] [ text error ]

            Nothing ->
                text ""
        ]


isCut : Model -> Item -> Bool
isCut model item =
    case model.clipboard of
        Just c ->
            c.cut && List.member item.path c.paths

        Nothing ->
            False


iconClass : Model -> Item -> String
iconClass model item =
    if item.isDir then
        folderIcon model item.path

    else
        Item.iconName item


{-| An item's icon: the system icon when that setting is on and the icon has
arrived (FR-ICON-02), otherwise the built-in one (FR-ICON-01). A folder with a
colour keeps the built-in icon, so the colour shows (spec 6.4.5).
-}
viewIcon : Model -> Item -> Html msg
viewIcon model item =
    if item.isDir then
        viewFolderIcon model item.path

    else
        iconOrBuiltin model (iconKey model item) (iconClass model item)


viewFolderIcon : Model -> String -> Html msg
viewFolderIcon model path =
    if Dict.member path model.folderColours then
        span [ class ("icon " ++ folderIcon model path) ] []

    else
        iconOrBuiltin model "folder" "folder"


viewBookmarkIcon : Model -> Bookmark -> Html msg
viewBookmarkIcon model b =
    case bookmarkIconKey b of
        Just key ->
            iconOrBuiltin model key (bookmarkIcon b)

        Nothing ->
            span [ class ("icon " ++ bookmarkIcon b) ] []


iconOrBuiltin : Model -> String -> String -> Html msg
iconOrBuiltin model key builtin =
    case ( model.settings.icons, Dict.get key model.systemIcons ) of
        ( "system", Just url ) ->
            Html.img [ class "sysicon", Html.Attributes.src url, Html.Attributes.alt "", attribute "draggable" "false" ] []

        _ ->
            span [ class ("icon " ++ builtin) ] []


{-| The folder icon, in the folder's colour when it has one (spec 6.4.5).
-}
folderIcon : Model -> String -> String
folderIcon model path =
    case Dict.get path model.folderColours of
        Just colour ->
            "folder fc-" ++ colour

        Nothing ->
            "folder"


syncGlyph : Item.Sync -> String
syncGlyph sync =
    case sync of
        Item.SyncNone ->
            ""

        Item.SyncLocal ->
            "✓"

        Item.SyncPinned ->
            "✔"

        Item.SyncOnlineOnly ->
            "☁"

        Item.SyncSyncing ->
            "⟳"

        Item.SyncError ->
            "⚠"



-- STATUS BAR


viewStatusBar : Model -> Tab -> Html Msg
viewStatusBar model tab =
    let
        total =
            Array.length tab.visible

        selectedSize =
            Set.toList tab.selected
                |> List.filterMap (\id -> Dict.get id tab.items)
                |> List.filter (not << .isDir)
                |> List.map .size
                |> List.sum

        warnings =
            model.warnings ++ model.bookmarkWarnings ++ model.colourWarnings ++ model.keyWarnings ++ model.toolbarWarnings
    in
    div [ class "statusbar" ]
        [ span []
            [ text
                (if isFiltering tab then
                    Text.showing total tab.unfilteredCount

                 else
                    Text.itemCount total tab.folderCount (total - tab.folderCount)
                )
            ]
        , viewIf (tab.hiddenCount > 0) (span [] [ text (Text.hiddenCount tab.hiddenCount) ])
        , viewIf (not (Set.isEmpty tab.selected))
            (span []
                [ text
                    (Text.selected (Set.size tab.selected)
                        (if selectedSize > 0 then
                            Format.size selectedSize

                         else
                            ""
                        )
                    )
                ]
            )
        , case tab.search of
            Just search ->
                span [ class "search-status" ] [ text (searchStatus search) ]

            Nothing ->
                viewIf (tab.status == Loading) (span [] [ text Text.loading ])
        , span [ class "grow" ] []
        , case model.chord of
            Just key ->
                span [ class "message" ] [ text (Text.chordWaiting key) ]

            Nothing ->
                text ""
        , viewJobSummary model
        , case model.message of
            Just message ->
                span [ class "message" ] [ text message ]

            Nothing ->
                text ""
        , case warnings of
            first :: _ ->
                span [ class "warning", title (String.join "\n" warnings) ] [ text first ]

            [] ->
                text ""
        , case model.freeSpace of
            Just bytes ->
                span [ class "free" ] [ text (Text.free (Format.size bytes)) ]

            Nothing ->
                text ""
        ]



-- QUICK FIND


{-| Progress and outcome of a Quick Find search (FR-FIND-03).
-}
searchStatus : Search -> String
searchStatus search =
    case ( search.relink, search.running ) of
        ( Just bookmark, False ) ->
            Text.locateHint bookmark.name

        _ ->
            searchProgress search


searchProgress : Search -> String
searchProgress search =
    if search.running then
        Text.searchRunning search.scanned search.found

    else if search.cancelled then
        Text.searchStopped search.found

    else if search.truncated then
        Text.searchTruncated search.found

    else if search.found == 0 then
        Text.searchNothing

    else
        Text.searchDone search.scanned search.found search.millis



-- COMMAND PALETTE


viewPalette : Model -> Html Msg
viewPalette model =
    case model.palette of
        Nothing ->
            text ""

        Just p ->
            div [ class "palette-overlay", onClick (PaletteKey "Escape" False) ]
                [ div [ class "palette", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
                    [ input
                        [ id paletteInputId
                        , value p.text
                        , onInput PaletteInput
                        , placeholder Text.palettePlaceholder
                        , spellcheck False
                        , attribute "autocomplete" "off"
                        , Html.Events.custom "keydown"
                            (D.map2 Tuple.pair (D.field "key" D.string) (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
                                |> D.andThen
                                    (\( key, ctrl ) ->
                                        if List.member key [ "ArrowDown", "ArrowUp", "PageDown", "PageUp", "Enter", "Escape", "Tab" ] then
                                            D.succeed { message = PaletteKey key ctrl, stopPropagation = True, preventDefault = True }

                                        else
                                            D.fail "typing"
                                    )
                            )
                        ]
                        []
                    , if String.startsWith "?" p.text then
                        div [ class "palette-hint" ] [ text Text.paletteFindHint ]

                      else
                        text ""
                    , if List.isEmpty p.results && String.length p.text > 1 then
                        div [ class "palette-empty" ] [ text Text.paletteNoResults ]

                      else
                        Html.Keyed.node "div"
                            [ class "palette-results", attribute "role" "listbox" ]
                            (List.indexedMap (viewPaletteItem p.active) p.results)
                    ]
                ]


viewPaletteItem : Int -> Int -> PaletteItem -> ( String, Html Msg )
viewPaletteItem active index result =
    ( String.fromInt index ++ result.label ++ result.detail
    , div
        [ class "palette-item"
        , classList [ ( "active", index == active ) ]
        , attribute "role" "option"
        , on "click" (D.map (\ctrl -> PaletteRun index ctrl) (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool)))
        , onMouseEnter (PaletteHover index)
        ]
        [ span [ class ("icon " ++ result.icon) ] []
        , span [ class "palette-label" ] (highlightHits result.label result.hits)
        , span [ class "palette-detail" ] [ text result.detail ]
        , span [ class "key" ] [ text result.key ]
        ]
    )


{-| The label with its matched letters marked (FR-CMD-03).
-}
highlightHits : String -> List Int -> List (Html msg)
highlightHits label hits =
    if List.isEmpty hits then
        [ text label ]

    else
        String.toList label
            |> List.indexedMap
                (\i c ->
                    if List.member i hits then
                        Html.mark [] [ text (String.fromChar c) ]

                    else
                        text (String.fromChar c)
                )



-- KEYBOARD SHORTCUTS (FR-KEY-04)


viewShortcuts : Model -> ShortcutsState -> Html Msg
viewShortcuts model state =
    let
        search =
            String.toLower (String.trim state.search)

        rows =
            Commands.all
                |> List.filter (\d -> d.id /= "bookmark.manage")
                |> List.filter
                    (\d ->
                        search
                            == ""
                            || String.contains search (String.toLower (Commands.name d.id))
                            || String.contains search d.id
                            || List.any (\k -> String.contains search (String.toLower k)) (Keys.keysFor d.id model.keymap)
                    )
                |> List.sortBy (\d -> String.toLower (Commands.name d.id))

        changedByUser id =
            List.any (\b -> b.command == id) model.userBindings
    in
    div [ class "overlay" ]
        [ div [ class "dialog shortcuts", id shortcutsDialogId, tabindex -1, attribute "role" "dialog" ]
            [ div [ class "dialog-title" ] [ text Text.shortcutsTitle ]
            , input
                [ id shortcutsSearchId
                , class "shortcuts-search"
                , value state.search
                , onInput ShortcutsSearch
                , placeholder Text.shortcutsSearch
                , spellcheck False
                ]
                []
            , case ( state.recording, state.proposal ) of
                ( Just r, _ ) ->
                    div [ class "shortcuts-banner recording" ]
                        [ text (Commands.name r.command ++ ": ")
                        , text
                            (if List.isEmpty r.strokes then
                                Text.pressKeys

                             else
                                String.join " " r.strokes ++ " …"
                            )
                        ]

                ( Nothing, Just p ) ->
                    let
                        owners =
                            Keys.lookup "global" p.key model.keymap
                                |> Maybe.map .command
                                |> Maybe.andThen
                                    (\c ->
                                        if c == p.command then
                                            Nothing

                                        else
                                            Just c
                                    )
                    in
                    div
                        [ class "shortcuts-banner"
                        , classList [ ( "conflict", owners /= Nothing ) ]
                        ]
                        [ span [ class "grow" ]
                            [ text (Commands.name p.command ++ ": ")
                            , case owners of
                                Just other ->
                                    text (Text.keyConflict p.key (Commands.name other))

                                Nothing ->
                                    text (Text.keyFree p.key)
                            ]
                        , button [ onClick ShortcutsDiscard ] [ text Text.cancel ]
                        , button [ class "primary", onClick ShortcutsSave ] [ text Text.saveKey ]
                        ]

                ( Nothing, Nothing ) ->
                    div [ class "shortcuts-banner muted" ] [ text Text.shortcutsHint ]
            , div [ class "shortcuts-list" ]
                (List.map
                    (\d ->
                        div [ class "shortcut-row" ]
                            [ span [ class "shortcut-name" ]
                                [ text (Commands.name d.id)
                                , viewIf (changedByUser d.id) (span [ class "shortcut-changed" ] [ text Text.customised ])
                                ]
                            , span [ class "shortcut-id" ] [ text d.id ]
                            , span [ class "shortcut-keys" ]
                                (case Keys.keysFor d.id model.keymap of
                                    [] ->
                                        [ span [ class "muted" ] [ text Text.noBinding ] ]

                                    keys ->
                                        List.map
                                            (\k ->
                                                span [ class "keycap" ]
                                                    [ text k
                                                    , button [ class "keycap-remove", title Text.removeKey, onClick (ShortcutsRemove d.id k) ] [ text "×" ]
                                                    ]
                                            )
                                            keys
                                )
                            , button [ class "small", onClick (ShortcutsRecord d.id) ] [ text Text.addKey ]
                            , button [ class "small", disabled (not (changedByUser d.id)), onClick (ShortcutsReset d.id) ] [ text Text.resetKeys ]
                            ]
                    )
                    rows
                )
            , div [ class "dialog-actions" ]
                [ button [ onClick (KeyCommand CmdOpenKeybindingsFile) ] [ text Text.openFile ]
                , button [ class "primary", onClick DialogCancel ] [ text Text.close ]
                ]
            ]
        ]



-- CUSTOMISE TOOLBAR (FR-TB-02)


viewToolbarDialog : Model -> ToolbarForm -> Html Msg
viewToolbarDialog model form =
    let
        itemLabel item =
            case item of
                "|" ->
                    "— " ++ Text.toolbarSeparator ++ " —"

                "->" ->
                    "↔ " ++ Text.toolbarSpace

                id ->
                    Commands.name id

        search =
            String.toLower (String.trim form.search)

        available =
            List.filter (\i -> search == "" || String.contains search (String.toLower (itemLabel i))) [ "|", "->" ]
                ++ (Commands.all
                        |> List.map .id
                        |> List.filter (\id -> id /= "bookmark.manage" && not (List.member id form.items))
                        |> List.filter (\id -> search == "" || String.contains search (String.toLower (Commands.name id)) || String.contains search id)
                        |> List.sortBy (Commands.name >> String.toLower)
                   )

        styleChoice value_ label_ =
            label [ class "radio" ]
                [ input [ Html.Attributes.type_ "radio", Html.Attributes.checked (form.style == value_), onClick (ToolbarStyle value_) ] []
                , text label_
                ]
    in
    div [ class "overlay" ]
        [ div [ class "dialog toolbar-dialog", attribute "role" "dialog" ]
            [ div [ class "dialog-title" ] [ text Text.customiseToolbar ]
            , div [ class "toolbar-preview toolbar" ] (List.map (viewToolbarPreview model form.style) form.items)
            , div [ class "toolbar-columns" ]
                [ div [ class "toolbar-column" ]
                    [ div [ class "column-title" ] [ text Text.toolbarButtons ]
                    , div [ class "toolbar-list" ]
                        (List.indexedMap
                            (\i item ->
                                div
                                    [ class "toolbar-entry"
                                    , classList [ ( "active", i == form.active ) ]
                                    , onClick (ToolbarPick i)
                                    ]
                                    [ text (itemLabel item) ]
                            )
                            form.items
                        )
                    , div [ class "toolbar-buttons" ]
                        [ button [ onClick (ToolbarMove -1), disabled (form.active <= 0) ] [ text ("↑ " ++ Text.moveUp) ]
                        , button [ onClick (ToolbarMove 1), disabled (form.active >= List.length form.items - 1) ] [ text ("↓ " ++ Text.moveDown) ]
                        , button [ onClick ToolbarRemove, disabled (List.isEmpty form.items) ] [ text Text.delete ]
                        ]
                    ]
                , div [ class "toolbar-column" ]
                    [ div [ class "column-title" ] [ text Text.toolbarAvailable ]
                    , input [ class "toolbar-search", value form.search, onInput ToolbarSearch, placeholder Text.shortcutsSearch, spellcheck False ] []
                    , div [ class "toolbar-list" ]
                        (List.map (\id -> div [ class "toolbar-entry", onClick (ToolbarAdd id), title id ] [ text ("+ " ++ itemLabel id) ]) available)
                    ]
                ]
            , div [ class "toolbar-style" ]
                [ span [] [ text Text.toolbarStyle ]
                , styleChoice "icon" Text.toolbarStyleIcon
                , styleChoice "iconText" Text.toolbarStyleIconText
                , styleChoice "text" Text.toolbarStyleText
                ]
            , div [ class "dialog-actions" ]
                [ button [ onClick ToolbarDefaults ] [ text Text.toolbarDefaults ]
                , span [ class "grow" ] []
                , button [ onClick DialogCancel ] [ text Text.cancel ]
                , button [ class "primary", onClick ToolbarSave ] [ text Text.saveKey ]
                ]
            ]
        ]


viewToolbarPreview : Model -> String -> String -> Html Msg
viewToolbarPreview model style item =
    case item of
        "|" ->
            span [ class "sep" ] []

        "->" ->
            span [ class "grow" ] []

        id ->
            button [ tabindex -1, title (Commands.name id) ] (toolbarFace style (Commands.icon id) (Commands.name id))



-- POPUPS AND DIALOG


viewPopup : Model -> Html Msg
viewPopup model =
    case model.popup of
        Nothing ->
            text ""

        Just (MenuPopup p) ->
            div [ class "popup", style "left" (keepOnScreen p.x 260), style "top" (px p.y) ]
                [ Menu.viewDropdown -1 Nothing False p.entries ]

        Just (ColumnFilterPopup s) ->
            viewColumnFilter s


{-| The values shown in a column filter, after its search box.
-}
filterPopupValues : ColumnFilterState -> List ( String, Int )
filterPopupValues s =
    let
        search =
            String.toLower s.search
    in
    if search == "" then
        s.values

    else
        List.filter (\( v, _ ) -> String.contains search (String.toLower v)) s.values


viewColumnFilter : ColumnFilterState -> Html Msg
viewColumnFilter s =
    let
        shown =
            filterPopupValues s

        shownValues =
            List.map Tuple.first shown

        allChecked =
            List.all (\v -> Set.member v s.checked) shownValues

        checkRow depth labelText values count =
            div
                [ class "check-row"
                , classList [ ( "group", depth == 0 && Columns.isDate s.column ) ]
                , onClick (ColumnFilterToggle values)
                , style "padding-left" (px (toFloat depth * 16 + 8))
                ]
                [ span [ class "box" ]
                    [ text
                        (if List.all (\v -> Set.member v s.checked) values then
                            "✓"

                         else if List.any (\v -> Set.member v s.checked) values then
                            "–"

                         else
                            ""
                        )
                    ]
                , span [ class "label" ] [ text labelText ]
                , span [ class "count" ] [ text (String.fromInt count) ]
                ]

        rows =
            if Columns.isDate s.column then
                -- Grouped by month, newest first (FR-CF-01).
                List.foldl
                    (\( v, _ ) months ->
                        let
                            month =
                                String.left 7 v
                        in
                        if List.member month months then
                            months

                        else
                            months ++ [ month ]
                    )
                    []
                    shown
                    |> List.concatMap
                        (\month ->
                            let
                                days =
                                    List.filter (\( v, _ ) -> String.left 7 v == month) shown
                            in
                            checkRow 0 month (List.map Tuple.first days) (List.sum (List.map Tuple.second days))
                                :: List.map (\( v, n ) -> checkRow 1 v [ v ] n) days
                        )

            else
                List.map (\( v, n ) -> checkRow 0 v [ v ] n) (List.take 1000 shown)

        quick key labelText =
            button [ onClick (ColumnFilterQuick key), tabindex -1 ] [ text labelText ]
    in
    div
        [ class "popup menu colfilter"
        , style "left" (keepOnScreen (s.x - 140) 296)
        , style "top" (px (s.y + 12))
        , stopPropagationOn "click" (D.succeed ( NoOp, True ))
        ]
        [ input
            [ id "colfilter-search"
            , class "colfilter-search"
            , placeholder (Text.searchColumn (Columns.title s.column))
            , value s.search
            , onInput ColumnFilterSearch
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            ColumnFilterApply

                        else
                            ClosePopups
                    )
                )
            , spellcheck False
            ]
            []
        , viewIf (Columns.isDate s.column)
            (div [ class "quick" ]
                [ quick "today" Text.today
                , quick "yesterday" Text.yesterday
                , quick "week" Text.thisWeek
                , quick "last7" Text.last7Days
                , quick "month" Text.thisMonth
                , quick "year" Text.thisYear
                ]
            )
        , viewIf (s.column == Columns.Size)
            (div [ class "size-range" ]
                [ span [] [ text Text.sizeBetween ]
                , rangeInput s.rangeFrom True
                , span [] [ text Text.sizeAnd ]
                , rangeInput s.rangeTo False
                ]
            )
        , div [ class "check-list" ]
            (div [ class "check-row all", onClick ColumnFilterSelectAll ]
                [ span [ class "box" ]
                    [ text
                        (if allChecked then
                            "✓"

                         else
                            ""
                        )
                    ]
                , span [ class "label" ] [ text Text.selectAll ]
                ]
                :: rows
            )
        , div [ class "colfilter-actions" ]
            [ button [ onClick ColumnFilterClear ] [ text Text.clearFilter ]
            , span [ class "grow" ] []
            , button [ onClick ClosePopups ] [ text Text.cancel ]
            , button [ class "primary", onClick ColumnFilterApply ] [ text Text.ok ]
            ]
        ]


{-| One end of the Size column's "between" range (FR-CF-01).
-}
rangeInput : String -> Bool -> Html Msg
rangeInput current isFrom =
    input
        [ value current
        , onInput (ColumnFilterRange isFrom)
        , placeholder
            (if isFrom then
                Text.sizeFromHint

             else
                Text.sizeToHint
            )
        , classList [ ( "invalid", String.trim current /= "" && Format.parseSize current == Nothing ) ]
        , spellcheck False
        , Html.Events.custom "keydown"
            (inputKeys [ "Enter", "Escape" ]
                (\key ->
                    if key == "Enter" then
                        ColumnFilterApply

                    else
                        ClosePopups
                )
            )
        ]
        []


viewDialog : Model -> Html Msg
viewDialog model =
    case model.dialog of
        Nothing ->
            text ""

        Just (NewItemDialog form) ->
            viewNewItemDialog form

        Just (ShortcutsDialog state) ->
            viewShortcuts model state

        Just (ToolbarDialog form) ->
            viewToolbarDialog model form

        Just (ConfirmDialog confirm) ->
            div [ class "overlay" ]
                [ div [ class "dialog", attribute "role" "alertdialog" ]
                    [ div [ class "dialog-title" ] [ text confirm.title ]
                    , viewIf (not (List.isEmpty confirm.lines)) (div [ class "dialog-list" ] (List.map (\line -> div [] [ text line ]) confirm.lines))
                    , div [ class "dialog-actions" ]
                        [ button [ id "confirm-no", onClick DialogCancel ] [ text Text.cancel ]
                        , button
                            [ id "confirm-yes"
                            , class
                                (if confirm.danger then
                                    "danger"

                                 else
                                    "primary"
                                )
                            , onClick ConfirmYes
                            ]
                            [ text confirm.confirmLabel ]
                        ]
                    ]
                ]

        Just (BookmarkDialog form) ->
            div [ class "overlay" ]
                [ div
                    [ class "dialog"
                    , attribute "role" "dialog"
                    , Html.Events.custom "keydown"
                        (inputKeys [ "Enter", "Escape" ]
                            (\key ->
                                if key == "Enter" then
                                    DialogSubmit

                                else
                                    DialogCancel
                            )
                        )
                    ]
                    [ div [ class "dialog-title" ]
                        [ text
                            (if form.index == Nothing then
                                Text.addBookmark

                             else
                                Text.editBookmark
                            )
                        ]
                    , field Text.name dialogFirstInputId form.name DialogName
                    , field Text.target "dialog-target" form.target DialogTarget
                    , viewGroupField model form
                    , div [ class "hint" ] [ text Text.groupHint ]
                    , case form.error of
                        Just error ->
                            div [ class "dialog-error" ] [ text error ]

                        Nothing ->
                            text ""
                    , div [ class "dialog-actions" ]
                        [ button [ onClick DialogCancel ] [ text Text.cancel ]
                        , button [ class "primary", onClick DialogSubmit ] [ text Text.save ]
                        ]
                    ]
                ]


{-| The bookmark group: a text box with a drop-down of the existing groups.
Typing filters them; a name that is not a group yet is offered as a new one
(spec 6.4.2).
-}
viewGroupField : Model -> BookmarkForm -> Html Msg
viewGroupField model form =
    let
        choices =
            groupChoices model form.group

        isNew choice =
            choice
                /= "bar"
                && not
                    (List.any
                        (\b -> List.any (\n -> String.join "/" (List.take n b.group) == choice) (List.range 1 (List.length b.group)))
                        model.bookmarks
                    )

        friendly choice =
            case String.split "/" choice of
                "bar" :: rest ->
                    String.join " › " (Text.bookmarkBar :: rest)

                parts ->
                    String.join " › " parts

        viewChoice index choice =
            div
                [ class "combo-option"
                , classList [ ( "active", index == form.groupActive ) ]
                , attribute "role" "option"
                , attribute "aria-selected"
                    (if index == form.groupActive then
                        "true"

                     else
                        "false"
                    )

                -- mousedown, so the pick happens before the text box loses focus.
                , preventDefaultOn "mousedown" (D.succeed ( DialogGroupPick choice, True ))
                ]
                (if isNew choice then
                    [ span [ class "combo-new" ] [ text (Text.newGroup choice) ] ]

                 else
                    [ span [] [ text choice ], span [ class "muted" ] [ text (friendly choice) ] ]
                )
    in
    label [ class "field" ]
        [ span [] [ text Text.group ]
        , div [ class "combo" ]
            [ input
                [ id "dialog-group"
                , value form.group
                , onInput DialogGroup
                , onFocus (DialogGroupOpen True)
                , onBlur (DialogGroupOpen False)
                , spellcheck False
                , attribute "autocomplete" "off"
                , attribute "role" "combobox"
                , attribute "aria-expanded"
                    (if form.groupOpen then
                        "true"

                     else
                        "false"
                    )
                , attribute "data-select-on-focus" ""
                , Html.Events.custom "keydown" (inputKeys [ "ArrowDown", "ArrowUp", "Enter", "Escape" ] DialogGroupKey)
                ]
                []
            , viewIf (form.groupOpen && not (List.isEmpty choices))
                (div [ class "combo-list", attribute "role" "listbox" ] (List.indexedMap viewChoice choices))
            ]
        ]


field : String -> String -> String -> (String -> Msg) -> Html Msg
field labelText domId current toMsg =
    label [ class "field" ]
        [ span [] [ text labelText ]
        , input [ id domId, value current, onInput toMsg, spellcheck False, attribute "data-select-on-focus" "" ] []
        ]



-- EVENTS


contextMenu : List MenuEntry -> Html.Attribute Msg
contextMenu entries =
    preventDefaultOn "contextmenu"
        (D.map2 (\x y -> ( ItemContextMenu entries x y, True )) (D.field "clientX" D.float) (D.field "clientY" D.float))


middleClick : Msg -> D.Decoder Msg
middleClick msg =
    D.field "button" D.int
        |> D.andThen
            (\b ->
                if b == 1 then
                    D.succeed msg

                else
                    D.fail "not the middle button"
            )


mouseNavDecoder : D.Decoder Msg
mouseNavDecoder =
    D.field "button" D.int
        |> D.andThen
            (\b ->
                case b of
                    3 ->
                        D.succeed (KeyCommand CmdBack)

                    4 ->
                        D.succeed (KeyCommand CmdForward)

                    _ ->
                        D.fail "other button"
            )


{-| Key presses anywhere in the window (spec 6.10). Bound keys run their
command; a key that starts a chord waits for the second key (FR-KEY-02).
Text boxes keep their typing keys, and focused buttons keep plain keys such
as Enter and Space.
-}
keyDecoder : Model -> D.Decoder ( Msg, Bool )
keyDecoder model =
    D.map7 Keys.KeyInfo
        (D.field "key" D.string)
        (D.oneOf [ D.field "code" D.string, D.succeed "" ])
        (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        (D.at [ "target", "tagName" ] D.string)
        (D.oneOf [ D.at [ "target", "id" ] D.string, D.succeed "" ])
        |> D.andThen (decideKey model)


decideKey : Model -> Keys.KeyInfo -> D.Decoder ( Msg, Bool )
decideKey model info =
    let
        stroke =
            Keys.fromEvent info

        inInput =
            info.target == "INPUT" || info.target == "TEXTAREA"

        plain =
            not info.ctrl && not info.alt && not (String.startsWith "F" info.key && String.length info.key > 1)

        context =
            keyContext model info

        full =
            case ( model.chord, stroke ) of
                ( Just first, Just s ) ->
                    Just (first ++ " " ++ s)

                ( Nothing, s ) ->
                    s

                _ ->
                    Nothing

        bound =
            full
                |> Maybe.andThen (\k -> Keys.lookup context k model.keymap)
                |> Maybe.andThen (\b -> Commands.fromBinding b.command b.args |> Maybe.map (\c -> ( b, c )))

        -- In a text box only keys made for it, or Ctrl/Alt/F-keys that don't edit text, run commands.
        allowedHere b s =
            if inInput then
                b.when == context || (not plain && not (List.member s textEditingKeys))

            else
                not (info.target == "BUTTON" && plain)
    in
    case ( recording model, stroke ) of
        ( True, Just s ) ->
            D.succeed ( KeyRecorded s, True )

        ( True, Nothing ) ->
            D.fail "a modifier key on its own"

        ( False, _ ) ->
            if ownsKeys model then
                if info.key == "Escape" then
                    D.succeed ( DialogCancel, True )

                else
                    D.fail "the dialog handles this key"

            else if info.key == "Alt" then
                D.succeed ( AltDown, False )

            else if model.menuBar /= Nothing then
                case builtinKey info of
                    Just command ->
                        D.succeed ( KeyCommand command, True )

                    Nothing ->
                        D.succeed ( KeyOther, False )

            else
                case ( bound, stroke ) of
                    ( Just ( b, command ), Just s ) ->
                        if allowedHere b s then
                            D.succeed ( KeyCommand command, True )

                        else
                            D.fail "the focused control handles this key"

                    _ ->
                        case ( model.chord, stroke ) of
                            ( Just _, Just "Esc" ) ->
                                D.succeed ( KeyOther, True )

                            ( Just _, Just _ ) ->
                                D.succeed ( KeyChordMiss (Maybe.withDefault "" full), True )

                            ( Nothing, Just s ) ->
                                if Keys.isChordStart s model.keymap && not (inInput && plain) then
                                    D.succeed ( KeyChord s, True )

                                else if inInput || (info.target == "BUTTON" && plain) then
                                    D.fail "the focused control handles this key"

                                else
                                    case builtinKey info of
                                        Just command ->
                                            D.succeed ( KeyCommand command, True )

                                        Nothing ->
                                            D.succeed ( KeyOther, False )

                            _ ->
                                D.fail "a modifier key on its own"


{-| Where the key was pressed, for bindings with a `when` (FR-KEY-03).
-}
keyContext : Model -> Keys.KeyInfo -> String
keyContext model info =
    if info.targetId == paletteInputId then
        "palette"

    else if info.targetId == filterInputId then
        "filter"

    else if info.targetId == addressInputId then
        "addressBar"

    else if model.region == RegionSidebar && sidebarModeFromString model.settings.sidebarMode == TreeMode then
        "tree"

    else
        "list"


{-| Keys that edit text, kept by text boxes even when a command uses them.
-}
textEditingKeys : List String
textEditingKeys =
    [ "Ctrl+A", "Ctrl+C", "Ctrl+V", "Ctrl+X", "Ctrl+Z", "Ctrl+Y", "Ctrl+Shift+Z", "Ctrl+Left", "Ctrl+Right", "Ctrl+Shift+Left", "Ctrl+Shift+Right", "Ctrl+Backspace", "Ctrl+Del", "Ctrl+Home", "Ctrl+End", "Ctrl+Shift+Home", "Ctrl+Shift+End" ]


recording : Model -> Bool
recording model =
    case model.dialog of
        Just (ShortcutsDialog s) ->
            s.recording /= Nothing

        _ ->
            False


{-| Dialogs that keep keys from the window, so typing in them never runs a command.
-}
ownsKeys : Model -> Bool
ownsKeys model =
    case model.dialog of
        Just (ShortcutsDialog _) ->
            True

        Just (ToolbarDialog _) ->
            True

        _ ->
            False


{-| Keys that move the cursor and selection, and the menu mnemonics. They
are not bindable; every other key comes from the key map.
-}
builtinKey : Keys.KeyInfo -> Maybe Command
builtinKey { key, ctrl, shift, alt } =
    let
        k =
            if String.length key == 1 then
                String.toLower key

            else
                key
    in
    case ( k, ctrl, alt ) of
        ( "Enter", False, False ) ->
            Just CmdOpen

        ( "ArrowDown", _, False ) ->
            Just (CmdMove 1 shift ctrl)

        ( "ArrowUp", _, False ) ->
            Just (CmdMove -1 shift ctrl)

        ( "ArrowLeft", False, False ) ->
            Just CmdLeft

        ( "ArrowRight", False, False ) ->
            Just CmdRight

        ( "PageDown", _, False ) ->
            Just (CmdPage 1 shift ctrl)

        ( "PageUp", _, False ) ->
            Just (CmdPage -1 shift ctrl)

        ( "Home", _, False ) ->
            Just (CmdEdge False shift)

        ( "End", _, False ) ->
            Just (CmdEdge True shift)

        ( " ", True, False ) ->
            Just CmdToggleSelect

        ( "Escape", _, _ ) ->
            Just CmdEscape

        _ ->
            if alt && not ctrl then
                List.indexedMap Tuple.pair [ "f", "e", "v", "g", "b", "t", "w", "h" ]
                    |> List.filter (\( _, letter ) -> letter == k)
                    |> List.head
                    |> Maybe.map (\( i, _ ) -> CmdMenuMnemonic i)

            else if String.length key == 1 && not ctrl && not alt then
                Just (CmdTypeahead key)

            else
                Nothing


{-| A left position that keeps a popup of the given width inside the window.
-}
keepOnScreen : Float -> Float -> String
keepOnScreen x width =
    "max(4px, min(" ++ px x ++ ", calc(100vw - " ++ px width ++ ")))"


px : Float -> String
px n =
    String.fromFloat n ++ "px"



-- FILE OPERATIONS


viewNewItemDialog : NewItemForm -> Html Msg
viewNewItemDialog form =
    let
        ( titleText, fields ) =
            case form.kind of
                NewFile ->
                    ( Text.newFileTitle, [ field Text.fileName dialogFirstInputId form.name NewItemName ] )

                NewShortcut ->
                    ( Text.newShortcutTitle
                    , [ field Text.shortcutTarget dialogFirstInputId form.target NewItemTarget
                      , field Text.shortcutNameHint "dialog-target" form.name NewItemName
                      ]
                    )

                NewWebLink ->
                    ( Text.newWebLinkTitle
                    , [ field Text.webAddress dialogFirstInputId form.target NewItemTarget
                      , field Text.webNameHint "dialog-target" form.name NewItemName
                      ]
                    )

                NewFromTemplate _ ->
                    ( Text.newFromTemplateTitle, [ field Text.templateName dialogFirstInputId form.name NewItemName ] )
    in
    div [ class "overlay" ]
        [ div
            [ class "dialog"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            NewItemSubmit

                        else
                            DialogCancel
                    )
                )
            ]
            ([ div [ class "dialog-title" ] [ text titleText ] ]
                ++ fields
                ++ [ case form.error of
                        Just error ->
                            div [ class "dialog-error" ] [ text error ]

                        Nothing ->
                            text ""
                   , div [ class "dialog-actions" ]
                        [ button [ onClick DialogCancel ] [ text Text.cancel ]
                        , button [ class "primary", onClick NewItemSubmit ] [ text Text.create ]
                        ]
                   ]
            )
        ]


{-| Both files side by side and the four answers (FR-COPY-04).
-}
viewConflict : Model -> Conflict -> Html Msg
viewConflict model conflict =
    let
        side heading info =
            div [ class "conflict-side" ]
                [ div [ class "conflict-heading" ] [ text heading ]
                , div [ class "conflict-name" ]
                    [ span
                        [ class
                            ("icon "
                                ++ (if info.isDir then
                                        "folder"

                                    else
                                        "file"
                                   )
                            )
                        ]
                        []
                    , text info.name
                    ]
                , div [ class "muted" ]
                    [ text
                        ((if info.isDir then
                            ""

                          else
                            Format.size info.size ++ " · "
                         )
                            ++ (Maybe.map (Format.date model.settings.dateFormat model.zone) info.modified |> Maybe.withDefault "")
                        )
                    ]
                ]

        answer key labelText =
            button [ onClick (ConflictAnswer key) ] [ text labelText ]
    in
    div [ class "overlay" ]
        [ div [ class "dialog conflict", attribute "role" "alertdialog" ]
            [ div [ class "dialog-title" ] [ text Text.conflictTitle ]
            , div [ class "conflict-sides" ]
                [ side Text.conflictNew conflict.source
                , side Text.conflictExisting conflict.target
                ]
            , label [ class "check-line" ]
                [ input
                    [ Html.Attributes.type_ "checkbox"
                    , Html.Attributes.checked conflict.applyToAll
                    , Html.Events.onCheck ConflictApplyAll
                    ]
                    []
                , text Text.applyToAll
                ]
            , div [ class "dialog-actions" ]
                [ answer "skip" Text.skip
                , answer "keepBoth" Text.keepBoth
                , answer "replaceIfNewer" Text.replaceIfNewer
                , button [ class "primary", onClick (ConflictAnswer "replace") ] [ text Text.replace ]
                ]
            ]
        ]


activeJobs : Model -> List JobStatus
activeJobs model =
    Dict.values model.jobs |> List.filter (\job -> List.member job.state [ "queued", "running", "paused", "waiting" ])


jobFraction : JobStatus -> Float
jobFraction job =
    if job.totalBytes > 0 then
        toFloat job.doneBytes / toFloat job.totalBytes

    else if job.totalItems > 0 then
        toFloat job.doneItems / toFloat job.totalItems

    else
        0


progressBar : Float -> Html msg
progressBar fraction =
    span [ class "progress" ] [ span [ class "bar", style "width" (String.fromFloat (clamp 0 100 (fraction * 100)) ++ "%") ] [] ]


{-| The running job in the status bar; click it for the Jobs panel (FR-STAT-01).
-}
viewJobSummary : Model -> Html Msg
viewJobSummary model =
    case activeJobs model of
        job :: rest ->
            button [ class "job-summary", stopPropagationOn "click" (D.succeed ( ToggleJobsPanel, True )), tabindex -1 ]
                [ text (Text.jobLabel job.kind False job.count job.first (Maybe.map (Path.name model.sep) job.dest) job.permanent)
                , progressBar (jobFraction job)
                , text (String.fromInt (round (jobFraction job * 100)) ++ "%")
                , viewIf (not (List.isEmpty rest)) (span [ class "muted" ] [ text (Text.moreJobs (List.length rest)) ])
                ]

        [] ->
            if Dict.isEmpty model.jobs then
                text ""

            else
                button [ class "job-summary", stopPropagationOn "click" (D.succeed ( ToggleJobsPanel, True )), tabindex -1 ] [ text Text.jobs ]


viewJobsPanel : Model -> Html Msg
viewJobsPanel model =
    let
        jobs =
            Dict.values model.jobs |> List.reverse
    in
    div [ class "jobs-panel", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
        [ div [ class "jobs-header" ]
            [ span [ class "dialog-title" ] [ text Text.jobs ]
            , span [ class "grow" ] []
            , button [ onClick ClearFinishedJobs ] [ text Text.clearFinished ]
            , button [ onClick ToggleJobsPanel, title Text.close ] [ text "×" ]
            ]
        , if List.isEmpty jobs then
            div [ class "muted" ] [ text Text.noJobs ]

          else
            div [ class "jobs-list" ] (List.map (viewJob model) jobs)
        ]


viewJob : Model -> JobStatus -> Html Msg
viewJob model job =
    let
        active =
            List.member job.state [ "queued", "running", "paused", "waiting" ]

        seconds =
            toFloat job.elapsedMs / 1000

        rate =
            if seconds > 1 && job.doneBytes > 0 then
                Just (toFloat job.doneBytes / seconds)

            else
                Nothing

        details =
            case ( job.state, rate ) of
                ( "running", Just perSecond ) ->
                    Text.speed (Format.size (round perSecond)) (round (toFloat (job.totalBytes - job.doneBytes) / perSecond))

                _ ->
                    Text.jobState job.state
    in
    div [ class "job" ]
        [ div [ class "job-line" ]
            [ span [ class "job-label" ] [ text (Text.jobLabel job.kind (not active) job.count job.first (Maybe.map (Path.name model.sep) job.dest) job.permanent) ]
            , viewIf (job.state == "running" || job.state == "paused")
                (button [ onClick (JobPause job.id (job.state /= "paused")) ]
                    [ text
                        (if job.state == "paused" then
                            Text.resume

                         else
                            Text.pause
                        )
                    ]
                )
            , viewIf active (button [ onClick (JobCancel job.id) ] [ text Text.cancelJob ])
            ]
        , viewIf active (div [ class "job-line" ] [ progressBar (jobFraction job), span [ class "muted" ] [ text details ] ])
        , viewIf (active && job.current /= "") (div [ class "muted job-current" ] [ text job.current ])
        , div [ class "job-errors" ]
            (List.map
                (\e ->
                    div [ class "job-error" ]
                        [ span [] [ text e.message ]
                        , viewIf (not active) (button [ onClick (JobRetry job.id [ e ]) ] [ text Text.retry ])
                        , viewIf (not active) (button [ onClick (JobSkip job.id [ e ]) ] [ text Text.skip ])
                        , button [ onClick (RevealPath e.path) ] [ text Text.showInFolder ]
                        ]
                )
                (List.take 20 job.errors)
                ++ [ viewIf (not active && List.length job.errors > 1)
                        (div [ class "job-error" ]
                            [ span [] []
                            , button [ onClick (JobRetry job.id job.errors) ] [ text Text.retryAll ]
                            , button [ onClick (JobSkip job.id job.errors) ] [ text Text.skipAll ]
                            ]
                        )
                   ]
            )
        ]


{-| Makes an element a drop target for items dragged inside File Catalog, and
(through `data-drop`) for files dropped from other apps.
-}
dropTarget : Model -> DropTarget -> String -> List (Html.Attribute Msg)
dropTarget model target value =
    let
        active =
            case model.drag of
                Just (DragItems d) ->
                    d.moved && d.target == Just target

                _ ->
                    False
    in
    [ attribute "data-drop" value
    , on "mouseenter" (D.succeed (DragOver (Just target)))
    , on "mouseleave" (D.succeed (DragOver Nothing))
    , classList [ ( "drop-target", active ) ]
    ]


{-| The label that follows the pointer while dragging items.
-}
viewDragGhost : Model -> Html Msg
viewDragGhost model =
    case model.drag of
        Just (DragItems d) ->
            if d.moved then
                div [ class "drag-ghost", style "left" (px (d.x + 14)), style "top" (px (d.y + 14)) ]
                    [ text
                        (case d.names of
                            [ single ] ->
                                single

                            many ->
                                Text.plural (List.length many) "item" "items"
                        )
                    , span [ class "muted" ] [ text Text.dragHint ]
                    ]

            else
                text ""

        _ ->
            text ""
