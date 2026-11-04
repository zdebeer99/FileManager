module View.FileList exposing (viewContent, viewDragGhost)

{-| The file list (spec 5.8): the virtualised Details view, its header and cells, and the drag ghost.
-}

import Array
import Columns exposing (Column)
import Dict
import Filter
import Format
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, classList, id, spellcheck, style, tabindex, title, value)
import Html.Events exposing (on, onBlur, onClick, onInput, onMouseEnter, preventDefaultOn, stopPropagationOn)
import Html.Keyed
import Item exposing (Item)
import Json.Decode as D
import Set
import Text
import Types exposing (..)
import View.Common exposing (dropTarget, inputKeys, middleClick, px)
import View.Icons exposing (viewIcon)


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
