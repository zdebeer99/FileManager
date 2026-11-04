module View.App exposing (view)

{-| The window (spec 5.1): every bar and panel, the dialogs and popups on top, and the keyboard and mouse handlers.
-}

import Html exposing (Html, div, text)
import Html.Attributes exposing (attribute, class, tabindex)
import Html.Events exposing (on, onClick, preventDefaultOn)
import Json.Decode as D
import Menu
import Types exposing (..)
import View.AddressBar exposing (viewAddressBar)
import View.BookmarkBar exposing (viewBookmarkBar)
import View.Common exposing (viewIf)
import View.Dialogs exposing (viewDialog)
import View.FileList exposing (viewContent, viewDragGhost)
import View.Jobs exposing (viewConflict, viewJobsPanel)
import View.Keyboard exposing (keyDecoder, mouseNavDecoder)
import View.Palette exposing (viewPalette)
import View.Popup exposing (viewPopup)
import View.Sidebar exposing (viewSidebar)
import View.StatusBar exposing (viewStatusBar)
import View.TabBar exposing (viewTabBar)
import View.Toolbar exposing (viewToolbar)


view : Model -> Html Msg
view model =
    div
        ([ class "app"

         -- Focusable, so clicking an empty spot keeps keyboard focus inside the app.
         , tabindex -1
         , preventDefaultOn "keydown" (keyDecoder model)
         , on "mouseup" mouseNavDecoder
         , on "mouseleave" (D.succeed DragLeftWindow)
         ]
            ++ themeAttribute model.settings.theme
            ++ (if model.popup /= Nothing || model.menuBar /= Nothing then
                    [ onClick ClosePopups ]

                else
                    []
               )
            ++ (case model.drag of
                    Just (ResizeColumn _ _ _) ->
                        [ class "dragging-col" ]

                    Just (ResizeSidebar _) ->
                        [ class "dragging-col" ]

                    _ ->
                        []
               )
        )
        (if not model.booted then
            [ div [ class "placeholder" ] [ text (Maybe.withDefault "" model.bootError) ] ]

         else
            case activeTab model of
                Nothing ->
                    []

                Just tab ->
                    [ viewIf (model.settings.menuBar || model.menuBar /= Nothing) (Menu.viewMenuBar model tab)
                    , viewIf model.settings.toolbar (viewToolbar model tab)
                    , viewIf model.settings.bookmarkBar (viewBookmarkBar model)
                    , viewIf model.settings.tabBar (viewTabBar model)
                    , viewIf model.settings.addressBar (viewAddressBar model tab)
                    , viewMain model tab
                    , viewIf model.settings.statusBar (viewStatusBar model tab)
                    , viewIf model.jobsPanel (viewJobsPanel model)
                    , viewPopup model
                    , viewDragGhost model
                    , case model.conflicts of
                        conflict :: _ ->
                            viewConflict model conflict

                        [] ->
                            viewDialog model
                    , viewPalette model
                    ]
        )


themeAttribute : String -> List (Html.Attribute msg)
themeAttribute theme =
    if theme == "light" || theme == "dark" then
        [ attribute "data-theme" theme ]

    else
        []


viewMain : Model -> Tab -> Html Msg
viewMain model tab =
    let
        sidebar =
            if model.settings.sidebarVisible then
                [ viewSidebar model tab, div [ class "splitter", on "mousedown" (D.map SidebarResizeStart (D.field "clientX" D.float)) ] [] ]

            else
                []
    in
    div [ class "main" ]
        (if model.settings.sidebarSide == "right" then
            viewContent model tab :: List.reverse sidebar

         else
            sidebar ++ [ viewContent model tab ]
        )
