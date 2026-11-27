module SettingsPage exposing (Field, Kind(..), sections)

{-| The settings page (spec 8.3, REQ-038): which settings.toml values it
shows, in which section, and how each is edited. Labels and help texts are in
`Text.settingLabel` and `Text.settingHelp`, by the same dotted keys.
-}


type Kind
    = Toggle
    | Choice (List String)
    | TextValue
    | Number
      -- A list of strings, one per line.
    | Lines


type alias Field =
    { key : String
    , kind : Kind
    }


sections : List ( String, List Field )
sections =
    [ ( "general"
      , [ Field "general.theme" (Choice [ "system", "light", "dark" ])
        , Field "general.style" (Choice [ "studio", "typewriter", "explorer", "modern" ])
        , Field "general.startupFolder" TextValue
        , Field "general.restoreTabs" Toggle
        , Field "general.homeFolder" TextValue
        , Field "general.confirmDelete" Toggle
        , Field "general.confirmExtensionChange" Toggle
        , Field "general.keepFilterOnNavigate" Toggle
        , Field "general.terminal" TextValue
        ]
      )
    , ( "layout"
      , [ Field "layout.style" (Choice [ "browser", "classic" ])
        , Field "layout.systemTitleBar" Toggle
        , Field "layout.bookmarkBar" Toggle
        , Field "layout.statusBar" Toggle
        , Field "layout.sidebar.visible" Toggle
        , Field "layout.sidebar.side" (Choice [ "left", "right" ])
        , Field "layout.menuBar" Toggle
        , Field "layout.toolbar" Toggle
        , Field "layout.tabBar" Toggle
        , Field "layout.addressBar" Toggle
        ]
      )
    , ( "view"
      , [ Field "view.default.foldersFirst" Toggle
        , Field "view.default.showHidden" Toggle
        , Field "view.default.showExtensions" Toggle
        , Field "view.default.icons" (Choice [ "system", "builtin" ])
        , Field "view.default.dateFormat" TextValue
        ]
      )
    , ( "search"
      , [ Field "search.includeHidden" Toggle
        , Field "search.followLinks" Toggle
        , Field "search.skipOnlineOnlyFolders" Toggle
        , Field "search.maxDepth" Number
        , Field "search.maxResults" Number
        ]
      )
    , ( "editor"
      , [ Field "editor.command" TextValue
        , Field "editor.name" TextValue
        , Field "editor.args" Lines
        ]
      )
    , ( "templates"
      , [ Field "templates.folders" Lines
        , Field "templates.dateFormat" TextValue
        ]
      )
    , ( "network"
      , [ Field "network.timeoutSeconds" Number ]
      )
    ]
