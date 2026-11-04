module View.Jobs exposing (viewConflict, viewJobSummary, viewJobsPanel)

{-| Background jobs (spec 6.12): the status bar summary, the Jobs panel and the name-conflict dialog.
-}

import Dict
import Format
import Html exposing (Html, button, div, input, label, span, text)
import Html.Attributes exposing (attribute, class, style, tabindex, title)
import Html.Events exposing (onClick, stopPropagationOn)
import Json.Decode as D
import Path
import Text
import Types exposing (..)
import View.Common exposing (viewIf)


{-| Both files side by side and the four answers (FR-COPY-04).
-}
viewConflict : Model -> Conflict -> Html Msg
viewConflict model conflict =
    let
        side heading info =
            div [ class "conflict-side" ]
                [ div [ class "conflict-heading" ] [ text heading ]
                , div [ class "conflict-name" ]
                    [ span
                        [ class
                            ("icon "
                                ++ (if info.isDir then
                                        "folder"

                                    else
                                        "file"
                                   )
                            )
                        ]
                        []
                    , text info.name
                    ]
                , div [ class "muted" ]
                    [ text
                        ((if info.isDir then
                            ""

                          else
                            Format.size info.size ++ " · "
                         )
                            ++ (Maybe.map (Format.date model.settings.dateFormat model.zone) info.modified |> Maybe.withDefault "")
                        )
                    ]
                ]

        answer key labelText =
            button [ onClick (ConflictAnswer key) ] [ text labelText ]
    in
    div [ class "overlay" ]
        [ div [ class "dialog conflict", attribute "role" "alertdialog" ]
            [ div [ class "dialog-title" ] [ text Text.conflictTitle ]
            , div [ class "conflict-sides" ]
                [ side Text.conflictNew conflict.source
                , side Text.conflictExisting conflict.target
                ]
            , label [ class "check-line" ]
                [ input
                    [ Html.Attributes.type_ "checkbox"
                    , Html.Attributes.checked conflict.applyToAll
                    , Html.Events.onCheck ConflictApplyAll
                    ]
                    []
                , text Text.applyToAll
                ]
            , div [ class "dialog-actions" ]
                [ answer "skip" Text.skip
                , answer "keepBoth" Text.keepBoth
                , answer "replaceIfNewer" Text.replaceIfNewer
                , button [ class "primary", onClick (ConflictAnswer "replace") ] [ text Text.replace ]
                ]
            ]
        ]


activeJobs : Model -> List JobStatus
activeJobs model =
    Dict.values model.jobs |> List.filter (\job -> List.member job.state [ "queued", "running", "paused", "waiting" ])


jobFraction : JobStatus -> Float
jobFraction job =
    if job.totalBytes > 0 then
        toFloat job.doneBytes / toFloat job.totalBytes

    else if job.totalItems > 0 then
        toFloat job.doneItems / toFloat job.totalItems

    else
        0


progressBar : Float -> Html msg
progressBar fraction =
    span [ class "progress" ] [ span [ class "bar", style "width" (String.fromFloat (clamp 0 100 (fraction * 100)) ++ "%") ] [] ]


{-| The running job in the status bar; click it for the Jobs panel (FR-STAT-01).
-}
viewJobSummary : Model -> Html Msg
viewJobSummary model =
    case activeJobs model of
        job :: rest ->
            button [ class "job-summary", stopPropagationOn "click" (D.succeed ( ToggleJobsPanel, True )), tabindex -1 ]
                [ text (Text.jobLabel job.kind False job.count job.first (Maybe.map (Path.name model.sep) job.dest) job.permanent)
                , progressBar (jobFraction job)
                , text (String.fromInt (round (jobFraction job * 100)) ++ "%")
                , viewIf (not (List.isEmpty rest)) (span [ class "muted" ] [ text (Text.moreJobs (List.length rest)) ])
                ]

        [] ->
            if Dict.isEmpty model.jobs then
                text ""

            else
                button [ class "job-summary", stopPropagationOn "click" (D.succeed ( ToggleJobsPanel, True )), tabindex -1 ] [ text Text.jobs ]


viewJobsPanel : Model -> Html Msg
viewJobsPanel model =
    let
        jobs =
            Dict.values model.jobs |> List.reverse
    in
    div [ class "jobs-panel", stopPropagationOn "click" (D.succeed ( NoOp, True )) ]
        [ div [ class "jobs-header" ]
            [ span [ class "dialog-title" ] [ text Text.jobs ]
            , span [ class "grow" ] []
            , button [ onClick ClearFinishedJobs ] [ text Text.clearFinished ]
            , button [ onClick ToggleJobsPanel, title Text.close ] [ text "×" ]
            ]
        , if List.isEmpty jobs then
            div [ class "muted" ] [ text Text.noJobs ]

          else
            div [ class "jobs-list" ] (List.map (viewJob model) jobs)
        ]


viewJob : Model -> JobStatus -> Html Msg
viewJob model job =
    let
        active =
            List.member job.state [ "queued", "running", "paused", "waiting" ]

        seconds =
            toFloat job.elapsedMs / 1000

        rate =
            if seconds > 1 && job.doneBytes > 0 then
                Just (toFloat job.doneBytes / seconds)

            else
                Nothing

        details =
            case ( job.state, rate ) of
                ( "running", Just perSecond ) ->
                    Text.speed (Format.size (round perSecond)) (round (toFloat (job.totalBytes - job.doneBytes) / perSecond))

                _ ->
                    Text.jobState job.state
    in
    div [ class "job" ]
        [ div [ class "job-line" ]
            [ span [ class "job-label" ] [ text (Text.jobLabel job.kind (not active) job.count job.first (Maybe.map (Path.name model.sep) job.dest) job.permanent) ]
            , viewIf (job.state == "running" || job.state == "paused")
                (button [ onClick (JobPause job.id (job.state /= "paused")) ]
                    [ text
                        (if job.state == "paused" then
                            Text.resume

                         else
                            Text.pause
                        )
                    ]
                )
            , viewIf active (button [ onClick (JobCancel job.id) ] [ text Text.cancelJob ])
            ]
        , viewIf active (div [ class "job-line" ] [ progressBar (jobFraction job), span [ class "muted" ] [ text details ] ])
        , viewIf (active && job.current /= "") (div [ class "muted job-current" ] [ text job.current ])
        , div [ class "job-errors" ]
            (List.map
                (\e ->
                    div [ class "job-error" ]
                        [ span [] [ text e.message ]
                        , viewIf (not active) (button [ onClick (JobRetry job.id [ e ]) ] [ text Text.retry ])
                        , viewIf (not active) (button [ onClick (JobSkip job.id [ e ]) ] [ text Text.skip ])
                        , button [ onClick (RevealPath e.path) ] [ text Text.showInFolder ]
                        ]
                )
                (List.take 20 job.errors)
                ++ [ viewIf (not active && List.length job.errors > 1)
                        (div [ class "job-error" ]
                            [ span [] []
                            , button [ onClick (JobRetry job.id job.errors) ] [ text Text.retryAll ]
                            , button [ onClick (JobSkip job.id job.errors) ] [ text Text.skipAll ]
                            ]
                        )
                   ]
            )
        ]
