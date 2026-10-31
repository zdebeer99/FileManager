module Item exposing (Item, Kind(..), Sync(..), decoder, displayName, naturalKey, syncLabel, syncRank, typeLabel)

{-| A file, folder, shortcut or web link, as sent by the backend (spec 4.4).
-}

import Json.Decode as D


type Kind
    = Folder
    | File
    | Shortcut
    | WebLink


type Sync
    = SyncNone
    | SyncLocal
    | SyncPinned
    | SyncOnlineOnly
    | SyncSyncing
    | SyncError


type alias Item =
    { name : String
    , path : String
    , kind : Kind
    , isDir : Bool
    , size : Int
    , created : Maybe Int
    , modified : Maybe Int
    , accessed : Maybe Int
    , attributes : String
    , ext : String
    , hidden : Bool
    , readonly : Bool
    , sync : Sync
    , target : Maybe String

    -- Computed once when decoded, so sorting and filtering stay fast.
    , key : String
    , lower : String
    }


decoder : D.Decoder Item
decoder =
    D.succeed build
        |> andMap (D.field "name" D.string)
        |> andMap (D.field "path" D.string)
        |> andMap (D.field "kind" kindDecoder)
        |> andMap (D.field "isDir" D.bool)
        |> andMap (D.field "size" D.int)
        |> andMap (D.field "created" (D.nullable D.int))
        |> andMap (D.field "modified" (D.nullable D.int))
        |> andMap (D.field "accessed" (D.nullable D.int))
        |> andMap (D.field "attributes" D.string)
        |> andMap (D.field "ext" D.string)
        |> andMap (D.field "hidden" D.bool)
        |> andMap (D.field "readonly" D.bool)
        |> andMap (D.field "sync" syncDecoder)
        |> andMap (D.field "target" (D.nullable D.string))


build : String -> String -> Kind -> Bool -> Int -> Maybe Int -> Maybe Int -> Maybe Int -> String -> String -> Bool -> Bool -> Sync -> Maybe String -> Item
build name path kind isDir size created modified accessed attributes ext hidden readonly sync target =
    { name = name
    , path = path
    , kind = kind
    , isDir = isDir
    , size = size
    , created = created
    , modified = modified
    , accessed = accessed
    , attributes = attributes
    , ext = ext
    , hidden = hidden
    , readonly = readonly
    , sync = sync
    , target = target
    , key = naturalKey name
    , lower = String.toLower name
    }


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


kindDecoder : D.Decoder Kind
kindDecoder =
    D.string
        |> D.map
            (\s ->
                case s of
                    "folder" ->
                        Folder

                    "shortcut" ->
                        Shortcut

                    "weblink" ->
                        WebLink

                    _ ->
                        File
            )


syncDecoder : D.Decoder Sync
syncDecoder =
    D.string
        |> D.map
            (\s ->
                case s of
                    "local" ->
                        SyncLocal

                    "pinned" ->
                        SyncPinned

                    "onlineOnly" ->
                        SyncOnlineOnly

                    "syncing" ->
                        SyncSyncing

                    "error" ->
                        SyncError

                    _ ->
                        SyncNone
            )


{-| A key that sorts names naturally and ignoring case: "File 2" before
"File 10". Digit runs are zero-padded so a plain string compare works.
-}
naturalKey : String -> String
naturalKey name =
    let
        flush digits acc =
            if List.isEmpty digits then
                acc

            else
                List.reverse (String.toList (String.padLeft 20 '0' (String.fromList (List.reverse digits)))) ++ acc

        step c ( acc, digits ) =
            if Char.isDigit c then
                ( acc, c :: digits )

            else
                ( c :: flush digits acc, [] )

        ( done, rest ) =
            String.foldl step ( [], [] ) (String.toLower name)
    in
    String.fromList (List.reverse (flush rest done))


displayName : Bool -> Item -> String
displayName showExtensions item =
    if showExtensions || item.isDir || item.ext == "" then
        item.name

    else
        String.dropRight (String.length item.ext + 1) item.name


typeLabel : Item -> String
typeLabel item =
    case item.kind of
        Folder ->
            "File folder"

        Shortcut ->
            "Shortcut"

        WebLink ->
            "Internet shortcut"

        File ->
            if item.ext == "" then
                "File"

            else
                String.toUpper item.ext ++ " File"


syncRank : Sync -> Int
syncRank sync =
    case sync of
        SyncNone ->
            0

        SyncLocal ->
            1

        SyncPinned ->
            2

        SyncOnlineOnly ->
            3

        SyncSyncing ->
            4

        SyncError ->
            5


syncLabel : Sync -> String
syncLabel sync =
    case sync of
        SyncNone ->
            ""

        SyncLocal ->
            "Available on this device"

        SyncPinned ->
            "Always keep on this device"

        SyncOnlineOnly ->
            "Online-only"

        SyncSyncing ->
            "Syncing"

        SyncError ->
            "Sync problem"
