module View.TabBar exposing (viewTabBar)

{-| The Tab Bar (spec 5.5), with tab colours (FR-TAB-06).
-}

import Dict
import Html exposing (Html, button, div, span, text)
import Html.Attributes exposing (attribute, class, classList, tabindex, title)
import Html.Events exposing (on, onClick, stopPropagationOn)
import Json.Decode as D
import Path
import Text
import Types exposing (..)
import View.Common exposing (dropTarget, middleClick, viewIf)
import View.Icons exposing (ownFolderIcon)


viewTabBar : Model -> Html Msg
viewTabBar model =
    div [ class "tabbar", attribute "role" "tablist" ]
        (List.map (viewTab model) model.tabs
            ++ [ button [ class "newtab", onClick NewTab, title Text.newTab, tabindex -1 ] [ text "+" ] ]
        )


{-| A tab takes the colour of its folder or of the nearest folder above it
that has one, so it keeps the colour in sub-folders (REQ-012, spec 6.4.5).
-}
tabColour : Model -> String -> Maybe String
tabColour model path =
    case Dict.get path model.folderColours of
        Just colour ->
            Just colour

        Nothing ->
            if Dict.isEmpty model.folderColours then
                Nothing

            else
                Path.parent model.sep path |> Maybe.andThen (tabColour model)


{-| REQ-027: the own icon of the tab's folder or the nearest folder above it
that has one, and a cloud badge inside an online drive (REQ-028). Plain
folders show nothing, as before.
-}
viewTabIcon : Model -> String -> Html Msg
viewTabIcon model path =
    let
        nearest p =
            case ownFolderIcon model p of
                Just url ->
                    Just ( p, url )

                Nothing ->
                    Path.parent model.sep p |> Maybe.andThen nearest

        cloud =
            cloudRootOf model path

        badge =
            case cloud of
                Just root ->
                    span [ class ("icon tab-cloud cloud cloud-" ++ root.provider), title (Text.onlineDrive root.provider) ] []

                Nothing ->
                    text ""
    in
    case nearest path of
        Just ( from, url ) ->
            span [ class "tab-icons" ]
                [ Html.img [ class "sysicon", Html.Attributes.src url, Html.Attributes.alt "", attribute "draggable" "false" ] []

                -- The online drive's own folder icon already says which drive it is.
                , viewIf (Maybe.map .path cloud /= Just from) badge
                ]

        Nothing ->
            span [ class "tab-icons" ] [ badge ]


viewTab : Model -> Tab -> Html Msg
viewTab model tab =
    let
        dragOver =
            case model.drag of
                Just (MoveTab d) ->
                    d.moved && d.over == Just tab.id && d.tabId /= tab.id

                _ ->
                    False
    in
    div
        ([ class "tab"
         , classList
            [ ( "active", tab.id == model.active )
            , ( "tab-drop", dragOver )
            , ( "tc-" ++ Maybe.withDefault "" (tabColour model tab.path), tabColour model tab.path /= Nothing )
            ]
         , on "mousedown"
            (D.map2 Tuple.pair (D.field "button" D.int) (D.field "clientX" D.float)
                |> D.andThen
                    (\( b, x ) ->
                        if b == 0 then
                            D.succeed (TabMouseDown tab.id x)

                        else
                            D.fail "not the left button"
                    )
            )
         , on "mouseover" (D.succeed (TabHover tab.id))
         , attribute "role" "tab"
         , onClick (ActivateTab tab.id)
         , on "auxclick" (middleClick (CloseTab tab.id))
         , title tab.path
         ]
            ++ dropTarget model (DropFolder tab.path) tab.path
        )
        [ viewIf (tab.search == Nothing) (viewTabIcon model tab.path)
        , viewIf (isFiltering tab) (span [ class "icon filter", title Text.filtered ] [])
        , case tab.search of
            Just search ->
                span [ class "label search" ] [ text (Text.searchTabLabel search.query) ]

            Nothing ->
                span [ class "label" ] [ text (Path.name model.sep tab.path) ]
        , button
            [ class "close"
            , stopPropagationOn "click" (D.succeed ( CloseTab tab.id, True ))
            , title Text.closeTab
            , tabindex -1
            ]
            [ text "×" ]
        ]
