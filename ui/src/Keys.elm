module Keys exposing
    ( Bound
    , KeyInfo
    , Keymap
    , UserBinding
    , empty
    , fromEvent
    , isChordStart
    , keysFor
    , lookup
    , parse
    )

{-| Key names and the key map (spec 6.10). Keys are written the way people
read them: `Ctrl+Shift+N`, `Alt+Left`, `Del`, and chords such as
`Ctrl+K Ctrl+B` (FR-KEY-02). Modifiers always come in the order Ctrl, Alt, Shift.
-}

import Dict exposing (Dict)


{-| A key press, as read from the browser event.
-}
type alias KeyInfo =
    { key : String
    , code : String
    , ctrl : Bool
    , shift : Bool
    , alt : Bool
    , target : String
    , targetId : String
    }


{-| A binding from keybindings.toml, before it is checked.
-}
type alias UserBinding =
    { key : String
    , command : String
    , when : String
    , args : Dict String String
    , line : Int
    }


{-| What a key runs: a command id, where it applies, and its arguments.
-}
type alias Bound =
    { command : String
    , when : String
    , args : Dict String String
    }


{-| Keys to commands, and commands to their keys (for menus and the palette).
-}
type alias Keymap =
    { byKey : Dict String (List Bound)
    , byCommand : Dict String (List String)
    }


empty : Keymap
empty =
    { byKey = Dict.empty, byCommand = Dict.empty }


{-| The name of a key press, or Nothing for a modifier key on its own.
Letters and digits come from the key's position (`code`), so Shift+1 is
`Shift+1` rather than `!`.
-}
fromEvent : KeyInfo -> Maybe String
fromEvent info =
    let
        base =
            if String.startsWith "Key" info.code && String.length info.code == 4 then
                Just (String.dropLeft 3 info.code)

            else if String.startsWith "Digit" info.code then
                Just (String.dropLeft 5 info.code)

            else if List.member info.key [ "Control", "Shift", "Alt", "Meta", "AltGraph", "CapsLock", "Dead", "Unidentified" ] then
                Nothing

            else if String.length info.key == 1 then
                Just (normalKey (String.toUpper info.key))

            else
                Just (normalKey info.key)
    in
    Maybe.map (withModifiers info.ctrl info.alt info.shift) base


withModifiers : Bool -> Bool -> Bool -> String -> String
withModifiers ctrl alt shift key =
    String.concat
        [ if ctrl then
            "Ctrl+"

          else
            ""
        , if alt then
            "Alt+"

          else
            ""
        , if shift then
            "Shift+"

          else
            ""
        , key
        ]


{-| Browser key names and common spellings, to the names File Catalog shows.
-}
normalKey : String -> String
normalKey key =
    case String.toLower key of
        "arrowleft" ->
            "Left"

        "left" ->
            "Left"

        "arrowright" ->
            "Right"

        "right" ->
            "Right"

        "arrowup" ->
            "Up"

        "up" ->
            "Up"

        "arrowdown" ->
            "Down"

        "down" ->
            "Down"

        "delete" ->
            "Del"

        "del" ->
            "Del"

        "escape" ->
            "Esc"

        "esc" ->
            "Esc"

        " " ->
            "Space"

        "space" ->
            "Space"

        "enter" ->
            "Enter"

        "return" ->
            "Enter"

        "tab" ->
            "Tab"

        "backspace" ->
            "Backspace"

        "insert" ->
            "Insert"

        "ins" ->
            "Insert"

        "home" ->
            "Home"

        "end" ->
            "End"

        "pageup" ->
            "PageUp"

        "pgup" ->
            "PageUp"

        "pagedown" ->
            "PageDown"

        "pgdn" ->
            "PageDown"

        "contextmenu" ->
            "ContextMenu"

        "menu" ->
            "ContextMenu"

        "browserback" ->
            "BrowserBack"

        "browserforward" ->
            "BrowserForward"

        "plus" ->
            "+"

        "backtick" ->
            "`"

        lower ->
            if String.length key == 1 then
                String.toUpper key

            else if String.startsWith "f" lower && (String.toInt (String.dropLeft 1 lower) |> Maybe.map (\n -> n >= 1 && n <= 24) |> Maybe.withDefault False) then
                String.toUpper lower

            else
                key


knownKey : String -> Bool
knownKey key =
    String.length key
        == 1
        || List.member key [ "Left", "Right", "Up", "Down", "Del", "Esc", "Space", "Enter", "Tab", "Backspace", "Insert", "Home", "End", "PageUp", "PageDown", "ContextMenu", "BrowserBack", "BrowserForward" ]
        || (String.startsWith "F" key && String.toInt (String.dropLeft 1 key) /= Nothing)


{-| Reads a key as written in keybindings.toml (any case, `Control` or
`Ctrl`, `Delete` or `Del`) and gives its standard name.
-}
parse : String -> Result String String
parse text =
    let
        strokes =
            String.words text
    in
    if List.isEmpty strokes then
        Err "the key is empty"

    else if List.length strokes > 2 then
        Err "a chord has at most two keys"

    else
        List.foldr (\stroke acc -> Result.map2 (::) (parseStroke stroke) acc) (Ok []) strokes
            |> Result.map (String.join " ")


parseStroke : String -> Result String String
parseStroke stroke =
    let
        -- "Ctrl++" names the + key.
        parts =
            if String.endsWith "++" stroke then
                String.split "+" (String.dropRight 2 stroke) ++ [ "+" ]

            else
                String.split "+" stroke

        modifiers =
            List.take (List.length parts - 1) parts |> List.map String.toLower

        key =
            List.drop (List.length parts - 1) parts |> List.head |> Maybe.withDefault "" |> normalKey

        has names =
            List.any (\m -> List.member m names) modifiers

        unknown =
            List.filter (\m -> not (List.member m [ "ctrl", "control", "cmd", "alt", "option", "shift" ])) modifiers
    in
    case unknown of
        bad :: _ ->
            Err ("\"" ++ bad ++ "\" is not a modifier key (use Ctrl, Alt or Shift)")

        [] ->
            if key == "" || not (knownKey key) then
                Err ("\"" ++ stroke ++ "\" is not a key name")

            else
                Ok (withModifiers (has [ "ctrl", "control", "cmd" ]) (has [ "alt", "option" ]) (has [ "shift" ]) key)


{-| The binding for a full key (one stroke, or a chord), preferring one made
for the current context over a global one (FR-KEY-03).
-}
lookup : String -> String -> Keymap -> Maybe Bound
lookup context key keymap =
    let
        candidates =
            Dict.get key keymap.byKey |> Maybe.withDefault []
    in
    case List.filter (\b -> b.when == context) candidates of
        bound :: _ ->
            Just bound

        [] ->
            List.filter (\b -> b.when == "global") candidates |> List.head


{-| True when some chord starts with this key.
-}
isChordStart : String -> Keymap -> Bool
isChordStart key keymap =
    Dict.keys keymap.byKey |> List.any (String.startsWith (key ++ " "))


keysFor : String -> Keymap -> List String
keysFor command keymap =
    Dict.get command keymap.byCommand |> Maybe.withDefault []
