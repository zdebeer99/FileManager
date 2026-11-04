module View.Sidebar exposing (treeRows, viewSidebar)

{-| The sidebar (spec 5.7): folder tree, Favourites (with browsing inside a favourite, FR-FAV-03) and Bookmarks.
-}

import Dict
import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, placeholder, spellcheck, style, tabindex, title, value)
import Html.Events exposing (on, onClick, onInput, stopPropagationOn)
import Item exposing (Item)
import Json.Decode as D
import Json.Encode
import Menu
import Path
import Set
import Text
import Types exposing (..)
import View.BookmarkBar exposing (bookmarkEntries)
import View.Common exposing (contextMenu, dropTarget, middleClick, px)
import View.Icons exposing (viewBookmarkIcon, viewFolderIcon, viewIcon)


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
    ]
        ++ (if model.editorName /= "" then
                [ action (Text.openFolderWith model.editorName) (OpenInEditor [ path ]) ]

            else
                []
           )
        ++ [ Separator
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
            [ Action { label = Text.open, key = "", msg = Just (OpenPath item.path), checked = Nothing } ]
                ++ (if model.editorName /= "" then
                        [ Action { label = Text.openWith model.editorName, key = "", msg = Just (OpenInEditor [ item.path ]), checked = Nothing } ]

                    else
                        []
                   )
                ++ [ Action { label = Text.reveal, key = "", msg = Just (RevealPath item.path), checked = Nothing } ]

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
