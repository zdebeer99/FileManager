module View.Toolbar exposing (toolbarFace, viewToolbar)

{-| The toolbar (spec 5.3) and its Save View button (FR-VIEW-05).
-}

import Commands
import Html exposing (Html, button, div, label, span, text)
import Html.Attributes exposing (attribute, class, disabled, id, style, tabindex, title)
import Html.Events exposing (onClick, preventDefaultOn, stopPropagationOn)
import Json.Decode as D
import Text
import Types exposing (..)
import View.Common exposing (viewIf)


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
