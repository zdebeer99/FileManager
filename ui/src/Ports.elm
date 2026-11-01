port module Ports exposing (fromBackend, selectText, toBackend)

{-| The connection to the Rust backend (see static/bridge.js), plus one
text-selection helper Elm can't do by itself.
-}

import Json.Encode as E


port toBackend : E.Value -> Cmd msg


port fromBackend : (E.Value -> msg) -> Sub msg


{-| Focuses a text box and selects `{ id, start, end }` after the next redraw.
-}
port selectText : E.Value -> Cmd msg
