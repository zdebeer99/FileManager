module Types exposing (..)

{-| The application state and messages, shared by Main (update) and View.
-}

import Array exposing (Array)
import Browser.Dom as Dom
import Columns exposing (Column)
import Dict exposing (Dict)
import Item exposing (Item)
import Json.Decode as D
import Keys exposing (Keymap, UserBinding)
import Path
import Set exposing (Set)
import Settings exposing (Settings)
import Time



-- TABS


{-| How a folder is shown (FR-VIEW-01). Saved per folder with Save View.
-}
type alias FolderView =
    { columns : List ( Column, Float )

    -- (column, descending); the first is the main sort, the second breaks ties.
    , sort : List ( Column, Bool )
    , foldersFirst : Bool
    , showHidden : Bool
    }


type Status
    = Idle
    | Loading
    | Loaded
    | Failed String String


type alias Tab =
    { id : Int
    , path : String
    , back : List String
    , forward : List String

    -- Every item by name; all items in sort order; the items shown after filters.
    , items : Dict String Item
    , ordered : List Item
    , visible : Array Item
    , hiddenCount : Int
    , folderCount : Int

    -- Items that would be shown without the Quick Filter and column filters.
    , unfilteredCount : Int
    , status : Status

    -- The dir_list request whose results this tab accepts.
    , req : Int
    , chunks : Int

    -- Selected item names.
    , selected : Set String
    , cursor : Int
    , anchor : Int
    , scrollTop : Float
    , view : FolderView

    -- The saved (or default) view, to show when the current view has changes.
    , savedView : FolderView

    -- The folder whose saved view applies; Nothing means the default view.
    , viewSource : Maybe String
    , filter : String

    -- Column name -> the values left checked in its filter drop-down.
    , columnFilters : Dict String (Set String)

    -- Name of the item to select once the listing is loaded (FR-NAV-03).
    , pendingSelect : Maybe String

    -- Set for a Quick Find results tab (FR-FIND-01); `path` is the search root.
    , search : Maybe Search
    }


{-| A Quick Find search and its progress (FR-FIND-03).
-}
type alias Search =
    { query : String

    -- The find_start request; also the id used to cancel it.
    , id : Int
    , running : Bool
    , scanned : Int
    , found : Int
    , truncated : Bool
    , cancelled : Bool
    , millis : Int

    -- Locate…: the missing bookmark the chosen result becomes the new target of (FR-BM-03).
    , relink : Maybe Bookmark
    }



-- BACKEND REQUESTS


type Request
    = ReqInit
    | ReqList Int
    | ReqView Int String
    | ReqResolve Int
    | ReqSubfolders SubfolderUse
    | ReqFreeSpace String
    | ReqBookmarks
    | ReqBookmarkEdit
    | ReqViewSaved Int String
    | ReqViewReset Int String
    | ReqOpenSettingsFile
    | ReqOpen
    | ReqIgnore
    | ReqJobStart
    | ReqRename Int
    | ReqCreate Int Bool
    | ReqUndo
    | ReqCopied String
    | ReqTemplates
    | ReqTemplatesFolder (Maybe (List String))
    | ReqClipboard Bool
    | ReqShortcuts Int
    | ReqFind Int
    | ReqKeybindings
    | ReqToolbar
    | ReqOpenReturnedFile
    | ReqLocate Bookmark


type SubfolderUse
    = ForCrumb String
    | ForComplete String
    | ForTree String
    | ForPalette String



-- MENUS AND POPUPS


type MenuEntry
    = Action { label : String, key : String, msg : Maybe Msg, checked : Maybe Bool }
    | Submenu String (List MenuEntry)
    | Separator


{-| The open Menu Bar menu, the highlighted entry and, inside a submenu,
the highlighted submenu entry.
-}
type alias MenuBarState =
    { index : Int
    , active : Int
    , sub : Maybe Int
    }


type Popup
    = MenuPopup { x : Float, y : Float, entries : List MenuEntry }
    | ColumnFilterPopup ColumnFilterState


type alias ColumnFilterState =
    { column : Column
    , x : Float
    , y : Float
    , search : String

    -- Every value in the column with its item count, in display order.
    , values : List ( String, Int )
    , checked : Set String
    , now : Time.Posix

    -- Size column: a custom "between" range, as typed (FR-CF-01).
    , rangeFrom : String
    , rangeTo : String
    }


type Dialog
    = BookmarkDialog BookmarkForm
    | NewItemDialog NewItemForm
    | ConfirmDialog Confirm
    | ShortcutsDialog ShortcutsState
    | ToolbarDialog ToolbarForm


{-| Help › Keyboard Shortcuts (FR-KEY-04).
-}
type alias ShortcutsState =
    { search : String

    -- The command whose new key is being recorded, and the keys pressed so far.
    , recording : Maybe { command : String, strokes : List String, seq : Int }

    -- A recorded key waiting for Save, with the command it would be taken from.
    , proposal : Maybe { command : String, key : String }
    }


{-| Customise Toolbar (FR-TB-02).
-}
type alias ToolbarForm =
    { style : String
    , items : List String
    , active : Int
    , search : String
    }


{-| The toolbar from toolbar.toml (FR-TB-01).
-}
type alias ToolbarConfig =
    { style : String
    , items : List String
    , defaults : List String
    , file : String
    }



-- COMMAND PALETTE


{-| The command palette (spec 6.9). The first character of `text` picks the mode.
-}
type alias Palette =
    { text : String
    , active : Int
    , results : List PaletteItem

    -- Path mode: the folder whose sub-folders are in `subfolders`.
    , listed : String
    , subfolders : List Path.Crumb
    }


type alias PaletteItem =
    { label : String
    , detail : String
    , key : String
    , icon : String

    -- Positions of the matched letters in `label` (FR-CMD-03).
    , hits : List Int
    , action : PaletteAction
    }


type PaletteAction
    = PalCommand String Command
    | PalFolder String
    | PalFile String
    | PalBookmark Bookmark
    | PalTab Int
    | PalFind String


type NewKind
    = NewFile
    | NewShortcut
    | NewWebLink
    | NewFromTemplate String


{-| A template from the templates folder (spec 6.8).
-}
type alias Template =
    { name : String
    , path : String
    , isDir : Bool
    , group : List String
    , needsName : Bool
    }


{-| Where dragged items can be dropped (FR-COPY-06, FR-BB-03).
-}
type DropTarget
    = DropFolder String
    | DropBookmarkBar


type alias DragState =
    { paths : List String
    , names : List String
    , startX : Float
    , startY : Float
    , x : Float
    , y : Float
    , moved : Bool
    , target : Maybe DropTarget
    }


{-| Modifier keys when the mouse button is released.
-}
type alias DropMods =
    { ctrl : Bool
    , shift : Bool
    , alt : Bool

    -- The `data-drop` value of the element under the pointer, if any.
    , under : Maybe String
    }


type alias NewItemForm =
    { kind : NewKind
    , name : String
    , target : String
    , error : Maybe String
    }


{-| A yes/no question. `onConfirm` runs when the user agrees.
-}
type alias Confirm =
    { title : String
    , lines : List String
    , confirmLabel : String
    , onConfirm : Msg
    , danger : Bool
    }



-- FILE OPERATIONS


{-| Progress of a background job, as sent by the backend (FR-OP-03).
-}
type alias JobStatus =
    { id : Int
    , kind : String
    , state : String
    , permanent : Bool
    , count : Int
    , first : String
    , dest : Maybe String
    , doneItems : Int
    , totalItems : Int
    , doneBytes : Int
    , totalBytes : Int
    , current : String
    , elapsedMs : Int
    , errors : List JobError
    }


type alias JobError =
    { path : String

    -- The folder the item was going into, for Retry (FR-OP-04).
    , dest : Maybe String
    , message : String
    , code : String
    }


type alias FileInfo =
    { name : String
    , path : String
    , size : Int
    , modified : Maybe Int
    , isDir : Bool
    }


{-| A name conflict a job is waiting on (FR-COPY-04).
-}
type alias Conflict =
    { jobId : Int
    , source : FileInfo
    , target : FileInfo
    , applyToAll : Bool
    }


{-| In-place rename (FR-REN-01). `step` counts F2 presses.
-}
type alias RenameState =
    { tabId : Int

    -- The item's id in its tab (Item.id).
    , key : String
    , original : String
    , text : String
    , error : Maybe String
    , step : Int
    }


{-| Items cut or copied inside File Catalog.
-}
type alias Clipboard =
    { paths : List String
    , cut : Bool
    }


type alias BookmarkForm =
    { index : Maybe Int
    , name : String
    , target : String
    , group : String
    , error : Maybe String
    }



-- SIDEBAR AND BOOKMARKS


type SidebarMode
    = TreeMode
    | FavouritesMode
    | BookmarksMode


type alias Root =
    { name : String
    , path : String
    , kind : String
    }


type alias Bookmark =
    { index : Int
    , name : String
    , target : String
    , kind : String
    , group : List String
    , exists : Bool
    }


type alias Favourite =
    { path : String
    , exists : Bool
    }


type Drag
    = ResizeColumn Column Float Float
    | MoveColumn { column : Column, startX : Float, moved : Bool, target : Maybe Column, shift : Bool }
    | ResizeSidebar { startX : Float, startWidth : Float, width : Float }
    | DragItems DragState
      -- Reordering tabs (FR-TAB-02): the dragged tab and the tab under the pointer.
    | MoveTab { tabId : Int, startX : Float, moved : Bool, over : Maybe Int }


type Region
    = RegionSidebar
    | RegionList
    | RegionFilter


type Address
    = ShowCrumbs
    | Editing String (Maybe String)



-- MODEL


type alias Model =
    { booted : Bool
    , bootError : Maybe String
    , nextReq : Int
    , requests : Dict Int Request
    , home : String
    , sep : String
    , syncSupported : Bool
    , version : String
    , settingsFile : String
    , bookmarksFile : String
    , settings : Settings
    , zone : Time.Zone
    , tabs : List Tab
    , active : Int
    , nextTabId : Int
    , closedTabs : List String
    , recent : List String
    , address : Address
    , viewportHeight : Float
    , freeSpace : Maybe Int
    , message : Maybe String
    , messageSeq : Int
    , warnings : List String
    , typeahead : String
    , typeaheadSeq : Int
    , firstListingMarked : Bool
    , menuBar : Maybe MenuBarState
    , altAlone : Bool
    , popup : Maybe Popup
    , dialog : Maybe Dialog
    , drag : Maybe Drag
    , region : Region
    , roots : List Root
    , treeChildren : Dict String (List Path.Crumb)
    , treeExpanded : Set String
    , treeCursor : Maybe String
    , favourites : List Favourite
    , bookmarks : List Bookmark
    , bookmarkWarnings : List String
    , bookmarkSearch : String
    , clipboard : Maybe Clipboard
    , jobs : Dict Int JobStatus
    , jobsPanel : Bool
    , conflicts : List Conflict
    , rename : Maybe RenameState
    , pendingRename : Maybe String
    , templates : List Template
    , templatesFolder : String
    , now : Time.Posix

    -- Key bindings (spec 6.10): the defaults with keybindings.toml applied.
    , keymap : Keymap
    , userBindings : List UserBinding
    , keyWarnings : List String

    -- The first key of a chord, waiting for the second (FR-KEY-02).
    , chord : Maybe String
    , palette : Maybe Palette

    -- Palette picks and Quick Find searches, most recent first (FR-CMD-03, FR-FIND-06).
    , paletteHistory : List String
    , findHistory : List String
    , toolbar : ToolbarConfig
    , toolbarWarnings : List String
    }



-- MESSAGES


type Msg
    = FromBackend D.Value
    | GotZone Time.Zone
    | KeyCommand Command
    | KeyOther
    | AltDown
    | KeyUp String
    | ListScrolled Float Float
    | GotListViewport (Result Dom.Error Dom.Viewport)
    | WindowResized
    | RowClicked Int Mods
    | RowActivated Int
    | RowMiddleClicked Int
    | NavigateTo String
    | NavigateNewTab String
    | OpenPath String
    | ActivateTab Int
    | CloseTab Int
    | NewTab
    | Retry
    | StartEditAddress
    | AddressInput String
    | AddressKey String
    | AddressBlur
    | OpenCrumbMenu String Float Float
    | ClosePopups
    | HideMessage Int
    | ClearTypeahead Int
    | NoOp
      -- Menu Bar
    | MenuBarClick Int
    | MenuBarHover Int
    | MenuItemHover Int (Maybe Int)
    | MenuRun Msg
      -- Quick Filter
    | FilterInput String
    | FilterKey String
      -- Columns
    | HeaderMouseDown Column Float Bool
    | HeaderResizeStart Column Float
    | HeaderEnter Column
    | MouseMove Float Float
    | MouseUp DropMods
    | ItemMouseDown Int Float Float
    | DragOver (Maybe DropTarget)
    | DragLeftWindow
    | CreateFromTemplate Template
    | GotTime Time.Posix
    | HeaderContext Float Float
    | ToggleColumn Column
    | OpenColumnFilter Column Float Float
    | ColumnFilterReady Column Float Float Time.Posix
    | ColumnFilterSearch String
    | ColumnFilterToggle (List String)
    | ColumnFilterSelectAll
    | ColumnFilterQuick String
    | ColumnFilterApply
    | ColumnFilterClear
    | ColumnFilterRange Bool String
    | SaveViewMenu Float Float
      -- Sidebar
    | TreeToggle String
    | TreeOpen String
    | SidebarResizeStart Float
    | ItemContextMenu (List MenuEntry) Float Float
    | BookmarkSearch String
    | OpenBookmark Bookmark Bool
    | BookmarkEditOp (List ( String, D.Value ))
    | EditBookmark Bookmark
    | LocateBookmark Bookmark
    | TabMouseDown Int Float
    | TabHover Int
    | RegionFocused Region
      -- Bookmark dialog
    | DialogName String
    | DialogTarget String
    | DialogGroup String
    | DialogSubmit
    | DialogCancel
      -- File operations
    | RowContext Int Float Float
    | ListContext Float Float
    | ItemMenuAt Float Float
    | RenameInput String
    | RenameKey String
    | RenameBlur
    | ApplyRename
    | ConflictApplyAll Bool
    | ConflictAnswer String
    | StartJob String (List String) (Maybe String) Bool
    | JobCancel Int
    | JobRetry Int (List JobError)
    | JobSkip Int (List JobError)
    | JobPause Int Bool
    | ToggleJobsPanel
    | ClearFinishedJobs
    | RevealPath String
    | NewItemName String
    | NewItemTarget String
    | NewItemSubmit
    | ConfirmYes
      -- Key bindings
    | KeyChord String
    | KeyChordMiss String
      -- Command palette and Quick Find
    | StartFind String Time.Posix
    | PaletteInput String
    | PaletteKey String Bool
    | PaletteRun Int Bool
    | PaletteHover Int
      -- Keyboard Shortcuts editor
    | ShortcutsSearch String
    | ShortcutsRecord String
    | KeyRecorded String
    | RecordDone Int
    | ShortcutsSave
    | ShortcutsDiscard
    | ShortcutsRemove String String
    | ShortcutsReset String
      -- Customise Toolbar
    | ToolbarContext Float Float
    | ToolbarPick Int
    | ToolbarMove Int
    | ToolbarRemove
    | ToolbarAdd String
    | ToolbarStyle String
    | ToolbarSearch String
    | ToolbarSave
    | ToolbarDefaults


type Command
    = CmdBack
    | CmdForward
    | CmdUp
    | CmdHome
    | CmdRefresh
    | CmdEditAddress
    | CmdNewTab
    | CmdCloseTab
    | CmdReopenTab
    | CmdDuplicateTab
    | CmdNextTab
    | CmdPrevTab
    | CmdGotoTab Int
    | CmdToggleHidden
    | CmdSelectAll
    | CmdSelectNone
    | CmdInvertSelection
    | CmdOpen
    | CmdOpenNewTab
    | CmdMove Int Bool Bool
    | CmdPage Int Bool Bool
    | CmdEdge Bool Bool
    | CmdLeft
    | CmdRight
    | CmdToggleSelect
    | CmdEscape
    | CmdTypeahead String
    | CmdFocusFilter
    | CmdClearFilters
    | CmdSaveView Bool
    | CmdResetView
    | CmdOpenViewFile
    | CmdSortBy Column
    | CmdSortDirection Bool
    | CmdToggleFoldersFirst
    | CmdSetting String Bool
    | CmdSetTheme String
    | CmdToggleSidebar
    | CmdSidebarMode SidebarMode
    | CmdSidebarSide String
    | CmdBookmarkFolder
    | CmdBookmarkItem
    | CmdTogglePin
    | CmdOpenSettingsFile
    | CmdOpenBookmarksFile
    | CmdOpenLogFolder
    | CmdAbout
    | CmdExit
    | CmdMenuBar
    | CmdMenuMnemonic Int
    | CmdFocusRegion Bool
    | CmdCut
    | CmdCopy
    | CmdPaste
    | CmdDuplicate
    | CmdCopyPath
    | CmdRename
    | CmdDelete Bool
    | CmdNewFolder
    | CmdNewItem NewKind
    | CmdUndo
    | CmdOpenTerminal
    | CmdReveal
    | CmdItemMenu
    | CmdPasteShortcut
    | CmdNewFromTemplate
    | CmdSaveAsTemplate
    | CmdEditTemplates
    | CmdPalette String
    | CmdShortcuts
    | CmdOpenKeybindingsFile
    | CmdOpenToolbarFile
    | CmdCustomiseToolbar
    | CmdToggleSetting String
    | CmdOpenBookmarkNamed String
    | CmdGoto String
    | CmdCopyName
    | CmdToggleJobs


type alias Mods =
    { ctrl : Bool
    , shift : Bool
    }



-- CONSTANTS


rowHeight : Float
rowHeight =
    24


headerHeight : Float
headerHeight =
    28


listId : String
listId =
    "list"


addressInputId : String
addressInputId =
    "address-input"


filterInputId : String
filterInputId =
    "filter-input"


sidebarId : String
sidebarId =
    "sidebar"


sidebarBodyId : String
sidebarBodyId =
    "sidebar-body"


treeCursorId : String
treeCursorId =
    "tree-cursor"


dialogFirstInputId : String
dialogFirstInputId =
    "dialog-name"


renameInputId : String
renameInputId =
    "rename-input"


paletteInputId : String
paletteInputId =
    "palette-input"


shortcutsDialogId : String
shortcutsDialogId =
    "shortcuts-dialog"


shortcutsSearchId : String
shortcutsSearchId =
    "shortcuts-search"


sidebarModeName : SidebarMode -> String
sidebarModeName mode =
    case mode of
        TreeMode ->
            "tree"

        FavouritesMode ->
            "favourites"

        BookmarksMode ->
            "bookmarks"


sidebarModeFromString : String -> SidebarMode
sidebarModeFromString s =
    case s of
        "favourites" ->
            FavouritesMode

        "bookmarks" ->
            BookmarksMode

        _ ->
            TreeMode



-- HELPERS


activeTab : Model -> Maybe Tab
activeTab model =
    findTab model.active model


findTab : Int -> Model -> Maybe Tab
findTab tabId model =
    List.filter (\tab -> tab.id == tabId) model.tabs |> List.head


replaceTab : Tab -> Model -> Model
replaceTab tab model =
    { model
        | tabs =
            List.map
                (\t ->
                    if t.id == tab.id then
                        tab

                    else
                        t
                )
                model.tabs
    }


{-| True when the Quick Filter or a column filter hides items (FR-QF-06).
-}
isFiltering : Tab -> Bool
isFiltering tab =
    String.trim tab.filter /= "" || not (Dict.isEmpty tab.columnFilters)
