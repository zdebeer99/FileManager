module View.Shortcuts exposing (viewShortcuts)

{-| Help › Keyboard Shortcuts (FR-KEY-04).
-}

import Commands
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, classList, disabled, id, placeholder, spellcheck, tabindex, title, value)
import Html.Events exposing (onClick, onInput)
import Keys
import Text
import Types exposing (..)
import View.Common exposing (viewIf)


viewShortcuts : Model -> ShortcutsState -> Html Msg
viewShortcuts model state =
    let
        search =
            String.toLower (String.trim state.search)

        rows =
            Commands.all
                |> List.filter (\d -> d.id /= "bookmark.manage")
                |> List.filter
                    (\d ->
                        search
                            == ""
                            || String.contains search (String.toLower (Commands.name d.id))
                            || String.contains search d.id
                            || List.any (\k -> String.contains search (String.toLower k)) (Keys.keysFor d.id model.keymap)
                    )
                |> List.sortBy (\d -> String.toLower (Commands.name d.id))

        changedByUser id =
            List.any (\b -> b.command == id) model.userBindings
    in
    div [ class "overlay" ]
        [ div [ class "dialog shortcuts", id shortcutsDialogId, tabindex -1, attribute "role" "dialog" ]
            [ div [ class "dialog-title" ] [ text Text.shortcutsTitle ]
            , input
                [ id shortcutsSearchId
                , class "shortcuts-search"
                , value state.search
                , onInput ShortcutsSearch
                , placeholder Text.shortcutsSearch
                , spellcheck False
                ]
                []
            , case ( state.recording, state.proposal ) of
                ( Just r, _ ) ->
                    div [ class "shortcuts-banner recording" ]
                        [ text (Commands.name r.command ++ ": ")
                        , text
                            (if List.isEmpty r.strokes then
                                Text.pressKeys

                             else
                                String.join " " r.strokes ++ " …"
                            )
                        ]

                ( Nothing, Just p ) ->
                    let
                        owners =
                            Keys.lookup "global" p.key model.keymap
                                |> Maybe.map .command
                                |> Maybe.andThen
                                    (\c ->
                                        if c == p.command then
                                            Nothing

                                        else
                                            Just c
                                    )
                    in
                    div
                        [ class "shortcuts-banner"
                        , classList [ ( "conflict", owners /= Nothing ) ]
                        ]
                        [ span [ class "grow" ]
                            [ text (Commands.name p.command ++ ": ")
                            , case owners of
                                Just other ->
                                    text (Text.keyConflict p.key (Commands.name other))

                                Nothing ->
                                    text (Text.keyFree p.key)
                            ]
                        , button [ onClick ShortcutsDiscard ] [ text Text.cancel ]
                        , button [ class "primary", onClick ShortcutsSave ] [ text Text.saveKey ]
                        ]

                ( Nothing, Nothing ) ->
                    div [ class "shortcuts-banner muted" ] [ text Text.shortcutsHint ]
            , div [ class "shortcuts-list" ]
                (List.map
                    (\d ->
                        div [ class "shortcut-row" ]
                            [ span [ class "shortcut-name" ]
                                [ text (Commands.name d.id)
                                , viewIf (changedByUser d.id) (span [ class "shortcut-changed" ] [ text Text.customised ])
                                ]
                            , span [ class "shortcut-id" ] [ text d.id ]
                            , span [ class "shortcut-keys" ]
                                (case Keys.keysFor d.id model.keymap of
                                    [] ->
                                        [ span [ class "muted" ] [ text Text.noBinding ] ]

                                    keys ->
                                        List.map
                                            (\k ->
                                                span [ class "keycap" ]
                                                    [ text k
                                                    , button [ class "keycap-remove", title Text.removeKey, onClick (ShortcutsRemove d.id k) ] [ text "×" ]
                                                    ]
                                            )
                                            keys
                                )
                            , button [ class "small", onClick (ShortcutsRecord d.id) ] [ text Text.addKey ]
                            , button [ class "small", disabled (not (changedByUser d.id)), onClick (ShortcutsReset d.id) ] [ text Text.resetKeys ]
                            ]
                    )
                    rows
                )
            , div [ class "dialog-actions" ]
                [ button [ onClick (KeyCommand CmdOpenKeybindingsFile) ] [ text Text.openFile ]
                , button [ class "primary", onClick DialogCancel ] [ text Text.close ]
                ]
            ]
        ]
