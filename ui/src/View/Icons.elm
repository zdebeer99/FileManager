module View.Icons exposing (bookmarkMenuIcon, ownFolderIcon, viewBookmarkIcon, viewFolderIcon, viewIcon, viewPlaceIcon)

{-| Item, folder and bookmark icons: system icons when available (FR-ICON-02), else the built-in ones (FR-ICON-01), and folder colours (spec 6.4.5).
-}

import Dict
import Html exposing (Html, span)
import Html.Attributes exposing (attribute, class)
import Item exposing (Item)
import Types exposing (..)


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
    viewPlaceIcon model path "folder"


{-| A folder's icon: its colour (spec 6.4.5), else its own system icon
(REQ-025: Downloads, Pictures, a custom icon, an online drive), else the
built-in icon for an online drive's folder (REQ-028), else `builtin` (or the
system folder icon when `builtin` is "folder").
-}
viewPlaceIcon : Model -> String -> String -> Html msg
viewPlaceIcon model path builtin =
    if Dict.member path model.folderColours then
        span [ class ("icon " ++ folderIcon model path) ] []

    else
        case ownFolderIcon model path of
            Just url ->
                sysIcon url

            Nothing ->
                case List.filter (\r -> r.kind == "cloud" && r.path == path) model.roots of
                    root :: _ ->
                        span [ class ("icon cloud cloud-" ++ root.provider) ] []

                    [] ->
                        if builtin == "folder" then
                            iconOrBuiltin model "folder" "folder"

                        else
                            span [ class ("icon " ++ builtin) ] []


{-| A folder's own system icon, once it has arrived (REQ-025).
-}
ownFolderIcon : Model -> String -> Maybe String
ownFolderIcon model path =
    if model.settings.icons == "system" then
        Dict.get ("dir:" ++ path) model.systemIcons

    else
        Nothing


sysIcon : String -> Html msg
sysIcon url =
    Html.img [ class "sysicon", Html.Attributes.src url, Html.Attributes.alt "", attribute "draggable" "false" ] []


viewBookmarkIcon : Model -> Bookmark -> Html msg
viewBookmarkIcon model b =
    case ( b.kind, bookmarkIconKey b ) of
        -- A bookmarked folder shows the folder's own icon (REQ-026).
        ( "folder", _ ) ->
            viewFolderIcon model b.target

        ( _, key ) ->
            bookmarkKeyIcon model b key


bookmarkKeyIcon : Model -> Bookmark -> Maybe String -> Html msg
bookmarkKeyIcon model b maybeKey =
    case maybeKey of
        Just key ->
            iconOrBuiltin model key (bookmarkIcon b)

        Nothing ->
            span [ class ("icon " ++ bookmarkIcon b) ] []


{-| A bookmark's icon for a menu entry (REQ-017): the same choice as
`viewBookmarkIcon`, as data the menu can draw.
-}
bookmarkMenuIcon : Model -> Bookmark -> MenuIcon
bookmarkMenuIcon model b =
    { url =
        if model.settings.icons == "system" then
            -- A folder's own icon first (REQ-026).
            (if b.kind == "folder" then
                ownFolderIcon model b.target

             else
                Nothing
            )
                |> Maybe.map Just
                |> Maybe.withDefault (bookmarkIconKey b |> Maybe.andThen (\key -> Dict.get key model.systemIcons))

        else
            Nothing
    , builtin = bookmarkIcon b
    }


iconOrBuiltin : Model -> String -> String -> Html msg
iconOrBuiltin model key builtin =
    case ( model.settings.icons, Dict.get key model.systemIcons ) of
        ( "system", Just url ) ->
            sysIcon url

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
