module View.Common exposing (bookmarkDragSource, bookmarkDropTarget, contextMenu, dropTarget, field, inputKeys, keepOnScreen, middleClick, noAutocomplete, px, viewIf)

{-| Small helpers shared by the view components: optional elements, menus on right-click, middle-click, drop targets, sizes.
-}

import Html exposing (Html, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, spellcheck, value)
import Html.Events exposing (on, onInput, preventDefaultOn, stopPropagationOn)
import Json.Decode as D
import Json.Encode
import Types exposing (..)


viewIf : Bool -> Html msg -> Html msg
viewIf condition html =
    if condition then
        html

    else
        text ""


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


{-| No autofill or "earlier entries" drop-down on a text box (REQ-033). On
Windows the WebView's autofill is also turned off as a whole.
-}
noAutocomplete : Html.Attribute msg
noAutocomplete =
    attribute "autocomplete" "off"


field : String -> String -> String -> (String -> Msg) -> Html Msg
field labelText domId current toMsg =
    label [ class "field" ]
        [ span [] [ text labelText ]
        , input [ noAutocomplete, id domId, value current, onInput toMsg, spellcheck False, attribute "data-select-on-focus" "" ] []
        ]


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


{-| A left position that keeps a popup of the given width inside the window.
-}
keepOnScreen : Float -> Float -> String
keepOnScreen x width =
    "max(4px, min(" ++ px x ++ ", calc(100vw - " ++ px width ++ ")))"


px : Float -> String
px n =
    String.fromFloat n ++ "px"


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


{-| A bookmark that can be dragged (REQ-007): a left-button press starts a
bookmark drag; a click without moving still opens it.
-}
bookmarkDragSource : Bookmark -> Html.Attribute Msg
bookmarkDragSource b =
    on "mousedown"
        (D.field "button" D.int
            |> D.andThen
                (\button ->
                    if button == 0 then
                        D.map2 (BookmarkMouseDown b.index b.name) (D.field "clientX" D.float) (D.field "clientY" D.float)

                    else
                        D.fail "not the left button"
                )
        )


{-| A place a dragged bookmark can be dropped (REQ-007). The `data-bm-drop`
value decides the drop; hovering only draws the marker.
-}
bookmarkDropTarget : Model -> BookmarkDrop -> List (Html.Attribute Msg)
bookmarkDropTarget model drop =
    let
        ( before, group ) =
            case drop of
                BeforeBookmark index g ->
                    ( Json.Encode.int index, g )

                IntoGroup g ->
                    ( Json.Encode.null, g )

        isBefore =
            case drop of
                BeforeBookmark _ _ ->
                    True

                IntoGroup _ ->
                    False

        active =
            case model.drag of
                Just (MoveBookmark d) ->
                    d.moved && d.over == Just drop

                _ ->
                    False

        dragging =
            case model.drag of
                Just (MoveBookmark _) ->
                    True

                _ ->
                    False
    in
    [ attribute "data-bm-drop" (Json.Encode.encode 0 (Json.Encode.object [ ( "before", before ), ( "group", Json.Encode.list Json.Encode.string group ) ]))
    , classList
        [ ( "bm-drop-before", active && isBefore )
        , ( "bm-drop-into", active && not isBefore )
        ]
    ]
        ++ (if dragging then
                [ stopPropagationOn "mouseover" (D.succeed ( BookmarkDragOver (Just drop), True )) ]

            else
                []
           )
