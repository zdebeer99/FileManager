module View.BookmarkBar exposing (bookmarkEntries, viewBookmarkBar)

{-| The Bookmark Bar (spec 5.4) and the right-click menu of a bookmark.
-}

import Html exposing (Html, button, div, label, span, text)
import Html.Attributes exposing (class, classList, tabindex, title)
import Html.Events exposing (on, stopPropagationOn)
import Json.Decode as D
import Json.Encode
import Text
import Types exposing (..)
import View.Common exposing (contextMenu, dropTarget, middleClick)
import View.Icons exposing (viewBookmarkIcon)


type BarEntry
    = BarBookmark Bookmark
    | BarGroup String (List Bookmark)


viewBookmarkBar : Model -> Html Msg
viewBookmarkBar model =
    let
        onBar =
            List.filter (\b -> List.head b.group == Just "bar") model.bookmarks

        entries =
            List.foldl
                (\b acc ->
                    case b.group of
                        [ "bar" ] ->
                            acc ++ [ BarBookmark b ]

                        _ :: group :: _ ->
                            if List.any (isGroup group) acc then
                                acc

                            else
                                acc ++ [ BarGroup group (List.filter (\x -> List.drop 1 x.group |> List.head |> (==) (Just group)) onBar) ]

                        _ ->
                            acc
                )
                []
                onBar

        isGroup group entry =
            case entry of
                BarGroup g _ ->
                    g == group

                _ ->
                    False
    in
    div (class "bookmarkbar" :: dropTarget model DropBookmarkBar "bookmark-bar")
        (if List.isEmpty entries then
            [ span [ class "hint" ] [ text Text.bookmarkBarHint ] ]

         else
            List.map
                (\entry ->
                    case entry of
                        BarBookmark b ->
                            bookmarkButton model b

                        BarGroup group members ->
                            button
                                [ class "bm group"
                                , stopPropagationOn "click"
                                    (D.map2
                                        (\x y ->
                                            ( ItemContextMenu
                                                (List.map
                                                    (\b -> Action { label = b.name, key = "", msg = Just (OpenBookmark b False), checked = Nothing })
                                                    members
                                                )
                                                x
                                                (y + 10)
                                            , True
                                            )
                                        )
                                        (D.field "clientX" D.float)
                                        (D.field "clientY" D.float)
                                    )
                                , tabindex -1
                                ]
                                [ span [ class "icon folder" ] [], text (group ++ " ▾") ]
                )
                entries
        )


bookmarkButton : Model -> Bookmark -> Html Msg
bookmarkButton model b =
    button
        [ class "bm"
        , classList [ ( "missing", not b.exists ) ]
        , on "click" (D.map (\ctrl -> OpenBookmark b (ctrl && b.kind == "folder")) (D.field "ctrlKey" D.bool))
        , on "auxclick" (middleClick (OpenBookmark b (b.kind == "folder")))
        , contextMenu (bookmarkEntries b)
        , title b.target
        , tabindex -1
        ]
        [ viewBookmarkIcon model b, text b.name ]


bookmarkEntries : Bookmark -> List MenuEntry
bookmarkEntries b =
    let
        action label msg =
            Action { label = label, key = "", msg = Just msg, checked = Nothing }

        edit op extra =
            BookmarkEditOp (( "op", Json.Encode.string op ) :: ( "index", Json.Encode.int b.index ) :: extra)
    in
    [ action Text.open (OpenBookmark b False) ]
        ++ (if b.kind == "folder" then
                [ action Text.openInNewTab (OpenBookmark b True) ]

            else
                []
           )
        ++ (if b.exists then
                []

            else
                [ action Text.locate (LocateBookmark b) ]
           )
        ++ [ Separator
           , action Text.edit (EditBookmark b)
           , action Text.moveUp (edit "move" [ ( "delta", Json.Encode.int -1 ) ])
           , action Text.moveDown (edit "move" [ ( "delta", Json.Encode.int 1 ) ])
           , Separator
           , action Text.delete (edit "remove" [])
           ]
