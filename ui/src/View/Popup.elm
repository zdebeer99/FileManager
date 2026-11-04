module View.Popup exposing (filterPopupValues, viewPopup)

{-| Popups: right-click menus kept on screen (FR-MENU-02) and column filters (spec 6.3.2).
-}

import Columns
import Format
import Html exposing (Html, button, div, input, span, text)
import Html.Attributes exposing (class, classList, id, placeholder, spellcheck, style, tabindex, value)
import Html.Events exposing (onClick, onInput, stopPropagationOn)
import Json.Decode as D
import Menu
import Set
import Text
import Types exposing (..)
import View.Common exposing (inputKeys, keepOnScreen, px, viewIf)


viewPopup : Model -> Html Msg
viewPopup model =
    case model.popup of
        Nothing ->
            text ""

        Just (MenuPopup p) ->
            let
                -- Moved up when it would run off the bottom of the window (REQ-011).
                top =
                    max 4 (min p.y (model.windowHeight - 4 - Menu.menuHeight p.entries))
            in
            div [ class "popup", style "left" (keepOnScreen p.x 260), style "top" (px top) ]
                [ Menu.viewDropdown model.windowHeight top -1 Nothing False p.entries ]

        Just (ColumnFilterPopup s) ->
            viewColumnFilter s


{-| The values shown in a column filter, after its search box.
-}
filterPopupValues : ColumnFilterState -> List ( String, Int )
filterPopupValues s =
    let
        search =
            String.toLower s.search
    in
    if search == "" then
        s.values

    else
        List.filter (\( v, _ ) -> String.contains search (String.toLower v)) s.values


viewColumnFilter : ColumnFilterState -> Html Msg
viewColumnFilter s =
    let
        shown =
            filterPopupValues s

        shownValues =
            List.map Tuple.first shown

        allChecked =
            List.all (\v -> Set.member v s.checked) shownValues

        checkRow depth labelText values count =
            div
                [ class "check-row"
                , classList [ ( "group", depth == 0 && Columns.isDate s.column ) ]
                , onClick (ColumnFilterToggle values)
                , style "padding-left" (px (toFloat depth * 16 + 8))
                ]
                [ span [ class "box" ]
                    [ text
                        (if List.all (\v -> Set.member v s.checked) values then
                            "✓"

                         else if List.any (\v -> Set.member v s.checked) values then
                            "–"

                         else
                            ""
                        )
                    ]
                , span [ class "label" ] [ text labelText ]
                , span [ class "count" ] [ text (String.fromInt count) ]
                ]

        rows =
            if Columns.isDate s.column then
                -- Grouped by month, newest first (FR-CF-01).
                List.foldl
                    (\( v, _ ) months ->
                        let
                            month =
                                String.left 7 v
                        in
                        if List.member month months then
                            months

                        else
                            months ++ [ month ]
                    )
                    []
                    shown
                    |> List.concatMap
                        (\month ->
                            let
                                days =
                                    List.filter (\( v, _ ) -> String.left 7 v == month) shown
                            in
                            checkRow 0 month (List.map Tuple.first days) (List.sum (List.map Tuple.second days))
                                :: List.map (\( v, n ) -> checkRow 1 v [ v ] n) days
                        )

            else
                List.map (\( v, n ) -> checkRow 0 v [ v ] n) (List.take 1000 shown)

        quick key labelText =
            button [ onClick (ColumnFilterQuick key), tabindex -1 ] [ text labelText ]
    in
    div
        [ class "popup menu colfilter"
        , style "left" (keepOnScreen (s.x - 140) 296)
        , style "top" (px (s.y + 12))
        , stopPropagationOn "click" (D.succeed ( NoOp, True ))
        ]
        [ input
            [ id "colfilter-search"
            , class "colfilter-search"
            , placeholder (Text.searchColumn (Columns.title s.column))
            , value s.search
            , onInput ColumnFilterSearch
            , Html.Events.custom "keydown"
                (inputKeys [ "Enter", "Escape" ]
                    (\key ->
                        if key == "Enter" then
                            ColumnFilterApply

                        else
                            ClosePopups
                    )
                )
            , spellcheck False
            ]
            []
        , viewIf (Columns.isDate s.column)
            (div [ class "quick" ]
                [ quick "today" Text.today
                , quick "yesterday" Text.yesterday
                , quick "week" Text.thisWeek
                , quick "last7" Text.last7Days
                , quick "month" Text.thisMonth
                , quick "year" Text.thisYear
                ]
            )
        , viewIf (s.column == Columns.Size)
            (div [ class "size-range" ]
                [ span [] [ text Text.sizeBetween ]
                , rangeInput s.rangeFrom True
                , span [] [ text Text.sizeAnd ]
                , rangeInput s.rangeTo False
                ]
            )
        , div [ class "check-list" ]
            (div [ class "check-row all", onClick ColumnFilterSelectAll ]
                [ span [ class "box" ]
                    [ text
                        (if allChecked then
                            "✓"

                         else
                            ""
                        )
                    ]
                , span [ class "label" ] [ text Text.selectAll ]
                ]
                :: rows
            )
        , div [ class "colfilter-actions" ]
            [ button [ onClick ColumnFilterClear ] [ text Text.clearFilter ]
            , span [ class "grow" ] []
            , button [ onClick ClosePopups ] [ text Text.cancel ]
            , button [ class "primary", onClick ColumnFilterApply ] [ text Text.ok ]
            ]
        ]


{-| One end of the Size column's "between" range (FR-CF-01).
-}
rangeInput : String -> Bool -> Html Msg
rangeInput current isFrom =
    input
        [ value current
        , onInput (ColumnFilterRange isFrom)
        , placeholder
            (if isFrom then
                Text.sizeFromHint

             else
                Text.sizeToHint
            )
        , classList [ ( "invalid", String.trim current /= "" && Format.parseSize current == Nothing ) ]
        , spellcheck False
        , Html.Events.custom "keydown"
            (inputKeys [ "Enter", "Escape" ]
                (\key ->
                    if key == "Enter" then
                        ColumnFilterApply

                    else
                        ClosePopups
                )
            )
        ]
        []
