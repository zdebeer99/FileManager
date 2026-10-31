module Settings exposing (Settings, decoder, default)

{-| The parts of settings.toml the UI uses (spec 8.3). The backend always
sends every field, filled in with defaults.
-}

import Json.Decode as D


type alias Settings =
    { theme : String
    , startupFolder : String
    , restoreTabs : Bool
    , keepFilterOnNavigate : Bool
    , menuBar : Bool
    , toolbar : Bool
    , bookmarkBar : Bool
    , tabBar : Bool
    , addressBar : Bool
    , statusBar : Bool
    , sidebarVisible : Bool
    , sidebarSide : String
    , sidebarWidth : Float
    , sidebarMode : String
    , columns : List String

    -- (column, descending)
    , sort : List ( String, Bool )
    , foldersFirst : Bool
    , showHidden : Bool
    , showExtensions : Bool
    , dateFormat : String
    }


default : Settings
default =
    { theme = "system"
    , startupFolder = "last"
    , restoreTabs = True
    , keepFilterOnNavigate = False
    , menuBar = True
    , toolbar = True
    , bookmarkBar = True
    , tabBar = True
    , addressBar = True
    , statusBar = True
    , sidebarVisible = True
    , sidebarSide = "left"
    , sidebarWidth = 260
    , sidebarMode = "tree"
    , columns = [ "name", "modified", "created", "size", "sync" ]
    , sort = [ ( "name", False ) ]
    , foldersFirst = True
    , showHidden = False
    , showExtensions = True
    , dateFormat = "yyyy-MM-dd HH:mm"
    }


decoder : D.Decoder Settings
decoder =
    let
        general field =
            D.at [ "general", field ]

        layout field =
            D.at [ "layout", field ] D.bool

        sidebar field =
            D.at [ "layout", "sidebar", field ]

        view field =
            D.at [ "view", "default", field ]
    in
    D.succeed Settings
        |> andMap (general "theme" D.string)
        |> andMap (general "startupFolder" D.string)
        |> andMap (general "restoreTabs" D.bool)
        |> andMap (general "keepFilterOnNavigate" D.bool)
        |> andMap (layout "menuBar")
        |> andMap (layout "toolbar")
        |> andMap (layout "bookmarkBar")
        |> andMap (layout "tabBar")
        |> andMap (layout "addressBar")
        |> andMap (layout "statusBar")
        |> andMap (sidebar "visible" D.bool)
        |> andMap (sidebar "side" D.string)
        |> andMap (sidebar "width" D.float)
        |> andMap (sidebar "mode" D.string)
        |> andMap (view "columns" (D.list D.string))
        |> andMap (view "sort" (D.list sortKeyDecoder))
        |> andMap (view "foldersFirst" D.bool)
        |> andMap (view "showHidden" D.bool)
        |> andMap (view "showExtensions" D.bool)
        |> andMap (view "dateFormat" D.string)


sortKeyDecoder : D.Decoder ( String, Bool )
sortKeyDecoder =
    D.map2 (\column direction -> ( column, direction == "desc" ))
        (D.field "column" D.string)
        (D.field "direction" D.string)


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)
