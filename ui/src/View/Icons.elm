module View.Icons exposing (viewBookmarkIcon, viewFolderIcon, viewIcon)

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
