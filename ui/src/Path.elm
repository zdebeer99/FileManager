module Path exposing (Crumb, crumbs, name, parent)

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
        case nonEmptyParts "\\" (String.dropLeft 2 path) of
            server :: share :: rest ->
                let
                    root =
                        "\\\\" ++ server ++ "\\" ++ share
                in
                { label = root, path = root } :: below "\\" root rest

            _ ->
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
