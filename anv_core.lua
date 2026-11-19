-- anv_core.lua — Annotations Viewer
--
-- Bottom-of-graph module owning plugin settings, shared layout/visual
-- constants and note helpers for the other anv_* modules. Requires KOReader
-- APIs and anv_i18n directly; the link to anv_item is resolved lazily to
-- avoid a require cycle. Callers require widget classes themselves.
--
-- Public API (used by other modules):
--   getSetting / setSetting / flushSettings    read, write and persist settings
--   getContentFontSize / getTitleFontSize / getInfoFontSize    scaled font sizes
--   getHMargin / getNoteSpacing / getTextMargin    scaled horizontal/spacing margins
--   getTruncateLines / getDefaultTruncateLines    note line limit, current and default
--   getAntiAlias    whether KOReader UI anti-aliasing is on
--   getJustify    whether note text is justified
--   getTitleMargin / getInfoMargin    scaled title/info margins
--   getTitleFont / getInfoFont / getContentFont    configured font names
--   getShowTotalNotes    whether to show the total note count
--   getTopPadding    scaled top padding
--   getHideDupTitle / getHideDupInfo    hide duplicate title/info headers
--   getSwipeSetting    configured swipe direction
--   getDedupInfoFields / getInfoFields    fields used for dedup / info line
--   getShowInfo    whether to show the info line
--   getRepeatTitleOnPage / getRepeatInfoOnPage    repeat headers on each page
--   getHeaderSkips    skip repeated title/info for a note
--   getPaginationStyle    current pagination style
--   getScrollbarBookMarks    whether bookmarks show on the scrollbar
--   isScrollbarStyle    test a style against the scrollbar family
--   getNoteInfoKey    cache key for a note's info fields
--   getFaceOr    resolve a font face with fallback
--   pluginIcon    full path of a plugin icon
--   colorName / getHighlightColor / isNoBackgroundStyle    highlight color helpers
--   NoteWrapper    note wrapper class exposing display authors, tags and color
--   COLORS / HIGHLIGHT_STYLES / SERIF_FONT / SPIN_MENUS    shared visuals
--   BOOK_GAP    scaled gap between books
--   TOPBAR_HEIGHT / TOPBAR_BOOK_HEIGHT / TABS_HEIGHT / FOOTER_BAR_HEIGHT    bar sizes
--   HEADER_ICON_SIZE / HEADER_ICON_PAD    header icon dimensions
--   SB_THUMB_WIDTH / SB_TRACK_WIDTH / SB_STRIP_WIDTH    scrollbar sizes
--   SB_MARGIN_RIGHT / SB_MARGIN_V_TOP / SB_MARGIN_V_BOTTOM    scrollbar margins
--   SB_MARK_OVERHANG / SB_MARK_HEIGHT    bookmark mark geometry

local Core = {}

local _settings_dirty = false

-- Lazy link to anv_item (item depends on core); resolve only at call time.
local _item
local function item()
    if not _item then _item = require("anv_item").NoteItemWidget end
    return _item
end

local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local BlitBuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local G_reader_settings = require("luasettings"):open(require("datastorage"):getSettingsDir() .. "/settings.annotationsviewer.lua")
local Font = require("ui/font")
local _ = require("anv_i18n").gettext

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

function Core.getSetting(key, default)
    local val = G_reader_settings:readSetting("annotationsviewer_" .. key)
    if val == nil then return default end
    if type(default) == "number" then
        local nval = tonumber(val)
        if nval == nil then return default end
        return nval
    end
    return val
end

function Core.setSetting(key, value)
    G_reader_settings:saveSetting("annotationsviewer_" .. key, value)
    _settings_dirty = true
end
function Core.flushSettings()
    if _settings_dirty then
        G_reader_settings:flush()
        _settings_dirty = false
    end
end
function Core.getContentFontSize()
    local v = Core.getSetting("content_font_size", DEFAULT_CONTENT_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_CONTENT_FONT_SIZE end
    return v
end
function Core.getTitleFontSize()
    local v = Core.getSetting("title_font_size", DEFAULT_TITLE_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_TITLE_FONT_SIZE end
    return v
end
function Core.getInfoFontSize()
    local v = Core.getSetting("info_font_size", DEFAULT_INFO_FONT_SIZE)
    v = tonumber(v)
    if not v or v <= 0 then return DEFAULT_INFO_FONT_SIZE end
    return v
end
function Core.getHMargin() return Screen:scaleBySize(Core.getSetting("h_margin", DEFAULT_H_MARGIN)) end
function Core.getNoteSpacing() return Screen:scaleBySize(Core.getSetting("note_spacing", DEFAULT_NOTE_SPACING)) end
function Core.getTextMargin() return Screen:scaleBySize(Core.getSetting("text_margin", DEFAULT_TEXT_MARGIN)) end
function Core.getTruncateLines()
    local v = tonumber(Core.getSetting("truncate_lines", DEFAULT_TRUNCATE_LINES))
    if not v or v < 1 then return DEFAULT_TRUNCATE_LINES end
    return math.floor(v)
end
function Core.getDefaultTruncateLines() return DEFAULT_TRUNCATE_LINES end
function Core.getAntiAlias()
    -- anti_alias_ui is a KOReader global UI setting; the local G_reader_settings above is this
    -- plugin's private settings file, so read the global directly. Default to on when absent.
    local ko = rawget(_G, "G_reader_settings")
    if ko and type(ko.nilOrTrue) == "function" then return ko:nilOrTrue("anti_alias_ui") end
    return true
end
function Core.getJustify() return Core.getSetting("justify", false) end
function Core.getTitleMargin() return Screen:scaleBySize(Core.getSetting("title_margin", DEFAULT_TITLE_MARGIN)) end
function Core.getInfoMargin() return Screen:scaleBySize(Core.getSetting("info_margin", DEFAULT_INFO_MARGIN)) end
function Core.getTitleFont() return Core.getSetting("title_font", nil) end
function Core.getInfoFont() return Core.getSetting("info_font", nil) end
function Core.getContentFont() return Core.getSetting("content_font", nil) end
function Core.getShowTotalNotes() return Core.getSetting("show_total", true) end
function Core.getTopPadding() return Screen:scaleBySize(Core.getSetting("top_padding", DEFAULT_TOP_PADDING)) end
function Core.getHideDupTitle() return Core.getSetting("hide_dup_title", true) ~= false end
function Core.getHideDupInfo() return Core.getSetting("hide_dup_info", true) ~= false end
function Core.getSwipeSetting() return Core.getSetting("swipe_direction", "both") end
function Core.getDedupInfoFields() return Core.getSetting("dedup_info_fields", "date,author,chapter") end
function Core.getShowInfo() return Core.getSetting("show_info", true) ~= false end
function Core.getInfoFields() return Core.getSetting("info_fields", "date,author,chapter") end
local function getAlwaysShowFirstOnPage() return Core.getSetting("always_show_first_on_page", true) ~= false end
-- Repeat the book title / the chapter·date line at the top of every page. Both start from the
-- older single "show on every page" setting.
function Core.getRepeatTitleOnPage() return Core.getSetting("repeat_title_on_page", getAlwaysShowFirstOnPage()) ~= false end
function Core.getRepeatInfoOnPage() return Core.getSetting("repeat_info_on_page", getAlwaysShowFirstOnPage()) ~= false end
-- extra space above a book title that is not at the top of the page
Core.BOOK_GAP = Screen:scaleBySize(14)
-- Which header rows an annotation leaves out, given what came right before it.
function Core.getHeaderSkips(note, is_first_on_page, prev_title, prev_info_key, dedup_fields)
    local skip_title = Core.getHideDupTitle()
        and not (Core.getRepeatTitleOnPage() and is_first_on_page)
        and (note.book_title == prev_title)
    local skip_info = Core.getHideDupInfo()
        and not (Core.getRepeatInfoOnPage() and is_first_on_page)
        and (Core.getNoteInfoKey(note, dedup_fields) == prev_info_key)
    return skip_title, skip_info
end
-- "default" = Prev / Next bar at the bottom. The older "left" / "right" bars were merged into it.
function Core.getPaginationStyle()
    local style = Core.getSetting("pagination_style", "default")
    if style == "left" or style == "right" then return "default" end
    return style
end
function Core.getScrollbarBookMarks() return Core.getSetting("sb_book_marks", true) ~= false end
function Core.isScrollbarStyle(style)
    style = style or Core.getPaginationStyle()
    return style == "scrollbar" or style == "scrollbar_chevrons"
end
-- Same look as before the redesign: 1px black track, narrow outline thumb
Core.SB_THUMB_WIDTH  = Screen:scaleBySize(8)
Core.SB_TRACK_WIDTH  = Screen:scaleBySize(1)
Core.SB_STRIP_WIDTH  = Screen:scaleBySize(32 + 16 + 3)
Core.SB_MARGIN_RIGHT = 0
Core.SB_MARGIN_V_TOP    = Screen:scaleBySize(16)
Core.SB_MARGIN_V_BOTTOM = Core.SB_MARGIN_V_TOP -- same space below as above
-- The plugin's own colours (from the design), as fixed grey values rather than KOReader's
-- named greys, so every screen uses exactly the same shades.
Core.COLORS = {
    ink        = BlitBuffer.COLOR_BLACK,
    muted      = BlitBuffer.Color8(0x45), -- secondary text: tabs, info line, author, counts
    disabled   = BlitBuffer.Color8(0xAA), -- buttons that can't be used
    line       = BlitBuffer.Color8(0xBD), -- separators
    line_light = BlitBuffer.Color8(0xD6), -- row lines, line under book titles
    section_bg = BlitBuffer.Color8(0xE9), -- section bars in Filter & sort
    section_fg = BlitBuffer.Color8(0x33),
}
-- where a book starts: a short notch across the track, like chapter ticks on Kindle/Kobo
Core.SB_MARK_OVERHANG = Screen:scaleBySize(3)          -- how far it sticks out on each side
Core.SB_MARK_HEIGHT   = math.max(1, math.floor(Screen:scaleBySize(1)))
-- Header: top bar (menu, title, search, filter, close), tab row, optional active-filter row
Core.TOPBAR_HEIGHT    = Screen:scaleBySize(50)
Core.TOPBAR_BOOK_HEIGHT = Screen:scaleBySize(54) -- one-book view: title + author line, a bit taller to fit the larger second line
Core.TABS_HEIGHT      = Screen:scaleBySize(38)
Core.FOOTER_BAR_HEIGHT = Screen:scaleBySize(48) -- page buttons bar (non-scrollbar styles)
-- mockup: 22px icons in 44px buttons, 8px from the screen edges, 4px between menu and title
Core.HEADER_ICON_SIZE = Screen:scaleBySize(22)
Core.HEADER_ICON_PAD  = Screen:scaleBySize(11)
-- Serif used for book titles, highlights and the screen title unless the user picked a font
Core.SERIF_FONT = "NotoSerif-Regular.ttf"
-- Icons shipped with the plugin (drawn in the style of KOReader's own mdlight set)
local PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*/)[^/]*$") or "./"
function Core.pluginIcon(name) return PLUGIN_DIR .. "icons/" .. name .. ".svg" end
function Core.getFaceOr(font_name, size, fallback)
    return (font_name and font_name ~= "" and Font:getFace(font_name, size))
        or Font:getFace(fallback, size) or Font:getFace("cfont", size)
end

Core.SPIN_MENUS = {
    font_size = {
        dialog_name = "font_size_dialog",
        title = _("Font sizes"),
        settings = {
            { label = _("Title size: "), key = "title_font_size", 
                default = DEFAULT_TITLE_FONT_SIZE, min = 8, max = 48, step = 1, 
                getter = Core.getTitleFontSize },
            { label = _("Info size: "), key = "info_font_size", 
                default = DEFAULT_INFO_FONT_SIZE, min = 8, max = 48, step = 1, 
                getter = Core.getInfoFontSize },
            { label = _("Content size: "), key = "content_font_size", 
                default = DEFAULT_CONTENT_FONT_SIZE, min = 8, max = 48, step = 1, 
                getter = Core.getContentFontSize },
        }
    },
    section_margin = {
        dialog_name = "section_margin_dialog",
        title = _("Space between notes"),
        settings = {
            { label = _("Below the book title: "), key = "title_margin", 
                default = DEFAULT_TITLE_MARGIN, min = 0, max = 30, step = 1, 
                getter = function() return Core.getSetting("title_margin", DEFAULT_TITLE_MARGIN) end },
            { label = _("Below the chapter · date line: "), key = "info_margin", 
                default = DEFAULT_INFO_MARGIN, min = 0, max = 30, step = 1, 
                getter = function() return Core.getSetting("info_margin", DEFAULT_INFO_MARGIN) end },
        }
    },
    margins = {
        dialog_name = "margin_dialog",
        title = _("Page margins"),
        settings = {
            { label = _("Top padding: "), key = "top_padding", 
                default = DEFAULT_TOP_PADDING, min = 0, max = 100, step = 5, 
                getter = function() return Core.getSetting("top_padding", DEFAULT_TOP_PADDING) end },
            { label = _("Horizontal margin: "), key = "h_margin", 
                default = DEFAULT_H_MARGIN, min = 5, max = 60, step = 5, 
                getter = function() return Core.getSetting("h_margin", DEFAULT_H_MARGIN) end },
            { label = _("Landscape width (%): "), key = "landscape_width_pct", 
                default = 80, min = 40, max = 100, step = 5, getter = function() return Core.getSetting("landscape_width_pct", 80) end },
            { label = _("Between annotations: "), key = "note_spacing", 
                default = DEFAULT_NOTE_SPACING, min = 5, max = 100, step = 2, 
                getter = function() return Core.getSetting("note_spacing", DEFAULT_NOTE_SPACING) end },
            { label = _("Space above the note: "), key = "note_offset", 
                default = 8, min = 0, max = 40, step = 2, 
                getter = function() return Core.getSetting("note_offset", 8) end },
            { label = _("Extra indent for the note: "), key = "note_indent", 
                default = 0, min = 0, max = 60, step = 2, 
                getter = function() return Core.getSetting("note_indent", 0) end },
            { label = _("Line spacing: "), key = "line_spacing", 
                default = 0, min = -15, max = 20, step = 1, 
                getter = function() return Core.getSetting("line_spacing", 0) end },
            { label = _("Text indent: "), key = "text_margin", 
                default = DEFAULT_TEXT_MARGIN, min = 0, max = 30, step = 2, 
                getter = function() return Core.getSetting("text_margin", DEFAULT_TEXT_MARGIN) end },
        }
    }
}

local HIGHLIGHT_COLORS = BlitBuffer.HIGHLIGHT_COLORS

-- A highlight colour's code ("#rrggbb"). Newer KOReader (after 2026.07) lets you give each
-- colour its own name and code (Highlight color → hold a colour): its code is used then, the
-- built-in one otherwise. Never inverted for night mode: the list paints true colours itself.
function Core.COLORS.highlightCode(key)
    if type(key) ~= "string" then return nil end
    key = key:lower()
    if ReaderHighlight.getHighlightColorCode then
        local ok, code = pcall(ReaderHighlight.getHighlightColorCode, ReaderHighlight, key, nil, false)
        if ok and type(code) == "string" and code:match("^#%x%x%x%x%x%x$") then return code end
    end
    return HIGHLIGHT_COLORS[key]
end
function Core.getHighlightColor(color)
    local val = Core.COLORS.highlightCode(color)
    if val and BlitBuffer.colorFromString then
        return BlitBuffer.colorFromString(val)
    end
    return BlitBuffer.COLOR_GRAY
end
function Core.isNoBackgroundStyle(drawer)
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

Core.NoteWrapper = {}
function Core.NoteWrapper:new(note)
    return setmetatable({ _note = note }, { __index = self })
end
function Core.NoteWrapper:getDisplayAuthors()
    if not self._note.book_authors or self._note.book_authors == "" or self._note.book_authors == "Unknown" then
        return nil
    end
    return truncateAuthorDisplay(self._note.book_authors)
end
function Core.NoteWrapper:getTags()
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
function Core.NoteWrapper:getNormalizedColor()
    return self._note.color and self._note.color:lower() or nil
end
function Core.NoteWrapper:getNormalizedDrawer()
    return self._note.drawer and self._note.drawer:lower() or nil
end
function Core.NoteWrapper:hasHighlightedText()
    return self._note.highlighted_text and self._note.highlighted_text ~= "" or false
end
function Core.NoteWrapper:hasUserNote()
    return self._note.user_note and self._note.user_note ~= "" or false
end

-- Text measurement caches. Font:getFace() returns cached face objects, so a face's
-- table identity is a stable key; weak keys let unused faces be collected.
-- A highlight colour as painted, and its name: the name you gave it in KOReader when it has one.
function Core.colorName(key)
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
Core.HIGHLIGHT_STYLES = {
    { "lighten", _("Lighten") }, { "underscore", _("Underline") },
    { "strikeout", _("Strikeout") }, { "invert", _("Invert") },
}
Core.getNoteInfoKey = function(note, fields_setting)
    local parts = {}
    local fields = {}
    for f in fields_setting:gmatch("[^,]+") do fields[f] = true end
    local function add(v)
        v = v or ""
        -- length-prefix so a "|" inside a field can't make two different infos share a key
        parts[#parts + 1] = #v .. ":" .. v
    end
    if fields["date"] and item().infoShowsDate() then
        add(note.datetime and note.datetime:match("^(%d+-%d+-%d+)") or "")
    end
    if fields["author"] then add(note.book_authors) end
    if fields["chapter"] then add(note.chapter) end
    return table.concat(parts, "|")
end

return Core
