module View.Keyboard exposing (keyDecoder, mouseNavDecoder)

{-| Keyboard and mouse-button routing (spec 6.10): which keys the app handles, in which context.
-}

import Commands
import Json.Decode as D
import Keys
import Types exposing (..)


mouseNavDecoder : D.Decoder Msg
mouseNavDecoder =
    D.field "button" D.int
        |> D.andThen
            (\b ->
                case b of
                    3 ->
                        D.succeed (KeyCommand CmdBack)

                    4 ->
                        D.succeed (KeyCommand CmdForward)

                    _ ->
                        D.fail "other button"
            )


{-| Key presses anywhere in the window (spec 6.10). Bound keys run their
command; a key that starts a chord waits for the second key (FR-KEY-02).
Text boxes keep their typing keys, and focused buttons keep plain keys such
as Enter and Space.
-}
keyDecoder : Model -> D.Decoder ( Msg, Bool )
keyDecoder model =
    D.map7 Keys.KeyInfo
        (D.field "key" D.string)
        (D.oneOf [ D.field "code" D.string, D.succeed "" ])
        (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
        (D.field "shiftKey" D.bool)
        (D.field "altKey" D.bool)
        (D.at [ "target", "tagName" ] D.string)
        (D.oneOf [ D.at [ "target", "id" ] D.string, D.succeed "" ])
        |> D.andThen (decideKey model)


decideKey : Model -> Keys.KeyInfo -> D.Decoder ( Msg, Bool )
decideKey model info =
    let
        stroke =
            Keys.fromEvent info

        inInput =
            info.target == "INPUT" || info.target == "TEXTAREA"

        plain =
            not info.ctrl && not info.alt && not (String.startsWith "F" info.key && String.length info.key > 1)

        context =
            keyContext model info

        full =
            case ( model.chord, stroke ) of
                ( Just first, Just s ) ->
                    Just (first ++ " " ++ s)

                ( Nothing, s ) ->
                    s

                _ ->
                    Nothing

        bound =
            full
                |> Maybe.andThen (\k -> Keys.lookup context k model.keymap)
                |> Maybe.andThen (\b -> Commands.fromBinding b.command b.args |> Maybe.map (\c -> ( b, c )))

        -- In a text box only keys made for it, or Ctrl/Alt/F-keys that don't edit text, run commands.
        allowedHere b s =
            if inInput then
                b.when == context || (not plain && not (List.member s textEditingKeys))

            else
                not (info.target == "BUTTON" && plain)
    in
    case ( recording model, stroke ) of
        ( True, Just s ) ->
            D.succeed ( KeyRecorded s, True )

        ( True, Nothing ) ->
            D.fail "a modifier key on its own"

        ( False, _ ) ->
            if ownsKeys model then
                if info.key == "Escape" then
                    D.succeed ( DialogCancel, True )

                else
                    D.fail "the dialog handles this key"

            else if info.key == "Alt" then
                D.succeed ( AltDown, False )

            else if model.menuBar /= Nothing then
                case builtinKey info of
                    Just command ->
                        D.succeed ( KeyCommand command, True )

                    Nothing ->
                        D.succeed ( KeyOther, False )

            else
                case ( bound, stroke ) of
                    ( Just ( b, command ), Just s ) ->
                        if allowedHere b s then
                            D.succeed ( KeyCommand command, True )

                        else
                            D.fail "the focused control handles this key"

                    _ ->
                        case ( model.chord, stroke ) of
                            ( Just _, Just "Esc" ) ->
                                D.succeed ( KeyOther, True )

                            ( Just _, Just _ ) ->
                                D.succeed ( KeyChordMiss (Maybe.withDefault "" full), True )

                            ( Nothing, Just s ) ->
                                if Keys.isChordStart s model.keymap && not (inInput && plain) then
                                    D.succeed ( KeyChord s, True )

                                else if inInput || (info.target == "BUTTON" && plain) then
                                    D.fail "the focused control handles this key"

                                else
                                    case builtinKey info of
                                        Just command ->
                                            D.succeed ( KeyCommand command, True )

                                        Nothing ->
                                            D.succeed ( KeyOther, False )

                            _ ->
                                D.fail "a modifier key on its own"


{-| Where the key was pressed, for bindings with a `when` (FR-KEY-03).
-}
keyContext : Model -> Keys.KeyInfo -> String
keyContext model info =
    if info.targetId == paletteInputId then
        "palette"

    else if info.targetId == filterInputId then
        "filter"

    else if info.targetId == addressInputId then
        "addressBar"

    else if model.region == RegionSidebar && sidebarModeFromString model.settings.sidebarMode == TreeMode then
        "tree"

    else
        "list"


{-| Keys that edit text, kept by text boxes even when a command uses them.
-}
textEditingKeys : List String
textEditingKeys =
    [ "Ctrl+A", "Ctrl+C", "Ctrl+V", "Ctrl+X", "Ctrl+Z", "Ctrl+Y", "Ctrl+Shift+Z", "Ctrl+Left", "Ctrl+Right", "Ctrl+Shift+Left", "Ctrl+Shift+Right", "Ctrl+Backspace", "Ctrl+Del", "Ctrl+Home", "Ctrl+End", "Ctrl+Shift+Home", "Ctrl+Shift+End" ]


recording : Model -> Bool
recording model =
    case model.dialog of
        Just (ShortcutsDialog s) ->
            s.recording /= Nothing

        _ ->
            False


{-| Dialogs that keep keys from the window, so typing in them never runs a command.
-}
ownsKeys : Model -> Bool
ownsKeys model =
    case model.dialog of
        Just (ShortcutsDialog _) ->
            True

        Just (ToolbarDialog _) ->
            True

        _ ->
            False


{-| Keys that move the cursor and selection, and the menu mnemonics. They
are not bindable; every other key comes from the key map.
-}
builtinKey : Keys.KeyInfo -> Maybe Command
builtinKey { key, ctrl, shift, alt } =
    let
        k =
            if String.length key == 1 then
                String.toLower key

            else
                key
    in
    case ( k, ctrl, alt ) of
        ( "Enter", False, False ) ->
            Just CmdOpen

        ( "ArrowDown", _, False ) ->
            Just (CmdMove 1 shift ctrl)

        ( "ArrowUp", _, False ) ->
            Just (CmdMove -1 shift ctrl)

        ( "ArrowLeft", False, False ) ->
            Just CmdLeft

        ( "ArrowRight", False, False ) ->
            Just CmdRight

        ( "PageDown", _, False ) ->
            Just (CmdPage 1 shift ctrl)

        ( "PageUp", _, False ) ->
            Just (CmdPage -1 shift ctrl)

        ( "Home", _, False ) ->
            Just (CmdEdge False shift)

        ( "End", _, False ) ->
            Just (CmdEdge True shift)

        ( " ", True, False ) ->
            Just CmdToggleSelect

        ( "Escape", _, _ ) ->
            Just CmdEscape

        _ ->
            if alt && not ctrl then
                List.indexedMap Tuple.pair [ "f", "e", "v", "g", "b", "t", "w", "h" ]
                    |> List.filter (\( _, letter ) -> letter == k)
                    |> List.head
                    |> Maybe.map (\( i, _ ) -> CmdMenuMnemonic i)

            else if String.length key == 1 && not ctrl && not alt then
                Just (CmdTypeahead key)

            else
                Nothing
