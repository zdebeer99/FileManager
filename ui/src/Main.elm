module Main exposing (main)

{-| File Catalog UI: state changes and backend messages. The screen is drawn by View.
-}

import Array exposing (Array)
import Browser
import Browser.Dom as Dom
import Browser.Events
import Columns exposing (Column)
import Dict exposing (Dict)
import FileName
import Filter
import Format
import Item exposing (Item)
import Json.Decode as D
import Json.Encode as E
import Menu
import Path
import Ports
import Process
import Set exposing (Set)
import Settings exposing (Settings)
import Task
import Text
import Time
import Types exposing (..)
import View


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = View.view
        , subscriptions = subscriptions
        }


init : () -> ( Model, Cmd Msg )
init _ =
    let
        model =
            { booted = False
            , bootError = Nothing
            , nextReq = 1
            , requests = Dict.empty
            , home = ""
            , sep = "/"
            , syncSupported = False
            , version = ""
            , settingsFile = ""
            , bookmarksFile = ""
            , settings = Settings.default
            , zone = Time.utc
            , tabs = []
            , active = 0
            , nextTabId = 1
            , closedTabs = []
            , recent = []
            , address = ShowCrumbs
            , viewportHeight = 600
            , freeSpace = Nothing
            , message = Nothing
            , messageSeq = 0
            , warnings = []
            , typeahead = ""
            , typeaheadSeq = 0
            , firstListingMarked = False
            , menuBar = Nothing
            , altAlone = False
            , popup = Nothing
            , dialog = Nothing
            , drag = Nothing
            , region = RegionList
            , roots = []
            , treeChildren = Dict.empty
            , treeExpanded = Set.empty
            , treeCursor = Nothing
            , favourites = []
            , bookmarks = []
            , bookmarkWarnings = []
            , bookmarkSearch = ""
            , clipboard = Nothing
            , jobs = Dict.empty
            , jobsPanel = False
            , conflicts = []
            , rename = Nothing
            , pendingRename = Nothing
            , templates = []
            , templatesFolder = ""
            , now = Time.millisToPosix 0
            }

        ( withRequest, initCmd ) =
            request "app_init" (E.object []) False ReqInit model
    in
    ( withRequest, Cmd.batch [ initCmd, Task.perform GotZone Time.here, Task.perform GotTime Time.now ] )


emptyTab : Model -> Int -> String -> Tab
emptyTab model tabId path =
    let
        view =
            defaultView model
    in
    { id = tabId
    , path = path
    , back = []
    , forward = []
    , items = Dict.empty
    , ordered = []
    , visible = Array.empty
    , hiddenCount = 0
    , folderCount = 0
    , unfilteredCount = 0
    , status = Idle
    , req = -1
    , chunks = 0
    , selected = Set.empty
    , cursor = 0
    , anchor = 0
    , scrollTop = 0
    , view = view
    , savedView = view
    , viewSource = Nothing
    , filter = ""
    , columnFilters = Dict.empty
    , pendingSelect = Nothing
    }


{-| The view a folder gets when it has no saved view (settings.toml [view.default]).
-}
defaultView : Model -> FolderView
defaultView model =
    let
        s =
            model.settings

        columns =
            s.columns
                |> List.filterMap Columns.fromString
                |> List.filter (\c -> c /= Columns.Sync || model.syncSupported)
                |> dedupe
                |> withName

        sort =
            s.sort
                |> List.filterMap (\( c, desc ) -> Columns.fromString c |> Maybe.map (\col -> ( col, desc )))
                |> List.take 2
    in
    { columns = List.map (\c -> ( c, Columns.defaultWidth c )) columns
    , sort =
        if List.isEmpty sort then
            [ ( Columns.Name, False ) ]

        else
            sort
    , foldersFirst = s.foldersFirst
    , showHidden = s.showHidden
    }


withName : List Column -> List Column
withName columns =
    if List.member Columns.Name columns then
        columns

    else
        Columns.Name :: columns



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        FromBackend value ->
            case D.decodeValue envelopeDecoder value of
                Ok envelope ->
                    handleEnvelope envelope model

                Err _ ->
                    ( model, Cmd.none )

        GotZone zone ->
            ( { model | zone = zone }, Cmd.none )

        KeyCommand command ->
            routeKey command { model | altAlone = False }

        KeyOther ->
            ( { model | altAlone = False }, Cmd.none )

        AltDown ->
            ( { model | altAlone = True }, Cmd.none )

        KeyUp key ->
            if key == "Alt" && model.altAlone then
                if model.menuBar == Nothing then
                    openMenu 0 { model | altAlone = False }

                else
                    ( { model | menuBar = Nothing, altAlone = False }, focusList )

            else
                ( model, Cmd.none )

        ListScrolled top height ->
            ( updateActive (\tab -> { tab | scrollTop = top }) { model | viewportHeight = height }, Cmd.none )

        GotListViewport result ->
            case result of
                Ok viewport ->
                    ( { model | viewportHeight = viewport.viewport.height }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        WindowResized ->
            ( model, measureList )

        RowClicked index mods ->
            ( updateActive (clickRow index mods) { model | popup = Nothing, menuBar = Nothing }, Cmd.none )

        RowActivated index ->
            withActive model (\tab -> Array.get index tab.visible |> Maybe.map (\item -> openItem item model))

        RowMiddleClicked index ->
            withActive model
                (\tab ->
                    Array.get index tab.visible
                        |> Maybe.andThen
                            (\item ->
                                if item.isDir then
                                    Just (addTab item.path False model)

                                else
                                    Nothing
                            )
                )

        NavigateTo path ->
            navigate Push path Nothing { model | popup = Nothing }

        NavigateNewTab path ->
            addTab path False { model | popup = Nothing }

        OpenPath path ->
            request "open_item" (E.object [ ( "path", E.string path ) ]) False ReqOpen model

        ActivateTab tabId ->
            activateTab tabId model

        CloseTab tabId ->
            closeTab tabId model

        NewTab ->
            withActive model (\tab -> Just (addTab tab.path True model))

        Retry ->
            withActive model (\tab -> Just (loadTab tab.id model))

        StartEditAddress ->
            startEditAddress model

        AddressInput newText ->
            ( { model | address = Editing newText Nothing }, Cmd.none )

        AddressKey key ->
            addressKey key model

        AddressBlur ->
            case model.address of
                Editing _ _ ->
                    ( { model | address = ShowCrumbs }, Cmd.none )

                ShowCrumbs ->
                    ( model, Cmd.none )

        OpenCrumbMenu path x y ->
            let
                showHidden =
                    activeTab model |> Maybe.map (.view >> .showHidden) |> Maybe.withDefault False
            in
            request "list_subfolders"
                (E.object [ ( "path", E.string path ), ( "showHidden", E.bool showHidden ) ])
                False
                (ReqSubfolders (ForCrumb path))
                { model | popup = Just (MenuPopup { x = x - 12, y = y + 14, entries = [ loadingEntry ] }), menuBar = Nothing }

        ClosePopups ->
            ( { model | popup = Nothing, menuBar = Nothing }, Cmd.none )

        HideMessage seq ->
            if seq == model.messageSeq then
                ( { model | message = Nothing }, Cmd.none )

            else
                ( model, Cmd.none )

        ClearTypeahead seq ->
            if seq == model.typeaheadSeq then
                ( { model | typeahead = "" }, Cmd.none )

            else
                ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )

        -- Menu Bar
        MenuBarClick index ->
            if Maybe.map .index model.menuBar == Just index then
                ( { model | menuBar = Nothing }, Cmd.none )

            else
                openMenu index { model | popup = Nothing }

        MenuBarHover index ->
            case model.menuBar of
                Just state ->
                    if state.index /= index then
                        ( { model | menuBar = Just { index = index, active = -1, sub = Nothing } }, Cmd.none )

                    else
                        ( model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        MenuItemHover index sub ->
            ( { model | menuBar = Maybe.map (\s -> { s | active = index, sub = sub }) model.menuBar }, Cmd.none )

        MenuRun inner ->
            -- The clicked menu item disappears, so give the list focus back first;
            -- an action that opens a dialog then moves focus into the dialog.
            update inner { model | menuBar = Nothing, popup = Nothing }
                |> (\( m, cmd ) ->
                        if m.dialog == Nothing && m.rename == Nothing then
                            ( m, Cmd.batch [ focusList, cmd ] )

                        else
                            ( m, cmd )
                   )

        -- Quick Filter
        FilterInput text ->
            ( updateActive (\tab -> refilter model { tab | filter = text, cursor = 0, scrollTop = 0 }) model
            , scrollListTo 0
            )

        FilterKey key ->
            case key of
                "Escape" ->
                    ( updateActive (\tab -> refilter model { tab | filter = "" }) model, focusList )

                "F6" ->
                    focusRegion True model

                _ ->
                    ( model, focusList )

        -- Columns
        HeaderMouseDown column x shift ->
            if model.dialog /= Nothing || not (List.isEmpty model.conflicts) then
                -- A click meant for a dialog must never re-sort the list.
                ( model, Cmd.none )

            else
                ( { model | drag = Just (MoveColumn { column = column, startX = x, moved = False, target = Nothing, shift = shift }), popup = Nothing }
                , Cmd.none
                )

        HeaderResizeStart column x ->
            let
                width =
                    activeTab model
                        |> Maybe.andThen (\tab -> List.filter (\( c, _ ) -> c == column) tab.view.columns |> List.head)
                        |> Maybe.map Tuple.second
                        |> Maybe.withDefault (Columns.defaultWidth column)
            in
            ( { model | drag = Just (ResizeColumn column x width) }, Cmd.none )

        HeaderEnter column ->
            case model.drag of
                Just (MoveColumn d) ->
                    ( { model | drag = Just (MoveColumn { d | target = Just column }) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        MouseMove x y ->
            mouseMove x y model

        MouseUp mods ->
            mouseUp mods model

        ItemMouseDown index x y ->
            withActive model
                (\tab ->
                    Array.get index tab.visible
                        |> Maybe.map
                            (\item ->
                                let
                                    -- Dragging an unselected item drags just that item, like Explorer.
                                    -- The selection itself is left alone, so Ctrl+click still works.
                                    items =
                                        if Set.member item.name tab.selected then
                                            targetItems tab

                                        else
                                            [ item ]
                                in
                                ( { model
                                    | drag =
                                        Just
                                            (DragItems
                                                { paths = List.map .path items
                                                , names = List.map .name items
                                                , startX = x
                                                , startY = y
                                                , x = x
                                                , y = y
                                                , moved = False
                                                , target = Nothing
                                                }
                                            )
                                  }
                                , Cmd.none
                                )
                            )
                )

        DragOver target ->
            case model.drag of
                Just (DragItems d) ->
                    let
                        -- Never drop a folder onto itself.
                        allowed =
                            case target of
                                Just (DropFolder path) ->
                                    if List.member path d.paths then
                                        Nothing

                                    else
                                        target

                                _ ->
                                    target
                    in
                    ( { model | drag = Just (DragItems { d | target = allowed }) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        DragLeftWindow ->
            case model.drag of
                Just (DragItems d) ->
                    if d.moved then
                        -- Leaving the window hands the drag to the system, so the items
                        -- can be dropped on Explorer, the desktop or another app.
                        request "drag_out" (E.object [ ( "paths", E.list E.string d.paths ) ]) False ReqIgnore { model | drag = Nothing }

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        CreateFromTemplate template ->
            if template.needsName then
                ( { model | dialog = Just (NewItemDialog { kind = NewFromTemplate template.path, name = "", target = "", error = Nothing }), popup = Nothing, menuBar = Nothing }
                , Task.attempt (\_ -> NoOp) (Dom.focus dialogFirstInputId)
                )

            else
                createFromTemplate template.path "" { model | popup = Nothing }

        GotTime now ->
            ( { model | now = now }, Cmd.none )

        HeaderContext x y ->
            withActive model (\tab -> Just ( { model | popup = Just (MenuPopup { x = x, y = y, entries = Menu.columnEntries model tab }) }, Cmd.none ))

        ToggleColumn column ->
            ( updateActive (\tab -> { tab | view = toggleColumn column tab.view }) model, Cmd.none )

        OpenColumnFilter column x y ->
            ( model, Task.perform (ColumnFilterReady column x y) Time.now )

        ColumnFilterReady column x y now ->
            withActive model
                (\tab ->
                    Just
                        ( { model | popup = Just (ColumnFilterPopup (columnFilterState model tab column x y now)), menuBar = Nothing }
                        , Task.attempt (\_ -> NoOp) (Dom.focus "colfilter-search")
                        )
                )

        ColumnFilterSearch text ->
            ( updateFilterPopup (\s -> { s | search = text }) model, Cmd.none )

        ColumnFilterToggle values ->
            ( updateFilterPopup
                (\s ->
                    if List.all (\v -> Set.member v s.checked) values then
                        { s | checked = List.foldl Set.remove s.checked values }

                    else
                        { s | checked = List.foldl Set.insert s.checked values }
                )
                model
            , Cmd.none
            )

        ColumnFilterSelectAll ->
            ( updateFilterPopup
                (\s ->
                    let
                        shown =
                            List.map Tuple.first (View.filterPopupValues s)
                    in
                    if List.all (\v -> Set.member v s.checked) shown then
                        { s | checked = List.foldl Set.remove s.checked shown }

                    else
                        { s | checked = List.foldl Set.insert s.checked shown }
                )
                model
            , Cmd.none
            )

        ColumnFilterQuick choice ->
            ( updateFilterPopup (\s -> { s | checked = quickDateChoice model.zone s.now choice s.values }) model, Cmd.none )

        ColumnFilterApply ->
            case model.popup of
                Just (ColumnFilterPopup s) ->
                    let
                        shown =
                            Set.fromList (List.map Tuple.first (View.filterPopupValues s))

                        allValues =
                            Set.fromList (List.map Tuple.first s.values)

                        allowed =
                            if s.search == "" then
                                s.checked

                            else
                                Set.intersect s.checked shown

                        name =
                            Columns.toString s.column

                        set tab =
                            if s.search == "" && Set.isEmpty (Set.diff allValues allowed) then
                                Dict.remove name tab.columnFilters

                            else
                                Dict.insert name allowed tab.columnFilters
                    in
                    ( updateActive (\tab -> refilter model { tab | columnFilters = set tab, cursor = 0 }) { model | popup = Nothing }
                    , focusList
                    )

                _ ->
                    ( model, Cmd.none )

        ColumnFilterClear ->
            case model.popup of
                Just (ColumnFilterPopup s) ->
                    ( updateActive
                        (\tab -> refilter model { tab | columnFilters = Dict.remove (Columns.toString s.column) tab.columnFilters })
                        { model | popup = Nothing }
                    , focusList
                    )

                _ ->
                    ( model, Cmd.none )

        SaveViewMenu x y ->
            ( { model
                | popup =
                    Just
                        (MenuPopup
                            { x = x
                            , y = y
                            , entries =
                                [ menuCmd "Save for This Folder" "Ctrl+S" (CmdSaveView False)
                                , menuCmd "Save for This Folder and Subfolders" "" (CmdSaveView True)
                                , Separator
                                , menuCmd "Reset to Default View" "" CmdResetView
                                , menuCmd "Open Folder Settings File" "" CmdOpenViewFile
                                ]
                            }
                        )
              }
            , Cmd.none
            )

        -- Sidebar
        TreeToggle path ->
            toggleTreeNode path model

        TreeOpen path ->
            navigate Push path Nothing { model | treeCursor = Just path }

        SidebarResizeStart x ->
            ( { model | drag = Just (ResizeSidebar { startX = x, startWidth = model.settings.sidebarWidth, width = model.settings.sidebarWidth }) }
            , Cmd.none
            )

        ItemContextMenu entries x y ->
            ( { model | popup = Just (MenuPopup { x = x, y = y, entries = entries }), menuBar = Nothing }, Cmd.none )

        BookmarkSearch text ->
            ( { model | bookmarkSearch = text }, Cmd.none )

        OpenBookmark bookmark newTab ->
            openBookmark bookmark newTab { model | popup = Nothing }

        BookmarkEditOp fields ->
            request "bookmarks_edit" (E.object [ ( "edit", E.object fields ) ]) False ReqBookmarkEdit { model | popup = Nothing }

        EditBookmark bookmark ->
            openDialog
                { index = Just bookmark.index
                , name = bookmark.name
                , target = bookmark.target
                , group = String.join "/" bookmark.group
                , error = Nothing
                }
                { model | popup = Nothing }

        RegionFocused region ->
            ( { model | region = region }, Cmd.none )

        -- Bookmark dialog
        DialogName text ->
            ( updateDialog (\f -> { f | name = text, error = Nothing }) model, Cmd.none )

        DialogTarget text ->
            ( updateDialog (\f -> { f | target = text, error = Nothing }) model, Cmd.none )

        DialogGroup text ->
            ( updateDialog (\f -> { f | group = text, error = Nothing }) model, Cmd.none )

        DialogSubmit ->
            submitDialog model

        DialogCancel ->
            ( { model | dialog = Nothing, rename = Nothing }, focusList )

        -- File operations
        RowContext index x y ->
            withActive model
                (\tab ->
                    Array.get index tab.visible
                        |> Maybe.map
                            (\item ->
                                let
                                    selected =
                                        if Set.member item.name tab.selected then
                                            tab

                                        else
                                            { tab | cursor = index, anchor = index, selected = Set.singleton item.name }

                                    withSelection =
                                        replaceTab selected model
                                in
                                ( { withSelection | popup = Just (MenuPopup { x = x, y = y, entries = itemEntries withSelection selected item }), menuBar = Nothing }
                                , Cmd.none
                                )
                            )
                )

        ListContext x y ->
            withActive model (\tab -> Just ( { model | popup = Just (MenuPopup { x = x, y = y, entries = folderMenuEntries model tab }), menuBar = Nothing }, Cmd.none ))

        ItemMenuAt x y ->
            withActive model
                (\tab ->
                    case Array.get tab.cursor tab.visible of
                        Just item ->
                            Just ( { model | popup = Just (MenuPopup { x = x, y = y, entries = itemEntries model tab item }) }, Cmd.none )

                        Nothing ->
                            Just ( { model | popup = Just (MenuPopup { x = x, y = y, entries = folderMenuEntries model tab }) }, Cmd.none )
                )

        RenameInput text ->
            ( updateRename (\r -> { r | text = text, error = validateRename model r.original text }) model, Cmd.none )

        RenameKey key ->
            case key of
                "Escape" ->
                    ( { model | rename = Nothing }, focusList )

                "F2" ->
                    case model.rename of
                        Just r ->
                            ( updateRename (\s -> { s | step = s.step + 1 }) model, selectRenameText model { r | step = r.step + 1 } )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    commitRename True model

        RenameBlur ->
            commitRename False model

        ApplyRename ->
            applyRename { model | dialog = Nothing }

        ConflictApplyAll on ->
            ( { model
                | conflicts =
                    List.indexedMap
                        (\i c ->
                            if i == 0 then
                                { c | applyToAll = on }

                            else
                                c
                        )
                        model.conflicts
              }
            , Cmd.none
            )

        ConflictAnswer action ->
            case model.conflicts of
                c :: rest ->
                    request "job_resolve"
                        (E.object [ ( "jobId", E.int c.jobId ), ( "action", E.string action ), ( "applyToAll", E.bool c.applyToAll ) ])
                        False
                        ReqIgnore
                        { model | conflicts = rest }

                [] ->
                    ( model, Cmd.none )

        StartJob kind sources dest permanent ->
            startJob kind sources dest permanent { model | popup = Nothing, dialog = Nothing }

        JobCancel jobId ->
            request "job_cancel" (E.object [ ( "jobId", E.int jobId ) ]) False ReqIgnore model

        JobPause jobId paused ->
            request "job_pause" (E.object [ ( "jobId", E.int jobId ), ( "paused", E.bool paused ) ]) False ReqIgnore model

        ToggleJobsPanel ->
            ( { model | jobsPanel = not model.jobsPanel, popup = Nothing }, Cmd.none )

        ClearFinishedJobs ->
            ( { model | jobs = Dict.filter (\_ job -> isActiveJob job) model.jobs }, Cmd.none )

        RevealPath path ->
            request "reveal_item" (E.object [ ( "path", E.string path ) ]) False ReqOpen { model | popup = Nothing }

        NewItemName text ->
            ( updateNewItem (\f -> { f | name = text, error = Nothing }) model, Cmd.none )

        NewItemTarget text ->
            ( updateNewItem (\f -> { f | target = text, error = Nothing }) model, Cmd.none )

        NewItemSubmit ->
            submitNewItem model

        ConfirmYes ->
            case model.dialog of
                Just (ConfirmDialog confirm) ->
                    update confirm.onConfirm { model | dialog = Nothing }

                _ ->
                    ( model, Cmd.none )



-- KEYBOARD ROUTING


{-| Keys go to the open menu first, then the folder tree when it has focus,
then the file list.
-}
routeKey : Command -> Model -> ( Model, Cmd Msg )
routeKey command model =
    if model.menuBar /= Nothing then
        menuKey command model

    else if model.popup /= Nothing && command == CmdEscape then
        ( { model | popup = Nothing }, Cmd.none )

    else if model.region == RegionSidebar && model.settings.sidebarVisible && sidebarModeFromString model.settings.sidebarMode == TreeMode && isTreeKey command then
        treeKey command model

    else
        runCommand command model


runCommand : Command -> Model -> ( Model, Cmd Msg )
runCommand command model =
    case command of
        CmdBack ->
            withActive model
                (\tab ->
                    List.head tab.back
                        |> Maybe.map (\path -> navigate GoingBack path (Just (Path.name model.sep tab.path)) model)
                )

        CmdForward ->
            withActive model (\tab -> List.head tab.forward |> Maybe.map (\path -> navigate GoingForward path Nothing model))

        CmdUp ->
            withActive model
                (\tab ->
                    Path.parent model.sep tab.path
                        |> Maybe.map (\path -> navigate Push path (Just (Path.name model.sep tab.path)) model)
                )

        CmdHome ->
            navigate Push model.home Nothing model

        CmdRefresh ->
            withActive model (\tab -> Just (loadTab tab.id model))

        CmdEditAddress ->
            startEditAddress model

        CmdNewTab ->
            withActive model (\tab -> Just (addTab tab.path True model))

        CmdDuplicateTab ->
            withActive model (\tab -> Just (addTab tab.path True model))

        CmdCloseTab ->
            closeTab model.active model

        CmdReopenTab ->
            case model.closedTabs of
                path :: rest ->
                    addTab path True { model | closedTabs = rest }

                [] ->
                    ( model, Cmd.none )

        CmdNextTab ->
            activateTab (tabIdAtOffset 1 model) model

        CmdPrevTab ->
            activateTab (tabIdAtOffset -1 model) model

        CmdGotoTab n ->
            let
                index =
                    if n == 9 then
                        List.length model.tabs - 1

                    else
                        n - 1
            in
            case List.head (List.drop index model.tabs) of
                Just tab ->
                    activateTab tab.id model

                Nothing ->
                    ( model, Cmd.none )

        CmdToggleHidden ->
            ( updateActive (\tab -> changeView (\v -> { v | showHidden = not v.showHidden }) model tab) model, Cmd.none )

        CmdSelectAll ->
            ( updateActive (\tab -> { tab | selected = Array.foldl (\item -> Set.insert item.name) Set.empty tab.visible }) model
            , Cmd.none
            )

        CmdSelectNone ->
            ( updateActive (\tab -> { tab | selected = Set.empty }) model, Cmd.none )

        CmdInvertSelection ->
            ( updateActive
                (\tab -> { tab | selected = Array.foldl (\item -> toggle item.name) tab.selected tab.visible })
                model
            , Cmd.none
            )

        CmdOpen ->
            withActive model
                (\tab ->
                    case selectedItems tab of
                        [ item ] ->
                            Just (openItem item model)

                        [] ->
                            Array.get tab.cursor tab.visible |> Maybe.map (\item -> openItem item model)

                        many ->
                            Just (openFiles (List.filter (not << .isDir) many) model)
                )

        CmdOpenNewTab ->
            withActive model
                (\tab ->
                    Array.get tab.cursor tab.visible
                        |> Maybe.andThen
                            (\item ->
                                if item.isDir then
                                    Just (addTab item.path False model)

                                else
                                    Nothing
                            )
                )

        CmdMove delta shift ctrl ->
            moveCursor (\tab -> tab.cursor + delta) shift ctrl model

        CmdPage direction shift ctrl ->
            moveCursor (\tab -> tab.cursor + direction * pageRows model) shift ctrl model

        CmdEdge toEnd shift ->
            moveCursor
                (\tab ->
                    if toEnd then
                        Array.length tab.visible - 1

                    else
                        0
                )
                shift
                False
                model

        CmdLeft ->
            ( model, Cmd.none )

        CmdRight ->
            ( model, Cmd.none )

        CmdToggleSelect ->
            ( updateActive
                (\tab ->
                    case Array.get tab.cursor tab.visible of
                        Just item ->
                            { tab | selected = toggle item.name tab.selected, anchor = tab.cursor }

                        Nothing ->
                            tab
                )
                model
            , Cmd.none
            )

        CmdEscape ->
            ( updateActive (\tab -> { tab | selected = Set.empty }) model, Cmd.none )

        CmdTypeahead char ->
            typeahead char model

        CmdFocusFilter ->
            ( model, Task.attempt (\_ -> NoOp) (Dom.focus filterInputId) )

        CmdClearFilters ->
            ( updateActive (\tab -> refilter model { tab | filter = "", columnFilters = Dict.empty }) model, focusList )

        CmdSaveView subfolders ->
            saveView subfolders model

        CmdResetView ->
            withActive model
                (\tab ->
                    Just
                        (request "folder_view_reset" (E.object [ ( "path", E.string tab.path ) ]) False (ReqViewReset tab.id tab.path) model)
                )

        CmdOpenViewFile ->
            withActive model
                (\tab ->
                    case tab.viewSource of
                        Just source ->
                            Just (request "folder_view_file" (E.object [ ( "path", E.string source ) ]) False ReqOpenSettingsFile model)

                        Nothing ->
                            Just (flash Text.noSavedView model)
                )

        CmdSortBy column ->
            ( updateActive
                (\tab ->
                    changeView
                        (\v ->
                            case v.sort of
                                ( primary, desc ) :: rest ->
                                    if primary == column then
                                        v

                                    else
                                        { v | sort = [ ( column, False ) ] }

                                [] ->
                                    { v | sort = [ ( column, False ) ] }
                        )
                        model
                        tab
                )
                model
            , Cmd.none
            )

        CmdSortDirection desc ->
            ( updateActive
                (\tab ->
                    changeView
                        (\v ->
                            case v.sort of
                                ( primary, _ ) :: rest ->
                                    { v | sort = ( primary, desc ) :: rest }

                                [] ->
                                    { v | sort = [ ( Columns.Name, desc ) ] }
                        )
                        model
                        tab
                )
                model
            , Cmd.none
            )

        CmdToggleFoldersFirst ->
            ( updateActive (\tab -> changeView (\v -> { v | foldersFirst = not v.foldersFirst }) model tab) model, Cmd.none )

        CmdSetting key value ->
            setSetting key (E.bool value) (localBoolSetting key value) model

        CmdSetTheme theme ->
            setSetting "general.theme" (E.string theme) (\s -> { s | theme = theme }) model

        CmdToggleSidebar ->
            let
                visible =
                    not model.settings.sidebarVisible
            in
            setSetting "layout.sidebar.visible" (E.bool visible) (\s -> { s | sidebarVisible = visible }) model

        CmdSidebarMode mode ->
            let
                name =
                    sidebarModeName mode
            in
            setSetting "layout.sidebar.mode" (E.string name) (\s -> { s | sidebarMode = name, sidebarVisible = True }) model
                |> andThen
                    (\m ->
                        if model.settings.sidebarVisible then
                            ( m, Cmd.none )

                        else
                            setSetting "layout.sidebar.visible" (E.bool True) identity m
                    )
                |> andThen followCurrentInTree

        CmdSidebarSide side ->
            setSetting "layout.sidebar.side" (E.string side) (\s -> { s | sidebarSide = side }) model

        CmdBookmarkFolder ->
            withActive model
                (\tab ->
                    Just
                        (openDialog
                            { index = Nothing, name = Path.name model.sep tab.path, target = tab.path, group = "bar", error = Nothing }
                            model
                        )
                )

        CmdBookmarkItem ->
            withActive model
                (\tab ->
                    case Array.get tab.cursor tab.visible of
                        Just item ->
                            Just (openDialog { index = Nothing, name = item.name, target = item.path, group = "bar", error = Nothing } model)

                        Nothing ->
                            Just (flash Text.nothingSelected model)
                )

        CmdTogglePin ->
            withActive model
                (\tab ->
                    let
                        op =
                            if List.any (\f -> f.path == tab.path) model.favourites then
                                "removeFavourite"

                            else
                                "addFavourite"
                    in
                    Just (update (BookmarkEditOp [ ( "op", E.string op ), ( "path", E.string tab.path ) ]) model)
                )

        CmdOpenSettingsFile ->
            update (OpenPath model.settingsFile) model

        CmdOpenBookmarksFile ->
            if model.bookmarksFile /= "" && (not (List.isEmpty model.bookmarks) || not (List.isEmpty model.favourites)) then
                update (OpenPath model.bookmarksFile) model

            else
                flash Text.noBookmarksFile model

        CmdOpenLogFolder ->
            update (OpenPath (Maybe.withDefault model.settingsFile (Path.parent model.sep model.settingsFile) ++ model.sep ++ "logs")) model

        CmdAbout ->
            flash (Text.about model.version) model

        CmdExit ->
            request "app_exit" (E.object []) False ReqIgnore model

        CmdMenuBar ->
            if model.menuBar == Nothing then
                openMenu 0 model

            else
                ( { model | menuBar = Nothing }, Cmd.none )

        CmdMenuMnemonic index ->
            openMenu index model

        CmdFocusRegion forward ->
            focusRegion forward model

        CmdCut ->
            toClipboard True model

        CmdCopy ->
            toClipboard False model

        CmdPaste ->
            request "clipboard_get_files" (E.object []) False (ReqClipboard False) model

        CmdPasteShortcut ->
            request "clipboard_get_files" (E.object []) False (ReqClipboard True) model

        CmdNewFromTemplate ->
            withActive model
                (\tab ->
                    Just
                        ( model
                        , Dom.getElement listId
                            |> Task.attempt
                                (\result ->
                                    case result of
                                        Ok el ->
                                            ItemContextMenu (Menu.templateEntries model) (el.element.x + 60) (el.element.y + headerHeight + toFloat (tab.cursor + 1) * rowHeight - tab.scrollTop)

                                        Err _ ->
                                            NoOp
                                )
                        )
                        |> Maybe.map (andThen (request "templates_list" (E.object []) False ReqTemplates))
                )

        CmdSaveAsTemplate ->
            withTargets model (\items -> request "templates_folder" (E.object []) False (ReqTemplatesFolder (Just (List.map .path items))) model)

        CmdEditTemplates ->
            request "templates_folder" (E.object []) False (ReqTemplatesFolder Nothing) model

        CmdDuplicate ->
            withTargets model (\items -> startJob "duplicate" (List.map .path items) Nothing False model)

        CmdCopyPath ->
            withTargets model
                (\items ->
                    request "clipboard_write_text"
                        (E.object [ ( "text", E.string (String.join "\n" (List.map .path items)) ) ])
                        False
                        (ReqCopied (Text.pathsCopied (List.length items)))
                        model
                )

        CmdRename ->
            withActive model
                (\tab ->
                    case targetItems tab of
                        [ item ] ->
                            Just (startRename tab item model)

                        [] ->
                            Nothing

                        _ ->
                            Just (flash Text.renameOne model)
                )

        CmdDelete permanent ->
            withTargets model (\items -> deleteItems permanent items model)

        CmdNewFolder ->
            withActive model
                (\tab ->
                    Just
                        (request "fs_create"
                            (E.object [ ( "parent", E.string tab.path ), ( "item", E.object [ ( "kind", E.string "folder" ) ] ) ])
                            False
                            (ReqCreate tab.id True)
                            model
                        )
                )

        CmdNewItem kind ->
            let
                form =
                    case kind of
                        NewFile ->
                            { kind = kind, name = Text.newFileName, target = "", error = Nothing }

                        NewShortcut ->
                            { kind = kind, name = "", target = "", error = Nothing }

                        NewWebLink ->
                            { kind = kind, name = "", target = "https://", error = Nothing }

                        NewFromTemplate _ ->
                            { kind = kind, name = "", target = "", error = Nothing }
            in
            ( { model | dialog = Just (NewItemDialog form), popup = Nothing, menuBar = Nothing }
            , Task.attempt (\_ -> NoOp) (Dom.focus dialogFirstInputId)
            )

        CmdUndo ->
            request "undo_last" (E.object []) False ReqUndo model

        CmdOpenTerminal ->
            withActive model
                (\tab ->
                    let
                        dir =
                            case targetItems tab of
                                [ item ] ->
                                    if item.isDir then
                                        item.path

                                    else
                                        tab.path

                                _ ->
                                    tab.path
                    in
                    Just (request "open_terminal" (E.object [ ( "path", E.string dir ) ]) False ReqOpen model)
                )

        CmdReveal ->
            withActive model
                (\tab ->
                    case targetItems tab of
                        item :: _ ->
                            Just (update (RevealPath item.path) model)

                        [] ->
                            Just (update (RevealPath tab.path) model)
                )

        CmdItemMenu ->
            withActive model
                (\tab ->
                    Just
                        ( model
                        , Dom.getElement listId
                            |> Task.attempt
                                (\result ->
                                    case result of
                                        Ok el ->
                                            ItemMenuAt (el.element.x + 60)
                                                (el.element.y + headerHeight + toFloat (tab.cursor + 1) * rowHeight - tab.scrollTop)

                                        Err _ ->
                                            NoOp
                                )
                        )
                )


localBoolSetting : String -> Bool -> Settings -> Settings
localBoolSetting key value s =
    case key of
        "layout.menuBar" ->
            { s | menuBar = value }

        "layout.toolbar" ->
            { s | toolbar = value }

        "layout.bookmarkBar" ->
            { s | bookmarkBar = value }

        "layout.tabBar" ->
            { s | tabBar = value }

        "layout.addressBar" ->
            { s | addressBar = value }

        "layout.statusBar" ->
            { s | statusBar = value }

        "view.default.showExtensions" ->
            { s | showExtensions = value }

        _ ->
            s


{-| Changes settings.toml (keeping the user's comments) and applies the change
at once; the file watcher confirms it a moment later.
-}
setSetting : String -> E.Value -> (Settings -> Settings) -> Model -> ( Model, Cmd Msg )
setSetting key value local model =
    request "settings_set" (E.object [ ( "key", E.string key ), ( "value", value ) ]) False ReqIgnore { model | settings = local model.settings }
        |> addCmd measureList


pageRows : Model -> Int
pageRows model =
    max 1 (floor ((model.viewportHeight - headerHeight) / rowHeight) - 1)


focusRegion : Bool -> Model -> ( Model, Cmd Msg )
focusRegion forward model =
    let
        regions =
            (if model.settings.sidebarVisible then
                [ ( RegionSidebar, sidebarId ) ]

             else
                []
            )
                ++ [ ( RegionList, listId ) ]
                ++ (if model.settings.addressBar then
                        [ ( RegionFilter, filterInputId ) ]

                    else
                        []
                   )

        count =
            List.length regions

        current =
            regions |> List.indexedMap Tuple.pair |> List.filter (\( _, ( r, _ ) ) -> r == model.region) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0

        next =
            modBy count
                (current
                    + (if forward then
                        1

                       else
                        -1
                      )
                )
    in
    case List.head (List.drop next regions) of
        Just ( region, domId ) ->
            ( { model | region = region }, Task.attempt (\_ -> NoOp) (Dom.focus domId) )

        Nothing ->
            ( model, Cmd.none )



-- MENU BAR


openMenu : Int -> Model -> ( Model, Cmd Msg )
openMenu index model =
    ( { model | menuBar = Just { index = index, active = -1, sub = Nothing }, popup = Nothing }, Cmd.none )


menuKey : Command -> Model -> ( Model, Cmd Msg )
menuKey command model =
    case ( model.menuBar, activeTab model ) of
        ( Just state, Just tab ) ->
            let
                all =
                    Menu.menus model tab

                count =
                    List.length all

                entries =
                    List.drop state.index all |> List.head |> Maybe.map .entries |> Maybe.withDefault []

                activeEntry =
                    List.drop state.active entries |> List.head

                children =
                    case activeEntry of
                        Just (Submenu _ items) ->
                            items

                        _ ->
                            []

                set s =
                    ( { model | menuBar = Just s }, Cmd.none )

                switchMenu delta =
                    set { index = modBy count (state.index + delta), active = -1, sub = Nothing }
            in
            case command of
                CmdEscape ->
                    if state.sub /= Nothing then
                        set { state | sub = Nothing }

                    else
                        ( { model | menuBar = Nothing }, focusList )

                CmdMenuBar ->
                    ( { model | menuBar = Nothing }, focusList )

                CmdMenuMnemonic i ->
                    openMenu i model

                CmdMove delta _ _ ->
                    case state.sub of
                        Just subIndex ->
                            set { state | sub = Just (step (Menu.selectable children) subIndex delta) }

                        Nothing ->
                            set { state | active = step (Menu.selectable entries) state.active delta }

                CmdLeft ->
                    if state.sub /= Nothing then
                        set { state | sub = Nothing }

                    else
                        switchMenu -1

                CmdRight ->
                    if state.sub == Nothing && not (List.isEmpty children) then
                        set { state | sub = Just (step (Menu.selectable children) -1 1) }

                    else
                        switchMenu 1

                CmdOpen ->
                    let
                        run entry =
                            case entry of
                                Just (Action { msg }) ->
                                    case msg of
                                        Just m ->
                                            update (MenuRun m) model

                                        Nothing ->
                                            ( model, Cmd.none )

                                Just (Submenu _ _) ->
                                    set { state | sub = Just (step (Menu.selectable children) -1 1) }

                                _ ->
                                    ( model, Cmd.none )
                    in
                    case state.sub of
                        Just subIndex ->
                            run (List.drop subIndex children |> List.head)

                        Nothing ->
                            run activeEntry

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( { model | menuBar = Nothing }, Cmd.none )


{-| The next selectable index after `current`, wrapping around.
-}
step : List Int -> Int -> Int -> Int
step indexes current delta =
    case indexes of
        [] ->
            current

        first :: _ ->
            let
                later =
                    List.filter (\i -> i > current) indexes

                earlier =
                    List.filter (\i -> i < current) indexes |> List.reverse
            in
            if delta > 0 then
                List.head later |> Maybe.withDefault first

            else
                List.head earlier |> Maybe.withDefault (List.reverse indexes |> List.head |> Maybe.withDefault first)


menuCmd : String -> String -> Command -> MenuEntry
menuCmd label key command =
    Action { label = label, key = key, msg = Just (KeyCommand command), checked = Nothing }


loadingEntry : MenuEntry
loadingEntry =
    Action { label = Text.loading, key = "", msg = Nothing, checked = Nothing }



-- LIST CURSOR AND SELECTION


typeahead : String -> Model -> ( Model, Cmd Msg )
typeahead char model =
    if char == " " && model.typeahead == "" then
        ( model, Cmd.none )

    else
        let
            buffer =
                model.typeahead ++ String.toLower char

            seq =
                model.typeaheadSeq + 1

            clear =
                Process.sleep 1000 |> Task.perform (\_ -> ClearTypeahead seq)

            withBuffer =
                { model | typeahead = buffer, typeaheadSeq = seq }
        in
        case activeTab model of
            Nothing ->
                ( withBuffer, clear )

            Just tab ->
                let
                    start =
                        if String.length buffer == 1 then
                            tab.cursor + 1

                        else
                            tab.cursor

                    count =
                        Array.length tab.visible

                    matches i =
                        Array.get (modBy (max 1 count) i) tab.visible
                            |> Maybe.map (\item -> String.startsWith buffer item.lower)
                            |> Maybe.withDefault False

                    found =
                        List.range start (start + count - 1)
                            |> List.filter matches
                            |> List.head
                            |> Maybe.map (modBy (max 1 count))
                in
                case found of
                    Just index ->
                        moveCursor (\_ -> index) False False withBuffer |> addCmd clear

                    Nothing ->
                        ( withBuffer, clear )


moveCursor : (Tab -> Int) -> Bool -> Bool -> Model -> ( Model, Cmd Msg )
moveCursor target shift ctrl model =
    ( updateActive (\tab -> moveCursorTo (target tab) shift ctrl tab) model, Cmd.none )
        |> ensureCursorVisible


moveCursorTo : Int -> Bool -> Bool -> Tab -> Tab
moveCursorTo index shift ctrl tab =
    let
        count =
            Array.length tab.visible

        i =
            clamp 0 (count - 1) index
    in
    if count == 0 then
        tab

    else if shift then
        { tab | cursor = i, selected = rangeSelection tab.anchor i tab }

    else if ctrl then
        { tab | cursor = i }

    else
        { tab | cursor = i, anchor = i, selected = nameSet i tab }


clickRow : Int -> Mods -> Tab -> Tab
clickRow index mods tab =
    if mods.shift then
        { tab | cursor = index, selected = rangeSelection tab.anchor index tab }

    else if mods.ctrl then
        case Array.get index tab.visible of
            Just item ->
                { tab | cursor = index, anchor = index, selected = toggle item.name tab.selected }

            Nothing ->
                tab

    else
        { tab | cursor = index, anchor = index, selected = nameSet index tab }


rangeSelection : Int -> Int -> Tab -> Set String
rangeSelection a b tab =
    Array.slice (min a b) (max a b + 1) tab.visible
        |> Array.foldl (\item -> Set.insert item.name) Set.empty


nameSet : Int -> Tab -> Set String
nameSet index tab =
    Array.get index tab.visible
        |> Maybe.map (\item -> Set.singleton item.name)
        |> Maybe.withDefault Set.empty


toggle : comparable -> Set comparable -> Set comparable
toggle value set =
    if Set.member value set then
        Set.remove value set

    else
        Set.insert value set


selectedItems : Tab -> List Item
selectedItems tab =
    Array.toList tab.visible |> List.filter (\item -> Set.member item.name tab.selected)


ensureCursorVisible : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
ensureCursorVisible ( model, cmd ) =
    case activeTab model of
        Nothing ->
            ( model, cmd )

        Just tab ->
            let
                top =
                    toFloat tab.cursor * rowHeight

                body =
                    model.viewportHeight - headerHeight

                newTop =
                    if top < tab.scrollTop then
                        Just top

                    else if top + rowHeight > tab.scrollTop + body then
                        Just (top + rowHeight - body)

                    else
                        Nothing
            in
            case newTop of
                Just y ->
                    ( replaceTab { tab | scrollTop = y } model, Cmd.batch [ cmd, scrollListTo y ] )

                Nothing ->
                    ( model, cmd )


scrollListTo : Float -> Cmd Msg
scrollListTo y =
    Task.attempt (\_ -> NoOp) (Dom.setViewportOf listId 0 y)


focusList : Cmd Msg
focusList =
    Task.attempt (\_ -> NoOp) (Dom.focus listId)


measureList : Cmd Msg
measureList =
    Task.attempt GotListViewport (Dom.getViewportOf listId)



-- NAVIGATION AND TABS


type NavMode
    = Push
    | GoingBack
    | GoingForward


navigate : NavMode -> String -> Maybe String -> Model -> ( Model, Cmd Msg )
navigate mode path select model =
    case activeTab model of
        Nothing ->
            ( model, Cmd.none )

        Just tab ->
            let
                withHistory =
                    case mode of
                        Push ->
                            if path == tab.path then
                                tab

                            else
                                { tab | back = List.take 100 (tab.path :: tab.back), forward = [] }

                        GoingBack ->
                            { tab | back = List.drop 1 tab.back, forward = tab.path :: tab.forward }

                        GoingForward ->
                            { tab | back = tab.path :: tab.back, forward = List.drop 1 tab.forward }

                view =
                    defaultView model

                moved =
                    resetListing
                        { withHistory
                            | path = path
                            , pendingSelect = select
                            , view = view
                            , savedView = view
                            , viewSource = Nothing
                            , columnFilters = Dict.empty
                            , filter =
                                if model.settings.keepFilterOnNavigate then
                                    tab.filter

                                else
                                    ""
                        }

                focus =
                    if model.region == RegionSidebar then
                        Cmd.none

                    else
                        focusList
            in
            { model | address = ShowCrumbs, popup = Nothing, recent = addRecent path model.recent, freeSpace = Nothing }
                |> replaceTab moved
                |> loadTab moved.id
                |> andThen (loadView moved.id)
                |> andThen persist
                |> andThen followCurrentInTree
                |> addCmd (Cmd.batch [ scrollListTo 0, focus ])


resetListing : Tab -> Tab
resetListing tab =
    { tab
        | items = Dict.empty
        , ordered = []
        , visible = Array.empty
        , hiddenCount = 0
        , folderCount = 0
        , unfilteredCount = 0
        , selected = Set.empty
        , cursor = 0
        , anchor = 0
        , scrollTop = 0
        , status = Loading
    }


addRecent : String -> List String -> List String
addRecent path recent =
    List.take 50 (path :: List.filter ((/=) path) recent)


loadTab : Int -> Model -> ( Model, Cmd Msg )
loadTab tabId model =
    case findTab tabId model of
        Nothing ->
            ( model, Cmd.none )

        Just tab ->
            let
                ( withRequest, cmd ) =
                    request "dir_list" (E.object [ ( "path", E.string tab.path ) ]) True (ReqList tabId) model
            in
            ( replaceTab { tab | req = model.nextReq, status = Loading, chunks = 0 } withRequest, cmd )


loadView : Int -> Model -> ( Model, Cmd Msg )
loadView tabId model =
    case findTab tabId model of
        Just tab ->
            request "folder_view_get" (E.object [ ( "path", E.string tab.path ) ]) False (ReqView tabId tab.path) model

        Nothing ->
            ( model, Cmd.none )


addTab : String -> Bool -> Model -> ( Model, Cmd Msg )
addTab path activate model =
    let
        tab =
            emptyTab model model.nextTabId path

        withTab =
            { model | tabs = model.tabs ++ [ tab ], nextTabId = model.nextTabId + 1 }
    in
    if activate then
        activateTab tab.id withTab

    else
        persist withTab


activateTab : Int -> Model -> ( Model, Cmd Msg )
activateTab tabId model =
    case findTab tabId model of
        Nothing ->
            ( model, Cmd.none )

        Just tab ->
            let
                switched =
                    { model | active = tabId, address = ShowCrumbs, popup = Nothing, freeSpace = Nothing }

                ( loaded, loadCmd ) =
                    if tab.status == Idle then
                        loadTab tabId switched |> andThen (loadView tabId)

                    else
                        requestFreeSpace tab.path switched
            in
            persist loaded
                |> andThen followCurrentInTree
                |> addCmd (Cmd.batch [ loadCmd, scrollListTo tab.scrollTop, focusList ])


closeTab : Int -> Model -> ( Model, Cmd Msg )
closeTab tabId model =
    case ( findTab tabId model, model.tabs ) of
        ( Just tab, _ :: _ :: _ ) ->
            let
                index =
                    List.length (List.filter (\t -> t.id < tabId) model.tabs)

                remaining =
                    List.filter (\t -> t.id /= tabId) model.tabs

                closed =
                    { model | tabs = remaining, closedTabs = List.take 20 (tab.path :: model.closedTabs) }
            in
            if tabId == model.active then
                case List.head (List.drop (min index (List.length remaining - 1)) remaining) of
                    Just next ->
                        activateTab next.id closed

                    Nothing ->
                        persist closed

            else
                persist closed

        _ ->
            ( model, Cmd.none )


tabIdAtOffset : Int -> Model -> Int
tabIdAtOffset offset model =
    let
        ids =
            List.map .id model.tabs

        index =
            List.length (List.filter (\i -> i < model.active) ids)
    in
    List.drop (modBy (max 1 (List.length ids)) (index + offset)) ids |> List.head |> Maybe.withDefault model.active


openItem : Item -> Model -> ( Model, Cmd Msg )
openItem item model =
    if item.isDir then
        navigate Push item.path Nothing model

    else
        openFiles [ item ] model


openFiles : List Item -> Model -> ( Model, Cmd Msg )
openFiles items model =
    List.foldl
        (\item acc -> acc |> andThen (request "open_item" (E.object [ ( "path", E.string item.path ) ]) False ReqOpen))
        ( model, Cmd.none )
        (List.take 20 items)


openBookmark : Bookmark -> Bool -> Model -> ( Model, Cmd Msg )
openBookmark bookmark newTab model =
    if not bookmark.exists then
        flash (Text.missingTarget bookmark.target) model

    else if bookmark.kind == "folder" then
        if newTab then
            addTab bookmark.target False model

        else
            navigate Push bookmark.target Nothing model

    else
        request "open_item" (E.object [ ( "path", E.string bookmark.target ) ]) False ReqOpen model


{-| Saves the open tabs and watches their folders.
-}
persist : Model -> ( Model, Cmd Msg )
persist model =
    let
        paths =
            List.map .path model.tabs

        activeIndex =
            List.length (List.filter (\t -> t.id < model.active) model.tabs)

        session =
            E.object
                [ ( "activeTab", E.int activeIndex )
                , ( "tabs", E.list E.string paths )
                , ( "recent", E.list E.string model.recent )
                ]
    in
    ( model, Cmd.none )
        |> andThen (request "session_save" (E.object [ ( "session", session ) ]) False ReqIgnore)
        |> andThen (request "watch_set" (E.object [ ( "paths", E.list E.string (dedupe paths) ) ]) False ReqIgnore)


requestFreeSpace : String -> Model -> ( Model, Cmd Msg )
requestFreeSpace path =
    request "free_space" (E.object [ ( "path", E.string path ) ]) False (ReqFreeSpace path)



-- ADDRESS BAR


startEditAddress : Model -> ( Model, Cmd Msg )
startEditAddress model =
    withActive model
        (\tab ->
            Just
                ( { model | address = Editing tab.path Nothing, popup = Nothing, menuBar = Nothing }
                , Task.attempt (\_ -> NoOp) (Dom.focus addressInputId)
                )
        )


addressKey : String -> Model -> ( Model, Cmd Msg )
addressKey key model =
    case ( model.address, activeTab model ) of
        ( Editing typed _, Just tab ) ->
            case key of
                "Enter" ->
                    request "resolve_path"
                        (E.object [ ( "input", E.string typed ), ( "base", E.string tab.path ) ])
                        False
                        (ReqResolve tab.id)
                        model

                "Escape" ->
                    ( { model | address = ShowCrumbs }, focusList )

                "Tab" ->
                    case List.reverse (String.indexes model.sep typed) of
                        last :: _ ->
                            request "list_subfolders"
                                (E.object [ ( "path", E.string (String.left (last + 1) typed) ), ( "showHidden", E.bool True ) ])
                                False
                                (ReqSubfolders (ForComplete typed))
                                model

                        [] ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


complete : String -> List Path.Crumb -> Model -> Model
complete typed folders model =
    case model.address of
        Editing current _ ->
            if current /= typed then
                model

            else
                let
                    partial =
                        String.toLower (List.reverse (String.split model.sep typed) |> List.head |> Maybe.withDefault "")
                in
                case List.filter (\f -> String.startsWith partial (String.toLower f.label)) folders of
                    first :: _ ->
                        if String.toLower first.label == partial && partial /= "" then
                            { model | address = Editing (first.path ++ model.sep) Nothing }

                        else
                            { model | address = Editing first.path Nothing }

                    [] ->
                        model

        ShowCrumbs ->
            model



-- VIEWS (sorting, filters, columns, saved views)


{-| Applies a view change to a tab and redraws it.
-}
changeView : (FolderView -> FolderView) -> Model -> Tab -> Tab
changeView change model tab =
    recompute model { tab | view = change tab.view }


toggleColumn : Column -> FolderView -> FolderView
toggleColumn column view =
    if List.any (\( c, _ ) -> c == column) view.columns then
        if column == Columns.Name then
            view

        else
            { view | columns = List.filter (\( c, _ ) -> c /= column) view.columns }

    else
        { view | columns = view.columns ++ [ ( column, Columns.defaultWidth column ) ] }


sortClick : Column -> Bool -> FolderView -> FolderView
sortClick column shift view =
    let
        sort =
            case ( view.sort, shift ) of
                ( ( primary, desc ) :: rest, True ) ->
                    if primary == column then
                        ( primary, not desc ) :: rest

                    else
                        case rest of
                            ( second, secondDesc ) :: _ ->
                                if second == column then
                                    [ ( primary, desc ), ( second, not secondDesc ) ]

                                else
                                    [ ( primary, desc ), ( column, False ) ]

                            [] ->
                                [ ( primary, desc ), ( column, False ) ]

                ( ( primary, desc ) :: _, False ) ->
                    if primary == column then
                        [ ( primary, not desc ) ]

                    else
                        [ ( column, False ) ]

                ( [], _ ) ->
                    [ ( column, False ) ]
    in
    { view | sort = sort }


mouseMove : Float -> Float -> Model -> ( Model, Cmd Msg )
mouseMove x y model =
    case model.drag of
        Just (DragItems d) ->
            ( { model | drag = Just (DragItems { d | x = x, y = y, moved = d.moved || abs (x - d.startX) + abs (y - d.startY) > 6 }) }, Cmd.none )

        Just (ResizeColumn column startX startWidth) ->
            let
                width =
                    max 40 (startWidth + x - startX)
            in
            ( updateActive
                (\tab ->
                    let
                        view =
                            tab.view
                    in
                    { tab
                        | view =
                            { view
                                | columns =
                                    List.map
                                        (\( c, w ) ->
                                            ( c
                                            , if c == column then
                                                width

                                              else
                                                w
                                            )
                                        )
                                        view.columns
                            }
                    }
                )
                model
            , Cmd.none
            )

        Just (MoveColumn d) ->
            ( { model | drag = Just (MoveColumn { d | moved = d.moved || abs (x - d.startX) > 5 }) }, Cmd.none )

        Just (ResizeSidebar d) ->
            let
                delta =
                    if model.settings.sidebarSide == "right" then
                        d.startX - x

                    else
                        x - d.startX
            in
            ( { model | drag = Just (ResizeSidebar { d | width = clamp 160 640 (d.startWidth + delta) }) }, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


mouseUp : DropMods -> Model -> ( Model, Cmd Msg )
mouseUp mods model =
    let
        done =
            { model | drag = Nothing }
    in
    case model.drag of
        Just (DragItems d) ->
            if d.moved then
                let
                    -- The element under the pointer decides; hover events can arrive late.
                    target =
                        case mods.under of
                            Just "bookmark-bar" ->
                                Just DropBookmarkBar

                            Just path ->
                                if List.member path d.paths then
                                    Nothing

                                else
                                    Just (DropFolder path)

                            Nothing ->
                                d.target
                in
                dropItems mods d.paths target done

            else
                ( done, Cmd.none )

        Just (MoveColumn d) ->
            if not d.moved then
                ( updateActive (\tab -> changeView (sortClick d.column d.shift) model tab) done, Cmd.none )

            else
                case d.target of
                    Just target ->
                        ( updateActive (\tab -> { tab | view = moveColumn d.column target tab.view }) done, Cmd.none )

                    Nothing ->
                        ( done, Cmd.none )

        Just (ResizeSidebar d) ->
            setSetting "layout.sidebar.width" (E.int (round d.width)) (\s -> { s | sidebarWidth = toFloat (round d.width) }) done

        _ ->
            ( done, measureList )


moveColumn : Column -> Column -> FolderView -> FolderView
moveColumn column target view =
    case List.filter (\( c, _ ) -> c == column) view.columns of
        moving :: _ ->
            if column == target then
                view

            else
                let
                    others =
                        List.filter (\( c, _ ) -> c /= column) view.columns

                    oldIndex =
                        indexWhere (\( c, _ ) -> c == column) view.columns

                    targetIndex =
                        indexWhere (\( c, _ ) -> c == target) others

                    -- Dropping on a column to the right puts it after that column.
                    insertAt =
                        if targetIndex >= oldIndex then
                            targetIndex + 1

                        else
                            targetIndex
                in
                { view | columns = List.take insertAt others ++ [ moving ] ++ List.drop insertAt others }

        [] ->
            view


indexWhere : (a -> Bool) -> List a -> Int
indexWhere test list =
    list |> List.indexedMap Tuple.pair |> List.filter (Tuple.second >> test) |> List.head |> Maybe.map Tuple.first |> Maybe.withDefault 0


saveView : Bool -> Model -> ( Model, Cmd Msg )
saveView subfolders model =
    withActive model
        (\tab ->
            Just
                (request "folder_view_save"
                    (E.object
                        [ ( "path", E.string tab.path )
                        , ( "view", encodeView tab.view )
                        , ( "applyToSubfolders", E.bool subfolders )
                        ]
                    )
                    False
                    (ReqViewSaved tab.id tab.path)
                    model
                )
        )


encodeView : FolderView -> E.Value
encodeView view =
    E.object
        [ ( "mode", E.string "details" )
        , ( "columns", E.list (Tuple.first >> Columns.toString >> E.string) view.columns )
        , ( "widths", E.object (List.map (\( c, w ) -> ( Columns.toString c, E.int (round w) )) view.columns) )
        , ( "sort"
          , E.list
                (\( c, desc ) ->
                    E.object
                        [ ( "column", E.string (Columns.toString c) )
                        , ( "direction"
                          , E.string
                                (if desc then
                                    "desc"

                                 else
                                    "asc"
                                )
                          )
                        ]
                )
                view.sort
          )
        , ( "foldersFirst", E.bool view.foldersFirst )
        , ( "showHidden", E.bool view.showHidden )
        ]


viewDecoder : Model -> D.Decoder FolderView
viewDecoder model =
    let
        fallback =
            defaultView model
    in
    D.map5
        (\columns widths sort foldersFirst showHidden ->
            let
                chosen =
                    columns
                        |> List.filterMap Columns.fromString
                        |> List.filter (\c -> c /= Columns.Sync || model.syncSupported)
                        |> dedupe
                        |> withName

                sortKeys =
                    List.filterMap
                        (\( c, d ) -> Columns.fromString c |> Maybe.map (\col -> ( col, d == "desc" )))
                        sort
            in
            { columns =
                if List.isEmpty columns then
                    fallback.columns

                else
                    List.map
                        (\c -> ( c, Dict.get (Columns.toString c) widths |> Maybe.map toFloat |> Maybe.withDefault (Columns.defaultWidth c) ))
                        chosen
            , sort =
                if List.isEmpty sortKeys then
                    fallback.sort

                else
                    List.take 2 sortKeys
            , foldersFirst = foldersFirst
            , showHidden = showHidden
            }
        )
        (D.field "columns" (D.list D.string))
        (D.field "widths" (D.dict D.int))
        (D.field "sort" (D.list (D.map2 Tuple.pair (D.field "column" D.string) (D.field "direction" D.string))))
        (D.field "foldersFirst" D.bool)
        (D.field "showHidden" D.bool)


{-| Values and counts for a column filter drop-down, taken from the items
the other filters leave (like Excel).
-}
columnFilterState : Model -> Tab -> Column -> Float -> Float -> Time.Posix -> ColumnFilterState
columnFilterState model tab column x y now =
    let
        name =
            Columns.toString column

        candidates =
            filtered model { tab | columnFilters = Dict.remove name tab.columnFilters }

        counts =
            List.foldl
                (\item -> Dict.update (Columns.filterValue model.zone column item) (Just << (+) 1 << Maybe.withDefault 0))
                Dict.empty
                candidates

        values =
            Dict.toList counts
                |> (if Columns.isDate column then
                        List.sortBy Tuple.first >> List.reverse

                    else if column == Columns.Size then
                        List.sortBy (Tuple.first >> Columns.sizeBucketOrder)

                    else
                        List.sortBy (Tuple.first >> Item.naturalKey)
                   )
    in
    { column = column
    , x = x
    , y = y
    , search = ""
    , values = values
    , checked = Dict.get name tab.columnFilters |> Maybe.withDefault (Set.fromList (List.map Tuple.first values))
    , now = now
    }


quickDateChoice : Time.Zone -> Time.Posix -> String -> List ( String, Int ) -> Set String
quickDateChoice zone now choice values =
    let
        day offset =
            Format.date "yyyy-MM-dd" zone (Time.posixToMillis now - offset * 86400000)

        today =
            day 0

        weekday =
            case Time.toWeekday zone now of
                Time.Mon ->
                    0

                Time.Tue ->
                    1

                Time.Wed ->
                    2

                Time.Thu ->
                    3

                Time.Fri ->
                    4

                Time.Sat ->
                    5

                Time.Sun ->
                    6

        test v =
            case choice of
                "today" ->
                    v == today

                "yesterday" ->
                    v == day 1

                "week" ->
                    v >= day weekday && v <= today

                "last7" ->
                    v >= day 6 && v <= today

                "month" ->
                    String.left 7 v == String.left 7 today

                "year" ->
                    String.left 4 v == String.left 4 today

                _ ->
                    False
    in
    values |> List.map Tuple.first |> List.filter test |> Set.fromList


updateFilterPopup : (ColumnFilterState -> ColumnFilterState) -> Model -> Model
updateFilterPopup f model =
    case model.popup of
        Just (ColumnFilterPopup s) ->
            { model | popup = Just (ColumnFilterPopup (f s)) }

        _ ->
            model



-- LISTING


byName : List Item -> Dict String Item
byName items =
    insertAll items Dict.empty


insertAll : List Item -> Dict String Item -> Dict String Item
insertAll items dict =
    List.foldl (\item -> Dict.insert item.name item) dict items


applyPatch : Patch -> Tab -> Tab
applyPatch patch tab =
    { tab | items = insertAll (patch.added ++ patch.changed) (List.foldl Dict.remove tab.items patch.removed) }


{-| Re-sorts and re-filters the tab.
-}
recompute : Model -> Tab -> Tab
recompute model tab =
    refilter model { tab | ordered = sortItems tab.view (Dict.values tab.items) }


{-| Applies the hidden-files setting, Quick Filter and column filters to the
sorted items, keeping the cursor on the same item.
-}
refilter : Model -> Tab -> Tab
refilter model tab =
    let
        notHidden =
            withoutHidden tab

        shown =
            Array.fromList (filtered model tab)

        lastIndex =
            max 0 (Array.length shown - 1)

        cursor =
            Array.get tab.cursor tab.visible
                |> Maybe.andThen (\item -> indexOf item.name shown)
                |> Maybe.withDefault (min tab.cursor lastIndex)
    in
    { tab
        | visible = shown
        , hiddenCount = List.length tab.ordered - List.length notHidden
        , unfilteredCount = List.length notHidden
        , folderCount =
            Array.foldl
                (\i n ->
                    if i.isDir then
                        n + 1

                    else
                        n
                )
                0
                shown
        , cursor = cursor
        , anchor = min tab.anchor lastIndex
        , selected = Set.filter (\name -> Dict.member name tab.items) tab.selected
    }


withoutHidden : Tab -> List Item
withoutHidden tab =
    if tab.view.showHidden then
        tab.ordered

    else
        List.filter (not << .hidden) tab.ordered


filtered : Model -> Tab -> List Item
filtered model tab =
    let
        query =
            Filter.parse tab.filter

        columnTests =
            Dict.toList tab.columnFilters
                |> List.filterMap (\( name, allowed ) -> Columns.fromString name |> Maybe.map (\c -> ( c, allowed )))

        passes item =
            Filter.matches query item
                && List.all (\( c, allowed ) -> Set.member (Columns.filterValue model.zone c item) allowed) columnTests
    in
    if Filter.isEmpty query && List.isEmpty columnTests then
        withoutHidden tab

    else
        List.filter passes (withoutHidden tab)


indexOf : String -> Array Item -> Maybe Int
indexOf name items =
    Array.foldl
        (\item ( i, found ) ->
            case found of
                Just _ ->
                    ( i, found )

                Nothing ->
                    if item.name == name then
                        ( i, Just i )

                    else
                        ( i + 1, Nothing )
        )
        ( 0, Nothing )
        items
        |> Tuple.second


sortItems : FolderView -> List Item -> List Item
sortItems view items =
    let
        sorted =
            case view.sort of
                [ ( Columns.Name, desc ) ] ->
                    List.sortBy .key items |> reverseIf desc

                [ ( column, desc ) ] ->
                    List.sortBy (\i -> ( Columns.sortKey column i, i.key )) items |> reverseIf desc

                ( c1, d1 ) :: ( c2, d2 ) :: _ ->
                    items
                        |> List.map (\i -> ( ( Columns.sortKey c1 i, Columns.sortKey c2 i ), i ))
                        |> List.sortWith
                            (\( ( a1, a2 ), a ) ( ( b1, b2 ), b ) ->
                                case directed d1 (compare a1 b1) of
                                    EQ ->
                                        case directed d2 (compare a2 b2) of
                                            EQ ->
                                                compare a.key b.key

                                            order ->
                                                order

                                    order ->
                                        order
                            )
                        |> List.map Tuple.second

                [] ->
                    List.sortBy .key items
    in
    if view.foldersFirst then
        let
            ( dirs, files ) =
                List.partition .isDir sorted
        in
        dirs ++ files

    else
        sorted


reverseIf : Bool -> List a -> List a
reverseIf condition list =
    if condition then
        List.reverse list

    else
        list


directed : Bool -> Order -> Order
directed desc order =
    if desc then
        case order of
            LT ->
                GT

            GT ->
                LT

            EQ ->
                EQ

    else
        order



-- SIDEBAR TREE


toggleTreeNode : String -> Model -> ( Model, Cmd Msg )
toggleTreeNode path model =
    if Set.member path model.treeExpanded then
        ( { model | treeExpanded = Set.remove path model.treeExpanded }, Cmd.none )

    else
        expandTree [ path ] model


{-| Expands tree nodes, loading their sub-folders when not loaded yet.
-}
expandTree : List String -> Model -> ( Model, Cmd Msg )
expandTree paths model =
    List.foldl
        (\path acc ->
            acc
                |> andThen
                    (\m ->
                        let
                            expanded =
                                { m | treeExpanded = Set.insert path m.treeExpanded }
                        in
                        if Dict.member path m.treeChildren then
                            ( expanded, Cmd.none )

                        else
                            request "list_subfolders"
                                (E.object [ ( "path", E.string path ), ( "showHidden", E.bool False ) ])
                                False
                                (ReqSubfolders (ForTree path))
                                expanded
                    )
        )
        ( model, Cmd.none )
        paths


{-| Opens the tree down to the current folder (FR-SB-01).
-}
followCurrentInTree : Model -> ( Model, Cmd Msg )
followCurrentInTree model =
    case activeTab model of
        Just tab ->
            if model.settings.sidebarVisible && sidebarModeFromString model.settings.sidebarMode == TreeMode then
                let
                    inside root =
                        tab.path == root.path || String.startsWith (withSep model.sep root.path) tab.path

                    best =
                        model.roots
                            |> List.filter inside
                            |> List.sortBy (\r -> -(String.length r.path))
                            |> List.head
                in
                case best of
                    Just root ->
                        let
                            ancestors =
                                Path.crumbs model.sep tab.path
                                    |> List.map .path
                                    |> List.filter (\p -> p /= tab.path && (p == root.path || String.startsWith (withSep model.sep root.path) p))
                        in
                        expandTree (root.path :: ancestors) { model | treeCursor = Just tab.path }

                    Nothing ->
                        ( { model | treeCursor = Just tab.path }, Cmd.none )

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


withSep : String -> String -> String
withSep sep path =
    if String.endsWith sep path then
        path

    else
        path ++ sep


isTreeKey : Command -> Bool
isTreeKey command =
    case command of
        CmdMove _ _ _ ->
            True

        CmdPage _ _ _ ->
            True

        CmdEdge _ _ ->
            True

        CmdLeft ->
            True

        CmdRight ->
            True

        CmdOpen ->
            True

        _ ->
            False


treeKey : Command -> Model -> ( Model, Cmd Msg )
treeKey command model =
    let
        rows =
            View.treeRows model

        count =
            List.length rows

        index =
            model.treeCursor
                |> Maybe.map (\p -> indexWhere (\r -> r.path == p) rows)
                |> Maybe.withDefault 0

        at i =
            List.drop (clamp 0 (count - 1) i) rows |> List.head

        moveTo i =
            ( { model | treeCursor = Maybe.map .path (at i) }, revealTreeCursor )

        current =
            at index
    in
    case ( command, current ) of
        ( CmdMove delta _ _, _ ) ->
            moveTo (index + delta)

        ( CmdPage delta _ _, _ ) ->
            moveTo (index + delta * 10)

        ( CmdEdge toEnd _, _ ) ->
            moveTo
                (if toEnd then
                    count - 1

                 else
                    0
                )

        ( CmdRight, Just row ) ->
            if Set.member row.path model.treeExpanded then
                moveTo (index + 1)

            else
                expandTree [ row.path ] model

        ( CmdLeft, Just row ) ->
            if Set.member row.path model.treeExpanded then
                ( { model | treeExpanded = Set.remove row.path model.treeExpanded }, Cmd.none )

            else
                let
                    parentIndex =
                        List.take index rows
                            |> List.indexedMap Tuple.pair
                            |> List.filter (\( _, r ) -> r.depth < row.depth)
                            |> List.reverse
                            |> List.head
                            |> Maybe.map Tuple.first
                            |> Maybe.withDefault index
                in
                moveTo parentIndex

        ( CmdOpen, Just row ) ->
            navigate Push row.path Nothing model

        _ ->
            ( model, Cmd.none )


{-| Scrolls the sidebar so the tree cursor row is visible.
-}
revealTreeCursor : Cmd Msg
revealTreeCursor =
    Task.map3
        (\row body viewport ->
            let
                top =
                    row.element.y - body.element.y + viewport.viewport.y

                bottom =
                    top + row.element.height
            in
            if top < viewport.viewport.y then
                Just (top - 24)

            else if bottom > viewport.viewport.y + viewport.viewport.height then
                Just (bottom - viewport.viewport.height + 24)

            else
                Nothing
        )
        (Dom.getElement treeCursorId)
        (Dom.getElement sidebarBodyId)
        (Dom.getViewportOf sidebarBodyId)
        |> Task.andThen
            (\target ->
                case target of
                    Just y ->
                        Dom.setViewportOf sidebarBodyId 0 y

                    Nothing ->
                        Task.succeed ()
            )
        |> Task.attempt (\_ -> NoOp)



-- FILE OPERATIONS


{-| The items a command acts on: the selection, or the cursor item.
-}
targetItems : Tab -> List Item
targetItems tab =
    case selectedItems tab of
        [] ->
            Array.get tab.cursor tab.visible |> Maybe.map List.singleton |> Maybe.withDefault []

        items ->
            items


withTargets : Model -> (List Item -> ( Model, Cmd Msg )) -> ( Model, Cmd Msg )
withTargets model f =
    case activeTab model |> Maybe.map targetItems |> Maybe.withDefault [] of
        [] ->
            flash Text.nothingSelected model

        items ->
            f items


toClipboard : Bool -> Model -> ( Model, Cmd Msg )
toClipboard cut model =
    withTargets model
        (\items ->
            flash
                (if cut then
                    Text.itemsCut (List.length items)

                 else
                    Text.itemsCopied (List.length items)
                )
                { model | clipboard = Just { paths = List.map .path items, cut = cut } }
                -- Also on the system clipboard, so Explorer and other file managers can paste them (FR-OP-01).
                |> andThen
                    (request "clipboard_set_files"
                        (E.object [ ( "paths", E.list E.string (List.map .path items) ), ( "cut", E.bool cut ) ])
                        False
                        ReqIgnore
                    )
        )


startJob : String -> List String -> Maybe String -> Bool -> Model -> ( Model, Cmd Msg )
startJob kind sources dest permanent model =
    request "job_start"
        (E.object
            [ ( "request"
              , E.object
                    [ ( "kind", E.string kind )
                    , ( "sources", E.list E.string sources )
                    , ( "dest", Maybe.map E.string dest |> Maybe.withDefault E.null )
                    , ( "permanent", E.bool permanent )
                    ]
              )
            ]
        )
        False
        ReqJobStart
        model


{-| Del sends to the Recycle Bin (asking only if confirmDelete is on);
Shift+Del always asks first (FR-DEL-01, FR-DEL-02).
-}
deleteItems : Bool -> List Item -> Model -> ( Model, Cmd Msg )
deleteItems permanent items model =
    let
        paths =
            List.map .path items

        names =
            List.map .name items
    in
    if permanent then
        askConfirm
            { title = Text.deletePermanentlyTitle (List.length items)
            , lines = Text.nameList names
            , confirmLabel = Text.deletePermanently
            , onConfirm = StartJob "delete" paths Nothing True
            , danger = True
            }
            model

    else if model.settings.confirmDelete then
        askConfirm
            { title = Text.recycleTitle (List.length items)
            , lines = Text.nameList names
            , confirmLabel = Text.delete
            , onConfirm = StartJob "delete" paths Nothing False
            , danger = False
            }
            model

    else
        startJob "delete" paths Nothing False model


askConfirm : Confirm -> Model -> ( Model, Cmd Msg )
askConfirm confirm model =
    ( { model | dialog = Just (ConfirmDialog confirm), popup = Nothing, menuBar = Nothing }
      -- For dangerous actions Enter cancels, so a double Enter can't delete anything.
    , Task.attempt (\_ -> NoOp)
        (Dom.focus
            (if confirm.danger then
                "confirm-no"

             else
                "confirm-yes"
            )
        )
    )


{-| Reloads the tab and selects `name` when it shows up (FR-NEW-05).
-}
selectAfterReload : Int -> String -> Model -> ( Model, Cmd Msg )
selectAfterReload tabId name model =
    case findTab tabId model of
        Just tab ->
            loadTab tabId (replaceTab { tab | pendingSelect = Just name } model)

        Nothing ->
            ( model, Cmd.none )


reloadActive : Model -> ( Model, Cmd Msg )
reloadActive model =
    case activeTab model of
        Just tab ->
            if tab.status == Loaded then
                loadTab tab.id model

            else
                ( model, Cmd.none )

        Nothing ->
            ( model, Cmd.none )


isActiveJob : JobStatus -> Bool
isActiveJob job =
    List.member job.state [ "queued", "running", "paused", "waiting" ]


{-| Updates the job list; when a job ends, reports it and offers a
permanent delete for items the Recycle Bin refused (FR-DEL-03).
-}
jobProgress : JobStatus -> Model -> ( Model, Cmd Msg )
jobProgress job model =
    let
        wasActive =
            Dict.get job.id model.jobs |> Maybe.map isActiveJob |> Maybe.withDefault True

        updated =
            { model | jobs = Dict.insert job.id job model.jobs }

        refused =
            List.filter (\e -> e.code == "noTrash") job.errors
    in
    if isActiveJob job || not wasActive then
        ( updated, Cmd.none )

    else if job.kind == "delete" && not job.permanent && not (List.isEmpty refused) then
        askConfirm
            { title = Text.noRecycleTitle (List.length refused)
            , lines = Text.nameList (List.map (\e -> Path.name model.sep e.path) refused)
            , confirmLabel = Text.deletePermanently
            , onConfirm = StartJob "delete" (List.map .path refused) Nothing True
            , danger = True
            }
            updated
            |> andThen reloadActive

    else if not (List.isEmpty job.errors) then
        flash (Text.jobProblems (List.length job.errors)) { updated | jobsPanel = True }
            |> andThen reloadActive

    else
        flash (Text.jobFinished job.kind job.state job.count job.first job.permanent) updated
            |> andThen reloadActive


jobDecoder : D.Decoder JobStatus
jobDecoder =
    D.succeed JobStatus
        |> andMap (D.field "id" D.int)
        |> andMap (D.field "kind" D.string)
        |> andMap (D.field "state" D.string)
        |> andMap (D.field "permanent" D.bool)
        |> andMap (D.field "count" D.int)
        |> andMap (D.field "first" D.string)
        |> andMap (D.field "dest" (D.nullable D.string))
        |> andMap (D.field "doneItems" D.int)
        |> andMap (D.field "totalItems" D.int)
        |> andMap (D.field "doneBytes" D.int)
        |> andMap (D.field "totalBytes" D.int)
        |> andMap (D.field "current" D.string)
        |> andMap (D.field "elapsedMs" D.int)
        |> andMap (D.field "errors" (D.list (D.map3 JobError (D.field "path" D.string) (D.field "message" D.string) (D.field "code" D.string))))


conflictDecoder : D.Decoder Conflict
conflictDecoder =
    let
        info =
            D.map5 FileInfo
                (D.field "name" D.string)
                (D.field "path" D.string)
                (D.field "size" D.int)
                (D.field "modified" (D.nullable D.int))
                (D.field "isDir" D.bool)
    in
    D.map4 Conflict (D.field "jobId" D.int) (D.field "source" info) (D.field "target" info) (D.succeed False)


{-| The right-click menu for items (FR-CC-07).
-}
itemEntries : Model -> Tab -> Item -> List MenuEntry
itemEntries model tab item =
    let
        act label key msg =
            Action { label = label, key = key, msg = Just msg, checked = Nothing }

        single =
            List.length (targetItems tab) == 1

        pasteInto =
            case ( model.clipboard, item.isDir ) of
                ( Just c, True ) ->
                    [ act Text.pasteInto
                        ""
                        (StartJob
                            (if c.cut then
                                "move"

                             else
                                "copy"
                            )
                            c.paths
                            (Just item.path)
                            False
                        )
                    ]

                _ ->
                    []
    in
    [ act Text.open "Enter" (KeyCommand CmdOpen) ]
        ++ (if item.isDir then
                [ act Text.openInNewTab "Ctrl+Enter" (NavigateNewTab item.path) ]

            else
                []
           )
        ++ [ Separator
           , act Text.cut "Ctrl+X" (KeyCommand CmdCut)
           , act Text.copy "Ctrl+C" (KeyCommand CmdCopy)
           ]
        ++ pasteInto
        ++ [ act Text.duplicate "" (KeyCommand CmdDuplicate)
           , act Text.copyPath "Ctrl+Shift+C" (KeyCommand CmdCopyPath)
           , Separator
           ]
        ++ (if single then
                [ act Text.rename "F2" (KeyCommand CmdRename) ]

            else
                []
           )
        ++ [ act Text.delete "Del" (KeyCommand (CmdDelete False))
           , act Text.deletePermanently "Shift+Del" (KeyCommand (CmdDelete True))
           , Separator
           ]
        ++ (if item.isDir then
                [ act Text.pin "" (BookmarkEditOp [ ( "op", E.string "addFavourite" ), ( "path", E.string item.path ) ])
                , act Text.openTerminalHere "" (KeyCommand CmdOpenTerminal)
                ]

            else
                []
           )
        ++ [ act Text.bookmarkItem "" (KeyCommand CmdBookmarkItem)
           , act Text.reveal "" (RevealPath item.path)
           ]


{-| The right-click menu for empty space in the list.
-}
folderMenuEntries : Model -> Tab -> List MenuEntry
folderMenuEntries model tab =
    let
        act label key msg =
            Action { label = label, key = key, msg = Just msg, checked = Nothing }
    in
    [ act Text.newFolder "Ctrl+Shift+N" (KeyCommand CmdNewFolder)
    , act Text.newFile "Ctrl+N" (KeyCommand (CmdNewItem NewFile))
    , act Text.newShortcut "" (KeyCommand (CmdNewItem NewShortcut))
    , act Text.newWebLink "" (KeyCommand (CmdNewItem NewWebLink))
    , Separator
    , Action { label = Text.paste, key = "Ctrl+V", msg = Maybe.map (\_ -> KeyCommand CmdPaste) model.clipboard, checked = Nothing }
    , act Text.undo "Ctrl+Z" (KeyCommand CmdUndo)
    , Separator
    , act Text.selectAllItems "Ctrl+A" (KeyCommand CmdSelectAll)
    , act Text.refreshFolder "F5" (KeyCommand CmdRefresh)
    , act Text.openTerminalHere "" (KeyCommand CmdOpenTerminal)
    ]



-- CLIPBOARD, DRAG AND DROP, TEMPLATES


{-| Pastes files from the system clipboard, or from File Catalog's own when
the system one has no files. A cut made in File Catalog (or, on Windows, in
Explorer) moves; anything else copies (FR-OP-01).
-}
pasteFiles : Bool -> List String -> Maybe Bool -> Model -> ( Model, Cmd Msg )
pasteFiles asShortcut systemPaths systemCut model =
    let
        own =
            model.clipboard

        ( paths, cut, fromOwn ) =
            case ( systemPaths, own ) of
                ( [], Just c ) ->
                    ( c.paths, c.cut, True )

                ( _, Just c ) ->
                    if List.sort c.paths == List.sort systemPaths then
                        ( c.paths, c.cut, True )

                    else
                        ( systemPaths, Maybe.withDefault False systemCut, False )

                _ ->
                    ( systemPaths, Maybe.withDefault False systemCut, False )
    in
    case ( paths, activeTab model ) of
        ( [], _ ) ->
            flash Text.clipboardEmpty model

        ( _, Just tab ) ->
            if asShortcut then
                request "fs_create_shortcuts" (E.object [ ( "parent", E.string tab.path ), ( "targets", E.list E.string paths ) ]) False (ReqShortcuts tab.id) model

            else
                startJob
                    (if cut then
                        "move"

                     else
                        "copy"
                    )
                    paths
                    (Just tab.path)
                    False
                    (if cut && fromOwn then
                        { model | clipboard = Nothing }

                     else
                        model
                    )

        ( _, Nothing ) ->
            ( model, Cmd.none )


{-| Drop: Ctrl copies, Shift moves, Alt makes shortcuts; otherwise a move on
the same drive and a copy across drives (FR-COPY-06). On the Bookmark Bar,
dropped items become bookmarks (FR-BB-03).
-}
dropItems : DropMods -> List String -> Maybe DropTarget -> Model -> ( Model, Cmd Msg )
dropItems mods paths target model =
    case target of
        Just (DropFolder dest) ->
            if mods.alt then
                request "fs_create_shortcuts" (E.object [ ( "parent", E.string dest ), ( "targets", E.list E.string paths ) ]) False ReqIgnore model
                    |> andThen reloadActive

            else
                startJob
                    (if mods.ctrl then
                        "copy"

                     else if mods.shift then
                        "move"

                     else
                        "transfer"
                    )
                    paths
                    (Just dest)
                    False
                    model

        Just DropBookmarkBar ->
            List.foldl
                (\path acc ->
                    acc
                        |> andThen
                            (request "bookmarks_edit"
                                (E.object
                                    [ ( "edit"
                                      , E.object
                                            [ ( "op", E.string "add" )
                                            , ( "name", E.string (Path.name model.sep path) )
                                            , ( "target", E.string path )
                                            , ( "group", E.list E.string [ "bar" ] )
                                            ]
                                      )
                                    ]
                                )
                                False
                                ReqBookmarkEdit
                            )
                )
                ( model, Cmd.none )
                paths

        Nothing ->
            ( model, Cmd.none )


{-| The nearest `data-drop` value at or above an element.
-}
dropAttribute : D.Decoder (Maybe String)
dropAttribute =
    D.oneOf
        [ D.at [ "dataset", "drop" ] D.string |> D.map Just
        , D.field "parentElement" (D.nullable (D.lazy (\_ -> dropAttribute))) |> D.map (Maybe.andThen identity)
        , D.succeed Nothing
        ]


templateDecoder : D.Decoder Template
templateDecoder =
    D.map5 Template
        (D.field "name" D.string)
        (D.field "path" D.string)
        (D.field "isDir" D.bool)
        (D.field "group" (D.list D.string))
        (D.field "needsName" D.bool)


createFromTemplate : String -> String -> Model -> ( Model, Cmd Msg )
createFromTemplate template name model =
    case activeTab model of
        Just tab ->
            request "fs_create_from_template"
                (E.object
                    [ ( "parent", E.string tab.path )
                    , ( "template", E.string template )
                    , ( "name", E.string name )
                    , ( "today"
                      , E.list E.int
                            [ Time.toYear model.zone model.now
                            , Format.monthNumber (Time.toMonth model.zone model.now)
                            , Time.toDay model.zone model.now
                            ]
                      )
                    ]
                )
                False
                (ReqCreate tab.id False)
                model

        Nothing ->
            ( model, Cmd.none )


isTemplateForm : NewItemForm -> Bool
isTemplateForm form =
    case form.kind of
        NewFromTemplate _ ->
            True

        _ ->
            False



-- RENAME


startRename : Tab -> Item -> Model -> ( Model, Cmd Msg )
startRename tab item model =
    let
        state =
            { tabId = tab.id, original = item.name, text = item.name, error = Nothing, step = 0 }
    in
    ( { model | rename = Just state, popup = Nothing, menuBar = Nothing }, selectRenameText model state )


selectRenameText : Model -> RenameState -> Cmd Msg
selectRenameText model state =
    let
        isDir =
            activeTab model
                |> Maybe.andThen (\tab -> Dict.get state.original tab.items)
                |> Maybe.map .isDir
                |> Maybe.withDefault False

        ( start, end ) =
            FileName.selection isDir state.step state.text
    in
    Ports.selectText (E.object [ ( "id", E.string renameInputId ), ( "start", E.int start ), ( "end", E.int end ) ])


updateRename : (RenameState -> RenameState) -> Model -> Model
updateRename f model =
    { model | rename = Maybe.map f model.rename }


validateRename : Model -> String -> String -> Maybe String
validateRename model original text =
    let
        others =
            activeTab model |> Maybe.map (.items >> Dict.keys) |> Maybe.withDefault [] |> List.filter ((/=) original)
    in
    FileName.validate (model.sep == "\\") others text


{-| Enter or leaving the box ends the rename. A changed extension asks
first (FR-REN-03).
-}
commitRename : Bool -> Model -> ( Model, Cmd Msg )
commitRename pressedEnter model =
    case ( model.rename, model.dialog ) of
        ( Just r, Nothing ) ->
            if r.text == r.original then
                ( { model | rename = Nothing }, focusList )

            else
                case validateRename model r.original r.text of
                    Just error ->
                        if pressedEnter then
                            ( updateRename (\s -> { s | error = Just error }) model, Cmd.none )

                        else
                            ( { model | rename = Nothing }, Cmd.none )

                    Nothing ->
                        if model.settings.confirmExtensionChange && String.toLower (FileName.extension r.text) /= String.toLower (FileName.extension r.original) && not (isFolderName model r.original) then
                            askConfirm
                                { title = Text.changeExtensionTitle
                                , lines = [ Text.changeExtension (FileName.extension r.original) (FileName.extension r.text) ]
                                , confirmLabel = Text.changeIt
                                , onConfirm = ApplyRename
                                , danger = False
                                }
                                model

                        else
                            applyRename model

        _ ->
            ( model, Cmd.none )


isFolderName : Model -> String -> Bool
isFolderName model name =
    activeTab model |> Maybe.andThen (\tab -> Dict.get name tab.items) |> Maybe.map .isDir |> Maybe.withDefault False


applyRename : Model -> ( Model, Cmd Msg )
applyRename model =
    case ( model.rename, activeTab model ) of
        ( Just r, Just tab ) ->
            case Dict.get r.original tab.items of
                Just item ->
                    request "fs_rename"
                        (E.object [ ( "path", E.string item.path ), ( "newName", E.string r.text ) ])
                        False
                        (ReqRename r.tabId)
                        { model | rename = Nothing }
                        |> addCmd focusList

                Nothing ->
                    ( { model | rename = Nothing }, focusList )

        _ ->
            ( { model | rename = Nothing }, Cmd.none )



-- NEW ITEMS


updateNewItem : (NewItemForm -> NewItemForm) -> Model -> Model
updateNewItem f model =
    case model.dialog of
        Just (NewItemDialog form) ->
            { model | dialog = Just (NewItemDialog (f form)) }

        _ ->
            model


submitNewItem : Model -> ( Model, Cmd Msg )
submitNewItem model =
    case ( model.dialog, activeTab model ) of
        ( Just (NewItemDialog form), Just tab ) ->
            let
                target =
                    String.trim form.target

                name =
                    case ( String.trim form.name, form.kind ) of
                        ( "", NewShortcut ) ->
                            Path.name model.sep target

                        ( "", NewWebLink ) ->
                            domainOf target

                        ( n, _ ) ->
                            n

                item =
                    case form.kind of
                        NewFromTemplate _ ->
                            []

                        NewFile ->
                            [ ( "kind", E.string "file" ), ( "name", E.string name ) ]

                        NewShortcut ->
                            [ ( "kind", E.string "shortcut" ), ( "name", E.string name ), ( "target", E.string target ) ]

                        NewWebLink ->
                            [ ( "kind", E.string "webLink" ), ( "name", E.string name ), ( "url", E.string target ) ]

                problem =
                    if form.kind /= NewFile && not (isTemplateForm form) && (target == "" || target == "https://") then
                        Just Text.targetNeeded

                    else
                        FileName.validate (model.sep == "\\") (Dict.keys tab.items) name
            in
            case problem of
                Just error ->
                    ( updateNewItem (\f -> { f | error = Just error }) model, Cmd.none )

                Nothing ->
                    case form.kind of
                        NewFromTemplate template ->
                            createFromTemplate template name { model | dialog = Nothing }
                                |> addCmd focusList

                        _ ->
                            request "fs_create"
                                (E.object [ ( "parent", E.string tab.path ), ( "item", E.object item ) ])
                                False
                                (ReqCreate tab.id False)
                                { model | dialog = Nothing }
                                |> addCmd focusList

        _ ->
            ( model, Cmd.none )


{-| "example.com" from "<https://www.example.com/page">.
-}
domainOf : String -> String
domainOf url =
    url
        |> String.split "://"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault url
        |> String.split "/"
        |> List.head
        |> Maybe.withDefault url
        |> (\host ->
                if String.startsWith "www." host then
                    String.dropLeft 4 host

                else
                    host
           )



-- BOOKMARK DIALOG


openDialog : BookmarkForm -> Model -> ( Model, Cmd Msg )
openDialog form model =
    ( { model | dialog = Just (BookmarkDialog form), popup = Nothing, menuBar = Nothing }
    , Task.attempt (\_ -> NoOp) (Dom.focus dialogFirstInputId)
    )


updateDialog : (BookmarkForm -> BookmarkForm) -> Model -> Model
updateDialog f model =
    case model.dialog of
        Just (BookmarkDialog form) ->
            { model | dialog = Just (BookmarkDialog (f form)) }

        _ ->
            model


submitDialog : Model -> ( Model, Cmd Msg )
submitDialog model =
    case model.dialog of
        Just (BookmarkDialog form) ->
            let
                name =
                    String.trim form.name

                target =
                    String.trim form.target

                group =
                    String.split "/" form.group |> List.map String.trim |> List.filter ((/=) "")

                fields =
                    [ ( "name", E.string name ), ( "target", E.string target ), ( "group", E.list E.string group ) ]
            in
            if name == "" || target == "" then
                ( updateDialog (\f -> { f | error = Just Text.nameAndTargetNeeded }) model, Cmd.none )

            else
                let
                    op =
                        case form.index of
                            Just index ->
                                ( "op", E.string "update" ) :: ( "index", E.int index ) :: fields

                            Nothing ->
                                ( "op", E.string "add" ) :: fields
                in
                update (BookmarkEditOp op) { model | dialog = Nothing }
                    |> addCmd focusList

        _ ->
            ( model, Cmd.none )



-- BACKEND MESSAGES


type alias Envelope =
    { id : Int
    , kind : String
    , name : String
    , data : D.Value
    }


envelopeDecoder : D.Decoder Envelope
envelopeDecoder =
    D.map4 Envelope
        (D.field "id" D.int)
        (D.field "type" D.string)
        (D.oneOf [ D.field "name" D.string, D.succeed "" ])
        (D.field "data" D.value)


handleEnvelope : Envelope -> Model -> ( Model, Cmd Msg )
handleEnvelope envelope model =
    if envelope.kind == "event" then
        handleEvent envelope.name envelope.data model

    else
        case Dict.get envelope.id model.requests of
            Nothing ->
                ( model, Cmd.none )

            Just req ->
                let
                    -- A streamed listing stays open until its "done" or "error" message.
                    finished =
                        case ( req, envelope.kind ) of
                            ( ReqList _, "ok" ) ->
                                False

                            ( _, "stream" ) ->
                                False

                            _ ->
                                True

                    current =
                        if finished then
                            { model | requests = Dict.remove envelope.id model.requests }

                        else
                            model
                in
                handleResponse envelope.id req envelope current


handleResponse : Int -> Request -> Envelope -> Model -> ( Model, Cmd Msg )
handleResponse reqId req envelope model =
    let
        ok decoder =
            if envelope.kind == "ok" then
                D.decodeValue decoder envelope.data |> Result.toMaybe

            else
                Nothing

        errorMessage =
            if envelope.kind == "err" then
                D.decodeValue D.string envelope.data |> Result.toMaybe

            else
                Nothing

        flashError m =
            case errorMessage of
                Just message ->
                    flash message m

                Nothing ->
                    ( m, Cmd.none )
    in
    case req of
        ReqInit ->
            case ok initDecoder of
                Just data ->
                    boot data model

                Nothing ->
                    ( { model | bootError = Just (Maybe.withDefault "Could not start." errorMessage) }, Cmd.none )

        ReqList tabId ->
            if envelope.kind == "stream" then
                case D.decodeValue dirEventDecoder envelope.data of
                    Ok event ->
                        handleDirEvent reqId tabId event model

                    Err _ ->
                        ( model, Cmd.none )

            else
                case errorMessage of
                    Just message ->
                        handleDirEvent reqId tabId (EvError "other" message) model

                    Nothing ->
                        ( model, Cmd.none )

        ReqView tabId path ->
            case ( findTab tabId model, ok (D.map2 Tuple.pair (D.field "view" (D.nullable (viewDecoder model))) (D.field "source" (D.nullable D.string))) ) of
                ( Just tab, Just ( maybeView, source ) ) ->
                    if tab.path == path then
                        let
                            view =
                                Maybe.withDefault (defaultView model) maybeView
                        in
                        ( replaceTab (recompute model { tab | view = view, savedView = view, viewSource = source }) model, Cmd.none )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ReqViewSaved tabId path ->
            if envelope.kind == "ok" then
                case findTab tabId model of
                    Just tab ->
                        flash (Text.viewSaved (Path.name model.sep path)) (replaceTab { tab | savedView = tab.view, viewSource = Just path } model)

                    Nothing ->
                        ( model, Cmd.none )

            else
                flashError model

        ReqViewReset tabId path ->
            if envelope.kind == "ok" then
                loadView tabId model |> andThen (flash (Text.viewReset (Path.name model.sep path)))

            else
                flashError model

        ReqOpenSettingsFile ->
            case ok D.string of
                Just file ->
                    update (OpenPath file) model

                Nothing ->
                    flashError model

        ReqResolve tabId ->
            case ( ok resolvedDecoder, model.address ) of
                ( Just ( dir, select ), _ ) ->
                    if tabId == model.active then
                        navigate Push dir select model

                    else
                        ( model, Cmd.none )

                ( Nothing, Editing typed _ ) ->
                    ( { model | address = Editing typed errorMessage }, Cmd.none )

                ( Nothing, ShowCrumbs ) ->
                    ( model, Cmd.none )

        ReqSubfolders use ->
            let
                folders =
                    ok subfoldersDecoder |> Maybe.withDefault []
            in
            case use of
                ForCrumb path ->
                    case model.popup of
                        Just (MenuPopup p) ->
                            ( { model
                                | popup =
                                    Just
                                        (MenuPopup
                                            { p
                                                | entries =
                                                    if List.isEmpty folders then
                                                        [ Action { label = Text.noSubfolders, key = "", msg = Nothing, checked = Nothing } ]

                                                    else
                                                        List.map (\f -> Action { label = f.label, key = "", msg = Just (NavigateTo f.path), checked = Nothing }) folders
                                            }
                                        )
                              }
                            , Cmd.none
                            )

                        _ ->
                            ( model, Cmd.none )

                ForComplete typed ->
                    ( complete typed folders model, Cmd.none )

                ForTree path ->
                    ( { model | treeChildren = Dict.insert path folders model.treeChildren }, revealTreeCursor )

        ReqFreeSpace path ->
            if Maybe.map .path (activeTab model) == Just path then
                ( { model | freeSpace = ok (D.nullable D.int) |> Maybe.andThen identity }, Cmd.none )

            else
                ( model, Cmd.none )

        ReqBookmarks ->
            case ok bookmarksDecoder of
                Just ( favourites, bookmarks, warnings ) ->
                    ( { model | favourites = favourites, bookmarks = bookmarks, bookmarkWarnings = warnings }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ReqBookmarkEdit ->
            if envelope.kind == "ok" then
                request "bookmarks_get" (E.object []) False ReqBookmarks model

            else
                flashError model

        ReqOpen ->
            flashError model

        ReqIgnore ->
            ( model, Cmd.none )

        ReqJobStart ->
            flashError model

        ReqRename tabId ->
            case ok D.string of
                Just newPath ->
                    selectAfterReload tabId (Path.name model.sep newPath) model

                Nothing ->
                    flashError model

        ReqCreate tabId startRenaming ->
            case ok D.string of
                Just newPath ->
                    let
                        name =
                            Path.name model.sep newPath
                    in
                    selectAfterReload tabId
                        name
                        { model
                            | pendingRename =
                                if startRenaming then
                                    Just name

                                else
                                    Nothing
                        }

                Nothing ->
                    flashError model

        ReqUndo ->
            case ok D.string of
                Just message ->
                    flash message model |> andThen reloadActive

                Nothing ->
                    flashError model

        ReqCopied message ->
            if envelope.kind == "ok" then
                flash message model

            else
                flashError model

        ReqTemplates ->
            case ok (D.map2 Tuple.pair (D.field "folder" D.string) (D.field "templates" (D.list templateDecoder))) of
                Just ( folder, templates ) ->
                    ( { model | templatesFolder = folder, templates = templates }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        ReqTemplatesFolder saving ->
            case ( ok D.string, saving ) of
                ( Just folder, Just paths ) ->
                    startJob "copy" paths (Just folder) False { model | templatesFolder = folder }
                        |> andThen (request "templates_list" (E.object []) False ReqTemplates)

                ( Just folder, Nothing ) ->
                    addTab folder True model

                _ ->
                    flashError model

        ReqClipboard asShortcut ->
            case ok (D.map2 Tuple.pair (D.field "paths" (D.list D.string)) (D.field "cut" (D.nullable D.bool))) of
                Just ( paths, systemCut ) ->
                    pasteFiles asShortcut paths systemCut model

                Nothing ->
                    -- The system clipboard is not available: use File Catalog's own.
                    pasteFiles asShortcut [] Nothing model

        ReqShortcuts tabId ->
            case ok (D.list D.string) of
                Just (first :: _) ->
                    selectAfterReload tabId (Path.name model.sep first) model

                Just [] ->
                    ( model, Cmd.none )

                Nothing ->
                    flashError model


type alias InitData =
    { settings : Settings
    , warnings : List String
    , activeTab : Int
    , tabs : List String
    , recent : List String
    , home : String
    , sep : String
    , syncStatus : Bool
    , roots : List Root
    , settingsFile : String
    , bookmarksFile : String
    , version : String
    }


initDecoder : D.Decoder InitData
initDecoder =
    D.succeed InitData
        |> andMap (D.field "settings" Settings.decoder)
        |> andMap (D.field "warnings" (D.list D.string))
        |> andMap (D.at [ "session", "activeTab" ] D.int)
        |> andMap (D.at [ "session", "tabs" ] (D.list D.string))
        |> andMap (D.at [ "session", "recent" ] (D.list D.string))
        |> andMap (D.field "home" D.string)
        |> andMap (D.field "sep" D.string)
        |> andMap (D.field "syncStatus" D.bool)
        |> andMap (D.field "roots" (D.list (D.map3 Root (D.field "name" D.string) (D.field "path" D.string) (D.field "kind" D.string))))
        |> andMap (D.field "settingsFile" D.string)
        |> andMap (D.field "bookmarksFile" D.string)
        |> andMap (D.field "version" D.string)


andMap : D.Decoder a -> D.Decoder (a -> b) -> D.Decoder b
andMap =
    D.map2 (|>)


bookmarksDecoder : D.Decoder ( List Favourite, List Bookmark, List String )
bookmarksDecoder =
    D.map3 (\a b c -> ( a, b, c ))
        (D.field "favourites" (D.list (D.map2 Favourite (D.field "path" D.string) (D.field "exists" D.bool))))
        (D.field "bookmarks"
            (D.list
                (D.map6 Bookmark
                    (D.field "index" D.int)
                    (D.field "name" D.string)
                    (D.field "target" D.string)
                    (D.field "kind" D.string)
                    (D.field "group" (D.list D.string))
                    (D.field "exists" D.bool)
                )
            )
        )
        (D.field "warnings" (D.list D.string))


boot : InitData -> Model -> ( Model, Cmd Msg )
boot data model =
    let
        restored =
            if data.settings.restoreTabs then
                data.tabs

            else
                []

        lastFolder =
            List.head (List.drop data.activeTab data.tabs) |> Maybe.withDefault data.home

        startFolder =
            case data.settings.startupFolder of
                "home" ->
                    data.home

                "last" ->
                    lastFolder

                path ->
                    path

        ( paths, activeIndex ) =
            if List.isEmpty restored then
                ( [ startFolder ], 0 )

            else
                ( restored, clamp 0 (List.length restored - 1) data.activeTab )

        withSettings =
            { model
                | booted = True
                , settings = data.settings
                , warnings = data.warnings
                , recent = data.recent
                , home = data.home
                , sep = data.sep
                , syncSupported = data.syncStatus
                , roots = data.roots
                , settingsFile = data.settingsFile
                , bookmarksFile = data.bookmarksFile
                , version = data.version
            }

        tabs =
            List.indexedMap (\i path -> emptyTab withSettings (i + 1) path) paths

        booted =
            { withSettings | tabs = tabs, nextTabId = List.length tabs + 1, active = activeIndex + 1 }
    in
    loadTab booted.active booted
        |> andThen (loadView booted.active)
        |> andThen persist
        |> andThen (request "bookmarks_get" (E.object []) False ReqBookmarks)
        |> andThen (request "templates_list" (E.object []) False ReqTemplates)
        |> andThen (request "perf_mark" (E.object [ ( "label", E.string "ui-booted" ) ]) False ReqIgnore)
        |> addCmd (Cmd.batch [ focusList, measureList ])


type DirEvent
    = EvCached (List Item)
    | EvChunk (List Item)
    | EvPatch Patch
    | EvDone
    | EvError String String


type alias Patch =
    { added : List Item
    , removed : List String
    , changed : List Item
    }


patchDecoder : D.Decoder Patch
patchDecoder =
    D.map3 Patch
        (D.field "added" (D.list Item.decoder))
        (D.field "removed" (D.list D.string))
        (D.field "changed" (D.list Item.decoder))


dirEventDecoder : D.Decoder DirEvent
dirEventDecoder =
    D.field "type" D.string
        |> D.andThen
            (\kind ->
                case kind of
                    "cached" ->
                        D.map EvCached (D.field "items" (D.list Item.decoder))

                    "chunk" ->
                        D.map EvChunk (D.field "items" (D.list Item.decoder))

                    "patch" ->
                        D.map EvPatch patchDecoder

                    "done" ->
                        D.succeed EvDone

                    "error" ->
                        D.map2 EvError (D.field "kind" D.string) (D.field "message" D.string)

                    _ ->
                        D.fail kind
            )


handleDirEvent : Int -> Int -> DirEvent -> Model -> ( Model, Cmd Msg )
handleDirEvent reqId tabId event model =
    case findTab tabId model of
        Just tab ->
            if tab.req /= reqId then
                -- A stale answer for a folder this tab has already left.
                ( { model | requests = Dict.remove reqId model.requests }, Cmd.none )

            else
                case event of
                    EvCached items ->
                        ( replaceTab (recompute model { tab | items = byName items }) model, Cmd.none )

                    EvChunk items ->
                        let
                            chunks =
                                tab.chunks + 1

                            grown =
                                { tab | items = insertAll items tab.items, chunks = chunks }

                            -- Re-sorting on every chunk would be slow for huge folders.
                            shown =
                                if chunks == 1 || modBy 8 chunks == 0 then
                                    recompute model grown

                                else
                                    grown
                        in
                        ( replaceTab shown model, Cmd.none )

                    EvPatch patch ->
                        ( replaceTab (recompute model (applyPatch patch tab)) model, Cmd.none )

                    EvDone ->
                        finishLoading reqId tab model

                    EvError kind message ->
                        ( { model | requests = Dict.remove reqId model.requests }
                            |> replaceTab (resetListingTo (Failed kind message) tab)
                        , Cmd.none
                        )

        Nothing ->
            ( { model | requests = Dict.remove reqId model.requests }, Cmd.none )


finishLoading : Int -> Tab -> Model -> ( Model, Cmd Msg )
finishLoading reqId tab model =
    let
        loaded =
            recompute model { tab | status = Loaded }

        selected =
            case loaded.pendingSelect |> Maybe.andThen (\name -> indexOf name loaded.visible) of
                Just index ->
                    { loaded | cursor = index, anchor = index, selected = nameSet index loaded, pendingSelect = Nothing }

                Nothing ->
                    { loaded | pendingSelect = Nothing }

        updated =
            { model | requests = Dict.remove reqId model.requests } |> replaceTab selected

        -- A new folder starts in rename mode once it shows up (FR-NEW-01).
        renameNew m =
            case ( m.pendingRename, Array.get selected.cursor selected.visible ) of
                ( Just name, Just item ) ->
                    if item.name == name then
                        startRename selected item { m | pendingRename = Nothing }

                    else
                        ( m, Cmd.none )

                _ ->
                    ( m, Cmd.none )
    in
    if tab.id == model.active then
        ( updated, Cmd.none )
            |> ensureCursorVisible
            |> andThen renameNew
            |> andThen (requestFreeSpace tab.path)
            |> andThen
                (\m ->
                    if m.firstListingMarked then
                        ( m, Cmd.none )

                    else
                        -- The folder tree loads only after the first listing, so its
                        -- requests don't queue ahead of it at start-up.
                        request "perf_mark" (E.object [ ( "label", E.string "first-listing" ) ]) False ReqIgnore { m | firstListingMarked = True }
                            |> andThen followCurrentInTree
                )

    else
        ( updated, Cmd.none )


resetListingTo : Status -> Tab -> Tab
resetListingTo status tab =
    let
        reset =
            resetListing tab
    in
    { reset | status = status }


handleEvent : String -> D.Value -> Model -> ( Model, Cmd Msg )
handleEvent name data model =
    case name of
        "dir-changed" ->
            case D.decodeValue (D.map3 (\p patch gone -> ( p, patch, gone )) (D.field "path" D.string) patchDecoder (D.field "gone" D.bool)) data of
                Ok ( path, patch, gone ) ->
                    let
                        apply tab =
                            if tab.path /= path || tab.status /= Loaded then
                                tab

                            else if gone then
                                resetListingTo (Failed "notFound" "") tab

                            else
                                recompute model (applyPatch patch tab)
                    in
                    ( { model | tabs = List.map apply model.tabs }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        "settings-changed" ->
            case D.decodeValue (D.map2 Tuple.pair (D.field "settings" Settings.decoder) (D.field "warnings" (D.list D.string))) data of
                Ok ( settings, warnings ) ->
                    let
                        updated =
                            { model | settings = settings, warnings = warnings }

                        newDefault =
                            defaultView updated

                        -- Folders on the default view follow the new default.
                        adjust tab =
                            if tab.viewSource == Nothing && tab.view == tab.savedView then
                                recompute updated { tab | view = newDefault, savedView = newDefault }

                            else
                                tab
                    in
                    ( { updated | tabs = List.map adjust model.tabs }, measureList )

                Err _ ->
                    ( model, Cmd.none )

        "bookmarks-changed" ->
            request "bookmarks_get" (E.object []) False ReqBookmarks model

        "job-progress" ->
            case D.decodeValue jobDecoder data of
                Ok job ->
                    jobProgress job model

                Err _ ->
                    ( model, Cmd.none )

        "file-drop" ->
            case D.decodeValue (D.map3 (\k p t -> ( k, p, t )) (D.field "kind" D.string) (D.field "paths" (D.list D.string)) (D.field "target" (D.nullable D.string))) data of
                Ok ( "drop", paths, target ) ->
                    if List.isEmpty paths then
                        ( model, Cmd.none )

                    else
                        let
                            dropTarget =
                                case target of
                                    Just "bookmark-bar" ->
                                        Just DropBookmarkBar

                                    Just path ->
                                        Just (DropFolder path)

                                    Nothing ->
                                        activeTab model |> Maybe.map (.path >> DropFolder)
                        in
                        dropItems { ctrl = False, shift = False, alt = False, under = Nothing } paths dropTarget model

                _ ->
                    ( model, Cmd.none )

        "job-conflict" ->
            case D.decodeValue conflictDecoder data of
                Ok conflict ->
                    ( { model | conflicts = model.conflicts ++ [ conflict ] }, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )


resolvedDecoder : D.Decoder ( String, Maybe String )
resolvedDecoder =
    D.map2 Tuple.pair (D.field "dir" D.string) (D.field "select" (D.nullable D.string))


subfoldersDecoder : D.Decoder (List Path.Crumb)
subfoldersDecoder =
    D.list (D.map2 Path.Crumb (D.field "name" D.string) (D.field "path" D.string))



-- HELPERS


request : String -> E.Value -> Bool -> Request -> Model -> ( Model, Cmd Msg )
request cmd args stream kind model =
    ( { model | nextReq = model.nextReq + 1, requests = Dict.insert model.nextReq kind model.requests }
    , Ports.toBackend
        (E.object
            [ ( "id", E.int model.nextReq )
            , ( "cmd", E.string cmd )
            , ( "args", args )
            , ( "stream", E.bool stream )
            ]
        )
    )


andThen : (Model -> ( Model, Cmd Msg )) -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
andThen next ( model, cmd ) =
    let
        ( newModel, newCmd ) =
            next model
    in
    ( newModel, Cmd.batch [ cmd, newCmd ] )


addCmd : Cmd Msg -> ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
addCmd extra ( model, cmd ) =
    ( model, Cmd.batch [ cmd, extra ] )


flash : String -> Model -> ( Model, Cmd Msg )
flash message model =
    let
        seq =
            model.messageSeq + 1
    in
    ( { model | message = Just message, messageSeq = seq }
    , Process.sleep 4000 |> Task.perform (\_ -> HideMessage seq)
    )


updateActive : (Tab -> Tab) -> Model -> Model
updateActive f model =
    case activeTab model of
        Just tab ->
            replaceTab (f tab) model

        Nothing ->
            model


withActive : Model -> (Tab -> Maybe ( Model, Cmd Msg )) -> ( Model, Cmd Msg )
withActive model f =
    activeTab model |> Maybe.andThen f |> Maybe.withDefault ( model, Cmd.none )


dedupe : List a -> List a
dedupe =
    List.foldr
        (\x acc ->
            if List.member x acc then
                acc

            else
                x :: acc
        )
        []



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.fromBackend FromBackend
        , Browser.Events.onResize (\_ _ -> WindowResized)
        , Browser.Events.onKeyUp (D.map KeyUp (D.field "key" D.string))
        , Time.every 60000 GotTime
        , if model.drag /= Nothing then
            Sub.batch
                [ Browser.Events.onMouseMove (D.map2 MouseMove (D.field "clientX" D.float) (D.field "clientY" D.float))
                , Browser.Events.onMouseUp
                    (D.map4 DropMods
                        (D.map2 (||) (D.field "ctrlKey" D.bool) (D.field "metaKey" D.bool))
                        (D.field "shiftKey" D.bool)
                        (D.field "altKey" D.bool)
                        (D.field "target" dropAttribute)
                        |> D.map MouseUp
                    )
                ]

          else
            Sub.none
        ]
