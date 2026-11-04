module View.Common exposing (contextMenu, dropTarget, field, inputKeys, keepOnScreen, middleClick, px, viewIf)

{-| Small helpers shared by the view components: optional elements, menus on right-click, middle-click, drop targets, sizes.
-}

import Html exposing (Html, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, spellcheck, value)
import Html.Events exposing (on, onInput, preventDefaultOn)
import Json.Decode as D
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


field : String -> String -> String -> (String -> Msg) -> Html Msg
field labelText domId current toMsg =
    label [ class "field" ]
        [ span [] [ text labelText ]
        , input [ id domId, value current, onInput toMsg, spellcheck False, attribute "data-select-on-focus" "" ] []
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
