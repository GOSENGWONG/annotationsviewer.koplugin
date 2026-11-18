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

local AllNotesViewer  -- injected by main assembly
local NotesListWidget -- injected by main assembly

local function normalizeColorStyle(af)
    if type(af) ~= "table" then return end
    local function valid(t, v) return (t == "color" or t == "style") and type(v) == "string" and v ~= "" end
    local inc = valid(af.type, af.value)
    local exc = valid(af.type_exclude, af.value_exclude)
    if inc then
        af.cs = type(af.cs) == "table" and af.cs or {}
        af.cs[af.type .. ":" .. af.value] = true
        af.cs_exclude = false
        -- an old filter that also hid something: "show yellow, hide Underline" is "yellow, with
        -- any style but Underline" (colours and styles together must both match). Hiding the same
        -- kind as the one shown adds nothing.
        if exc and af.type_exclude ~= af.type then
            if af.type_exclude == "style" then
                local styles = { "lighten", "underscore", "strikeout", "invert" }
                for n = 1, #styles do
                    if styles[n] ~= af.value_exclude then af.cs["style:" .. styles[n]] = true end
                end
            else
                local colors = ReaderHighlight.highlight_colors or {}
                for n = 1, #colors do
                    local key = colors[n][2]
                    if type(key) == "string" and key ~= af.value_exclude then af.cs["color:" .. key] = true end
                end
            end
        end
    elseif exc and not (type(af.cs) == "table" and next(af.cs)) then
        af.cs = { [af.type_exclude .. ":" .. af.value_exclude] = true }
        af.cs_exclude = true
    end
    af.type, af.value, af.type_exclude, af.value_exclude = nil, nil, nil, nil
    -- drop what can't be a colour or style (a hand-edited or broken saved filter)
    if af.cs ~= nil and type(af.cs) ~= "table" then af.cs = nil end
    if af.cs then
        for k in pairs(af.cs) do
            local t, v
            if type(k) == "string" then t, v = k:match("^(%a+):(.+)$") end
            if not valid(t, v) or af.cs[k] ~= true then af.cs[k] = nil end
        end
    end
    if af.cs and not next(af.cs) then af.cs, af.cs_exclude = nil, nil end
end
local function colorStyleMatches(af, note)
    local nw = NoteWrapper:new(note)
    local c, d = nw:getNormalizedColor(), nw:getNormalizedDrawer()
    local has_c, has_s, hit_c, hit_s = false, false, false, false
    for k in pairs(af.cs) do
        local t, v = k:match("^(%a+):(.+)$")
        if t == "color" then has_c = true; if v == c then hit_c = true end
        elseif t == "style" then has_s = true; if v == d then hit_s = true end end
    end
    if af.cs_exclude then return not (hit_c or hit_s) end
    -- several colours: any of them; colours and styles together: both must match. A highlight
    -- without a colour (Invert never has one, nor do some older highlights) matches on its style
    -- alone, or Invert with a colour would never show anything.
    if has_c and has_s and hit_s and (c == nil or d == "invert") then return true end
    return (not has_c or hit_c) and (not has_s or hit_s)
end

local _annotation_cache = {}  -- [book_path] = { data = {...}, mtime = key }
local _book_info_cache   = {}  -- [book_path] = { data = {...}, mtime = key }

local function fileStamp(path)
    local attr = path and lfs.attributes(path)
    if attr and attr.mode == "file" then
        return attr.modification .. ":" .. attr.size
    end
end

-- Returns a key for the current state of a book's sidecar, plus the sidecar path.
-- The second value is false when the book definitely has no sidecar (so no annotations),
-- and nil when that can't be determined (KOReader < 2023).
-- The sidecar is the one KOReader's DocSettings:open would read, found without its side effects
-- (open() deletes empty or broken files): every place KOReader keeps one (book folder, docsettings
-- folder, hash folder when in use, history folder, and their ".old" backups), the most recently
-- changed first; a backup never goes before its own file.
local function getSidecarKey(book_path)
    local ok, sidecar = pcall(function()
        local list = NotesListWidget.sidecarCandidates(book_path)
        for i = 1, #list do
            if list[i].size > 0 then return list[i].path end -- open() skips empty files
        end
    end)
    local stamp = ok and type(sidecar) == "string" and fileStamp(sidecar)
    if stamp then return stamp, sidecar end
    -- Fall back to the book file itself. false: KOReader looked and there is no sidecar;
    -- nil: it couldn't look (`a and false or nil` would always give nil)
    local none = nil
    if ok then none = false end
    return "book:" .. (fileStamp(book_path) or ""), none
end

-- Key for the book info (title/authors/tags): the sidecar key plus the custom metadata file,
-- which KOReader keeps next to the sidecar and updates when book info is edited.
local function getBookInfoKey(sidecar_key, sidecar)
    local dir = sidecar and sidecar:match("^(.*)/")
    return sidecar_key .. "|" .. ((dir and fileStamp(dir .. "/custom_metadata.lua")) or "")
end

-- On-disk copy of the caches above, so a KOReader restart doesn't mean parsing every
-- book's sidecar again. Bump CACHE_VERSION whenever the cached data's shape changes.
local CACHE_VERSION = 5 -- 3: bookmarks and page labels are kept; 4: old-format books marked legacy, with notes;
                        -- 5: book info keeps series and language
local _persist = nil        -- LuaSettings object, loaded on the first scan
local _persist_dirty = false
local _persist_count = 0

local function loadPersistentCache()
    if _persist then return end
    local ok_ds, DataStorage = pcall(require, "datastorage")
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    if not (ok_ds and ok_ls) then return end
    local dir = DataStorage:getDataDir() .. "/cache"
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local ok, settings = pcall(LuaSettings.open, LuaSettings, dir .. "/annotationsviewer.lua")
    if not ok or not settings then return end
    _persist = settings
    local d = settings.data
    if d.version ~= CACHE_VERSION or type(d.books) ~= "table" then
        settings.data = { version = CACHE_VERSION, books = {} }
        _persist_dirty = true
        return
    end
    _persist_count = 0
    for path, b in pairs(d.books) do
        _persist_count = _persist_count + 1
        if not _annotation_cache[path] and b.key and b.annotations then
            _annotation_cache[path] = { data = b.annotations, mtime = b.key }
        end
        if not _book_info_cache[path] and b.info_key and b.info then
            _book_info_cache[path] = { data = b.info, mtime = b.info_key }
        end
    end
end

-- Writes the caches for the given books (the ones found by the last scan) back to disk,
-- but only if something was read from a sidecar since the last save.
local function savePersistentCache(paths)
    if not _persist then return end
    if not _persist_dirty and #paths == _persist_count then return end
    local books = {}
    for _, path in ipairs(paths) do
        local a, i = _annotation_cache[path], _book_info_cache[path]
        if a then
            books[path] = {
                key = a.mtime, annotations = a.data,
                info_key = i and i.mtime, info = i and i.data,
            }
        end
    end
    _persist.data = { version = CACHE_VERSION, books = books }
    local ok, err = pcall(_persist.flush, _persist)
    if not ok then logger.warn("AnnotationsViewer: could not save cache:", err) end
    _persist_dirty = false
    _persist_count = #paths
end

-- Write-back helpers -------------------------------------------------------------------

local function positionsEqual(a, b)
    if a == b then return true end
    if type(a) == "table" and type(b) == "table" then -- PDF/CBZ positions
        return a.x == b.x and a.y == b.y and a.page == b.page
    end
    return false
end

-- Does a stored or live annotation item correspond to this plugin note?
-- Matches on date, highlighted text and position, so two highlights saved in the same
-- second with the same text are told apart.
local function itemMatchesNote(item, note)
    -- the list keeps "" for an item without a date, so compare both the same way
    if (item.datetime or "") ~= (note.datetime or "") then return false end
    if note.bookmark then -- a bookmark has no text of its own: match on its place
        return item.drawer == nil and positionsEqual(item.page or item.pageno, note.page)
    end
    if (item.text or "") ~= (note.highlighted_text or "") then return false end
    if note.pos0 ~= nil then
        return positionsEqual(item.pos0, note.pos0) and positionsEqual(item.pos1, note.pos1)
    end
    return true
end

-- Returns the ReaderUI if this book is currently open, so changes go through KOReader.
local function getLiveReader(book_path)
    local ReaderUI = require("apps/reader/readerui")
    local ui = ReaderUI and ReaderUI.instance
    if ui and ui.document and NotesListWidget.samePath(ui.document.file, book_path)
            and ui.annotation and ui.annotation.annotations then
        return ui
    end
end

local function findLiveIndex(ui, note)
    for i, item in ipairs(ui.annotation.annotations) do
        if itemMatchesNote(item, note) then return i end
    end
end

-- Finds the annotation for `note` in its (closed) book's sidecar, calls fn(item, list, index)
-- on it and saves the sidecar. Returns true if the annotation was found.
local function editStoredAnnotation(note, fn)
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, note.book_path)
    if not ok or not doc_settings or not doc_settings.data then return false end
    local data = doc_settings.data
    local found = false
    if type(data.annotations) == "table" then
        for i, item in ipairs(data.annotations) do
            if itemMatchesNote(item, note) then
                fn(item, data.annotations, i)
                found = true
                break
            end
        end
    end
    -- an old-format sidecar (no `annotations` list) is never written: see AllNotesViewer.legacyBlocked
    if found then doc_settings:flush() end
    return found
end

local function nowStamp() return os.date("%Y-%m-%d %H:%M:%S") end

-- Changes the style or colour of a highlight in the open book, the way ReaderHighlight does
-- (including the PDF annotation), and tells KOReader about the real item.
local function setLiveHighlightField(ui, index, field, value)
    local item = ui.annotation.annotations[index]
    local hl = ui.highlight
    local pdf = hl and hl.writePdfAnnotation
    if pdf then hl:writePdfAnnotation("delete", item) end
    item[field] = value
    if pdf and ui.paging then
        hl:writePdfAnnotation("save", item)
        if item.note then hl:writePdfAnnotation("content", item, item.note) end
    end
    ui:handleEvent(Event:new("AnnotationsModified", { item }))
    UIManager:setDirty(ui.dialog) -- repainted with the new colour / style when the list closes
end


-- Module exports
M.normalizeColorStyle = normalizeColorStyle
M.colorStyleMatches = colorStyleMatches
M._annotation_cache = _annotation_cache
M._book_info_cache = _book_info_cache
M.fileStamp = fileStamp
M.getSidecarKey = getSidecarKey
M.getBookInfoKey = getBookInfoKey
M.CACHE_VERSION = CACHE_VERSION
M._persist = _persist
M._persist_dirty = _persist_dirty
M._persist_count = _persist_count
M.loadPersistentCache = loadPersistentCache
M.savePersistentCache = savePersistentCache
M.positionsEqual = positionsEqual
M.itemMatchesNote = itemMatchesNote
M.getLiveReader = getLiveReader
M.findLiveIndex = findLiveIndex
M.editStoredAnnotation = editStoredAnnotation
M.nowStamp = nowStamp
M.setLiveHighlightField = setLiveHighlightField

-- Cache state is module-local (loadPersistentCache replaces _persist at runtime), so callers
-- reach the scalars through these accessors rather than capturing a stale snapshot.
function M.clearCaches()
    for k in pairs(_annotation_cache) do _annotation_cache[k] = nil end
    for k in pairs(_book_info_cache) do _book_info_cache[k] = nil end
    if _persist then
        _persist.data = { version = CACHE_VERSION, books = {} }
        pcall(_persist.flush, _persist)
    end
    _persist, _persist_dirty, _persist_count = nil, false, 0
end
function M.invalidateBook(book_path)
    _annotation_cache[book_path] = nil
    -- book_info rarely changes, but clear it too so tags/title edits are reflected
    _book_info_cache[book_path] = nil
end
function M.markPersistDirty() _persist_dirty = true end
function M.isPersistLoaded() return _persist ~= nil end

function M.bind(deps)
    if deps.AllNotesViewer then AllNotesViewer = deps.AllNotesViewer end
    if deps.NotesListWidget then NotesListWidget = deps.NotesListWidget end
end

return M
