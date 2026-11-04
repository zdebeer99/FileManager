module View.StatusBar exposing (viewStatusBar)

{-| The status bar (spec 5.10), including Quick Find progress (spec 6.6).
-}

import Array
import Dict
import Format
import Html exposing (Html, div, span, text)
import Html.Attributes exposing (class, id, title)
import Set
import Text
import Types exposing (..)
import View.Common exposing (viewIf)
import View.Jobs exposing (viewJobSummary)


viewStatusBar : Model -> Tab -> Html Msg
viewStatusBar model tab =
    let
        total =
            Array.length tab.visible

        selectedSize =
            Set.toList tab.selected
                |> List.filterMap (\id -> Dict.get id tab.items)
                |> List.filter (not << .isDir)
                |> List.map .size
                |> List.sum

        warnings =
            model.warnings ++ model.bookmarkWarnings ++ model.colourWarnings ++ model.keyWarnings ++ model.toolbarWarnings
    in
    div [ class "statusbar" ]
        [ span []
            [ text
                (if isFiltering tab then
                    Text.showing total tab.unfilteredCount

                 else
                    Text.itemCount total tab.folderCount (total - tab.folderCount)
                )
            ]
        , viewIf (tab.hiddenCount > 0) (span [] [ text (Text.hiddenCount tab.hiddenCount) ])
        , viewIf (not (Set.isEmpty tab.selected))
            (span []
                [ text
                    (Text.selected (Set.size tab.selected)
                        (if selectedSize > 0 then
                            Format.size selectedSize

                         else
                            ""
                        )
                    )
                ]
            )
        , case tab.search of
            Just search ->
                span [ class "search-status" ] [ text (searchStatus search) ]

            Nothing ->
                viewIf (tab.status == Loading) (span [] [ text Text.loading ])
        , span [ class "grow" ] []
        , case model.chord of
            Just key ->
                span [ class "message" ] [ text (Text.chordWaiting key) ]

            Nothing ->
                text ""
        , viewJobSummary model
        , case model.message of
            Just message ->
                span [ class "message" ] [ text message ]

            Nothing ->
                text ""
        , case warnings of
            first :: _ ->
                span [ class "warning", title (String.join "\n" warnings) ] [ text first ]

            [] ->
                text ""
        , case model.freeSpace of
            Just bytes ->
                span [ class "free" ] [ text (Text.free (Format.size bytes)) ]

            Nothing ->
                text ""
        ]


{-| Progress and outcome of a Quick Find search (FR-FIND-03).
-}
searchStatus : Search -> String
searchStatus search =
    case ( search.relink, search.running ) of
        ( Just bookmark, False ) ->
            Text.locateHint bookmark.name

        _ ->
            searchProgress search


searchProgress : Search -> String
searchProgress search =
    if search.running then
        Text.searchRunning search.scanned search.found

    else if search.cancelled then
        Text.searchStopped search.found

    else if search.truncated then
        Text.searchTruncated search.found

    else if search.found == 0 then
        Text.searchNothing

    else
        Text.searchDone search.scanned search.found search.millis
