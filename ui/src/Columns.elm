module Columns exposing
    ( Column(..)
    , available
    , defaultWidth
    , filterValue
    , fromString
    , isDate
    , isRight
    , sizeBucketOrder
    , sortKey
    , title
    , toString
    )

{-| The Details view columns (spec 5.8.2): names, widths, and the keys used
to sort them and to group them in column filters.
-}

import Format
import Item exposing (Item)
import Time


type Column
    = Name
    | Modified
    | Created
    | Accessed
    | Size
    | Type
    | Ext
    | Attributes
    | LinkTarget
    | Sync
      -- Search results only: the folder relative to the search root (FR-FIND-01).
    | Folder


{-| Every column that can be shown, in the order the column chooser lists them.
-}
available : Bool -> List Column
available syncSupported =
    [ Name, Modified, Created, Accessed, Size, Type, Ext, Attributes, LinkTarget ]
        ++ (if syncSupported then
                [ Sync ]

            else
                []
           )


toString : Column -> String
toString column =
    case column of
        Name ->
            "name"

        Modified ->
            "modified"

        Created ->
            "created"

        Accessed ->
            "accessed"

        Size ->
            "size"

        Type ->
            "type"

        Ext ->
            "ext"

        Attributes ->
            "attributes"

        LinkTarget ->
            "linkTarget"

        Sync ->
            "sync"

        Folder ->
            "folder"


fromString : String -> Maybe Column
fromString s =
    case s of
        "name" ->
            Just Name

        "modified" ->
            Just Modified

        "created" ->
            Just Created

        "accessed" ->
            Just Accessed

        "size" ->
            Just Size

        "type" ->
            Just Type

        "ext" ->
            Just Ext

        "attributes" ->
            Just Attributes

        "linkTarget" ->
            Just LinkTarget

        "sync" ->
            Just Sync

        "folder" ->
            Just Folder

        _ ->
            Nothing


title : Column -> String
title column =
    case column of
        Name ->
            "Name"

        Modified ->
            "Date modified"

        Created ->
            "Date created"

        Accessed ->
            "Date accessed"

        Size ->
            "Size"

        Type ->
            "Type"

        Ext ->
            "Extension"

        Attributes ->
            "Attributes"

        LinkTarget ->
            "Link target"

        Sync ->
            "Sync"

        Folder ->
            "Folder"


defaultWidth : Column -> Float
defaultWidth column =
    case column of
        Name ->
            320

        Size ->
            90

        Type ->
            130

        Ext ->
            80

        Attributes ->
            90

        LinkTarget ->
            260

        Sync ->
            56

        Folder ->
            240

        _ ->
            140


isRight : Column -> Bool
isRight column =
    column == Size


isDate : Column -> Bool
isDate column =
    column == Modified || column == Created || column == Accessed


{-| A string that sorts the column correctly with a plain comparison.
-}
sortKey : Column -> Item -> String
sortKey column item =
    case column of
        Name ->
            item.key

        Modified ->
            timeKey item.modified

        Created ->
            timeKey item.created

        Accessed ->
            timeKey item.accessed

        Size ->
            String.padLeft 16 '0' (String.fromInt item.size)

        Type ->
            String.toLower (Item.typeLabel item)

        Ext ->
            item.ext

        Attributes ->
            item.attributes

        LinkTarget ->
            String.toLower (Maybe.withDefault "" item.target)

        Sync ->
            String.fromInt (Item.syncRank item.sync)

        Folder ->
            String.toLower item.folder


timeKey : Maybe Int -> String
timeKey millis =
    String.padLeft 15 '0' (String.fromInt (max 0 (Maybe.withDefault 0 millis)))


{-| The value an item is grouped under in the column's filter drop-down (FR-CF-01).
-}
filterValue : Time.Zone -> Column -> Item -> String
filterValue zone column item =
    let
        day millis =
            Maybe.map (Format.date "yyyy-MM-dd" zone) millis |> Maybe.withDefault "(no date)"
    in
    case column of
        Name ->
            item.name

        Modified ->
            day item.modified

        Created ->
            day item.created

        Accessed ->
            day item.accessed

        Size ->
            if item.isDir then
                "(folders)"

            else
                sizeBucket item.size

        Type ->
            Item.typeLabel item

        Ext ->
            if item.ext == "" then
                "(none)"

            else
                item.ext

        Attributes ->
            if item.attributes == "" then
                "(none)"

            else
                item.attributes

        LinkTarget ->
            Maybe.withDefault "(none)" item.target

        Sync ->
            case Item.syncLabel item.sync of
                "" ->
                    "(not synced)"

                label ->
                    label

        Folder ->
            if item.folder == "" then
                "(top folder)"

            else
                item.folder


sizeBuckets : List ( Int, String )
sizeBuckets =
    [ ( 0, "Empty" )
    , ( 16 * 1024 - 1, "< 16 KB" )
    , ( 1024 * 1024 - 1, "16 KB – 1 MB" )
    , ( 16 * 1024 * 1024 - 1, "1 – 16 MB" )
    , ( 128 * 1024 * 1024 - 1, "16 – 128 MB" )
    ]


sizeBucket : Int -> String
sizeBucket bytes =
    sizeBuckets
        |> List.filter (\( limit, _ ) -> bytes <= limit)
        |> List.head
        |> Maybe.map Tuple.second
        |> Maybe.withDefault "> 128 MB"


{-| Position of a size bucket label, so buckets list small to large.
-}
sizeBucketOrder : String -> Int
sizeBucketOrder label =
    (List.map Tuple.second sizeBuckets ++ [ "> 128 MB", "(folders)" ])
        |> List.indexedMap Tuple.pair
        |> List.filter (\( _, l ) -> l == label)
        |> List.head
        |> Maybe.map Tuple.first
        |> Maybe.withDefault 99
