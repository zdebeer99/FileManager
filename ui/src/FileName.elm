module FileName exposing (extension, selection, validate)

{-| Name checks while renaming or creating items (FR-REN-02). The backend
checks again before it changes anything.
-}

import Text


{-| An error message, or Nothing when the name can be used. `others` are the
names of the other items in the folder.
-}
validate : Bool -> List String -> String -> Maybe String
validate windows others name =
    let
        invalid =
            if windows then
                String.toList "<>:\"/\\|?*"

            else
                [ '/' ]

        badChar =
            String.toList name |> List.filter (\c -> List.member c invalid || Char.toCode c < 32) |> List.head

        stem =
            String.split "." name |> List.head |> Maybe.withDefault "" |> String.trimRight |> String.toUpper

        reserved =
            [ "CON", "PRN", "AUX", "NUL" ]
                ++ List.map (\n -> "COM" ++ String.fromInt n) (List.range 1 9)
                ++ List.map (\n -> "LPT" ++ String.fromInt n) (List.range 1 9)

        same a b =
            if windows then
                String.toLower a == String.toLower b

            else
                a == b
    in
    if String.trim name == "" then
        Just Text.nameEmpty

    else if name == "." || name == ".." then
        Just Text.nameReserved

    else
        case badChar of
            Just c ->
                Just (Text.nameBadChar (String.fromChar c))

            Nothing ->
                if String.length name > 255 then
                    Just Text.nameTooLong

                else if windows && List.member stem reserved then
                    Just (Text.nameReservedWindows stem)

                else if windows && (String.endsWith "." name || String.endsWith " " name) then
                    Just Text.nameTrailing

                else if List.any (same name) others then
                    Just (Text.nameTaken name)

                else
                    Nothing


{-| The extension including the dot, or "" (folders and dot-files have none).
-}
extension : String -> String
extension name =
    case List.reverse (String.indexes "." name) of
        last :: _ ->
            if last > 0 then
                String.dropLeft last name

            else
                ""

        [] ->
            ""


{-| The text range to select for each F2 press (FR-REN-01): the name without
its extension, then the whole name, then the extension only.
-}
selection : Bool -> Int -> String -> ( Int, Int )
selection isDir step name =
    let
        length =
            String.length name

        dot =
            if isDir then
                length

            else
                length - String.length (extension name)
    in
    case modBy 3 step of
        0 ->
            ( 0, dot )

        1 ->
            ( 0, length )

        _ ->
            ( min length (dot + 1), length )
