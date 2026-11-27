module View.Dialogs exposing (viewDialog)

{-| Dialogs: confirmations, the bookmark dialog with its group drop-down (FR-BM-01), and New File / Shortcut / Web Link.
-}

import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, spellcheck, value)
import Html.Events exposing (onBlur, onClick, onFocus, onInput, preventDefaultOn)
import Json.Decode as D
import Json.Encode
import Text
import Types exposing (..)
import View.Common exposing (field, inputKeys, noAutocomplete, viewIf)
import View.SettingsDialog exposing (viewSettingsDialog)
import View.Shortcuts exposing (viewShortcuts)
import View.ToolbarDialog exposing (viewToolbarDialog)


viewDialog : Model -> Html Msg
viewDialog model =
    case model.dialog of
        Nothing ->
            text ""

        Just (NewItemDialog form) ->
            viewNewItemDialog form

        Just (ShortcutsDialog state) ->
            viewShortcuts model state

        Just (ToolbarDialog form) ->
            viewToolbarDialog model form

        Just (TopicDialog form) ->
            viewTopicDialog form

        Just (TopicFolderDialog form) ->
            viewTopicFolderDialog form

        Just (OpenWithDialog state) ->
            viewOpenWith state

        Just (SettingsDialog state) ->
            viewSettingsDialog model state

        Just (ConfirmDialog confirm) ->
            div [ class "overlay" ]
                [ div [ class "dialog", attribute "role" "alertdialog" ]
                    [ div [ class "dialog-title" ] [ text confirm.title ]
                    , viewIf (not (List.isEmpty confirm.lines)) (div [ class "dialog-list" ] (List.map (\line -> div [] [ text line ]) confirm.lines))
                    , div [ class "dialog-actions" ]
                        [ button [ id "confirm-no", onClick DialogCancel ] [ text Text.cancel ]
                        , button
                            [ id "confirm-yes"
                            , class
                                (if confirm.danger then
                                    "danger"

                                 else
                                    "primary"
                                )
                            , onClick ConfirmYes
                            ]
                            [ text confirm.confirmLabel ]
                        ]
                    ]
                ]

        Just (BookmarkDialog form) ->
            div [ class "overlay" ]
                [ div
                    [ class "dialog"
                    , attribute "role" "dialog"
                    , Html.Events.custom "keydown"
                        (inputKeys [ "Enter", "Escape" ]
                            (\key ->
                                if key == "Enter" then
                                    DialogSubmit

                                else
                                    DialogCancel
                            )
                        )
                    ]
                    [ div [ class "dialog-title" ]
                        [ text
                            (if form.index == Nothing then
                                Text.addBookmark

                             else
                                Text.editBookmark
                            )
                        ]
                    , field Text.name dialogFirstInputId form.name DialogName
                    , field Text.target "dialog-target" form.target DialogTarget
                    , viewGroupField model form
                    , div [ class "hint" ] [ text Text.groupHint ]
                    , case form.error of
                        Just error ->
                            div [ class "dialog-error" ] [ text error ]

                        Nothing ->
                            text ""
                    , div [ class "dialog-actions" ]
                        [ button [ onClick DialogCancel ] [ text Text.cancel ]
                        , button [ class "primary", onClick DialogSubmit ] [ text Text.save ]
                        ]
                    ]
                ]


{-| The bookmark group: a text box with a drop-down of the existing groups.
Typing filters them; a name that is not a group yet is offered as a new one
(spec 6.4.2).
-}
viewGroupField : Model -> BookmarkForm -> Html Msg
viewGroupField model form =
    let
        choices =
            groupChoices model form.group

        isNew choice =
            choice
                /= "bar"
                && not
                    (List.any
                        (\b -> List.any (\n -> String.join "/" (List.take n b.group) == choice) (List.range 1 (List.length b.group)))
                        model.bookmarks
                    )

        friendly choice =
            case String.split "/" choice of
                "bar" :: rest ->
                    String.join " › " (Text.bookmarkBar :: rest)

                parts ->
                    String.join " › " parts

        viewChoice index choice =
            div
                [ class "combo-option"
                , classList [ ( "active", index == form.groupActive ) ]
                , attribute "role" "option"
                , attribute "aria-selected"
                    (if index == form.groupActive then
                        "true"

                     else
                        "false"
                    )

                -- mousedown, so the pick happens before the text box loses focus.
                , preventDefaultOn "mousedown" (D.succeed ( DialogGroupPick choice, True ))
                ]
                (if isNew choice then
                    [ span [ class "combo-new" ] [ text (Text.newGroup choice) ] ]

                 else
                    [ span [] [ text choice ], span [ class "muted" ] [ text (friendly choice) ] ]
                )
    in
    label [ class "field" ]
        [ span [] [ text Text.group ]
        , div [ class "combo" ]
            [ input
                [ noAutocomplete
                , id "dialog-group"
                , value form.group
                , onInput DialogGroup
                , onFocus (DialogGroupOpen True)
                , onBlur (DialogGroupOpen False)
                , spellcheck False
                , attribute "autocomplete" "off"
                , attribute "role" "combobox"
                , attribute "aria-expanded"
                    (if form.groupOpen then
                        "true"

                     else
                        "false"
                    )
                , attribute "data-select-on-focus" ""
                , Html.Events.custom "keydown" (inputKeys [ "ArrowDown", "ArrowUp", "Enter", "Escape" ] DialogGroupKey)
                ]
                []
            , viewIf (form.groupOpen && not (List.isEmpty choices))
                (div [ class "combo-list", attribute "role" "listbox" ] (List.indexedMap viewChoice choices))
            ]
        ]


viewNewItemDialog : NewItemForm -> Html Msg
viewNewItemDialog form =
    let
        ( titleText, fields ) =
            case form.kind of
                NewFile ->
                    ( Text.newFileTitle, [ field Text.fileName dialogFirstInputId form.name NewItemName ] )

                NewShortcut ->
                    ( Text.newShortcutTitle
                    , [ field Text.shortcutTarget dialogFirstInputId form.target NewItemTarget
                      , field Text.shortcutNameHint "dialog-target" form.name NewItemName
                      ]
                    )

                NewWebLink ->
                    ( Text.newWebLinkTitle
                    , [ field Text.webAddress dialogFirstInputId form.target NewItemTarget
                      , field Text.webNameHint "dialog-target" form.name NewItemName
                      ]
                    )

                NewFromTemplate _ ->
                    ( Text.newFromTemplateTitle, [ field Text.templateName dialogFirstInputId form.name NewItemName ] )
    in
    div [ class "overlay" ]
        [ div
            [ class "dialog"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            NewItemSubmit

                        else
                            DialogCancel
                    )
                )
            ]
            ([ div [ class "dialog-title" ] [ text titleText ] ]
                ++ fields
                ++ [ case form.error of
                        Just error ->
                            div [ class "dialog-error" ] [ text error ]

                        Nothing ->
                            text ""
                   , div [ class "dialog-actions" ]
                        [ button [ onClick DialogCancel ] [ text Text.cancel ]
                        , button [ class "primary", onClick NewItemSubmit ] [ text Text.create ]
                        ]
                   ]
            )
        ]


{-| New Topic and Edit Topic (REQ-021).
-}
viewTopicDialog : TopicForm -> Html Msg
viewTopicDialog form =
    div [ class "overlay" ]
        [ div
            [ class "dialog"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            TopicSubmit

                        else
                            DialogCancel
                    )
                )
            ]
            [ div [ class "dialog-title" ]
                [ text
                    (if form.index == Nothing then
                        Text.newTopicTitle

                     else
                        Text.editTopicTitle
                    )
                ]
            , field Text.topicTitleField dialogFirstInputId form.title TopicTitle
            , field Text.topicDescriptionField "dialog-target" form.description TopicDescription
            , viewIf (form.index == Nothing && not (List.isEmpty form.folders))
                (div [ class "hint" ] [ text (Text.topicStartsWith (List.length form.folders)) ])
            , case form.error of
                Just error ->
                    div [ class "dialog-error" ] [ text error ]

                Nothing ->
                    text ""
            , div [ class "dialog-actions" ]
                ((case form.index of
                    -- Archive and Delete live here, not under the folders (REQ-023).
                    Just index ->
                        [ button [ class "danger", onClick (DeleteTopic index) ] [ text Text.deleteTopic ]
                        , button
                            [ onClick (TopicEditOp [ ( "op", Json.Encode.string "archive" ), ( "index", Json.Encode.int index ), ( "archived", Json.Encode.bool (not form.archived) ) ]) ]
                            [ text
                                (if form.archived then
                                    Text.unarchiveTopic

                                 else
                                    Text.archiveTopic
                                )
                            ]
                        , span [ class "dialog-spacer" ] []
                        ]

                    Nothing ->
                        []
                 )
                    ++ [ button [ onClick DialogCancel ] [ text Text.cancel ]
                       , button [ class "primary", onClick TopicSubmit ] [ text Text.save ]
                       ]
                )
            ]
        ]


{-| One folder of a topic (REQ-023): the name shown for it, its path, and
Remove from Topic. Like the bookmark dialog; the folder itself is not renamed.
-}
viewTopicFolderDialog : TopicFolderForm -> Html Msg
viewTopicFolderDialog form =
    div [ class "overlay" ]
        [ div
            [ class "dialog"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            TopicFolderSubmit

                        else
                            DialogCancel
                    )
                )
            ]
            [ div [ class "dialog-title" ] [ text Text.editTopicFolderTitle ]
            , field Text.name dialogFirstInputId form.name TopicFolderName
            , field Text.topicFolderPath "dialog-target" form.newPath TopicFolderPath
            , div [ class "hint" ] [ text Text.topicFolderHint ]
            , case form.error of
                Just error ->
                    div [ class "dialog-error" ] [ text error ]

                Nothing ->
                    text ""
            , div [ class "dialog-actions" ]
                [ button [ class "danger", onClick TopicFolderRemove ] [ text Text.removeFromTopic ]
                , span [ class "dialog-spacer" ] []
                , button [ onClick DialogCancel ] [ text Text.cancel ]
                , button [ class "primary", onClick TopicFolderSubmit ] [ text Text.save ]
                ]
            ]
        ]


{-| Open With on Linux (FR-OPEN-02): click an app to open the file with it.
-}
viewOpenWith : OpenWithState -> Html Msg
viewOpenWith state =
    let
        name =
            String.split "/" state.path |> List.reverse |> List.head |> Maybe.withDefault state.path

        appButton index app =
            button
                ([ class "openwith-app"
                 , onClick (OpenWithPick app.id)
                 ]
                    ++ (if index == 0 then
                            [ id dialogFirstInputId ]

                        else
                            []
                       )
                )
                [ span [] [ text app.name ]
                , viewIf app.default (span [ class "muted" ] [ text Text.openWithDefault ])
                ]

        shown =
            if state.showAll then
                state.apps ++ state.others

            else
                state.apps
    in
    div [ class "overlay" ]
        [ div
            [ class "dialog openwith"
            , attribute "role" "dialog"
            , Html.Events.custom "keydown" (inputKeys [ "Escape" ] (\_ -> DialogCancel))
            ]
            [ div [ class "dialog-title" ] [ text (Text.openWithTitle name) ]
            , if List.isEmpty shown then
                div [ class "hint" ] [ text Text.openWithNone ]

              else
                div [ class "openwith-list" ] (List.indexedMap appButton shown)
            , div [ class "dialog-actions" ]
                [ viewIf (not state.showAll && not (List.isEmpty state.others)) (button [ onClick OpenWithShowAll ] [ text Text.openWithShowAll ])
                , span [ class "dialog-spacer" ] []
                , button [ onClick DialogCancel ] [ text Text.cancel ]
                ]
            ]
        ]
