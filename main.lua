local M = {}

local core = require("anv_core")

local WidgetContainer = core.WidgetContainer
local ReaderHighlight = core.ReaderHighlight
local FrameContainer = core.FrameContainer
local VerticalGroup = core.VerticalGroup
local VerticalSpan = core.VerticalSpan
local Event = core.Event
local HorizontalGroup = core.HorizontalGroup
local HorizontalSpan = core.HorizontalSpan
local LeftContainer = core.LeftContainer
local TopContainer = core.TopContainer
local BottomContainer = core.BottomContainer
local OverlapGroup = core.OverlapGroup
local CenterContainer = core.CenterContainer
local TextBoxWidget = core.TextBoxWidget
local TextWidget = core.TextWidget
local InputContainer = core.InputContainer
local GestureRange = core.GestureRange
local UIManager = core.UIManager
local InfoMessage = core.InfoMessage
local TextViewer = core.TextViewer
local SpinWidget = core.SpinWidget
local IconButton = core.IconButton
local IconWidget = core.IconWidget
local LineWidget = core.LineWidget
local RightContainer = core.RightContainer
local BlitBuffer = core.BlitBuffer
local Screen = core.Screen
local Device = core.Device
local Input = core.Input
local logger = core.logger
local FontList = core.FontList
local DocSettings = core.DocSettings
local ReadHistory = core.ReadHistory
local G_reader_settings = core.G_reader_settings
local lfs = core.lfs
local Font = core.Font
local Size = core.Size
local Geom = core.Geom
local _ = core._
local BD = core.BD

local DEFAULT_CONTENT_FONT_SIZE = core.DEFAULT_CONTENT_FONT_SIZE
local DEFAULT_TITLE_FONT_SIZE = core.DEFAULT_TITLE_FONT_SIZE
local DEFAULT_INFO_FONT_SIZE = core.DEFAULT_INFO_FONT_SIZE
local DEFAULT_H_MARGIN = core.DEFAULT_H_MARGIN
local DEFAULT_NOTE_SPACING = core.DEFAULT_NOTE_SPACING
local DEFAULT_TEXT_MARGIN = core.DEFAULT_TEXT_MARGIN
local DEFAULT_TRUNCATE_LINES = core.DEFAULT_TRUNCATE_LINES
local DEFAULT_TITLE_MARGIN = core.DEFAULT_TITLE_MARGIN
local DEFAULT_INFO_MARGIN = core.DEFAULT_INFO_MARGIN
local DEFAULT_TOP_PADDING = core.DEFAULT_TOP_PADDING
local getSetting = core.getSetting
local setSetting = core.setSetting
local flushSettings = core.flushSettings
local getContentFontSize = core.getContentFontSize
local getTitleFontSize = core.getTitleFontSize
local getInfoFontSize = core.getInfoFontSize
local getHMargin = core.getHMargin
local getNoteSpacing = core.getNoteSpacing
local getTextMargin = core.getTextMargin
local getTruncateLines = core.getTruncateLines
local getJustify = core.getJustify
local getTitleMargin = core.getTitleMargin
local getInfoMargin = core.getInfoMargin
local getTitleFont = core.getTitleFont
local getInfoFont = core.getInfoFont
local getContentFont = core.getContentFont
local getShowTotalNotes = core.getShowTotalNotes
local getTopPadding = core.getTopPadding
local getHideDupTitle = core.getHideDupTitle
local getHideDupInfo = core.getHideDupInfo
local getSwipeSetting = core.getSwipeSetting
local getDedupInfoFields = core.getDedupInfoFields
local getShowInfo = core.getShowInfo
local getInfoFields = core.getInfoFields
local getAlwaysShowFirstOnPage = core.getAlwaysShowFirstOnPage
local getRepeatTitleOnPage = core.getRepeatTitleOnPage
local getRepeatInfoOnPage = core.getRepeatInfoOnPage
local getHeaderSkips = core.getHeaderSkips
local getPaginationStyle = core.getPaginationStyle
local getScrollbarBookMarks = core.getScrollbarBookMarks
local isScrollbarStyle = core.isScrollbarStyle
local getNoteInfoKey = core.getNoteInfoKey
local BOOK_GAP = core.BOOK_GAP
local SB_THUMB_WIDTH = core.SB_THUMB_WIDTH
local SB_TRACK_WIDTH = core.SB_TRACK_WIDTH
local SB_STRIP_WIDTH = core.SB_STRIP_WIDTH
local SB_MARGIN_RIGHT = core.SB_MARGIN_RIGHT
local SB_MARGIN_V_TOP = core.SB_MARGIN_V_TOP
local SB_MARGIN_V_BOTTOM = core.SB_MARGIN_V_BOTTOM
local SB_MARK_OVERHANG = core.SB_MARK_OVERHANG
local SB_MARK_HEIGHT = core.SB_MARK_HEIGHT
local TOPBAR_HEIGHT = core.TOPBAR_HEIGHT
local TOPBAR_BOOK_HEIGHT = core.TOPBAR_BOOK_HEIGHT
local TABS_HEIGHT = core.TABS_HEIGHT
local FOOTER_BAR_HEIGHT = core.FOOTER_BAR_HEIGHT
local HEADER_ICON_SIZE = core.HEADER_ICON_SIZE
local HEADER_ICON_PAD = core.HEADER_ICON_PAD
local SERIF_FONT = core.SERIF_FONT
local PLUGIN_DIR = core.PLUGIN_DIR
local pluginIcon = core.pluginIcon
local getFaceOr = core.getFaceOr
local COLORS = core.COLORS
local HIGHLIGHT_COLORS = core.HIGHLIGHT_COLORS
local SPIN_MENUS = core.SPIN_MENUS
local HIGHLIGHT_STYLES = core.HIGHLIGHT_STYLES
local getHighlightColor = core.getHighlightColor
local colorName = core.colorName
local isNoBackgroundStyle = core.isNoBackgroundStyle
local truncateAuthorDisplay = core.truncateAuthorDisplay
local NoteWrapper = core.NoteWrapper

local sort = require("anv_sort")
local text = require("anv_text")
local exportmod = require("anv_export")
local data = require("anv_data")
local item = require("anv_item")
local sheet = require("anv_sheet")
local pages = require("anv_pages")
local list = require("anv_list")
local SortState = sort.SortState
local SORT_COMPARATORS = sort.SORT_COMPARATORS
local sortModeLabel = sort.sortModeLabel
local compareByPosition = sort.compareByPosition
local normalizeBookTitle = sort.normalizeBookTitle
local wrapText = text.wrapText
local filterToString = text.filterToString
local trimParagraph = text.trimParagraph
local Export = exportmod.Export
local getSidecarKey = data.getSidecarKey
local normalizeColorStyle = data.normalizeColorStyle
local itemMatchesNote = data.itemMatchesNote
local getBookInfoKey = data.getBookInfoKey
local loadPersistentCache = data.loadPersistentCache
local savePersistentCache = data.savePersistentCache
local getLiveReader = data.getLiveReader
local findLiveIndex = data.findLiveIndex
local setLiveHighlightField = data.setLiveHighlightField
local editStoredAnnotation = data.editStoredAnnotation
local nowStamp = data.nowStamp
local buildInfoText = item.buildInfoText
local NoteItemWidget = item.NoteItemWidget
local _annotation_cache = data._annotation_cache
local _book_info_cache = data._book_info_cache
local clearCaches = data.clearCaches
local invalidateBook = data.invalidateBook
local markPersistDirty = data.markPersistDirty
local isPersistLoaded = data.isPersistLoaded
local AnnotationSheet = sheet.AnnotationSheet
local Page = pages.Page
local States = pages.States
local SS = pages.SS
local SubPage = pages.SubPage
local ListPicker = pages.ListPicker
local NotesListWidget = list.NotesListWidget

local AllNotesViewer = WidgetContainer:extend{ name = "allnotesviewer", is_doc_only = false }
AllNotesViewer.is_doc_only = false
function AllNotesViewer:init()
    AllNotesViewer.registerGestures()
    AllNotesViewer._current = self -- the open file browser's or book's plugin (used by the long-press button)
    AllNotesViewer.addFileDialogButton()
    self:takeOverInBook()
    self:takeOverBrowser()
    self.ui.menu:registerToMainMenu(self)
end
-- The plugin's gestures (Settings → Taps and gestures → Gesture manager), the same in the file
-- browser and in a book: "Annotations" opens this book's list in a book and all books in the file
-- browser; "Annotations: Bookmarks" does the same on the Bookmarks tab. Older versions had a
-- separate in-book action; it stays only for those who still have it on a gesture, so that gesture
-- keeps working.
AllNotesViewer.GESTURES = {
    { id = "show_all_annotations", event = "ShowAnnotationsHere", title = _("Annotations") },
    { id = "show_all_bookmarks", event = "ShowBookmarksHere", title = _("Annotations: Bookmarks") },
}
-- Actions of earlier versions. They stay registered so anything still set to them keeps working:
-- a gesture, a profile, or another plugin (SimpleUI and the like) that saved the action. They have
-- no menu section, so KOReader lists them nowhere for new choices, but still runs them.
AllNotesViewer.LEGACY_GESTURES = {
    { id = "show_current_book_annotations", event = "ShowCurrentBookAnnotations", title = _("Annotations") },
    { id = "show_current_book_bookmarks", event = "ShowCurrentBookBookmarksList", title = _("Annotations: Bookmarks") },
}
function AllNotesViewer.registerGestures()
    local Dispatcher = require("dispatcher")
    for n = 1, #AllNotesViewer.GESTURES do
        local g = AllNotesViewer.GESTURES[n]
        -- "general": KOReader runs it in the file browser and in a book. An action marked
        -- reader = true is switched off in the file browser (Dispatcher:isActionEnabled).
        Dispatcher:registerAction(g.id, { category = "none", event = g.event, title = g.title,
            general = true })
    end
    for _, g in ipairs(AllNotesViewer.LEGACY_GESTURES) do
        Dispatcher:registerAction(g.id, { category = "none", event = g.event, title = g.title })
    end
end
function AllNotesViewer:onShowAnnotationsHere()
    if self.ui and self.ui.document then self:showCurrentBookNotes() else self:showAllNotes() end
    return true
end
function AllNotesViewer:onShowBookmarksHere()
    if self.ui and self.ui.document then self:showCurrentBookNotes("bookmarks") else self:showAllNotes("bookmarks") end
    return true
end
-- the events of earlier versions, for anything that sends them itself
AllNotesViewer.onShowAllAnnotations = AllNotesViewer.onShowAnnotationsHere
AllNotesViewer.onShowCurrentBookAnnotations = AllNotesViewer.onShowAnnotationsHere
AllNotesViewer.onShowAllBookmarksList = AllNotesViewer.onShowBookmarksHere
AllNotesViewer.onShowCurrentBookBookmarksList = AllNotesViewer.onShowBookmarksHere
-- "Annotations" in a book's long-press menu (file browser, History, collections, search): opens
-- that book's list (on the Bookmarks tab when the book has only bookmarks). Only shown for a book
-- with annotations or bookmarks. Added once to KOReader's file dialogs; uses the plugin of the
-- open file browser or book.
function AllNotesViewer.addFileDialogButton()
    if AllNotesViewer._fd_added then return end
    local classes = {}
    for _, m in ipairs({ "apps/filemanager/filemanager", "apps/filemanager/filemanagerhistory",
            "apps/filemanager/filemanagercollection", "apps/filemanager/filemanagerfilesearcher" }) do
        local ok, c = pcall(require, m)
        if ok and type(c) == "table" then table.insert(classes, c) end
    end
    local FM = classes[1]
    if not FM or type(FM.addFileDialogButtons) ~= "function" then return end
    AllNotesViewer._fd_added = true
    local okr, DocumentRegistry = pcall(require, "document/documentregistry")
    local function row(file, is_file)
        if not is_file or (okr and type(DocumentRegistry.hasProvider) == "function" and not DocumentRegistry:hasProvider(file)) then
            return nil
        end
        local viewer = AllNotesViewer._current
        if viewer and not viewer:bookHasAnnotations(file) then return nil end
        return { { text = _("Annotations"), callback = function()
            for _, c in ipairs(classes) do
                local ok, menu = pcall(c.getMenuInstance)
                if ok and type(menu) == "table" and menu.file_dialog then UIManager:close(menu.file_dialog); menu.file_dialog = nil end
            end
            local v = AllNotesViewer._current
            if v then v:showBookFile(file) end
        end } }
    end
    for _, c in ipairs(classes) do FM.addFileDialogButtons(c, "annotationsviewer", row) end
    AllNotesViewer.takeOverBookmarksButton()
end
-- Whether a book has any annotations or bookmarks (the book open in the reader: its live ones).
function AllNotesViewer:bookHasAnnotations(path)
    local ReaderUI = require("apps/reader/readerui")
    local open = ReaderUI and ReaderUI.instance
    if open and open.document and NotesListWidget.samePath(open.document.file, path)
            and open.annotation and open.annotation.annotations then
        return #open.annotation.annotations > 0
    end
    local ok, list = pcall(self.loadBookAnnotations, self, path)
    return ok and type(list) == "table" and #list > 0
end
-- Switch "KOReader's Bookmarks open here" (Settings → KOREADER, off by default). When on, every
-- way into KOReader's own bookmark lists opens this plugin's Bookmarks tab instead:
--   in a book: the Bookmarks menu entry, gesture and key (ReaderBookmark:onShowBookmark)
--   the Bookmark browser (2026.03 and later): its menu entry and gesture (onShowBookmarkBrowser)
--   the "Bookmarks" button in a book's long-press menu, History, search and collections
--   (genBookmarkBrowserButton): one book opens that book, several open all books.
-- KOReader's functions get a wrapper that looks at the switch each time, so turning it off works
-- straight away.
function AllNotesViewer.takeOverOn()
    local v = getSetting("take_over_bookmarks", false)
    return v == true or v == "all" or v == "bookmarks" -- (test builds stored a tab name)
end
function AllNotesViewer:takeOverInBook()
    local bm = self.ui and self.ui.bookmark
    if not bm or bm._av_show_bookmark or type(bm.onShowBookmark) ~= "function" then return end
    bm._av_show_bookmark = bm.onShowBookmark
    local viewer = self
    bm.onShowBookmark = function(this, ...)
        if AllNotesViewer.takeOverOn() then
            viewer:showCurrentBookNotes("bookmarks")
            return true
        end
        return this._av_show_bookmark(this, ...)
    end
end
function AllNotesViewer:takeOverBrowser()
    local coll = self.ui and self.ui.collections
    if not coll or coll._av_show_browser or type(coll.onShowBookmarkBrowser) ~= "function" then return end
    coll._av_show_browser = coll.onShowBookmarkBrowser
    local viewer = self
    coll.onShowBookmarkBrowser = function(this, ...)
        if AllNotesViewer.takeOverOn() then
            viewer:showAllNotes("bookmarks")
            return true
        end
        return this._av_show_browser(this, ...)
    end
end
function AllNotesViewer.takeOverBookmarksButton()
    local ok, coll = pcall(require, "apps/filemanager/filemanagercollection")
    if not ok or type(coll) ~= "table" or type(coll.genBookmarkBrowserButton) ~= "function" or coll._av_gen_button then return end
    coll._av_gen_button = coll.genBookmarkBrowserButton
    coll.genBookmarkBrowserButton = function(this, files, caller_pre_callback, ...)
        local button = this._av_gen_button(this, files, caller_pre_callback, ...)
        local paths = {}
        for path in pairs(type(files) == "table" and files or {}) do table.insert(paths, path) end
        if type(button) == "table" and #paths > 0 then
            local orig = button.callback
            button.callback = function(...)
                local viewer = AllNotesViewer._current
                if viewer and AllNotesViewer.takeOverOn() then
                    if caller_pre_callback then caller_pre_callback() end
                    if #paths == 1 then viewer:showBookFile(paths[1], "bookmarks") else viewer:showAllNotes("bookmarks") end
                elseif orig then
                    return orig(...)
                end
            end
        end
        return button
    end
end
-- One book's list by its path (tab: "bookmarks" or nil). The book open in the reader uses its live
-- annotations.
function AllNotesViewer:showBookFile(path, tab)
    local ReaderUI = require("apps/reader/readerui")
    local open = ReaderUI and ReaderUI.instance
    if open and open.document and NotesListWidget.samePath(open.document.file, path) then
        return self:showCurrentBookNotes(tab)
    end
    local info = self:getBookInfo(path)
    self:showNotesForBook(path, info and info.title or (path:match("([^/\\]+)$") or path),
        self:loadBookAnnotations(path) or {}, tab)
end
-- tab: "bookmarks" opens the list on the Bookmarks tab; nil on All
function AllNotesViewer:showCurrentBookNotes(tab)
    local ReaderUI = require("apps/reader/readerui")
    local ui = self.ui or (ReaderUI and ReaderUI.instance)
    if not ui or not ui.document then return end
    local book_path = ui.document.file
    if not book_path then return end
    -- Prefer live in-memory annotations so unsaved changes are visible
    local annotations
    if ui.annotation and ui.annotation.annotations then
        annotations = self:convertLiveAnnotations(ui.annotation.annotations)
    else
        annotations = self:loadBookAnnotations(book_path)
    end
    if not annotations or #annotations == 0 then
        annotations = {} -- the list shows "No annotations yet"
    end
    local book_info = self:getBookInfo(book_path)
    local book_title = book_info and book_info.title or (book_path:match("([^/\\]+)$") or book_path)
    self:showNotesForBook(book_path, book_title, annotations, tab)
end
function AllNotesViewer:addToMainMenu(menu_items)
    if self.ui and self.ui.document then
        menu_items.current_book_notes_viewer = {
            text = _("Annotations"),
            sorting_hint = "navi",
            callback = function() self:showCurrentBookNotes() end,
        }
        -- "Annotations: Bookmarks" next to it, left out while KOReader's own Bookmarks open here
        -- (that entry then does the same). Read when KOReader builds its menu.
        if not AllNotesViewer.takeOverOn() then
            menu_items.current_book_bookmarks_viewer = {
                text = _("Annotations: Bookmarks"),
                sorting_hint = "navi",
                callback = function() self:showCurrentBookNotes("bookmarks") end,
            }
        end
    else
        menu_items.all_notes_viewer = {
            text = _("Annotations"),
            sorting_hint = "filemanager_settings",
            callback = function() self:showAllNotes() end,
        }
        if not AllNotesViewer.takeOverOn() then
            menu_items.all_bookmarks_viewer = {
                text = _("Annotations: Bookmarks"),
                sorting_hint = "filemanager_settings",
                callback = function() self:showAllNotes("bookmarks") end,
            }
        end
    end
end
-- "Reload annotations" in the ☰ menu: forget everything read so far (memory and the file in the
-- cache folder), then open the list again, which reads all books afresh.
function AllNotesViewer:reloadAnnotations(list)
    clearCaches()
    local single = list and list.single_book
    if list then list:onClose() end
    if single then self:showCurrentBookNotes() else self:showAllNotes() end
end
function AllNotesViewer:clearBookCache(book_path)
    invalidateBook(book_path)
end
-- One item of KOReader's `annotations` list (sidecar or open book) as the plugin keeps it, or
-- nil when there is nothing to show. Highlights and notes have a `drawer`; an item without one
-- is a page bookmark: KOReader stores its place, chapter, date and an optional note, but no
-- text from the page (its `text` is only "in <chapter>"), so the list shows the page instead.
function AllNotesViewer.toNote(item, idx)
    local label = item.pageref or item.pageno -- page number as KOReader shows it
    if not item.drawer then
        if item.page == nil and item.pageno == nil then return nil end
        return {
            page = item.page or item.pageno, order = idx, page_label = label,
            chapter = item.chapter or "", text = "", notes = item.note or "",
            datetime = item.datetime or "", bookmark = true, bm_text = item.text,
            tags = item.tags, keywords = item.keywords,
        }
    end
    local has_highlight = item.text and item.text ~= ""
    local has_note = item.note and item.note ~= ""
    if not (has_highlight or has_note) then return nil end
    return {
        page = item.page or item.pageno or 0, order = idx, page_label = label,
        pos0 = item.pos0, pos1 = item.pos1,
        chapter = item.chapter or "", text = item.text or "", notes = item.note or "",
        datetime = item.datetime or "", drawer = item.drawer, color = item.color or "yellow",
        tags = item.tags, keywords = item.keywords,
    }
end
function AllNotesViewer:convertLiveAnnotations(live)
    local annotations = {}
    for idx, item in ipairs(live) do
        local n = AllNotesViewer.toNote(item, idx)
        if n then table.insert(annotations, n) end
    end
    return annotations
end
-- A sidecar in KOReader's old format (no `annotations` list; the book was not opened since
-- KOReader 2024) as plugin notes, each marked legacy. Built the way KOReader converts the file
-- when it opens the book (readerannotation.lua migrateToAnnotations / buildAnnotation), so the
-- list shows what KOReader will keep: every bookmark becomes one annotation, with its text
-- (`notes`), note (`text`, unless KOReader wrote it itself), date and position; the style and
-- colour come from the matching `highlight[page]` entry (the same date when both have one, and
-- the same position). A highlight without a bookmark only counts when KOReader still imports
-- those (no `highlights_imported`).
function AllNotesViewer.legacyNotes(data)
    local out = {}
    if type(data) ~= "table" then return out end
    local highlights = type(data.highlight) == "table" and data.highlight or {}
    local bookmarks = type(data.bookmarks) == "table" and data.bookmarks or {}
    local function samePos(a, b)
        if type(a) == "table" and type(b) == "table" then return a.x == b.x and a.y == b.y end
        return a == b
    end
    local function matches(hl, page, bm)
        if hl.datetime ~= nil and bm.datetime ~= nil and hl.datetime ~= bm.datetime then return false end
        if type(hl.pos0) == "table" and tonumber(bm.page) ~= tonumber(page) then return false end
        return samePos(hl.pos0, bm.pos0) and samePos(hl.pos1, bm.pos1)
    end
    -- KOReader's own text on a bookmark ("Page 12 <text> @ <date>", in KOReader's language) is
    -- not a note (readerbookmark.lua isBookmarkAutoText)
    local auto_tpl = "Page %1 %2 @ %3"
    local ok_gt, gettext = pcall(require, "gettext")
    if ok_gt and gettext then -- KOReader's gettext is a callable table
        local ok_t, t = pcall(gettext, auto_tpl)
        if ok_t and type(t) == "string" then auto_tpl = t end
    end
    local function esc(str) return (tostring(str):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
    local function noteOf(bm)
        local t = type(bm.text) == "string" and bm.text or ""
        if t == "" or t == bm.notes then return "" end
        local pat = esc(auto_tpl):gsub("%%%%([123])", function(d)
            if d == "1" then return ".-" end
            local v = d == "2" and bm.notes or bm.datetime
            return v ~= nil and esc(v) or ".-"
        end)
        if t:match("^" .. pat .. "$") then return "" end
        return t
    end
    -- a PDF position without its page (old reflow highlights) gets it, as KOReader does
    local function withPage(pos, page)
        if type(pos) ~= "table" or pos.page ~= nil then return pos end
        local copy = {}
        for k, v in pairs(pos) do copy[k] = v end
        copy.page = page
        return copy
    end
    local hl_list = {}
    for page, page_highlights in pairs(highlights) do
        if type(page_highlights) == "table" then
            for k = 1, #page_highlights do
                local hl = page_highlights[k]
                if type(hl) == "table" and hl.drawer then table.insert(hl_list, { hl = hl, page = page }) end
            end
        end
    end
    local used = {}
    for j = 1, #bookmarks do
        local bm = bookmarks[j]
        if type(bm) == "table" and bm.page ~= nil then
            local note = noteOf(bm)
            if bm.highlighted then
                local hl, hl_page
                for k = 1, #hl_list do
                    -- KOReader takes the first match, even one another bookmark matched already
                    if matches(hl_list[k].hl, hl_list[k].page, bm) then
                        used[k] = true
                        hl, hl_page = hl_list[k].hl, hl_list[k].page
                        break
                    end
                end
                local text = type(bm.notes) == "string" and bm.notes or ""
                if text ~= "" or note ~= "" then
                    table.insert(out, {
                        page = bm.page, page_label = tonumber(hl_page) or tonumber(bm.page),
                        pos0 = withPage(bm.pos0, bm.page), pos1 = withPage(bm.pos1, bm.page),
                        chapter = bm.chapter or (hl and hl.chapter) or "", text = text, notes = note,
                        datetime = bm.datetime or "",
                        -- without its highlight entry KOReader uses the default style (lighten, yellow)
                        drawer = hl and hl.drawer or "lighten", color = hl and hl.color or "yellow",
                        tags = hl and hl.tags, keywords = hl and hl.keywords, legacy = true,
                    })
                end
            else -- a page bookmark
                table.insert(out, {
                    page = bm.page, page_label = tonumber(bm.page), chapter = bm.chapter or "", text = "",
                    notes = note, datetime = bm.datetime or "", bookmark = true, bm_text = bm.notes,
                    legacy = true,
                })
            end
        end
    end
    -- very old books (before 2014) had highlights that were never added to the bookmarks:
    -- KOReader imports those once, while highlights_imported is not set
    if not data.highlights_imported then
        for k = 1, #hl_list do
            local hl, page = hl_list[k].hl, hl_list[k].page
            local text = type(hl.text) == "string" and hl.text or ""
            if not used[k] and hl.pos0 ~= nil and text ~= "" then
                table.insert(out, {
                    page = type(hl.pos0) == "table" and (tonumber(page) or page) or hl.pos0, page_label = tonumber(page), pos0 = withPage(hl.pos0, page), pos1 = withPage(hl.pos1, page),
                    chapter = hl.chapter or "", text = text, notes = "",
                    datetime = hl.datetime or "", drawer = hl.drawer, color = hl.color or "yellow",
                    tags = hl.tags, keywords = hl.keywords, legacy = true,
                })
            end
        end
    end
    return out
end
-- What a sidecar file holds, read without changing anything on disk (DocSettings:open removes
-- empty or broken candidates), or nil. A missing or empty file falls back to KOReader's backup
-- copy (".old"), as DocSettings:open does.
-- book_path: when the sidecar couldn't be looked for (sidecar nil: KOReader before 2024 has no
-- findSidecarFile), read the book's settings the old way.
function AllNotesViewer.readSidecar(sidecar, book_path)
    if sidecar == nil and type(book_path) == "string" then
        local ok, ds = pcall(DocSettings.open, DocSettings, book_path)
        return ok and ds and type(ds.data) == "table" and ds.data or nil
    end
    if type(sidecar) ~= "string" or sidecar == "" then return nil end
    local paths = { sidecar, sidecar .. ".old" }
    for k = 1, 2 do
        local path = paths[k]
        local ok, stored
        if DocSettings.openSettingsFile then
            local ok_ds, ds = pcall(DocSettings.openSettingsFile, path)
            ok, stored = ok_ds and ds ~= nil, ds and ds.data
        else
            ok, stored = pcall(dofile, path)
        end
        if ok and type(stored) == "table" and next(stored) ~= nil then return stored end
    end
    -- that file doesn't load: the next one KOReader would read (it would delete this one)
    if type(book_path) == "string" then
        local ok_c, list = pcall(NotesListWidget.sidecarCandidates, book_path)
        for i = 1, ok_c and #list or 0 do
            local path = list[i].path
            if path ~= sidecar and path ~= sidecar .. ".old" and list[i].size > 0 then
                local ok_r, stored = pcall(dofile, path)
                if ok_r and type(stored) == "table" and next(stored) ~= nil then return stored end
            end
        end
    end
end
-- key/sidecar are optional: pass them when getSidecarKey() was already called for this book.
function AllNotesViewer:loadBookAnnotations(book_path, key, sidecar)
    local annotations = {}
    if not book_path then return annotations end
    if not key then key, sidecar = getSidecarKey(book_path) end
    local cached = _annotation_cache[book_path]
    if cached and cached.mtime == key then
        return cached.data
    end
    markPersistDirty()
    -- read only: DocSettings:open is for writing (it removes empty or broken sidecar files)
    local data = AllNotesViewer.readSidecar(sidecar, book_path) or {}
    
    local items = data.annotations
    -- an empty list is a converted book without annotations (KOReader keeps the old keys)
    if type(items) == "table" then
        for idx, item in ipairs(items) do
            local n = AllNotesViewer.toNote(item, idx)
            if n then table.insert(annotations, n) end
        end
    else -- old format (book not opened since KOReader 2024): shown, but not editable
        annotations = AllNotesViewer.legacyNotes(data)
    end
    table.sort(annotations, function(a, b) return (a.datetime or "") > (b.datetime or "") end)
    _annotation_cache[book_path] = { data = annotations, mtime = key }
    -- Fill the book info cache from the same file, so getBookInfo() doesn't open it again
    if #annotations > 0 then self:getBookInfo(book_path, data, key, sidecar) end
    return annotations
end
-- data/key/sidecar are optional: pass data when the book's settings are already open, and
-- key/sidecar when getSidecarKey() was already called for this book.
function AllNotesViewer:getBookInfo(book_path, data, key, sidecar)
    if not key then key, sidecar = getSidecarKey(book_path) end
    local info_key = getBookInfoKey(key, sidecar)
    local cached = _book_info_cache[book_path]
    if cached and cached.mtime == info_key then
        return cached.data
    end
    markPersistDirty()
    data = data or AllNotesViewer.readSidecar(sidecar, book_path) or {}
    local filename = book_path:match("([^/\\]+)$") or book_path
    
    local custom_metadata = {}
    do
        local custom_metadata_file = DocSettings:findCustomMetadataFile(book_path)
        if custom_metadata_file then
            local ok_cm, cm_data = pcall(dofile, custom_metadata_file)
            if ok_cm and cm_data then
                custom_metadata = cm_data
            end
        end
    end
    
    local title = (custom_metadata.custom_props and custom_metadata.custom_props.title) or 
                  (custom_metadata.doc_props and custom_metadata.doc_props.title) or
                  (data.doc_props and data.doc_props.title)
    local authors = (custom_metadata.custom_props and custom_metadata.custom_props.authors) or 
                    (custom_metadata.doc_props and custom_metadata.doc_props.authors) or
                    (data.doc_props and data.doc_props.authors)
    local tags = (custom_metadata.custom_props and (custom_metadata.custom_props.tags or custom_metadata.custom_props.keywords)) or
                 (custom_metadata.doc_props and (custom_metadata.doc_props.tags or custom_metadata.doc_props.keywords)) or
                 (data.doc_props and (data.doc_props.tags or data.doc_props.keywords))
    
    -- series and language: the book's own metadata, as KOReader's book information shows it
    local function prop(name)
        local v = (custom_metadata.custom_props and custom_metadata.custom_props[name])
            or (custom_metadata.doc_props and custom_metadata.doc_props[name])
            or (data.doc_props and data.doc_props[name])
        if type(v) == "number" then v = tostring(v) end
        return type(v) == "string" and v ~= "" and v or nil
    end
    local series, language = prop("series"), prop("language")

    if not title or title == "" then title = filename:gsub("%.[^.]+$", "") end
    
    local info = { path = book_path, filename = filename, title = title or filename, authors = authors or "Unknown", tags = tags,
        series = series, language = language }
    _book_info_cache[book_path] = { data = info, mtime = info_key }
    return info
end
function AllNotesViewer:findAllNotes()
    local notes_data = {}
    local seen = {}  -- paths already tried
    local scanned = {} -- books with a sidecar, kept in the on-disk cache
    loadPersistentCache()
    NotesListWidget._realpaths = {} -- links may have changed since the last scan

    -- Helper: load annotations for a path and add to notes_data if any found
    local added = {} -- real paths of the books already listed
    local function addBook(book_path)
        if seen[book_path] then return end
        seen[book_path] = true
        -- another spelling of a book already listed; one that found nothing doesn't count, as
        -- KOReader may keep the sidecar under the other spelling
        local real = NotesListWidget.realPath(book_path)
        if added[real] then return end
        if not lfs.attributes(book_path, "mode") then return end
        local live_ui = getLiveReader(book_path)
        local key, sidecar = getSidecarKey(book_path)
        -- Books without a sidecar have no annotations: skip opening their settings
        if sidecar == false and not live_ui then return end
        local annotations
        if live_ui then
            -- The open book's sidecar is only written on close/autosave: use what's in memory
            annotations = self:convertLiveAnnotations(live_ui.annotation.annotations)
        else
            table.insert(scanned, book_path)
            annotations = self:loadBookAnnotations(book_path, key, sidecar)
        end
        if #annotations > 0 then
            added[real] = true
            local book_info = self:getBookInfo(book_path, nil, key, sidecar)
            table.insert(notes_data, {
                path = book_path, filename = book_info.filename,
                title = book_info.title, authors = book_info.authors,
                series = book_info.series, language = book_info.language,
                tags = book_info.tags, notes = annotations,
            })
        end
    end

    -- Source 1: cover browser book info databases (every book ever shown in the file browser).
    -- KOReader's CoverBrowser keeps it in <settings>/bookinfo_cache.sqlite3; the Project Title
    -- plugin keeps its own copy. Opened read-only so a missing file is never created.
    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_sq and ok_ds then
        local settings_dir = DataStorage:getSettingsDir()
        for _, db_name in ipairs({ "bookinfo_cache.sqlite3", "PT_bookinfo_cache.sqlite3" }) do
            local db_path = settings_dir .. "/" .. db_name
            if lfs.attributes(db_path, "mode") == "file" then
                local ok_db, db = pcall(SQ3.open, db_path, "ro")
                if ok_db and db then
                    local ok_q, res = pcall(db.exec, db,
                        "SELECT directory, filename FROM bookinfo WHERE directory IS NOT NULL AND filename IS NOT NULL")
                    if ok_q and res and res[1] then
                        local dirs, files = res[1], res[2]
                        for i = 1, #dirs do
                            local dir = dirs[i]
                            local sep = dir:sub(-1) == "/" and "" or "/"
                            addBook(dir .. sep .. files[i])
                        end
                    elseif not ok_q then
                        logger.warn("AnnotationsViewer: could not read", db_path, res)
                    end
                    pcall(db.close, db)
                end
            end
        end
    end

    -- Source 2: ReadHistory (books opened but possibly not browsed via file manager)
    local history = ReadHistory.hist
    if history then
        for _, item in ipairs(history) do
            if item.file then addBook(item.file) end
        end
    end

    savePersistentCache(scanned)
    return notes_data
end
-- Tags from a book or an annotation: a list, or one string split at , ; | tab or newline.
function AllNotesViewer.splitTags(val)
    if type(val) == "table" then return val end
    if type(val) ~= "string" then return nil end
    local t = {}
    for tag in val:gmatch("[^,;\n|\t]+") do
        tag = tag:match("^%s*(.-)%s*$")
        if tag ~= "" then table.insert(t, tag) end
    end
    return t
end
-- One entry of the list from an annotation read from a book. book: { title, authors, filename,
-- path }; book_tags: the book's tags as a list (used when the annotation has none of its own).
function AllNotesViewer.listNote(note, book, book_tags)
    local tag_set, all_tags = {}, {}
    for _, tag in ipairs(AllNotesViewer.splitTags(note.tags) or book_tags or {}) do
        if tag ~= "" then tag_set[tag] = true end
    end
    for tag in pairs(tag_set) do table.insert(all_tags, tag) end
    table.sort(all_tags)
    return {
        book_title = book.title, book_authors = book.authors, book_filename = book.filename, book_path = book.path,
        book_series = book.series, book_language = book.language,
        page = note.page, chapter = note.chapter, order = note.order,
        pos0 = note.pos0, pos1 = note.pos1,
        highlighted_text = note.text, user_note = note.notes,
        datetime = note.datetime, drawer = note.drawer, color = note.color,
        bookmark = note.bookmark, bm_text = note.bm_text, page_label = note.page_label,
        legacy = note.legacy, tags = all_tags,
    }
end
function AllNotesViewer:showNotesForBook(book_path, book_title, raw_annotations, tab)
    local book_info = self:getBookInfo(book_path)
    local notes_list = {}
    local book = { title = book_title, authors = book_info and book_info.authors or nil,
        filename = book_path:match("([^/\\]+)$") or book_path, path = book_path,
        series = book_info and book_info.series, language = book_info and book_info.language }
    local book_tags = AllNotesViewer.splitTags(book_info and book_info.tags)
    for _, note in ipairs(raw_annotations) do
        table.insert(notes_list, AllNotesViewer.listNote(note, book, book_tags))
    end
    SortState.bm_tab = nil -- a new list starts sorted for the annotation tabs (see syncSortTab)
    NotesListWidget:sortNotesList(notes_list, SortState.get(true), true)
    UIManager:show(NotesListWidget:new{ notes_list = notes_list, viewer = self, single_book = true, book_title = book_title,
        active_filter = tab and { notes_presence = tab } or nil })
end
-- tab: "bookmarks" opens on the Bookmarks tab
function AllNotesViewer:showAllNotes(tab)
    -- The first open after starting KOReader may have to read many books: say so
    local loading
    if not isPersistLoaded() then
        loading = NotesListWidget.States.loading()
    end
    local all_notes_by_book = self:findAllNotes()
    local notes_list = {}
    for _, book_data in ipairs(all_notes_by_book) do
        local book = { title = book_data.title, authors = book_data.authors, filename = book_data.filename, path = book_data.path,
            series = book_data.series, language = book_data.language }
        local book_tags = AllNotesViewer.splitTags(book_data.tags)
        for _, note in ipairs(book_data.notes) do
            table.insert(notes_list, AllNotesViewer.listNote(note, book, book_tags))
        end
    end
    SortState.bm_tab = nil -- a new list starts sorted for the annotation tabs (see syncSortTab)
    NotesListWidget:sortNotesList(notes_list, SortState.get(false), false)
    local widget = NotesListWidget:new{ notes_list = notes_list, viewer = self, active_filter = tab and { notes_presence = tab } or nil }
    if loading then UIManager:close(loading) end
    UIManager:show(widget)
end
-- Annotation sheet and Filter & sort screen (in a block to stay under Lua's 200-locals limit)
function AllNotesViewer:showNoteDetails(note, parent_widget)
    UIManager:show(AnnotationSheet:new{ note = note, viewer = self, parent_widget = parent_widget }, "ui")
end
function AllNotesViewer:showColorPicker(note, parent_widget)
    local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
        local colors = {}
        for _, v in ipairs(ReaderHighlight.highlight_colors) do
            if v[2] ~= "gray" then
                table.insert(colors, { v[2], NoteItemWidget.colorLabel(v[2]), COLORS.highlightCode(v[2]) })
            end
        end
        table.insert(colors, { "gray", NoteItemWidget.colorLabel("gray"), BlitBuffer.COLOR_GRAY })
    local radio_buttons = {}
    for _, c in ipairs(colors) do
                table.insert(radio_buttons, {
                        { text = c[2], checked = note.color == c[1],
                            bgcolor = c[1] == "gray" and BlitBuffer.COLOR_GRAY or BlitBuffer.colorFromString(c[3]), provider = c[1] },
                })
    end
    NotesListWidget.showDialog(RadioButtonWidget:new{
        title_text = _("Select Color"),
        width_factor = 0.6,
        radio_buttons = radio_buttons,
        callback = function(radio)
            self:updateHighlightColor(note, radio.provider, parent_widget)
        end,
        colorful = true,
        dithered = true,
    })
end


function AllNotesViewer:showStylePicker(note, parent_widget)
    local ButtonDialog = require("ui/widget/buttondialog")
    local styles = {
        { _("Lighten"), "lighten" },
        { _("Underline"), "underscore" },
        { _("Strikethrough"), "strikeout" },
        { _("Invert"), "invert" },
    }
    local buttons = {}
    local dialog
    for _, style in ipairs(styles) do
        table.insert(buttons, {
            { text = style[1] .. (note.drawer == style[2] and "  ✓" or ""),
              callback = function()
                  UIManager:close(dialog)
                  self:updateHighlightStyle(note, style[2], parent_widget)
              end },
        })
    end
    table.insert(buttons, { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } })
    dialog = ButtonDialog:new{ title = _("Select Style"), buttons = buttons }
    NotesListWidget.showDialog(dialog)
end
-- Updates the plugin's own list after a change and redraws it.
local function updateListedNote(parent_widget, note, fn)
    for i, n in ipairs(parent_widget.notes_list) do
        if n == note or (n.book_path == note.book_path and itemMatchesNote(
                { datetime = n.datetime, text = n.highlighted_text, pos0 = n.pos0, pos1 = n.pos1,
                  page = n.page, drawer = n.drawer }, note)) then
            fn(n, i)
            break
        end
    end
    parent_widget:refresh()
end

-- A note from a book still in KOReader's old format can't be changed until KOReader has opened
-- the book once (it converts the file then). Says so and returns true. An open book is already
-- converted in memory, so changes go through KOReader as usual.
function AllNotesViewer.legacyBlocked(note)
    if not note.legacy or (note.book_path and getLiveReader(note.book_path)) then return false end
    NotesListWidget.showDialog(InfoMessage:new{
        text = _("This book still uses KOReader's old format. Open it once in KOReader, then try again."),
    })
    return true
end
function AllNotesViewer:setHighlightField(note, field, value, parent_widget, done_text)
    if not note.book_path or AllNotesViewer.legacyBlocked(note) then return end
    local updated = false
    local ui = getLiveReader(note.book_path)
    if ui then
        local index = findLiveIndex(ui, note)
        if index then
            setLiveHighlightField(ui, index, field, value)
            updated = true
        end
    else
        updated = editStoredAnnotation(note, function(item)
            item[field] = value
            item.datetime_updated = nowStamp()
        end)
    end
    if updated then
        self:clearBookCache(note.book_path)
        updateListedNote(parent_widget, note, function(n) n[field] = value end)
        if done_text then NotesListWidget.showDialog(InfoMessage:new{ text = done_text, timeout = 1 }) end
    else
        AllNotesViewer.saveFailed()
    end
end
-- Nothing was changed because the annotation is no longer in the book's file (changed elsewhere,
-- book moved ...): say so. on_dismiss runs when the message is closed.
function AllNotesViewer.saveFailed(on_dismiss)
    NotesListWidget.showDialog(InfoMessage:new{
        text = _("Could not save: this annotation was not found in the book's file. Tap Reload annotations and try again."),
        dismiss_callback = on_dismiss,
    })
end
function AllNotesViewer:updateHighlightStyle(note, new_style, parent_widget)
    self:setHighlightField(note, "drawer", new_style, parent_widget, _("Style updated."))
end
function AllNotesViewer:updateHighlightColor(note, new_color, parent_widget)
    self:setHighlightField(note, "color", new_color, parent_widget, _("Color updated."))
end
-- before_delete: runs once Delete is tapped (closes the sheet the card was opened from)
function AllNotesViewer:confirmDelete(note, parent_widget, before_delete)
    if AllNotesViewer.legacyBlocked(note) then return end
    NotesListWidget.States.confirmDelete(note, function()
        if before_delete then before_delete() end
        self:deleteAnnotation(note, parent_widget)
    end)
end
function AllNotesViewer:deleteAnnotation(note, parent_widget)
    if not note.book_path or AllNotesViewer.legacyBlocked(note) then return end
    local deleted = false
    local ui = getLiveReader(note.book_path)
    if ui then
        local index = findLiveIndex(ui, note)
        if index and note.bookmark then
            local item = ui.annotation.annotations[index]
            if ui.bookmark and ui.bookmark.removeItem then
                -- KOReader's own path: also hides the dog-ear when it is the page on screen
                ui.bookmark:removeItem(item, index)
            else
                table.remove(ui.annotation.annotations, index)
                ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = -index }))
            end
            deleted = true
        elseif index then
            if ui.highlight and ui.highlight.deleteHighlight then
                -- KOReader's own path: removes the PDF annotation, updates statistics,
                -- the "has annotations" flag and the footer
                ui.highlight:deleteHighlight(index)
            else
                local item = table.remove(ui.annotation.annotations, index)
                ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = -index }))
            end
            deleted = true
        end
    else
        local remaining
        deleted = editStoredAnnotation(note, function(_, list, i)
            table.remove(list, i)
            remaining = #list
        end)
        if deleted and remaining == 0 then
            -- keep the file browser's "has annotations" marker in sync
            local ok_bl, BookList = pcall(require, "ui/widget/booklist")
            if ok_bl and BookList.setBookInfoCacheProperty then
                BookList.setBookInfoCacheProperty(note.book_path, "has_annotations", false)
            end
        end
    end
    if deleted then
        self:clearBookCache(note.book_path)
        updateListedNote(parent_widget, note, function(_, i) table.remove(parent_widget.notes_list, i) end)
    else
        AllNotesViewer.saveFailed()
    end
end
-- First lines of the highlight, for the edit-note dialog (about three lines' worth).
local function cleanHighlightTextForDialog(text)
    local t = trimParagraph(((text or ""):gsub("%s+", " ")))
    if #t > 180 then
        local cut = t:sub(1, 180):gsub("[\128-\191]+$", "")
        -- do not leave half a UTF-8 character at the end
        while #cut > 0 and cut:byte(#cut) >= 0xC0 do cut = cut:sub(1, -2) end
        t = cut:gsub("%s+%S*$", "") .. "…"
    end
    return t
end
-- start_text: what the field starts with instead of the saved note (after a failed save).
function AllNotesViewer:editNote(note, parent_widget, on_done, start_text)
    if AllNotesViewer.legacyBlocked(note) then return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    local has_note = note.user_note and note.user_note:find("%S") ~= nil
    -- what the note is about: "Book · Chapter · date", then the start of the highlight
    local about = {}
    if note.book_title and note.book_title ~= "" then table.insert(about, note.book_title) end
    local info = buildInfoText(note, NoteWrapper:new(note))
    if info ~= "" then table.insert(about, info) end
    local quote = cleanHighlightTextForDialog(note.highlighted_text)
    local description = table.concat(about, " · ")
    if quote ~= "" then description = description .. (description ~= "" and "\n\n" or "") .. quote end
    local function save(text)
        local typed = input_dialog:getInputText() -- kept if the save fails
        UIManager:close(input_dialog)
        self:saveNoteEdit(note, text, parent_widget, function()
            self:editNote(note, parent_widget, on_done, typed)
        end)
        if on_done then on_done() end
    end
    local row = {}
    if has_note then
        -- blank input deletes the note too; this just says so
        table.insert(row, { text = _("Remove note"), callback = function() save("") end })
    end
    table.insert(row, { text = _("Cancel"), id = "close", callback = function() UIManager:close(input_dialog) end })
    -- Save last in the row (unpack(row) in the middle of a table keeps only its first button,
    -- which lost Cancel whenever there was a note)
    table.insert(row, {
        text = _("Save"),
        is_enter_default = true,
        callback = function() save(input_dialog:getInputText()) end,
    })
    input_dialog = InputDialog:new{
        title = has_note and _("Edit note") or _("Add note"),
        description = description ~= "" and description or nil,
        input = start_text or note.user_note or "",
        input_hint = note.bookmark and _("Your note on this page") or _("Your note on this passage"),
        input_type = "text",
        text_height = Screen:scaleBySize(120),
        buttons = { row },
    }
    NotesListWidget.showDialog(input_dialog)
    input_dialog:onShowKeyboard()
end
-- on_fail: run after the "could not save" message is closed (editNote reopens with the text).
function AllNotesViewer:saveNoteEdit(note, new_note_text, parent_widget, on_fail)
    if not note.book_path or AllNotesViewer.legacyBlocked(note) then return end
    local value = new_note_text ~= "" and new_note_text or nil -- blank input deletes the note, as in KOReader
    local updated = false
    local ui = getLiveReader(note.book_path)
    if ui then
        local index = findLiveIndex(ui, note)
        if index then
            -- same steps as ReaderBookmark:setBookmarkNote()
            local item = ui.annotation.annotations[index]
            local getType = ui.bookmark and ui.bookmark.getBookmarkType
            local type_before = getType and getType(item)
            item.note = value
            if ui.highlight and ui.highlight.writePdfAnnotation then
                ui.highlight:writePdfAnnotation("content", item, value or "")
            end
            local type_after = getType and getType(item)
            if type_before == "highlight" and type_after == "note" then
                ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = -1, nb_notes_added = 1 }))
            elseif type_before == "note" and type_after == "highlight" then
                ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1, nb_notes_added = -1 }))
            else
                ui:handleEvent(Event:new("AnnotationsModified", { item }))
            end
            updated = true
        end
    else
        updated = editStoredAnnotation(note, function(item)
            item.note = value
            item.datetime_updated = nowStamp()
        end)
    end
    if updated then
        self:clearBookCache(note.book_path)
        updateListedNote(parent_widget, note, function(n) n.user_note = value end)
        NotesListWidget.showDialog(InfoMessage:new{ text = _("Note saved."), timeout = 1 })
    else
        AllNotesViewer.saveFailed(on_fail)
    end
end
function AllNotesViewer:openBookAtNote(note)
    local book_path = note.book_path
    if not book_path then
        NotesListWidget.showDialog(InfoMessage:new{ text = _("Cannot find book path.") })
        return
    end

    local ReaderUI = require("apps/reader/readerui")

    -- Jump the way KOReader's own bookmark list does: to the exact spot (xpointer or page)
    -- with the highlight marked, after remembering where the reader was, so KOReader's Back
    -- returns there. Older KOReader without these: go to the page number.
    local function gotoNote(ui)
        if not ui or not ui.document then return end
        -- EPUB-like books need an xpointer here, PDFs a page number (very old sidecars kept a
        -- page number for EPUBs too: those take the fallback below)
        local fits = (ui.rolling and type(note.page) == "string")
            or (ui.paging and tonumber(note.page) and tonumber(note.page) > 0)
        if ui.bookmark and ui.bookmark.gotoBookmark and fits then
            if ui.link and ui.link.addCurrentLocationToStack then ui.link:addCurrentLocationToStack() end
            ui.bookmark:gotoBookmark(note.page, note.pos0)
            return
        end
        local target_page = tonumber(note.page)
        local xp = note.pos0 or (type(note.page) == "string" and note.page or nil)
        if xp and ui.document.getPageFromXPointer then
            local ok, page = pcall(function() return ui.document:getPageFromXPointer(xp) end)
            if ok and page then target_page = page end
        end
        if target_page and target_page > 0 then
            ui:handleEvent(Event:new("GotoPage", target_page))
        end
    end

    if ReaderUI.instance and ReaderUI.instance.document then
        if NotesListWidget.samePath(ReaderUI.instance.document.file, book_path) then
            gotoNote(ReaderUI.instance)
            return
        end
    end

    -- KOReader 2026.03+ calls this once the book is open; older versions ignore the extra
    -- argument, so the timer below is the fallback for them.
    local done = false
    local function after_open(ui)
        if done then return end
        done = true
        gotoNote(ui)
    end
    ReaderUI:showReader(book_path, nil, nil, nil, after_open)
    UIManager:scheduleIn(1.5, function()
        if done then return end
        local ui = require("apps/reader/readerui").instance
        if ui and ui.document and NotesListWidget.samePath(ui.document.file, book_path) then after_open(ui) end
    end)
end
-- Internals exposed for tests/run.lua; KOReader doesn't use this.

-- Cross-module references that are nil while the modules load are filled in here,
-- together with the assignments that used to run at load time.
data.bind{ AllNotesViewer = AllNotesViewer, NotesListWidget = NotesListWidget }
sheet.bind{ NotesListWidget = NotesListWidget }
pages.bind{ NotesListWidget = NotesListWidget, AllNotesViewer = AllNotesViewer,
            NoteItemWidget = NoteItemWidget }
list.bind{ AllNotesViewer = AllNotesViewer }
AllNotesViewer.samePath = NotesListWidget.samePath
NotesListWidget.Export = Export
NoteItemWidget.TextMark = Page.TextMark
NotesListWidget.Page = Page
NotesListWidget.States = States
NotesListWidget.SettingsScreen = SS
NotesListWidget.SubPage = SubPage
NotesListWidget.ListPicker = ListPicker

AllNotesViewer._test = {
    wrapText = wrapText,
    normalizeBookTitle = normalizeBookTitle,
    SORT_COMPARATORS = SORT_COMPARATORS,
    SortState = SortState,
    filterToString = filterToString,
    sortModeLabel = sortModeLabel,
    compareByPosition = compareByPosition,
    itemMatchesNote = itemMatchesNote,
    legacyNotes = AllNotesViewer.legacyNotes,
    samePath = AllNotesViewer.samePath,
    getSidecarKey = getSidecarKey,
    normalizeColorStyle = normalizeColorStyle,
    ReaderHighlight = ReaderHighlight,
    UIManager = UIManager,
    COLORS = COLORS,
    readSidecar = AllNotesViewer.readSidecar,
    DocSettings = DocSettings,
    notesToMarkdown = Export.notesToMarkdown,
    Export = Export,
    setSetting = setSetting,
    getSetting = getSetting,
    NotesListWidget = NotesListWidget,
    NoteItemWidget = NoteItemWidget,
    listNote = AllNotesViewer.listNote,
    splitTags = AllNotesViewer.splitTags,
}

return AllNotesViewer
