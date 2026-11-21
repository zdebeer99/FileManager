module View.Sidebar exposing (treeRows, viewSidebar)

{-| The sidebar (spec 5.7): folder tree, Favourites (with browsing inside a favourite, FR-FAV-03), Bookmarks and Topics (REQ-021).
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
import View.Common exposing (bookmarkDragSource, bookmarkDropTarget, contextMenu, dropTarget, middleClick, px)
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
            , modeButton TopicsMode "topic" Text.topicsMode
            ]
        , div [ id sidebarBodyId, class "sidebar-body" ]
            (case mode of
                TreeMode ->
                    viewTree model tab

                FavouritesMode ->
                    viewFavourites model tab

                BookmarksMode ->
                    viewBookmarksPanel model

                TopicsMode ->
                    viewTopics model tab
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
           , Menu.topicEntries model [ path ]
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

        clip item =
            [ Separator
            , Action { label = Text.cut, key = "", msg = Just (ClipboardPaths True [ item.path ]), checked = Nothing }
            , Action { label = Text.copy, key = "", msg = Just (ClipboardPaths False [ item.path ]), checked = Nothing }
            ]

        fileEntries item =
            [ Action { label = Text.open, key = "", msg = Just (OpenPath item.path), checked = Nothing } ]
                ++ (if model.editorName /= "" then
                        [ Action { label = Text.openWith model.editorName, key = "", msg = Just (OpenInEditor [ item.path ]), checked = Nothing } ]

                    else
                        []
                   )
                ++ [ Action { label = Text.reveal, key = "", msg = Just (RevealPath item.path), checked = Nothing } ]
                ++ clip item

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
                        folderEntries model item.path ++ clip item

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
                ([ class "side-item"
                 , classList [ ( "missing", not b.exists ) ]
                 , indent depth
                 , on "click" (D.map (\ctrl -> OpenBookmark b (ctrl && b.kind == "folder")) (D.field "ctrlKey" D.bool))
                 , on "auxclick" (middleClick (OpenBookmark b (b.kind == "folder")))
                 , contextMenu (bookmarkEntries b)
                 , title b.target
                 , bookmarkDragSource b
                 ]
                    ++ bookmarkDropTarget model (BeforeBookmark b.index b.group)
                )
                [ span [ class "twisty" ] [], viewBookmarkIcon model b, span [ class "label" ] [ text b.name ] ]

        -- A group heading that folds its bookmarks and sub-groups away (spec 5.7).
        -- While searching, every group is shown open so no match is hidden.
        viewGroup depth group label contents =
            let
                key =
                    String.join "/" group

                folded =
                    search == "" && Set.member key model.foldedGroups
            in
            button
                ([ class "side-group"
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
                    -- Dropping a bookmark on a group heading moves it into the group (REQ-007).
                    ++ bookmarkDropTarget model (IntoGroup group)
                )
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
                group
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
                            viewGroup 0 [] Text.otherBookmarks (List.map (viewBookmark 1) ungrouped)
                       )
           )



-- TOPICS (REQ-021)


viewTopics : Model -> Tab -> List (Html Msg)
viewTopics model tab =
    case Maybe.andThen (\i -> List.head (List.filter (\t -> t.index == i) model.topics)) model.openTopic of
        Just topic ->
            viewOpenTopic model tab topic

        Nothing ->
            viewTopicList model tab


{-| Whether `path` is `folder` or inside it (Windows paths ignore case).
-}
isInFolder : String -> String -> String -> Bool
isInFolder sep folder path =
    let
        fold =
            if sep == "\\" then
                String.toLower

            else
                identity

        f =
            fold folder

        p =
            fold path
    in
    p
        == f
        || String.startsWith
            (if String.endsWith sep f then
                f

             else
                f ++ sep
            )
            p


topicEdit : String -> Topic -> List ( String, Json.Encode.Value ) -> Msg
topicEdit op topic extra =
    TopicEditOp (( "op", Json.Encode.string op ) :: ( "index", Json.Encode.int topic.index ) :: extra)


addFolderOp : Topic -> String -> Msg
addFolderOp topic path =
    topicEdit "addFolders" topic [ ( "paths", Json.Encode.list Json.Encode.string [ path ] ) ]


archiveAction : Topic -> MenuEntry
archiveAction topic =
    Action
        { label =
            if topic.archived then
                Text.unarchiveTopic

            else
                Text.archiveTopic
        , key = ""
        , msg = Just (topicEdit "archive" topic [ ( "archived", Json.Encode.bool (not topic.archived) ) ])
        , checked = Nothing
        }


{-| The list of topics: search, the topics in order (drag to reorder), New
Topic, and the archived ones in a group that is folded away by default.
Topics with the open folder in them are marked.
-}
viewTopicList : Model -> Tab -> List (Html Msg)
viewTopicList model tab =
    let
        search =
            String.toLower (String.trim model.topicSearch)

        matches topic =
            search
                == ""
                || List.any (\t -> String.contains search (String.toLower t)) (topic.title :: topic.description :: topic.folders)

        matching =
            List.filter matches model.topics

        ( archived, active ) =
            List.partition .archived matching

        canAddOpen =
            tab.search == Nothing

        action label msg =
            Action { label = label, key = "", msg = Just msg, checked = Nothing }

        entries topic =
            [ action Text.open (OpenTopic topic.index)
            , action Text.edit (EditTopic (Just topic.index) [])
            ]
                ++ (if canAddOpen then
                        [ action Text.addOpenFolder (addFolderOp topic tab.path) ]

                    else
                        []
                   )
                ++ [ Separator, archiveAction topic, action Text.deleteTopic (DeleteTopic topic.index) ]

        dragSource topic =
            on "mousedown"
                (D.field "button" D.int
                    |> D.andThen
                        (\b ->
                            if b == 0 then
                                D.map2 (TopicMouseDown topic.index topic.title) (D.field "clientX" D.float) (D.field "clientY" D.float)

                            else
                                D.fail "not the left button"
                        )
                )

        row topic =
            button
                ([ class "side-item topic-item"
                 , classList [ ( "current", List.any (\f -> isInFolder model.sep f tab.path) topic.folders ) ]
                 , onClick (OpenTopic topic.index)
                 , contextMenu (entries topic)
                 , title
                    (if topic.description == "" then
                        Text.topicFolderCount (List.length topic.folders)

                     else
                        topic.description
                    )
                 , dragSource topic
                 , attribute "data-topic-drop" (String.fromInt topic.index)
                 ]
                    -- Dragging folders onto a topic adds them to it.
                    ++ dropTarget model (DropTopic topic.index) ("topic:" ++ String.fromInt topic.index)
                )
                [ span [ class "icon topic" ] []
                , span [ class "label" ] [ text topic.title ]
                , span [ class "topic-count" ] [ text (String.fromInt (List.length topic.folders)) ]
                ]

        archivedShown =
            model.archivedTopicsOpen || search /= ""

        draggingTopic =
            case model.drag of
                Just (MoveTopic d) ->
                    d.moved

                _ ->
                    False
    in
    [ div [ classList [ ( "topics", True ), ( "topic-dragging", draggingTopic ) ] ]
        ([ input
            [ class "side-search"
            , placeholder Text.searchTopics
            , value model.topicSearch
            , onInput TopicSearch
            , spellcheck False
            ]
            []
         ]
            ++ List.map (\w -> div [ class "sidebar-warning" ] [ text w ]) model.topicWarnings
            ++ (if List.isEmpty model.topics then
                    [ div [ class "sidebar-empty" ] [ text Text.noTopics ] ]

                else
                    List.map row active
               )
            ++ [ button
                    [ class "side-add topic-end"
                    , onClick
                        (EditTopic Nothing
                            (if canAddOpen then
                                [ tab.path ]

                             else
                                []
                            )
                        )
                    , attribute "data-topic-drop" "end"
                    ]
                    [ text Text.newTopicButton ]
               ]
            ++ (if List.isEmpty archived then
                    []

                else
                    button
                        [ class "side-group"
                        , onClick ToggleArchivedTopics
                        , attribute "aria-expanded"
                            (if archivedShown then
                                "true"

                             else
                                "false"
                            )
                        ]
                        [ span [ class "twisty" ]
                            [ text
                                (if archivedShown then
                                    "▾"

                                 else
                                    "▸"
                                )
                            ]
                        , span [ class "label" ] [ text (Text.archivedTopics ++ " (" ++ String.fromInt (List.length archived) ++ ")") ]
                        ]
                        :: (if archivedShown then
                                List.map row archived

                            else
                                []
                           )
               )
        )
    ]


{-| An open topic: its title and description, its folders (click to open
one in the active tab), and Edit, Archive and Delete.
-}
viewOpenTopic : Model -> Tab -> Topic -> List (Html Msg)
viewOpenTopic model tab topic =
    let
        action label msg =
            Action { label = label, key = "", msg = Just msg, checked = Nothing }

        hasOpen =
            List.any (\f -> isInFolder model.sep f tab.path && String.length f == String.length tab.path) topic.folders

        folderRow path =
            button
                ([ class "side-item"
                 , classList [ ( "current", isInFolder model.sep path tab.path ) ]
                 , onClick (NavigateTo path)
                 , on "auxclick" (middleClick (NavigateNewTab path))
                 , contextMenu
                    (folderEntries model path
                        ++ [ Separator, action Text.removeFromTopic (topicEdit "removeFolder" topic [ ( "path", Json.Encode.string path ) ]) ]
                    )
                 , title path
                 ]
                    ++ dropTarget model (DropFolder path) path
                )
                [ viewFolderIcon model path, span [ class "label" ] [ text (Path.name model.sep path) ] ]

        topicDrop =
            dropTarget model (DropTopic topic.index) ("topic:" ++ String.fromInt topic.index)
    in
    [ div ([ class "fav-header" ] ++ topicDrop)
        [ button [ class "fav-up", onClick CloseTopic, title Text.backToTopics, attribute "aria-label" Text.backToTopics ] [ text "‹" ]
        , span [ class "fav-location", title topic.title ] [ text topic.title ]
        , button [ class "fav-open", onClick (EditTopic (Just topic.index) []), title Text.editTopicTitle, attribute "aria-label" Text.editTopicTitle ] [ text "✎" ]
        ]
    , if topic.description == "" then
        text ""

      else
        div [ class "topic-description" ] [ text topic.description ]
    ]
        ++ (if List.isEmpty topic.folders then
                [ div ([ class "sidebar-empty" ] ++ topicDrop) [ text Text.topicNoFolders ] ]

            else
                List.map folderRow topic.folders
           )
        ++ (if tab.search == Nothing && not hasOpen then
                [ button [ class "side-add", onClick (addFolderOp topic tab.path) ] [ text Text.addOpenFolder ] ]

            else
                []
           )
        ++ [ div [ class "topic-actions" ]
                [ button [ onClick (EditTopic (Just topic.index) []) ] [ text Text.edit ]
                , button [ onClick (topicEdit "archive" topic [ ( "archived", Json.Encode.bool (not topic.archived) ) ]) ]
                    [ text
                        (if topic.archived then
                            Text.unarchiveTopic

                         else
                            Text.archiveTopic
                        )
                    ]
                , button [ class "danger", onClick (DeleteTopic topic.index) ] [ text Text.deleteTopic ]
                ]
           ]
