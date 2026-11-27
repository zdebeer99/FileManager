module View.SettingsDialog exposing (viewSettingsDialog)

{-| The settings page (REQ-038, spec 8.3): settings.toml in sections, with a
toggle, choice, text box, number or list for each value. A change is written
to settings.toml at once (toggles and choices) or when a text box is left or
Enter is pressed; the file keeps its comments.
-}

import Html exposing (Html, button, div, input, label, option, select, span, text, textarea)
import Html.Attributes exposing (attribute, checked, class, classList, id, selected, spellcheck, type_, value)
import Html.Events exposing (on, onCheck, onClick, targetValue)
import Json.Decode as D
import Json.Encode as E
import SettingsPage exposing (Field, Kind(..))
import Text
import Types exposing (..)
import View.Common exposing (inputKeys, noAutocomplete, viewIf)


viewSettingsDialog : Model -> SettingsState -> Html Msg
viewSettingsDialog model state =
    let
        current =
            List.filter (\( id, _ ) -> id == state.section) SettingsPage.sections
                |> List.head
                |> Maybe.withDefault ( "general", [] )
    in
    div [ class "overlay" ]
        [ div
            [ class "dialog settings-dialog"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown" (inputKeys [ "Escape" ] (\_ -> DialogCancel))
            ]
            [ div [ class "dialog-title" ] [ text Text.settingsTitle ]
            , div [ class "settings-body" ]
                [ div [ class "settings-nav", attribute "role" "tablist" ]
                    (List.map
                        (\( sectionId, _ ) ->
                            button
                                ([ class "settings-tab"
                                 , classList [ ( "active", sectionId == Tuple.first current ) ]
                                 , onClick (SettingsSection sectionId)
                                 , attribute "role" "tab"
                                 ]
                                    ++ (if sectionId == Tuple.first current then
                                            [ id dialogFirstInputId ]

                                        else
                                            []
                                       )
                                )
                                [ text (Text.settingsSection sectionId) ]
                        )
                        SettingsPage.sections
                    )
                , div [ class "settings-fields" ]
                    (List.map (\w -> div [ class "dialog-error" ] [ text w ]) model.warnings
                        ++ List.map (viewField model.settingsRaw) (Tuple.second current)
                    )
                ]
            , div [ class "dialog-actions" ]
                [ button [ onClick (KeyCommand CmdOpenSettingsFile) ] [ text Text.openSettingsFile ]
                , button [ onClick (KeyCommand CmdShortcuts) ] [ text Text.keyboardShortcutsButton ]
                , button [ onClick (KeyCommand CmdCustomiseToolbar) ] [ text Text.customiseToolbarButton ]
                , span [ class "dialog-spacer" ] []
                , button [ class "primary", onClick DialogCancel ] [ text Text.done ]
                ]
            ]
        ]


{-| The value at a dotted key in the settings the backend sent.
-}
valueAt : String -> D.Decoder a -> D.Value -> Maybe a
valueAt key decoder raw =
    D.decodeValue (D.at (String.split "." key) decoder) raw |> Result.toMaybe


viewField : D.Value -> Field -> Html Msg
viewField raw field =
    let
        help =
            Text.settingHelp field.key

        fieldId =
            "setting-" ++ String.replace "." "-" field.key

        caption =
            label [ class "setting-label", attribute "for" fieldId ] [ text (Text.settingLabel field.key) ]

        -- Text boxes save when left or on Enter, so typing is never interrupted.
        onCommit toValue =
            on "change" (D.map (\v -> SettingChange field.key (toValue v)) targetValue)

        control =
            case field.kind of
                Toggle ->
                    input
                        [ type_ "checkbox"
                        , id fieldId
                        , checked (valueAt field.key D.bool raw |> Maybe.withDefault False)
                        , onCheck (\on -> SettingChange field.key (E.bool on))
                        ]
                        []

                Choice options ->
                    let
                        now =
                            valueAt field.key D.string raw |> Maybe.withDefault ""
                    in
                    select [ id fieldId, onCommit E.string ]
                        (List.map
                            (\o -> option [ value o, selected (o == now) ] [ text (Text.settingChoice field.key o) ])
                            options
                        )

                TextValue ->
                    input
                        [ noAutocomplete
                        , id fieldId
                        , class "setting-text"
                        , value (valueAt field.key D.string raw |> Maybe.withDefault "")
                        , spellcheck False
                        , onCommit (String.trim >> E.string)
                        , Html.Events.custom "keydown" (inputKeys [ "Enter" ] (\_ -> NoOp))
                        ]
                        []

                Number ->
                    input
                        [ noAutocomplete
                        , id fieldId
                        , type_ "number"
                        , Html.Attributes.min "0"
                        , class "setting-number"
                        , value (valueAt field.key D.int raw |> Maybe.map String.fromInt |> Maybe.withDefault "")
                        , onCommit (String.toInt >> Maybe.withDefault 0 >> max 0 >> E.int)
                        ]
                        []

                Lines ->
                    textarea
                        [ noAutocomplete
                        , id fieldId
                        , class "setting-lines"
                        , spellcheck False
                        , attribute "rows" "3"
                        , value (valueAt field.key (D.list D.string) raw |> Maybe.withDefault [] |> String.join "\n")
                        , onCommit (String.lines >> List.map String.trim >> List.filter ((/=) "") >> E.list E.string)
                        ]
                        []
    in
    div [ class "setting", classList [ ( "setting-toggle", field.kind == Toggle ) ] ]
        [ div [ class "setting-head" ] [ caption, control ]
        , viewIf (help /= "") (div [ class "hint" ] [ text help ])
        ]
