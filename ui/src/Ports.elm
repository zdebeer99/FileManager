port module Ports exposing (fromBackend, toBackend)

{-| The only connection to the Rust backend (see static/bridge.js).
-}

import Json.Encode as E


port toBackend : E.Value -> Cmd msg


port fromBackend : (E.Value -> msg) -> Sub msg
