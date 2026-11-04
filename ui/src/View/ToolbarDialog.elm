module View.ToolbarDialog exposing (viewToolbarDialog)

{-| Customise Toolbar (FR-TB-02).
-}

import Commands
import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, placeholder, spellcheck, style, tabindex, title, value)
import Html.Events exposing (onClick, onInput)
import Text
import Types exposing (..)
import View.Toolbar exposing (toolbarFace)


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
