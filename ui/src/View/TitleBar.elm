module View.TitleBar exposing (dragRegion, viewWindowControls)

{-| File Catalog's own title bar (spec 5.1): the window buttons, and the
drag regions that move the window (double-click maximises). Not shown when
`layout.systemTitleBar` is on.
-}

import Html exposing (Html, button, div, span)
import Html.Attributes exposing (attribute, class, tabindex, title)
import Html.Events exposing (stopPropagationOn)
import Json.Decode as D
import Text
import Types exposing (..)


{-| Makes an element move the window when dragged. Only the element itself:
buttons and tabs inside it keep working.
-}
dragRegion : Model -> List (Html.Attribute msg)
dragRegion model =
    if model.settings.systemTitleBar then
        []

    else
        [ attribute "data-tauri-drag-region" "" ]


viewWindowControls : Model -> Html Msg
viewWindowControls model =
    let
        control action icon label extra =
            button
                [ class ("window-control " ++ extra)
                , stopPropagationOn "click" (D.succeed ( WindowControl action, True ))
                , title label
                , attribute "aria-label" label
                , tabindex -1
                ]
                [ span [ class ("icon " ++ icon) ] [] ]
    in
    if model.settings.systemTitleBar then
        Html.text ""

    else
        div [ class "window-controls" ]
            [ control "minimize" "win-minimize" Text.minimizeWindow ""
            , if model.maximized then
                control "maximize" "win-restore" Text.restoreWindow ""

              else
                control "maximize" "win-maximize" Text.maximizeWindow ""
            , control "close" "win-close" Text.closeWindow "close"
            ]
