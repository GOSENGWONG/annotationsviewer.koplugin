local M = {}

local _settings_dirty = false

-- Lazy link to anv_item (item depends on core); resolve only at call time.
local _item
local function item()
    if not _item then _item = require("anv_item").NoteItemWidget end
    return _item
end

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Event = require("ui/event")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local SpinWidget = require("ui/widget/spinwidget")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local BlitBuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Device = require("device")
local Input = Device.input
local logger = require("logger")
local FontList = require("fontlist")
local DocSettings = require("docsettings")
local ReadHistory = require("readhistory")
local G_reader_settings = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/settings.annotationsviewer.lua")
local lfs = require("libs/libkoreader-lfs")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local _ = require("anv_i18n").gettext
local BD = require("ui/bidi")
local DEFAULT_CONTENT_FONT_SIZE = 16
local DEFAULT_TITLE_FONT_SIZE = 22
local DEFAULT_INFO_FONT_SIZE = 15
local DEFAULT_H_MARGIN = 50
local DEFAULT_NOTE_SPACING = 30
local DEFAULT_TEXT_MARGIN = 0
local DEFAULT_TRUNCATE_LINES = 5
local DEFAULT_TITLE_MARGIN = 8
local DEFAULT_INFO_MARGIN = 6
local DEFAULT_TOP_PADDING = 16
local function getSetting(key, default)
    local val = G_reader_settings:readSetting("annotationsviewer_" .. key)
    if val == nil then return default end
    if type(default) == "number" then
        local nval = tonumber(val)
        if nval == nil then return default end
        return nval
    end
    return val
end

local function setSetting(key, value)
    G_reader_settings:saveSetting("annotationsviewer_" .. key, value)
    _settings_dirty = true
end
local function flushSettings()
    if _settings_dirty then
        G_reader_settings:flush()
        _settings_dirty = false
    end
end
local function getContentFontSize()
    local v = getSetting("content_font_size", DEFAULT_CONTENT_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_CONTENT_FONT_SIZE end
    return v
end
local function getTitleFontSize()
    local v = getSetting("title_font_size", DEFAULT_TITLE_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_TITLE_FONT_SIZE end
    return v
end
local function getInfoFontSize()
    local v = getSetting("info_font_size", DEFAULT_INFO_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_INFO_FONT_SIZE end
    return v
end
local function getHMargin() return Screen:scaleBySize(getSetting("h_margin", DEFAULT_H_MARGIN)) end
local function getNoteSpacing() return Screen:scaleBySize(getSetting("note_spacing", DEFAULT_NOTE_SPACING)) end
local function getTextMargin() return Screen:scaleBySize(getSetting("text_margin", DEFAULT_TEXT_MARGIN)) end
local function getTruncateLines()
    return getSetting("truncate_lines", DEFAULT_TRUNCATE_LINES)
end
local function getJustify() return getSetting("justify", false) end
local function getTitleMargin() return Screen:scaleBySize(getSetting("title_margin", DEFAULT_TITLE_MARGIN)) end
local function getInfoMargin() return Screen:scaleBySize(getSetting("info_margin", DEFAULT_INFO_MARGIN)) end
local function getTitleFont() return getSetting("title_font", nil) end
local function getInfoFont() return getSetting("info_font", nil) end
local function getContentFont() return getSetting("content_font", nil) end
local function getShowTotalNotes() return getSetting("show_total", true) end
local function getTopPadding() return Screen:scaleBySize(getSetting("top_padding", DEFAULT_TOP_PADDING)) end
local function getHideDupTitle() return getSetting("hide_dup_title", true) ~= false end
local function getHideDupInfo() return getSetting("hide_dup_info", true) ~= false end
local function getSwipeSetting() return getSetting("swipe_direction", "both") end
local function getDedupInfoFields() return getSetting("dedup_info_fields", "date,author,chapter") end
local function getShowInfo() return getSetting("show_info", true) ~= false end
local function getInfoFields() return getSetting("info_fields", "date,author,chapter") end
local getNoteInfoKey -- defined below
local function getAlwaysShowFirstOnPage() return getSetting("always_show_first_on_page", true) ~= false end
-- Repeat the book title / the chapter·date line at the top of every page. Both start from the
-- older single "show on every page" setting.
local function getRepeatTitleOnPage() return getSetting("repeat_title_on_page", getAlwaysShowFirstOnPage()) ~= false end
local function getRepeatInfoOnPage() return getSetting("repeat_info_on_page", getAlwaysShowFirstOnPage()) ~= false end
-- extra space above a book title that is not at the top of the page
local BOOK_GAP = Screen:scaleBySize(14)
-- Which header rows an annotation leaves out, given what came right before it.
local function getHeaderSkips(note, is_first_on_page, prev_title, prev_info_key, dedup_fields)
    local skip_title = getHideDupTitle()
        and not (getRepeatTitleOnPage() and is_first_on_page)
        and (note.book_title == prev_title)
    local skip_info = getHideDupInfo()
        and not (getRepeatInfoOnPage() and is_first_on_page)
        and (getNoteInfoKey(note, dedup_fields) == prev_info_key)
    return skip_title, skip_info
end
-- "default" = Prev / Next bar at the bottom. The older "left" / "right" bars were merged into it.
local function getPaginationStyle()
    local style = getSetting("pagination_style", "default")
    if style == "left" or style == "right" then return "default" end
    return style
end
local function getScrollbarBookMarks() return getSetting("sb_book_marks", true) ~= false end
local function isScrollbarStyle(style)
    style = style or getPaginationStyle()
    return style == "scrollbar" or style == "scrollbar_chevrons"
end
-- Same look as before the redesign: 1px black track, narrow outline thumb
local SB_THUMB_WIDTH  = Screen:scaleBySize(8)
local SB_TRACK_WIDTH  = Screen:scaleBySize(1)
local SB_STRIP_WIDTH  = Screen:scaleBySize(32 + 16 + 3)
local SB_MARGIN_RIGHT = 0
local SB_MARGIN_V_TOP    = Screen:scaleBySize(16)
local SB_MARGIN_V_BOTTOM = SB_MARGIN_V_TOP -- same space below as above
-- The plugin's own colours (from the design), as fixed grey values rather than KOReader's
-- named greys, so every screen uses exactly the same shades.
local COLORS = {
    ink        = BlitBuffer.COLOR_BLACK,
    muted      = BlitBuffer.Color8(0x45), -- secondary text: tabs, info line, author, counts
    disabled   = BlitBuffer.Color8(0xAA), -- buttons that can't be used
    line       = BlitBuffer.Color8(0xBD), -- separators
    line_light = BlitBuffer.Color8(0xD6), -- row lines, line under book titles
    section_bg = BlitBuffer.Color8(0xE9), -- section bars in Filter & sort
    section_fg = BlitBuffer.Color8(0x33),
}
-- where a book starts: a short notch across the track, like chapter ticks on Kindle/Kobo
local SB_MARK_OVERHANG = Screen:scaleBySize(3)          -- how far it sticks out on each side
local SB_MARK_HEIGHT   = math.max(1, math.floor(Screen:scaleBySize(1)))
-- Header: top bar (menu, title, search, filter, close), tab row, optional active-filter row
local TOPBAR_HEIGHT    = Screen:scaleBySize(50)
local TOPBAR_BOOK_HEIGHT = Screen:scaleBySize(54) -- one-book view: title + author line, a bit taller to fit the larger second line
local TABS_HEIGHT      = Screen:scaleBySize(38)
local FOOTER_BAR_HEIGHT = Screen:scaleBySize(48) -- page buttons bar (non-scrollbar styles)
-- mockup: 22px icons in 44px buttons, 8px from the screen edges, 4px between menu and title
local HEADER_ICON_SIZE = Screen:scaleBySize(22)
local HEADER_ICON_PAD  = Screen:scaleBySize(11)
-- Serif used for book titles, highlights and the screen title unless the user picked a font
local SERIF_FONT = "NotoSerif-Regular.ttf"
-- Icons shipped with the plugin (drawn in the style of KOReader's own mdlight set)
local PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*/)[^/]*$") or "./"
local function pluginIcon(name) return PLUGIN_DIR .. "icons/" .. name .. ".svg" end
local function getFaceOr(font_name, size, fallback)
    return (font_name and font_name ~= "" and Font:getFace(font_name, size))
        or Font:getFace(fallback, size) or Font:getFace("cfont", size)
end

local SPIN_MENUS = {
    font_size = {
        dialog_name = "font_size_dialog",
        title = _("Font sizes"),
        settings = {
            { label = _("Title size: "), key = "title_font_size", default = DEFAULT_TITLE_FONT_SIZE, min = 8, max = 48, step = 1, getter = getTitleFontSize },
            { label = _("Info size: "), key = "info_font_size", default = DEFAULT_INFO_FONT_SIZE, min = 8, max = 48, step = 1, getter = getInfoFontSize },
            { label = _("Content size: "), key = "content_font_size", default = DEFAULT_CONTENT_FONT_SIZE, min = 8, max = 48, step = 1, getter = getContentFontSize },
        }
    },
    section_margin = {
        dialog_name = "section_margin_dialog",
        title = _("Space between notes"),
        settings = {
            { label = _("Below the book title: "), key = "title_margin", default = DEFAULT_TITLE_MARGIN, min = 0, max = 30, step = 1, getter = function() return getSetting("title_margin", DEFAULT_TITLE_MARGIN) end },
            { label = _("Below the chapter · date line: "), key = "info_margin", default = DEFAULT_INFO_MARGIN, min = 0, max = 30, step = 1, getter = function() return getSetting("info_margin", DEFAULT_INFO_MARGIN) end },
        }
    },
    margins = {
        dialog_name = "margin_dialog",
        title = _("Page margins"),
        settings = {
            { label = _("Top padding: "), key = "top_padding", default = DEFAULT_TOP_PADDING, min = 0, max = 100, step = 5, getter = function() return getSetting("top_padding", DEFAULT_TOP_PADDING) end },
            { label = _("Horizontal margin: "), key = "h_margin", default = DEFAULT_H_MARGIN, min = 5, max = 60, step = 5, getter = function() return getSetting("h_margin", DEFAULT_H_MARGIN) end },
            { label = _("Landscape width (%): "), key = "landscape_width_pct", default = 80, min = 40, max = 100, step = 5, getter = function() return getSetting("landscape_width_pct", 80) end },
            { label = _("Between annotations: "), key = "note_spacing", default = DEFAULT_NOTE_SPACING, min = 5, max = 100, step = 2, getter = function() return getSetting("note_spacing", DEFAULT_NOTE_SPACING) end },
            { label = _("Space above the note: "), key = "note_offset", default = 8, min = 0, max = 40, step = 2, getter = function() return getSetting("note_offset", 8) end },
            { label = _("Extra indent for the note: "), key = "note_indent", default = 0, min = 0, max = 60, step = 2, getter = function() return getSetting("note_indent", 0) end },
            { label = _("Line spacing: "), key = "line_spacing", default = 0, min = -15, max = 20, step = 1, getter = function() return getSetting("line_spacing", 0) end },
            { label = _("Text indent: "), key = "text_margin", default = DEFAULT_TEXT_MARGIN, min = 0, max = 30, step = 2, getter = function() return getSetting("text_margin", DEFAULT_TEXT_MARGIN) end },
        }
    }
}

local HIGHLIGHT_COLORS = BlitBuffer.HIGHLIGHT_COLORS


-- A highlight colour's code ("#rrggbb"). Newer KOReader (after 2026.07) lets you give each
-- colour its own name and code (Highlight color → hold a colour): its code is used then, the
-- built-in one otherwise. Never inverted for night mode: the list paints true colours itself.
function COLORS.highlightCode(key)
    if type(key) ~= "string" then return nil end
    key = key:lower()
    if ReaderHighlight.getHighlightColorCode then
        local ok, code = pcall(ReaderHighlight.getHighlightColorCode, ReaderHighlight, key, nil, false)
        if ok and type(code) == "string" and code:match("^#%x%x%x%x%x%x$") then return code end
    end
    return HIGHLIGHT_COLORS[key]
end
local function getHighlightColor(color)
    local val = COLORS.highlightCode(color)
    if val and BlitBuffer.colorFromString then
        return BlitBuffer.colorFromString(val)
    end
    return BlitBuffer.COLOR_GRAY
end
local function isNoBackgroundStyle(drawer)
    if not drawer then return false end
    local d = drawer:lower()
    return d == "strikeout" or d == "underscore"
end

local function truncateAuthorDisplay(author_str)
    if not author_str or author_str == "Unknown" then return author_str end
    if not author_str:find("\n") then return author_str end
    local first_author = author_str:match("^([^\n]+)")
    if first_author then
        first_author = first_author:match("^%s*(.-)%s*$")
        return first_author .. " et al."
    end
    return author_str
end

local NoteWrapper = {}
function NoteWrapper:new(note)
    return setmetatable({ _note = note }, { __index = self })
end
function NoteWrapper:getDisplayAuthors()
    if not self._note.book_authors or self._note.book_authors == "" or self._note.book_authors == "Unknown" then
        return nil
    end
    return truncateAuthorDisplay(self._note.book_authors)
end
function NoteWrapper:getTags()
    local tags = self._note.tags or self._note.keywords or {}
    if type(tags) == "string" then
        local result = {}
        for tag in tags:gmatch("[^,;\n|\t]+") do
            tag = tag:match("^%s*(.-)%s*$")
            if tag ~= "" then table.insert(result, tag) end
        end
        return result
    end
    return tags
end
function NoteWrapper:getNormalizedColor()
    return self._note.color and self._note.color:lower() or nil
end
function NoteWrapper:getNormalizedDrawer()
    return self._note.drawer and self._note.drawer:lower() or nil
end
function NoteWrapper:hasHighlightedText()
    return self._note.highlighted_text and self._note.highlighted_text ~= "" or false
end
function NoteWrapper:hasUserNote()
    return self._note.user_note and self._note.user_note ~= "" or false
end

-- Text measurement caches. Font:getFace() returns cached face objects, so a face's
-- table identity is a stable key; weak keys let unused faces be collected.
-- A highlight colour as painted, and its name: the name you gave it in KOReader when it has one.
local function colorName(key)
    if type(key) ~= "string" or key == "" then return "" end
    key = key:lower()
    if ReaderHighlight.getHighlightColorString then
        local ok, name = pcall(ReaderHighlight.getHighlightColorString, ReaderHighlight, key)
        -- the key itself comes back for a colour KOReader doesn't know, unless you named it so
        local own = ReaderHighlight.custom_colors and ReaderHighlight.custom_colors[key]
        if ok and type(name) == "string" and name ~= "" and (name ~= key or (type(own) == "table" and own.name == key)) then
            return name
        end
    end
    for _i, v in ipairs(ReaderHighlight.highlight_colors or {}) do
        if v[2] == key then return v[1] end
    end
    return key:sub(1, 1):upper() .. key:sub(2)
end
local HIGHLIGHT_STYLES = {
    { "lighten", _("Lighten") }, { "underscore", _("Underline") },
    { "strikeout", _("Strikeout") }, { "invert", _("Invert") },
}
getNoteInfoKey = function(note, fields_setting)
    local parts = {}
    local fields = {}
    for f in fields_setting:gmatch("[^,]+") do fields[f] = true end
    if fields["date"] and item().infoShowsDate() then
        table.insert(parts, note.datetime and note.datetime:match("^(%d+-%d+-%d+)") or "")
    end
    if fields["author"] then
        table.insert(parts, note.book_authors or "")
    end
    if fields["chapter"] then
        table.insert(parts, note.chapter or "")
    end
    return table.concat(parts, "|")
end

-- Module exports
M.WidgetContainer = WidgetContainer
M.ReaderHighlight = ReaderHighlight
M.FrameContainer = FrameContainer
M.VerticalGroup = VerticalGroup
M.VerticalSpan = VerticalSpan
M.Event = Event
M.HorizontalGroup = HorizontalGroup
M.HorizontalSpan = HorizontalSpan
M.LeftContainer = LeftContainer
M.TopContainer = TopContainer
M.BottomContainer = BottomContainer
M.OverlapGroup = OverlapGroup
M.CenterContainer = CenterContainer
M.TextBoxWidget = TextBoxWidget
M.TextWidget = TextWidget
M.InputContainer = InputContainer
M.GestureRange = GestureRange
M.UIManager = UIManager
M.InfoMessage = InfoMessage
M.TextViewer = TextViewer
M.SpinWidget = SpinWidget
M.IconButton = IconButton
M.IconWidget = IconWidget
M.LineWidget = LineWidget
M.RightContainer = RightContainer
M.BlitBuffer = BlitBuffer
M.Screen = Screen
M.Device = Device
M.Input = Input
M.logger = logger
M.FontList = FontList
M.DocSettings = DocSettings
M.ReadHistory = ReadHistory
M.G_reader_settings = G_reader_settings
M.lfs = lfs
M.Font = Font
M.Size = Size
M.Geom = Geom
M._ = _
M.BD = BD
M.DEFAULT_CONTENT_FONT_SIZE = DEFAULT_CONTENT_FONT_SIZE
M.DEFAULT_TITLE_FONT_SIZE = DEFAULT_TITLE_FONT_SIZE
M.DEFAULT_INFO_FONT_SIZE = DEFAULT_INFO_FONT_SIZE
M.DEFAULT_H_MARGIN = DEFAULT_H_MARGIN
M.DEFAULT_NOTE_SPACING = DEFAULT_NOTE_SPACING
M.DEFAULT_TEXT_MARGIN = DEFAULT_TEXT_MARGIN
M.DEFAULT_TRUNCATE_LINES = DEFAULT_TRUNCATE_LINES
M.DEFAULT_TITLE_MARGIN = DEFAULT_TITLE_MARGIN
M.DEFAULT_INFO_MARGIN = DEFAULT_INFO_MARGIN
M.DEFAULT_TOP_PADDING = DEFAULT_TOP_PADDING
M.getSetting = getSetting
M.setSetting = setSetting
M.flushSettings = flushSettings
M.getContentFontSize = getContentFontSize
M.getTitleFontSize = getTitleFontSize
M.getInfoFontSize = getInfoFontSize
M.getHMargin = getHMargin
M.getNoteSpacing = getNoteSpacing
M.getTextMargin = getTextMargin
M.getTruncateLines = getTruncateLines
M.getJustify = getJustify
M.getTitleMargin = getTitleMargin
M.getInfoMargin = getInfoMargin
M.getTitleFont = getTitleFont
M.getInfoFont = getInfoFont
M.getContentFont = getContentFont
M.getShowTotalNotes = getShowTotalNotes
M.getTopPadding = getTopPadding
M.getHideDupTitle = getHideDupTitle
M.getHideDupInfo = getHideDupInfo
M.getSwipeSetting = getSwipeSetting
M.getDedupInfoFields = getDedupInfoFields
M.getShowInfo = getShowInfo
M.getInfoFields = getInfoFields
M.getNoteInfoKey = getNoteInfoKey
M.getAlwaysShowFirstOnPage = getAlwaysShowFirstOnPage
M.getRepeatTitleOnPage = getRepeatTitleOnPage
M.getRepeatInfoOnPage = getRepeatInfoOnPage
M.BOOK_GAP = BOOK_GAP
M.getHeaderSkips = getHeaderSkips
M.getPaginationStyle = getPaginationStyle
M.getScrollbarBookMarks = getScrollbarBookMarks
M.isScrollbarStyle = isScrollbarStyle
M.SB_THUMB_WIDTH = SB_THUMB_WIDTH
M.SB_TRACK_WIDTH = SB_TRACK_WIDTH
M.SB_STRIP_WIDTH = SB_STRIP_WIDTH
M.SB_MARGIN_RIGHT = SB_MARGIN_RIGHT
M.SB_MARGIN_V_TOP = SB_MARGIN_V_TOP
M.SB_MARGIN_V_BOTTOM = SB_MARGIN_V_BOTTOM
M.COLORS = COLORS
M.SB_MARK_OVERHANG = SB_MARK_OVERHANG
M.SB_MARK_HEIGHT = SB_MARK_HEIGHT
M.TOPBAR_HEIGHT = TOPBAR_HEIGHT
M.TOPBAR_BOOK_HEIGHT = TOPBAR_BOOK_HEIGHT
M.TABS_HEIGHT = TABS_HEIGHT
M.FOOTER_BAR_HEIGHT = FOOTER_BAR_HEIGHT
M.HEADER_ICON_SIZE = HEADER_ICON_SIZE
M.HEADER_ICON_PAD = HEADER_ICON_PAD
M.SERIF_FONT = SERIF_FONT
M.PLUGIN_DIR = PLUGIN_DIR
M.pluginIcon = pluginIcon
M.getFaceOr = getFaceOr
M.SPIN_MENUS = SPIN_MENUS
M.HIGHLIGHT_COLORS = HIGHLIGHT_COLORS
M.getHighlightColor = getHighlightColor
M.isNoBackgroundStyle = isNoBackgroundStyle
M.truncateAuthorDisplay = truncateAuthorDisplay
M.NoteWrapper = NoteWrapper
M.colorName = colorName
M.HIGHLIGHT_STYLES = HIGHLIGHT_STYLES

return M
