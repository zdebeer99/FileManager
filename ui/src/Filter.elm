module Filter exposing (Query, highlight, isEmpty, matches, parse)

{-| The Quick Filter syntax (FR-QF-02):

  - `contract draft` — every word must appear in the name (any case)
  - `*.pdf`, `report-??` — wildcards match the whole name
  - `!draft` — leave out names containing "draft"
  - `ext:pdf,docx` — only these extensions

-}

import Item exposing (Item)
import Regex exposing (Regex)


type Term
    = Contains String
    | Glob Regex
    | Ext (List String)


type alias Query =
    { include : List Term
    , exclude : List Term
    }


parse : String -> Query
parse text =
    List.foldr
        (\word query ->
            if String.startsWith "!" word && String.length word > 1 then
                { query | exclude = term (String.dropLeft 1 word) :: query.exclude }

            else
                { query | include = term word :: query.include }
        )
        { include = [], exclude = [] }
        (String.words (String.toLower text))


term : String -> Term
term word =
    if String.startsWith "ext:" word then
        Ext (String.dropLeft 4 word |> String.split "," |> List.map (dropDot << String.trim) |> List.filter ((/=) ""))

    else if String.contains "*" word || String.contains "?" word then
        Glob (globRegex word)

    else
        Contains word


dropDot : String -> String
dropDot s =
    if String.startsWith "." s then
        String.dropLeft 1 s

    else
        s


globRegex : String -> Regex
globRegex glob =
    let
        convert c =
            case c of
                '*' ->
                    ".*"

                '?' ->
                    "."

                _ ->
                    if String.contains (String.fromChar c) "\\^$.|+()[]{}" then
                        "\\" ++ String.fromChar c

                    else
                        String.fromChar c
    in
    Regex.fromStringWith { caseInsensitive = True, multiline = False }
        ("^" ++ String.concat (List.map convert (String.toList glob)) ++ "$")
        |> Maybe.withDefault Regex.never


isEmpty : Query -> Bool
isEmpty query =
    List.isEmpty query.include && List.isEmpty query.exclude


matches : Query -> Item -> Bool
matches query item =
    List.all (termMatches item) query.include && not (List.any (termMatches item) query.exclude)


termMatches : Item -> Term -> Bool
termMatches item t =
    case t of
        Contains word ->
            String.contains word item.lower

        Glob regex ->
            Regex.contains regex item.name

        Ext extensions ->
            List.member item.ext extensions


{-| Splits a name into parts, marking the parts that match the filter words (FR-QF-03).
-}
highlight : Query -> String -> List ( String, Bool )
highlight query name =
    let
        lower =
            String.toLower name

        ranges =
            query.include
                |> List.concatMap
                    (\t ->
                        case t of
                            Contains word ->
                                List.map (\start -> ( start, start + String.length word )) (String.indexes word lower)

                            _ ->
                                []
                    )
                |> List.sortBy Tuple.first
                |> merge
    in
    if List.isEmpty ranges then
        [ ( name, False ) ]

    else
        split name 0 ranges


merge : List ( Int, Int ) -> List ( Int, Int )
merge ranges =
    case ranges of
        ( a1, a2 ) :: ( b1, b2 ) :: rest ->
            if b1 <= a2 then
                merge (( a1, max a2 b2 ) :: rest)

            else
                ( a1, a2 ) :: merge (( b1, b2 ) :: rest)

        _ ->
            ranges


split : String -> Int -> List ( Int, Int ) -> List ( String, Bool )
split name from ranges =
    case ranges of
        ( start, end ) :: rest ->
            [ ( String.slice from start name, False ), ( String.slice start end name, True ) ]
                ++ split name end rest
                |> List.filter (\( text, _ ) -> text /= "")

        [] ->
            [ ( String.dropLeft from name, False ) ] |> List.filter (\( text, _ ) -> text /= "")
