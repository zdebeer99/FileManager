module View.Palette exposing (viewPalette)

{-| The command palette (spec 6.9).
-}

import Html exposing (Html, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, classList, id, placeholder, spellcheck, value)
import Html.Events exposing (on, onClick, onInput, onMouseEnter, stopPropagationOn)
import Html.Keyed
import Json.Decode as D
import Text
import Types exposing (..)


viewPalette : Model -> Html Msg
viewPalette model =
    case model.palette of
        Nothing ->
            text ""

        Just p ->
            div [ class "palette-overlay", onClick (PaletteKey "Escape" False) ]
                [ div [ class "palette", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
                    [ input
                        [ id paletteInputId
                        , value p.text
                        , onInput PaletteInput
                        , placeholder Text.palettePlaceholder
                        , spellcheck False
                        , attribute "autocomplete" "off"
                        , Html.Events.custom "keydown"
                            (D.map2 Tuple.pair (D.field "key" D.string) (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
                                |> D.andThen
                                    (\( key, ctrl ) ->
                                        if List.member key [ "ArrowDown", "ArrowUp", "PageDown", "PageUp", "Enter", "Escape", "Tab" ] then
                                            D.succeed { message = PaletteKey key ctrl, stopPropagation = True, preventDefault = True }

                                        else
                                            D.fail "typing"
                                    )
                            )
                        ]
                        []
                    , if String.startsWith "?" p.text then
                        div [ class "palette-hint" ] [ text Text.paletteFindHint ]

                      else
                        text ""
                    , if List.isEmpty p.results && String.length p.text > 1 then
                        div [ class "palette-empty" ] [ text Text.paletteNoResults ]

                      else
                        Html.Keyed.node "div"
                            [ class "palette-results", attribute "role" "listbox" ]
                            (List.indexedMap (viewPaletteItem p.active) p.results)
                    ]
                ]


viewPaletteItem : Int -> Int -> PaletteItem -> ( String, Html Msg )
viewPaletteItem active index result =
    ( String.fromInt index ++ result.label ++ result.detail
    , div
        [ class "palette-item"
        , classList [ ( "active", index == active ) ]
        , attribute "role" "option"
        , on "click" (D.map (\ctrl -> PaletteRun index ctrl) (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool)))
        , onMouseEnter (PaletteHover index)
        ]
        [ span [ class ("icon " ++ result.icon) ] []
        , span [ class "palette-label" ] (highlightHits result.label result.hits)
        , span [ class "palette-detail" ] [ text result.detail ]
        , span [ class "key" ] [ text result.key ]
        ]
    )


{-| The label with its matched letters marked (FR-CMD-03).
-}
highlightHits : String -> List Int -> List (Html msg)
highlightHits label hits =
    if List.isEmpty hits then
        [ text label ]

    else
        String.toList label
            |> List.indexedMap
                (\i c ->
                    if List.member i hits then
                        Html.mark [] [ text (String.fromChar c) ]

                    else
                        text (String.fromChar c)
                )
