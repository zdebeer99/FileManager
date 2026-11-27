module Path exposing (Crumb, crumbs, isInside, name, parent, samePath)

{-| Paths are kept as the strings the backend uses: `C:\Vendors\Acme`,
`\\server\share\Docs` or `/home/user/Docs`, with no trailing separator.
-}


type alias Crumb =
    { label : String
    , path : String
    }


{-| The Address Bar segments of a path, root first.
-}
crumbs : String -> String -> List Crumb
crumbs sep path =
    if sep == "/" then
        let
            parts =
                nonEmptyParts "/" path
        in
        { label = "/", path = "/" } :: below "/" "" parts

    else if String.startsWith "\\\\" path then
        -- A network computer, then its share (REQ-037): Up from a share lists
        -- the computer's shared folders.
        case nonEmptyParts "\\" (String.dropLeft 2 path) of
            server :: share :: rest ->
                let
                    computer =
                        "\\\\" ++ server

                    root =
                        computer ++ "\\" ++ share
                in
                { label = computer, path = computer } :: { label = share, path = root } :: below "\\" root rest

            [ server ] ->
                [ { label = "\\\\" ++ server, path = "\\\\" ++ server } ]

            [] ->
                [ { label = path, path = path } ]

    else
        case nonEmptyParts "\\" path of
            drive :: rest ->
                { label = drive, path = drive ++ "\\" } :: below "\\" drive rest

            [] ->
                []


below : String -> String -> List String -> List Crumb
below sep root parts =
    List.indexedMap
        (\i part ->
            { label = part
            , path = root ++ sep ++ String.join sep (List.take (i + 1) parts)
            }
        )
        parts


nonEmptyParts : String -> String -> List String
nonEmptyParts sep path =
    String.split sep path |> List.filter (not << String.isEmpty)


parent : String -> String -> Maybe String
parent sep path =
    case List.reverse (crumbs sep path) of
        _ :: up :: _ ->
            Just up.path

        _ ->
            Nothing


{-| The last segment: the folder's own name, or the root itself.
-}
name : String -> String -> String
name sep path =
    crumbs sep path
        |> List.reverse
        |> List.head
        |> Maybe.map .label
        |> Maybe.withDefault path


{-| Whether two paths name the same folder. Windows paths ignore case.
-}
samePath : String -> String -> String -> Bool
samePath sep a b =
    if sep == "\\" then
        String.toLower a == String.toLower b

    else
        a == b


{-| Whether `path` is `folder` or inside it.
-}
isInside : String -> String -> String -> Bool
isInside sep folder path =
    let
        fold =
            if sep == "\\" then
                String.toLower

            else
                identity

        f =
            fold folder

        withSep =
            if String.endsWith sep f then
                f

            else
                f ++ sep
    in
    fold path == f || String.startsWith withSep (fold path)
