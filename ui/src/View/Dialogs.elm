module View.Dialogs exposing (viewDialog)

{-| Dialogs: confirmations, the bookmark dialog with its group drop-down (FR-BM-01), and New File / Shortcut / Web Link.
-}

import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, spellcheck, value)
import Html.Events exposing (onBlur, onClick, onFocus, onInput, preventDefaultOn)
import Json.Decode as D
import Text
import Types exposing (..)
import View.Common exposing (field, inputKeys, viewIf)
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
                [ id "dialog-group"
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
