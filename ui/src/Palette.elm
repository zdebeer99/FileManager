module Palette exposing (fuzzy, pathInput, results, splitPath)

{-| The command palette's results (spec 6.9): fuzzy matching with the matched
letters marked, ranked by match quality and then by how often and how
recently each result was picked (FR-CMD-03).
-}

import Array
import Commands
import Dict
import Path
import Text
import Types exposing (..)


{-| Results shown for at most this many items in the current folder, so
typing stays fast in very large folders.
-}
folderItemLimit : Int
folderItemLimit =
    5000


maxResults : Int
maxResults =
    60


type alias Candidate =
    { item : PaletteItem

    -- Matched against the query when `label` does not match (a folder's full path).
    , alt : String

    -- Key in the palette history.
    , useKey : String
    }


results : Model -> String -> List PaletteItem
results model text =
    case String.uncons text of
        Just ( '>', rest ) ->
            rank model rest (commands model)

        Just ( '@', rest ) ->
            rank model rest (bookmarks model)

        Just ( '#', rest ) ->
            rank model rest (tabs model)

        Just ( '?', rest ) ->
            findResults model (String.trim rest)

        Just ( '/', _ ) ->
            pathResults model text

        _ ->
            if String.trim text == "" then
                rank model "" (dedupe (folders model ++ bookmarks model))

            else
                rank model text (dedupe (folders model ++ bookmarks model ++ folderItems model))


item : String -> String -> String -> String -> PaletteAction -> PaletteItem
item label detail key icon action =
    { label = label, detail = detail, key = key, icon = icon, hits = [], action = action }


commands : Model -> List Candidate
commands model =
    Commands.all
        |> List.filter (\d -> d.id /= "bookmark.manage")
        |> List.map
            (\d ->
                { item = item (Commands.name d.id) d.id (Commands.keyLabel model.keymap d.id) "command" (PalCommand d.id d.command)
                , alt = d.id
                , useKey = "cmd:" ++ d.id
                }
            )


folders : Model -> List Candidate
folders model =
    let
        folder path =
            { item = item (Path.name model.sep path) path "" "folder" (PalFolder path), alt = path, useKey = "dir:" ++ path }
    in
    List.map folder (List.take 30 model.recent) ++ List.map (.path >> folder) model.favourites


bookmarks : Model -> List Candidate
bookmarks model =
    List.map
        (\b ->
            { item =
                item b.name
                    b.target
                    ""
                    (if b.kind == "folder" then
                        "folder"

                     else if b.kind == "url" then
                        "weblink"

                     else
                        "file"
                    )
                    (PalBookmark b)
            , alt = b.target
            , useKey = "dir:" ++ b.target
            }
        )
        model.bookmarks


folderItems : Model -> List Candidate
folderItems model =
    case activeTab model of
        Just tab ->
            Array.toList (Array.slice 0 folderItemLimit tab.visible)
                |> List.map
                    (\i ->
                        { item =
                            item i.name
                                (if i.folder == "" then
                                    Text.paletteInFolder

                                 else
                                    i.folder
                                )
                                ""
                                (if i.isDir then
                                    "folder"

                                 else
                                    "file"
                                )
                                (if i.isDir then
                                    PalFolder i.path

                                 else
                                    PalFile i.path
                                )
                        , alt = ""
                        , useKey =
                            if i.isDir then
                                "dir:" ++ i.path

                            else
                                "file:" ++ i.path
                        }
                    )

        Nothing ->
            []


tabs : Model -> List Candidate
tabs model =
    List.indexedMap
        (\i t ->
            let
                label =
                    case t.search of
                        Just s ->
                            Text.searchTabLabel s.query

                        Nothing ->
                            Path.name model.sep t.path
            in
            { item = item label t.path (Commands.keyLabel model.keymap ("tab.goto" ++ String.fromInt (i + 1))) "folder" (PalTab t.id)
            , alt = t.path
            , useKey = ""
            }
        )
        model.tabs


{-| `?text`: start Quick Find with the text, or pick a recent search (FR-FIND-06).
-}
findResults : Model -> String -> List PaletteItem
findResults model query =
    let
        folder =
            activeTab model |> Maybe.map (\t -> Path.name model.sep t.path) |> Maybe.withDefault ""

        recent =
            model.findHistory
                |> List.filter (\h -> h /= query && (query == "" || String.contains (String.toLower query) (String.toLower h)))
                |> List.map (\h -> item h Text.paletteFindRecent "" "find" (PalFind h))
    in
    if query == "" then
        recent

    else
        item (Text.paletteFindIn query folder) "" "Enter" "find" (PalFind query) :: recent


{-| `/path`: a folder path with its sub-folders offered as you type.
-}
pathResults : Model -> String -> List PaletteItem
pathResults model text =
    let
        typed =
            pathInput model text

        ( parent, prefix ) =
            splitPath model typed

        subfolders =
            case model.palette of
                Just p ->
                    if p.listed == parent then
                        p.subfolders

                    else
                        []

                Nothing ->
                    []

        matches =
            subfolders
                |> List.filterMap
                    (\c ->
                        fuzzy (String.toLower prefix) c.label
                            |> Maybe.map
                                (\( score, hits ) ->
                                    ( if String.startsWith (String.toLower prefix) (String.toLower c.label) then
                                        score + 1000

                                      else
                                        score
                                    , { label = c.label, detail = c.path, key = "", icon = "folder", hits = hits, action = PalFolder c.path }
                                    )
                                )
                    )
                |> List.sortBy (\( score, _ ) -> negate score)
                |> List.map Tuple.second
                |> List.take maxResults
    in
    if typed == "" then
        []

    else
        item typed "" "Enter" "folder" (PalFolder typed) :: matches


{-| The path typed after `/`. On Linux the `/` also starts the path.
-}
pathInput : Model -> String -> String
pathInput model text =
    let
        rest =
            String.dropLeft 1 text
    in
    if model.sep == "/" && not (String.startsWith "~" rest) && not (String.startsWith "/" rest) then
        "/" ++ rest

    else
        rest


splitPath : Model -> String -> ( String, String )
splitPath model typed =
    let
        cut =
            List.maximum (String.indexes model.sep typed ++ String.indexes "/" typed)
    in
    case cut of
        Just i ->
            ( String.left (i + 1) typed, String.dropLeft (i + 1) typed )

        Nothing ->
            ( "", typed )


dedupe : List Candidate -> List Candidate
dedupe candidates =
    List.foldl
        (\c ( seen, acc ) ->
            if c.useKey /= "" && List.member c.useKey seen then
                ( seen, acc )

            else
                ( c.useKey :: seen, c :: acc )
        )
        ( [], [] )
        candidates
        |> Tuple.second
        |> List.reverse


{-| Sorts by match score plus a bonus for results picked often and lately.
With no query, the order is by use, then as given.
-}
rank : Model -> String -> List Candidate -> List PaletteItem
rank model text candidates =
    let
        query =
            String.toLower (String.replace " " "" text)

        usage =
            List.foldl
                (\( i, key ) acc ->
                    Dict.update key
                        (\old ->
                            Just
                                (Maybe.withDefault 0 old
                                    + 3
                                    + (if i < 10 then
                                        10 - i

                                       else
                                        0
                                      )
                                )
                        )
                        acc
                )
                Dict.empty
                (List.indexedMap Tuple.pair model.paletteHistory)

        bonus c =
            Dict.get c.useKey usage |> Maybe.withDefault 0

        scored =
            List.indexedMap Tuple.pair candidates
                |> List.filterMap
                    (\( order, c ) ->
                        if query == "" then
                            Just ( -(bonus c * 1000) + order, c.item )

                        else
                            case fuzzy query c.item.label of
                                Just ( score, hits ) ->
                                    let
                                        matched =
                                            c.item
                                    in
                                    Just ( -(score * 10 + bonus c), { matched | hits = hits } )

                                Nothing ->
                                    if c.alt /= "" then
                                        fuzzy query c.alt |> Maybe.map (\( score, _ ) -> ( -(score * 5 + bonus c), c.item ))

                                    else
                                        Nothing
                    )
    in
    scored
        |> List.sortBy Tuple.first
        |> List.take maxResults
        |> List.map Tuple.second


{-| Fuzzy match: every letter of the query, in order, somewhere in the label.
Letters that follow each other, start words, or start the label score more.
Gives the score and the matched positions.
-}
fuzzy : String -> String -> Maybe ( Int, List Int )
fuzzy query label =
    if query == "" then
        Just ( 0, [] )

    else
        let
            chars =
                String.toList label

            lower =
                String.toList (String.toLower label)

            starts =
                List.map2
                    (\prev c -> isSeparator prev || (Char.isLower prev && Char.isUpper c))
                    (' ' :: chars)
                    chars

            step ( index, ( c, isStart ) ) acc =
                case acc.remaining of
                    q :: rest ->
                        if q == c then
                            { remaining = rest
                            , hits = index :: acc.hits
                            , score =
                                acc.score
                                    + 1
                                    + (if acc.last == index - 1 then
                                        5

                                       else
                                        0
                                      )
                                    + (if isStart then
                                        8

                                       else
                                        0
                                      )
                                    + (if index == 0 then
                                        10

                                       else
                                        0
                                      )
                            , last = index
                            }

                        else
                            acc

                    [] ->
                        acc

            result =
                List.foldl step
                    { remaining = String.toList query, hits = [], score = 0, last = -2 }
                    (List.indexedMap Tuple.pair (List.map2 Tuple.pair lower starts))
        in
        if List.isEmpty result.remaining then
            Just ( result.score * 4 - String.length label // 4, List.reverse result.hits )

        else
            Nothing


isSeparator : Char -> Bool
isSeparator c =
    List.member c [ ' ', '-', '_', '.', '/', '\\', '(', '[' ]
