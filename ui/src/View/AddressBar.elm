module View.AddressBar exposing (viewAddressBar)

{-| The Address Bar (spec 5.6): breadcrumbs, edit mode and the Quick Filter box.
-}

import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (attribute, class, classList, id, placeholder, spellcheck, tabindex, title, value)
import Html.Events exposing (onBlur, onClick, onFocus, onInput, stopPropagationOn)
import Json.Decode as D
import Path
import Text
import Types exposing (..)
import View.Common exposing (inputKeys)


viewAddressBar : Model -> Tab -> Html Msg
viewAddressBar model tab =
    div [ class "addressbar" ]
        [ case model.address of
            Editing typed error ->
                div [ class "address-edit" ]
                    [ input
                        [ id addressInputId
                        , class "address-input"
                        , value typed
                        , onInput AddressInput
                        , onBlur AddressBlur
                        , Html.Events.custom "keydown" (inputKeys [ "Enter", "Escape", "Tab" ] AddressKey)
                        , attribute "data-select-on-focus" ""
                        , spellcheck False
                        ]
                        []
                    , case error of
                        Just message ->
                            span [ class "address-error" ] [ text message ]

                        Nothing ->
                            text ""
                    ]

            ShowCrumbs ->
                div [ class "crumbs", onClick StartEditAddress, title tab.path ]
                    (List.concatMap viewCrumb (Path.crumbs model.sep tab.path))
        , div [ class "filter-box", classList [ ( "active", tab.filter /= "" ) ] ]
            [ span [ class "icon filter" ] []
            , input
                [ id filterInputId
                , class "filter-input"
                , placeholder Text.filterPlaceholder
                , value tab.filter
                , onInput FilterInput
                , onFocus (RegionFocused RegionFilter)
                , Html.Events.custom "keydown" (inputKeys [ "Escape", "Enter", "ArrowDown", "F6" ] FilterKey)
                , spellcheck False
                , attribute "aria-label" Text.filterPlaceholder
                ]
                []
            ]
        ]


viewCrumb : Path.Crumb -> List (Html Msg)
viewCrumb crumb =
    [ button
        [ class "crumb"
        , stopPropagationOn "click" (D.succeed ( NavigateTo crumb.path, True ))
        , tabindex -1
        ]
        [ text crumb.label ]
    , button
        [ class "crumb-sep"
        , stopPropagationOn "click"
            (D.map2 (\x y -> ( OpenCrumbMenu crumb.path x y, True ))
                (D.field "clientX" D.float)
                (D.field "clientY" D.float)
            )
        , tabindex -1
        ]
        [ text "›" ]
    ]
