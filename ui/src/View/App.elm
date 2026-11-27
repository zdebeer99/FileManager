module View.App exposing (view)

{-| The window (spec 5.1): every bar and panel, the dialogs and popups on top, and the keyboard and mouse handlers.
-}

import Html exposing (Html, div, text)
import Html.Attributes exposing (attribute, class, classList, tabindex)
import Html.Events exposing (on, onClick, preventDefaultOn)
import Json.Decode as D
import Menu
import Types exposing (..)
import View.AddressBar exposing (viewAddressBar, viewAddressBarWith)
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
import View.TitleBar exposing (dragRegion, viewWindowControls)
import View.Toolbar exposing (viewToolbar, viewToolbarGroups)


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
            ++ [ attribute "data-style" model.settings.style
               , attribute "data-layout"
                    (if isBrowserLayout model then
                        "browser"

                     else
                        "classic"
                    )
               , classList [ ( "own-titlebar", not model.settings.systemTitleBar ) ]
               ]
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
                    viewTopRows model tab
                        ++ [ viewMain model tab
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


isBrowserLayout : Model -> Bool
isBrowserLayout model =
    model.settings.layoutStyle /= "classic"


{-| The rows above the file list (spec 5.1).

  - Browser layout: the tabs with the window buttons (the title bar), then the
    toolbar's first group, the Address Bar, the other toolbar buttons and ☰,
    then the Bookmark Bar.
  - Classic layout: the Menu Bar (with the window buttons), toolbar, Bookmark
    Bar, tabs and Address Bar, each as set in View. With File Catalog's own
    title bar the Menu Bar row is always shown, as it is the title bar.

-}
viewTopRows : Model -> Tab -> List (Html Msg)
viewTopRows model tab =
    let
        s =
            model.settings

        ownTitleBar =
            not s.systemTitleBar
    in
    if isBrowserLayout model then
        let
            ( left, right ) =
                viewToolbarGroups model tab
        in
        [ div ([ class "titlebar" ] ++ dragRegion model) [ viewTabBar model, viewWindowControls model ]
        , viewAddressBarWith [ left ] [ right, Menu.viewMenuButton model tab ] model tab
        , viewIf s.bookmarkBar (viewBookmarkBar model)
        ]

    else
        [ viewIf (s.menuBar || model.menuBar /= Nothing || ownTitleBar)
            (div ([ class "titlebar classic" ] ++ dragRegion model)
                [ Menu.viewMenuBar model tab
                , div ([ class "titlebar-space" ] ++ dragRegion model) []
                , viewWindowControls model
                ]
            )
        , viewIf s.toolbar (viewToolbar model tab)
        , viewIf s.bookmarkBar (viewBookmarkBar model)
        , viewIf s.tabBar (viewTabBar model)
        , viewIf s.addressBar (viewAddressBar model tab)
        ]


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
