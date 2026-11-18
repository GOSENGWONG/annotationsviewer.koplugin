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
local atoms = require("anv_atoms")
local SortState = sort.SortState
local compareByPosition = sort.compareByPosition
local normalizeBookTitle = sort.normalizeBookTitle
local wrapText = text.wrapText
local getWordWidths = text.getWordWidths
local getLineHeight = text.getLineHeight
local getBoxHeight = text.getBoxHeight
local measureTextWidth = text.measureTextWidth
local createJustifiedLine = text.createJustifiedLine
local trimParagraph = text.trimParagraph
local NBSP = text.NBSP
local Pill = atoms.Pill
local StrikeoutLineWidget = atoms.StrikeoutLineWidget
local UnderlineWidget = atoms.UnderlineWidget
local TapBox = atoms.TapBox

local NoteItemWidget = InputContainer:extend{ width = nil, note = nil, show_parent = nil, is_last = false, is_preview = false, disable_tap = false, skip_title = false, skip_info = false }
-- Colour helpers are pure logic in anv_core; mounted here for the class.
NoteItemWidget.colorValue = core.getHighlightColor
NoteItemWidget.colorLabel = core.colorName
-- Search without capitals in every language, as KOReader's own search does (Utf8Proc folds
-- "Élan" to "élan", "ÜBER" to "über"); string.lower only knows A-Z. Kept per text.
NoteItemWidget._lower = {}
NoteItemWidget._lower_n = 0
function NoteItemWidget.lower(s)
    if type(s) ~= "string" or s == "" then return s or "" end
    local l = NoteItemWidget._lower[s]
    if l then return l end
    local ok, r = pcall(function() return require("ffi/utf8proc").lowercase(require("util").fixUtf8(s, "?")) end)
    l = (ok and type(r) == "string") and r or s:lower()
    NoteItemWidget._lower[s] = l
    NoteItemWidget._lower_n = NoteItemWidget._lower_n + 1
    return l
end
-- For marking matches in a drawn line: the text lowered character by character (one character
-- for one, as TextBoxWidget's own search does), with, for every byte of it, where that character
-- starts and ends in the text. Returns the text (made valid UTF-8), the lowered text and the map.
function NoteItemWidget.lowerMap(s)
    local ok_u, util = pcall(require, "util")
    if ok_u and util.fixUtf8 then s = util.fixUtf8(s, "?") end
    local ok, low = pcall(function() return require("ffi/utf8proc").lowercase(s, false) end)
    if not ok or type(low) ~= "string" then low = s:lower() end
    if not s:find("[\128-\255]") then return s, low, nil end -- plain ASCII: positions are the same
    local pat = "[%z\1-\127\192-\253][\128-\191]*"
    local orig, lowc = {}, {}
    for c in s:gmatch(pat) do orig[#orig + 1] = c end
    for c in low:gmatch(pat) do lowc[#lowc + 1] = c end
    if #orig ~= #lowc then return s, s:lower(), nil end
    local map, ob, lb = { start = {}, stop = {} }, 1, 1
    for i = 1, #orig do
        for k = 0, #lowc[i] - 1 do
            map.start[lb + k] = ob
            map.stop[lb + k] = ob + #orig[i] - 1
        end
        ob, lb = ob + #orig[i], lb + #lowc[i]
    end
    return s, low, map
end

-- Longest a note (the text you wrote) is shown in the list; longer ones end with "...".
NoteItemWidget.DEFAULT_NOTE_LINES = 5
-- font of the user notes: its own font / size, otherwise the same as the highlight text
function NoteItemWidget.noteFace()
    local font = getSetting("note_font", nil)
    if not font or font == "" then font = getContentFont() end
    local size = getSetting("note_font_size", nil) or getContentFontSize()
    return getFaceOr(font ~= "" and font or SERIF_FONT, size, "cfont")
end
-- space between the highlight and its note
function NoteItemWidget.noteOffset() return Screen:scaleBySize(getSetting("note_offset", 8)) end
-- how far the note is moved in from the left
function NoteItemWidget.noteIndent() return Screen:scaleBySize(getSetting("note_indent", 0)) end
-- A box that shows only the middle part of its child (used for negative line spacing, where the lines
-- sit closer than their natural height): w x h, the child is moved by dy and cut off at the box.
NoteItemWidget.LineBox = WidgetContainer:extend{ w = 0, h = 0, dy = 0 }
function NoteItemWidget.LineBox:getSize() return Geom:new{ w = self.w, h = self.h } end
function NoteItemWidget.LineBox:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local buf = BlitBuffer.new(self.w, self.h, bb:getType())
    buf:blitFrom(bb, 0, 0, x, y, self.w, self.h) -- start from what is already there (the page, a highlight)
    self[1]:paintTo(buf, 0, self.dy)
    bb:blitFrom(buf, x, y, 0, 0, self.w, self.h)
    buf:free()
end
-- extra space between the lines of a highlight and of a note (Spacing page)
function NoteItemWidget.lineSpacing() return Screen:scaleBySize(getSetting("line_spacing", 0)) end
function NoteItemWidget.noteLinesMax()
    local v = tonumber(getSetting("truncate_note_lines", NoteItemWidget.DEFAULT_NOTE_LINES))
    if not v or v < 1 then return NoteItemWidget.DEFAULT_NOTE_LINES end
    return v
end
-- A line shortened until it fits `width` with `ell` after it, by whole characters (never half
-- of one). Returns the line without the ell.
function NoteItemWidget.cutLine(line, ell, face, width)
    while #line > 0 and measureTextWidth(line .. ell, face) > width do
        local shorter = line:gsub("[^\128-\191][\128-\191]*$", "")
        if shorter == line then shorter = line:sub(1, -2) end -- broken UTF-8: a byte at a time
        line = shorter
    end
    return line
end
-- First `max` lines, the last one shortened to take the ell ("..." unless given).
function NoteItemWidget.cutLines(lines, max, face, width, ell)
    if #lines <= max then return lines, false end
    ell = ell or "..."
    local out = {}
    for i = 1, max do out[i] = lines[i] end
    out[max] = NoteItemWidget.cutLine(out[max], ell, face, width) .. ell
    return out, true
end
-- Night mode inverts the whole screen. Things that must keep their real colours (highlight
-- colours and the text on them) are drawn in true colour into a copy of what is behind them and
-- copied back inverted, so the screen's own inversion turns them right again -- the same idea
-- as an image widget's `original_in_nightmode = false`.
function NoteItemWidget.paintTrue(bb, x, y, w, h, draw)
    if not Screen.night_mode or w <= 0 or h <= 0 then return draw(bb, x, y) end
    local buf = BlitBuffer.new(w, h, bb:getType())
    buf:blitFrom(bb, 0, 0, x, y, w, h)
    buf:invert()
    draw(buf, 0, 0)
    bb:invertblitFrom(buf, x, y, 0, 0, w, h)
    buf:free()
end
NoteItemWidget.TruePaint = WidgetContainer:extend{}
function NoteItemWidget.TruePaint:getSize() return self[1]:getSize() end
function NoteItemWidget.TruePaint:paintTo(bb, x, y)
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    NoteItemWidget.paintTrue(bb, x, y, size.w, size.h, function(b, xx, yy) self[1]:paintTo(b, xx, yy) end)
end

-- Faces used by NoteItemWidget (shared by the real layout and the height measurement).
local function getNoteFaces()
    local title_font, info_font, content_font = getTitleFont(), getInfoFont(), getContentFont()
    local title_size, info_size, content_size = getTitleFontSize(), getInfoFontSize(), getContentFontSize()
    local title_face = getFaceOr(title_font ~= "" and title_font or SERIF_FONT, title_size, "cfont")
    local info_face = getFaceOr(info_font, info_size, "cfont")
    local content_face = getFaceOr(content_font ~= "" and content_font or SERIF_FONT, content_size, "cfont")
    return title_face, info_face, content_face
end

-- Font of the author name in the book header: its own font / size when set, otherwise exactly the
-- info face (what the author always used).
function NoteItemWidget.authorFace()
    local font, size = getSetting("author_font", nil), getSetting("author_font_size", nil)
    local _, info_face = getNoteFaces()
    if (not font or font == "") and not size then return info_face end
    if not font or font == "" then font = getInfoFont() end
    return getFaceOr(font, tonumber(size) or getInfoFontSize(), "cfont")
end

-- Capitals: KOReader's UTF-8 aware upper-casing when it has one (accents), else plain ASCII upper
function NoteItemWidget.upper(str)
    local ok, u = pcall(require, "ffi/utf8proc")
    if ok and type(u) == "table" and u.uppercase_dumb then
        local ok2, r = pcall(u.uppercase_dumb, str)
        if ok2 and type(r) == "string" then return r end
    end
    return str:upper()
end
-- Book title and chapter headings / the chapter · date line, in capitals when the setting says so
function NoteItemWidget.titleText(str)
    return getSetting("title_case", "normal") == "upper" and NoteItemWidget.upper(str) or str
end
function NoteItemWidget.infoText(str)
    return getSetting("info_case", "normal") == "upper" and NoteItemWidget.upper(str) or str
end

-- Text of the line above each highlight (chapter · date), or "" when the row is turned off.
-- The author is shown in the book header instead (see getHeaderAuthor).
local function buildInfoText(note, note_wrapper, skip_title, hide_chapter) -- luacheck: ignore 212
    if not getShowInfo() then return "" end
    local info_fields = {}
    for f in getInfoFields():gmatch("[^,]+") do info_fields[f] = true end
    local info_parts = {}
    if info_fields["chapter"] and not hide_chapter and note.chapter and note.chapter ~= "" then
        table.insert(info_parts, NoteItemWidget.chapterLabel(note.chapter))
    end
    -- the date: always, or (setting) only when the order goes by date
    local show_date = info_fields["date"] and NoteItemWidget.infoShowsDate()
    local date_text = show_date and NoteItemWidget:formatDate(note.datetime) or ""
    if date_text ~= "" then table.insert(info_parts, date_text) end
    return NoteItemWidget.infoText(table.concat(info_parts, " · "))
end

-- "1." or "12" on its own reads oddly; show it as "Chapter 1"
function NoteItemWidget.chapterLabel(chapter)
    local num = chapter:match("^%s*(%d+)[%.%s]*$")
    return num and (_("Chapter") .. " " .. num) or chapter
end
-- Search words in a drawn line get a thick black line underneath. `widget` is a TextWidget, or a
-- justified line (HorizontalGroup of word widgets and gaps); `text` is the line's text.
function NoteItemWidget.markLine(widget, text, query, case_sensitive, face)
    if not query or query == "" or not text or text == "" then return widget end
    local q = query
    if not case_sensitive then q = select(2, NoteItemWidget.lowerMap(query)) end
    local function words_in(str)
        local found = {}
        local hay, map = str, nil
        if not case_sensitive then str, hay, map = NoteItemWidget.lowerMap(str) end
        for word in q:gmatch("%S+") do
            local from = 1
            while true do
                local a, b = hay:find(word, from, true)
                if not a then break end
                from = b + 1
                if map then a, b = map.start[a], map.stop[b] end -- back to the text's own bytes
                local pre = TextWidget:new{ text = str:sub(1, a - 1), face = face }
                local mid = TextWidget:new{ text = str:sub(a, b), face = face }
                table.insert(found, { x = pre:getSize().w, w = mid:getSize().w })
                pre:free(); mid:free()
            end
        end
        return found
    end
    local marks = {}
    if widget.text ~= nil then -- single TextWidget
        marks = words_in(text)
    else -- justified: word widgets with their own gaps
        local x = 0
        for _i, ch in ipairs(widget) do
            local cw = ch:getSize().w
            if ch.text ~= nil then
                for _j, m in ipairs(words_in(ch.text)) do table.insert(marks, { x = x + m.x, w = m.w }) end
            end
            x = x + cw
        end
    end
    if #marks == 0 then return widget end
    local size = widget:getSize()
    local thick = math.max(2, Screen:scaleBySize(2))
    local og = OverlapGroup:new{ dimen = Geom:new{ w = size.w, h = size.h }, widget }
    for _i, mk in ipairs(marks) do
        if mk.x < size.w then
            local mark = LineWidget:new{ dimen = Geom:new{ w = math.max(1, math.min(mk.w, size.w - mk.x)), h = thick }, background = BlitBuffer.COLOR_BLACK }
            mark.overlap_offset = { mk.x, size.h - thick }
            table.insert(og, mark)
        end
    end
    return og
end
-- Author shown on the right of the book header, in capitals (or as written, by setting); nil when off.
local function getHeaderAuthor(note_wrapper)
    if not getShowInfo() then return nil end
    if not getInfoFields():find("author", 1, true) then return nil end
    local a = note_wrapper:getDisplayAuthors()
    if not a or a == "" or a == "Unknown" then return nil end
    return getSetting("author_case", "upper") == "normal" and a or NoteItemWidget.upper(a)
end
local HEADER_AUTHOR_GAP = Screen:scaleBySize(12)
local HEADER_LINE_GAP = Screen:scaleBySize(3)
-- Size of the book header: title on the left, author on the right, thin line below.
-- Returns title width, author max width and total height. Shared by measuring and drawing.
local function getHeaderLayout(title_text, author_text, title_face, info_face, content_width)
    local author_w = 0
    if author_text then
        author_w = math.min(measureTextWidth(author_text, info_face), math.floor(content_width * 0.4))
    end
    local title_w = content_width - (author_text and (author_w + HEADER_AUTHOR_GAP) or 0)
    local title_h = getBoxHeight(title_text, title_face, title_w, true)
    return title_w, author_w, title_h + HEADER_LINE_GAP + Size.line.thin
end

local NOTE_ICON_CHAR = "\238\171\170" -- U+EAEA, pencil (Material Design, in KOReader's symbol font)

-- Height NoteItemWidget:init() would produce for these params, computed without building
-- any widgets. Must mirror the layout in NoteItemWidget:init().
-- Width of the annotation column: portrait uses all the room the scrollbar leaves (the side
-- margin does the rest); landscape uses the "Landscape width" share of the screen, centred.
function NoteItemWidget.columnWidth(avail, W, H)
    if W <= H then return avail end
    local pct = tonumber(getSetting("landscape_width_pct", 80)) or 80
    return math.min(avail, math.floor(W * math.max(pct, 30) / 100))
end
-- Width the annotations may use: with a scrollbar they reach to the middle of its track (the side margin
-- does the rest). A small side margin would put the text behind the scrollbar strip, so then the
-- column is made narrower to keep a little air between the text and the strip.
-- How far both sides are pushed in so that text stays clear of the scrollbar (thumb, marks, page number):
-- 0 when the side margin is already wide enough. The same on the left and the right, so the text stays centred.
-- no_sb: the list fits on one page, so no scrollbar is drawn and the full width is used.
function NoteItemWidget.scrollInset(no_sb)
    if no_sb or not isScrollbarStyle() then return 0 end
    return math.max(0, Screen:scaleBySize(22) - getHMargin())
end
function NoteItemWidget.listAvail(W, no_sb)
    if no_sb or not isScrollbarStyle() then return W end
    local center = W - SB_STRIP_WIDTH - SB_MARGIN_RIGHT + math.floor(SB_STRIP_WIDTH / 2)
    return center - 2 * NoteItemWidget.scrollInset()
end
function NoteItemWidget.showHeadings() return getSetting("chapter_headings", true) ~= false end
function NoteItemWidget.repeatChapter() return getSetting("repeat_chapter_on_page", true) ~= false end
-- Chapter heading of the one-book list: drawn exactly like a book header (same font, line, margin).
function NoteItemWidget.headingHeight(chapter, width)
    local content_width = width - getHMargin() * 2 - Size.padding.default * 2
    local title_face, info_face = getNoteFaces()
    local _tw, _aw, header_h = getHeaderLayout(NoteItemWidget.titleText(NoteItemWidget.chapterLabel(chapter)), nil, title_face, info_face, content_width)
    return header_h + getTitleMargin()
end
function NoteItemWidget.chapterHeading(chapter, width)
    local h_margin = getHMargin()
    local h_padding = Size.padding.default
    local inner_width = width - h_margin * 2
    local content_width = inner_width - h_padding * 2
    local title_face, info_face = getNoteFaces()
    local text = NoteItemWidget.titleText(NoteItemWidget.chapterLabel(chapter))
    local title_w, _aw, header_h = getHeaderLayout(text, nil, title_face, info_face, content_width)
    local widget = VerticalGroup:new{ align = "left",
        TextBoxWidget:new{ text = text, face = title_face, width = title_w, alignment = "left", bold = true },
        VerticalSpan:new{ width = HEADER_LINE_GAP },
        LineWidget:new{ dimen = Geom:new{ w = content_width, h = Size.line.thin }, background = COLORS.line_light } }
    widget = CenterContainer:new{ dimen = Geom:new{ w = content_width, h = header_h }, widget }
    return HorizontalGroup:new{ HorizontalSpan:new{ width = h_margin + h_padding },
        VerticalGroup:new{ widget, VerticalSpan:new{ width = getTitleMargin() } } }
end
-- A bookmark's line in the list, drawn like the info row above a highlight (same font and size):
-- ribbon and chapter on the left, "Page 34 · 8 Jan" on the right. Under a chapter heading (one
-- book) the chapter is left out and the page moves to the left. The date only shows when the
-- order goes by date. Bookmarks keep no text from the page, so this line and the note are all.
NoteItemWidget.BOOKMARK_CHAR = "\239\130\151" -- U+F097, KOReader's own bookmark mark (same font as the note icon)
function NoteItemWidget.pageText(note)
    local label = note.page_label
    if label == nil and type(note.page) == "number" and note.page > 0 then label = note.page end
    if label == nil or label == "" then return nil end
    return _("Page") .. " " .. tostring(label)
end
-- Bookmark settings: only what differs from an annotation. A bookmark is one short line (plus its
-- note), so it has its own space between bookmarks, its own size for that line (the info row's
-- size until changed) and its own choice of when the date shows. Fonts, capitals, margins and the
-- note's font and lines are the annotations' own.
NoteItemWidget.DEFAULT_BM_SPACING = 18
function NoteItemWidget.bmSpacing() return Screen:scaleBySize(getSetting("bm_spacing", NoteItemWidget.DEFAULT_BM_SPACING)) end
function NoteItemWidget.bookmarkFace()
    local font, size = getSetting("bm_font", nil), tonumber(getSetting("bm_line_size", nil))
    if (not font or font == "") and not size then return (select(2, getNoteFaces())) end
    if not font or font == "" then font = getInfoFont() end
    return getFaceOr(font, size or getInfoFontSize(), "cfont")
end
-- the ribbon and the space after it: the bookmark's chapter text and its note start this far in.
-- The column is as wide as the ribbon or the note icon, whichever is wider, so the note does not
-- move when its icon is turned on or off.
function NoteItemWidget.bookmarkIndent()
    return NoteItemWidget.bookmarkColumn() + Screen:scaleBySize(8)
end
function NoteItemWidget.bookmarkColumn()
    -- asked for every bookmark on a page: measured once per pair of faces
    local bf, nf = NoteItemWidget.bookmarkFace(), NoteItemWidget.noteFace()
    local c = NoteItemWidget._bm_col
    if not (c and c.bf == bf and c.nf == nf) then
        c = { bf = bf, nf = nf, w = math.max(measureTextWidth(NoteItemWidget.BOOKMARK_CHAR, bf), measureTextWidth(NOTE_ICON_CHAR, nf)) }
        NoteItemWidget._bm_col = c
    end
    return c.w
end
-- A bookmark's note: without the note icon (default) it lines up with the chapter text; with it,
-- the icon sits under the ribbon as on an annotation.
function NoteItemWidget.bmNoteIcon() return getSetting("bm_note_icon", false) == true end
-- "sort" (only when the order goes by date), "always" or "never"
function NoteItemWidget.bmDate() return getSetting("bm_date", "sort") end
-- Space above an item in the list: between bookmarks their own (smaller) space, else the space
-- between annotations; a new book header adds the book gap.
function NoteItemWidget.gapAbove(note, skip_title)
    return (note and note.bookmark and NoteItemWidget.bmSpacing() or getNoteSpacing()) + (skip_title and 0 or BOOK_GAP)
end
-- Whether the info row above a highlight shows the date: the Date field is on and, with the
-- "when sorted by date" setting, the order goes by date.
function NoteItemWidget.infoShowsDate()
    local single = NoteItemWidget.list_single
    local key = getInfoFields() .. "|" .. getSetting("info_date_when", "always") .. "|" .. SortState.get(single) .. tostring(single)
    if NoteItemWidget._isd_key ~= key then -- asked once per annotation when paging: worked out once
        local on = false
        for f in getInfoFields():gmatch("[^,]+") do if f == "date" then on = true end end
        NoteItemWidget._isd_key = key
        NoteItemWidget._isd = on and (getSetting("info_date_when", "always") ~= "sort" or NoteItemWidget.sortUsesDate(single))
    end
    return NoteItemWidget._isd
end
-- What makes two info rows "the same" for "Hide duplicate info header". A date that is not shown
-- does not count, or rows that look the same would both be drawn.
-- Whether the open order uses the date (then a bookmark shows its date).
function NoteItemWidget.sortUsesDate(single)
    for _, l in ipairs(SortState.view(SortState.get(single), single)) do
        if l.key == "date" then return true end
    end
    return false
end
function NoteItemWidget.bookmarkRow(note, content_width, hide_chapter, single)
    local info_face = NoteItemWidget.bookmarkFace()
    local chapter = (not hide_chapter and note.chapter and note.chapter ~= "") and NoteItemWidget.chapterLabel(note.chapter) or nil
    local page = NoteItemWidget.pageText(note)
    local when = NoteItemWidget.bmDate()
    local date = (when == "always" or (when == "sort" and NoteItemWidget.sortUsesDate(single)))
        and NoteItemWidget:formatDate(note.datetime) or nil
    local left_text, right_parts = chapter, {}
    if left_text then
        if page then table.insert(right_parts, page) end
    else
        left_text = page or _("Bookmark")
    end
    if date then table.insert(right_parts, date) end
    local right_text = NoteItemWidget.infoText(table.concat(right_parts, " · "))
    local gap = Screen:scaleBySize(12)
    local right = right_text ~= "" and TextWidget:new{ text = right_text, face = info_face, fgcolor = COLORS.muted,
        max_width = math.floor(content_width * 0.6) } or nil
    local right_w = right and right:getSize().w or 0
    local icon = TextWidget:new{ text = NoteItemWidget.BOOKMARK_CHAR, face = info_face }
    local col = NoteItemWidget.bookmarkColumn()
    local icon_gap = NoteItemWidget.bookmarkIndent() - col
    local label = TextWidget:new{ text = NoteItemWidget.infoText(left_text), face = info_face,
        max_width = math.max(Screen:scaleBySize(24), content_width - col - icon_gap - right_w - gap) }
    local h = math.max(label:getSize().h, icon:getSize().h)
    -- the mark is centred on the height of the text next to it
    local left = HorizontalGroup:new{ align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = col, h = h }, icon },
        HorizontalSpan:new{ width = icon_gap }, label }
    local d = Geom:new{ w = content_width, h = h }
    return OverlapGroup:new{ dimen = d, allow_mirroring = false,
        LeftContainer:new{ dimen = d, left }, right and RightContainer:new{ dimen = d, right } or nil }
end
local function measureNoteHeight(note, width, skip_title, skip_info)
    local h_margin = getHMargin()
    local text_margin = getTextMargin()
    local inner_width = width - h_margin * 2
    local content_width = inner_width - Size.padding.default * 2
    local line_width = content_width - text_margin * 2 - Size.padding.small * 2
    local title_face, info_face, content_face = getNoteFaces()
    local note_wrapper = NoteWrapper:new(note)

    local h = 0
    if not skip_title then
        local _tw, _aw, header_h = getHeaderLayout(NoteItemWidget.titleText(note.book_title or _("Unknown book")),
            getHeaderAuthor(note_wrapper), title_face, NoteItemWidget.authorFace(), content_width)
        h = h + header_h + getTitleMargin()
    end
    if note.bookmark then
        -- the bookmark line takes the place of the info row (and there is no highlight). It is one
        -- line of text and a mark in the same face, so it is as high as a line in that face
        -- (a TextWidget's height comes from its face, not its text).
        h = h + getLineHeight(NoteItemWidget.bookmarkFace())
    else
        local info_text = buildInfoText(note, note_wrapper, skip_title, NoteItemWidget.measure_hide_chapter)
        local info_visible = not skip_info and info_text ~= ""
        if info_visible then
            h = h + getBoxHeight(info_text, info_face, content_width, false)
        end
        if (not skip_title) or info_visible then
            h = h + getInfoMargin()
        end
    end
    local line_h = getLineHeight(content_face)
    if note_wrapper:hasHighlightedText() then
        local n = #wrapText(note.highlighted_text or "", content_face, line_width)
        local max_lines = getTruncateLines() or math.huge
        if n > max_lines then n = max_lines end
        h = h + n * (line_h + 2 + NoteItemWidget.lineSpacing()) -- each line has 1px padding above and below, plus the line spacing
    end
    if note_wrapper:hasUserNote() then
        -- a bookmark's note sits where a highlight's text would: the info margin below its line
        h = h + (note.bookmark and getInfoMargin() or NoteItemWidget.noteOffset())
        local note_face = NoteItemWidget.noteFace()
        local note_line_h = getLineHeight(note_face)
        local widths = getWordWidths(note_face)
        local icon_w = widths[NOTE_ICON_CHAR]
        if not icon_w then
            icon_w = measureTextWidth(NOTE_ICON_CHAR, note_face)
            widths[NOTE_ICON_CHAR] = icon_w
        end
        local wrap_w = line_width - icon_w - Screen:scaleBySize(6) - NoteItemWidget.noteIndent()
        if note.bookmark then wrap_w = content_width - NoteItemWidget.bookmarkIndent() end
        local n = math.min(#wrapText(note.user_note, note_face, wrap_w), NoteItemWidget.noteLinesMax())
        local ls = NoteItemWidget.lineSpacing()
        if ls < 0 then h = h + math.max(note_line_h + ls, n * (note_line_h + ls))
        else h = h + math.max(note_line_h, n * note_line_h + (n - 1) * ls) end
    end
    return h
end

-- Measured heights, kept across refreshes. Invalidated per note when its text changes and
-- for all notes when anything that affects layout changes (see getLayoutSignature).
local _note_height_cache = setmetatable({}, { __mode = "k" })

local function getLayoutSignature(width)
    return table.concat({
        width, getHMargin(), getTextMargin(), NoteItemWidget.lineSpacing(), getTitleMargin(), getInfoMargin(),
        getTitleFontSize(), getInfoFontSize(), getContentFontSize(),
        tostring(getTitleFont()), tostring(getInfoFont()), tostring(getContentFont()),
        tostring(getSetting("note_font", nil)), tostring(getSetting("note_font_size", nil)),
        tostring(getSetting("author_font", nil)), tostring(getSetting("author_font_size", nil)), getSetting("author_case", "upper"), getSetting("title_case", "normal"), getSetting("info_case", "normal"), NoteItemWidget.noteOffset(), NoteItemWidget.noteIndent(),
        tostring(getTruncateLines()), tostring(NoteItemWidget.noteLinesMax()), tostring(getShowInfo()), getInfoFields(), tostring(NoteItemWidget.measure_hide_chapter),
        os.date("%Y%m%d"), -- "Today"/"Yesterday" labels change the info row text
        getSetting("date_year_list", "relevant"), getSetting("date_time_list", "never"), getSetting("date_month", "short"), tostring(NoteItemWidget.twelveHour()),
        getSetting("info_date_when", "always"), SortState.get(NoteItemWidget.list_single), tostring(getSetting("bm_line_size", nil)), tostring(getSetting("bm_font", nil)), tostring(NoteItemWidget.bmNoteIcon()),
    }, "|")
end

local function getNoteHeight(note, width, skip_title, skip_info, signature)
    local entry = _note_height_cache[note]
    if not entry or entry.sig ~= signature
            or entry.hl ~= note.highlighted_text or entry.un ~= note.user_note then
        entry = { sig = signature, hl = note.highlighted_text, un = note.user_note }
        _note_height_cache[note] = entry
    end
    local key = (skip_title and 2 or 0) + (skip_info and 1 or 0)
    local h = entry[key]
    if not h then
        h = measureNoteHeight(note, width, skip_title, skip_info)
        entry[key] = h
    end
    return h
end

function NoteItemWidget:init()
    local h_margin = getHMargin()
    local text_margin = getTextMargin()
    local title_margin = getTitleMargin()
    local info_margin = getInfoMargin()
    local inner_width = self.width - h_margin * 2
    self.dimen = Geom:new{ w = self.width, h = 0 }

    local h_padding = Size.padding.default
    local content_width = inner_width - h_padding * 2
    local justify = getJustify()

    local note_wrapper = NoteWrapper:new(self.note)
    local title_text = NoteItemWidget.titleText(self.note.book_title or _("Unknown book"))

    local title_face, info_face, content_face = getNoteFaces()
    local header_widget
    if not self.skip_title then
        -- Book header: title left, author right (in capitals), thin line underneath
        local author_text = getHeaderAuthor(note_wrapper)
        local author_face = NoteItemWidget.authorFace()
        local title_w, author_w, header_h = getHeaderLayout(title_text, author_text, title_face, author_face, content_width)
        local title_widget = TextBoxWidget:new{
            text = title_text, face = title_face,
            width = title_w, alignment = "left", bold = true,
        }
        local row = HorizontalGroup:new{ align = "top", title_widget }
        if author_text then
            local author_widget = TextWidget:new{
                text = author_text, face = author_face, max_width = author_w,
                fgcolor = COLORS.muted,
            }
            -- line the author up with the middle of the title's first line
            local first_line_h = getLineHeight(title_face)
            local pad = math.max(0, math.floor((first_line_h - author_widget:getSize().h) / 2))
            table.insert(row, HorizontalSpan:new{ width = HEADER_AUTHOR_GAP + (author_w - author_widget:getSize().w) })
            table.insert(row, VerticalGroup:new{ VerticalSpan:new{ width = pad }, author_widget })
        end
        header_widget = VerticalGroup:new{
            align = "left",
            row,
            VerticalSpan:new{ width = HEADER_LINE_GAP },
            LineWidget:new{
                dimen = Geom:new{ w = content_width, h = Size.line.thin },
                background = COLORS.line_light,
            },
        }
        -- keep the measured and drawn heights identical
        header_widget = CenterContainer:new{ dimen = Geom:new{ w = content_width, h = header_h }, header_widget }
    end

    local drawer = self.note.drawer or "lighten"
    local show_info_header = getShowInfo()
    local info_text = buildInfoText(self.note, note_wrapper, self.skip_title, self.show_parent and self.show_parent.single_book and NoteItemWidget.showHeadings())

    -- Same colour and same kind of text widget as the tabs (a single-line TextWidget) when it
    -- fits on one line, so it renders exactly like them; the box keeps the measured height.
    local date_widget
    local info_box_h = getBoxHeight(info_text, info_face, content_width, false)
    if info_text ~= "" and measureTextWidth(info_text, info_face) <= content_width then
        date_widget = LeftContainer:new{
            dimen = Geom:new{ w = content_width, h = info_box_h },
            TextWidget:new{ text = info_text, face = info_face, fgcolor = COLORS.muted },
        }
    else
        date_widget = TextBoxWidget:new{
            text = info_text, face = info_face,
            width = content_width, alignment = "left",
            fgcolor = COLORS.muted,
        }
    end

    local text_fgcolor = BlitBuffer.COLOR_BLACK
    local show_strikeout = drawer == "strikeout"
    local show_underline = drawer == "underscore"
    local no_background = isNoBackgroundStyle(drawer)

    local bg_color = BlitBuffer.COLOR_WHITE
    if drawer == "invert" then
        text_fgcolor = BlitBuffer.COLOR_WHITE
        bg_color = BlitBuffer.COLOR_BLACK
    elseif not no_background then
        bg_color = getHighlightColor(self.note.color)
    end

    local text_content_width = content_width - text_margin * 2
    local line_width = text_content_width - Size.padding.small * 2
    -- underline the search words (not in the faded preview of the next annotation)
    local search_af = self.show_parent and self.show_parent.active_filter
    local function markw(widget, text, face)
        if self.is_preview or not search_af or not search_af.search_any then return widget end
        return NoteItemWidget.markLine(widget, text, search_af.search_any, search_af.search_any_case == true, face or content_face)
    end

    local note_content = VerticalGroup:new{ align = "left" }
    if header_widget then
        table.insert(note_content, LeftContainer:new{
            dimen = Geom:new{ w = inner_width, h = header_widget:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = h_padding }, header_widget },
        })
        table.insert(note_content, VerticalSpan:new{ width = title_margin })
    end
    local is_bookmark = self.note.bookmark == true
    if is_bookmark then
        local single = self.show_parent and self.show_parent.single_book
        local row = NoteItemWidget.bookmarkRow(self.note, content_width, single and NoteItemWidget.showHeadings(), single)
        table.insert(note_content, LeftContainer:new{
            dimen = Geom:new{ w = inner_width, h = row:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = h_padding }, row },
        })
    end
    local info_visible = not is_bookmark and show_info_header and not self.skip_info and info_text ~= ""
    if info_visible then
        table.insert(note_content, LeftContainer:new{
            dimen = Geom:new{ w = inner_width, h = date_widget:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = h_padding }, date_widget },
        })
    end
    -- only add the post-header margin when at least one header row is actually shown
    local any_header_visible = not is_bookmark and ((not self.skip_title) or info_visible)
    if any_header_visible then
        table.insert(note_content, VerticalSpan:new{ width = info_margin })
    end
    
    if note_wrapper:hasHighlightedText() then
        
        local full_lines, para_end = wrapText(self.note.highlighted_text or "", content_face, line_width)
        local max_lines = getTruncateLines() or math.huge
        local truncated = false
        local lines = full_lines
        local last_line_no_ell
        local ell = "..."
        if #full_lines > max_lines then
            truncated = true
            lines = {}
            for i = 1, max_lines do lines[i] = full_lines[i] end
            
            last_line_no_ell = NoteItemWidget.cutLine(lines[#lines] or "", ell, content_face, line_width)
        end

        local lines_group = VerticalGroup:new{ align = "left" }
        for i, line in ipairs(lines) do
            local line_widget
            local is_last = (i == #lines)
            if is_last and truncated then
                
                if justify == true then
                    
                    local ell_meas = TextWidget:new{ text = ell, face = content_face }
                    local ell_w = ell_meas:getSize().w
                    ell_meas:free()
                    if last_line_no_ell and #last_line_no_ell > 0 then
                        local justified_part = markw(createJustifiedLine(last_line_no_ell, content_face, math.max(0, line_width - ell_w), text_fgcolor), last_line_no_ell)
                        local ell_widget = TextWidget:new{ text = ell, face = content_face, fgcolor = text_fgcolor }
                        line_widget = HorizontalGroup:new{ justified_part, ell_widget }
                    else
                        line_widget = TextWidget:new{ text = ell, face = content_face, fgcolor = text_fgcolor }
                    end
                else
                    line_widget = markw(TextWidget:new{ text = (last_line_no_ell or line) .. ell, face = content_face, fgcolor = text_fgcolor }, (last_line_no_ell or line) .. ell)
                end
            else
                if justify == true and i < #lines and #lines > 1 and not para_end[i] then
                    line_widget = markw(createJustifiedLine(line, content_face, line_width, text_fgcolor), line)
                else
                    line_widget = markw(TextWidget:new{ text = line, face = content_face, fgcolor = text_fgcolor }, line)
                end
            end
            local line_size = line_widget:getSize()
            -- line spacing goes into the padding above and below the line, so a coloured highlight
            -- stays one solid block
            local ls = NoteItemWidget.lineSpacing()
            local lsp = math.max(0, ls) -- a negative spacing is done by trimming the line below
            local v_pad_top = 1 + math.floor(lsp / 2)
            local v_pad_bot = 1 + math.ceil(lsp / 2)
            local h_pad = Size.padding.small
            local line_container

            if show_strikeout or show_underline then
                local OverlapGroup = require("ui/widget/overlapgroup")
                local total_h = line_size.h + v_pad_top + v_pad_bot
                local total_w = line_size.w + h_pad * 2
                local overlap_items = {
                    CenterContainer:new{
                        dimen = Geom:new{ w = total_w, h = total_h },
                        line_widget,
                    },
                }
                if show_strikeout then
                    table.insert(overlap_items, StrikeoutLineWidget:new{ width = total_w, height = total_h, y_offset = math.floor(total_h / 2) })
                end
                if show_underline then
                    table.insert(overlap_items, UnderlineWidget:new{ width = total_w, height = total_h })
                end
                line_container = OverlapGroup:new{ dimen = Geom:new{ w = total_w, h = total_h }, unpack(overlap_items) }
            else
                line_container = FrameContainer:new{
                    padding = 1, padding_left = h_pad, padding_right = h_pad,
                    padding_top = v_pad_top, padding_bottom = v_pad_bot,
                    margin = 0, bordersize = 0, background = bg_color,
                    line_widget,
                }
            end
            if ls < 0 then
                local lc = line_container:getSize()
                line_container = NoteItemWidget.LineBox:new{ w = lc.w, h = math.max(2, lc.h + ls), dy = math.floor(ls / 2), line_container }
            end
            table.insert(lines_group, line_container)
        end

        local lines_widget = lines_group
        if drawer ~= "invert" and not no_background then -- coloured highlight: keeps its colour at night
            lines_widget = NoteItemWidget.TruePaint:new{ lines_group }
        end
        table.insert(note_content, LeftContainer:new{
            dimen = Geom:new{ w = inner_width, h = lines_group:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = h_padding + text_margin }, lines_widget },
        })
    end

    if note_wrapper:hasUserNote() then
        table.insert(note_content, VerticalSpan:new{ width = is_bookmark and info_margin or NoteItemWidget.noteOffset() })

        local note_face = NoteItemWidget.noteFace()
        local note_icon_char = NOTE_ICON_CHAR
        local icon_margin = Screen:scaleBySize(6)
        local note_icon = TextWidget:new{
            text = note_icon_char,
            face = note_face,
            fgcolor = BlitBuffer.COLOR_BLACK,
        }
        local icon_size = note_icon:getSize().w

        local note_text_width = line_width - icon_size - icon_margin - NoteItemWidget.noteIndent()
        -- a bookmark's note has no icon (unless the setting adds it): the ribbon above marks it, and the note lines up with
        -- the chapter text next to the ribbon
        local note_x = h_padding + text_margin + NoteItemWidget.noteIndent()
        local bm_pencil = is_bookmark and NoteItemWidget.bmNoteIcon()
        if is_bookmark then
            -- with or without its icon, the note starts where the chapter text does
            note_x = h_padding + (bm_pencil and 0 or NoteItemWidget.bookmarkIndent())
            note_text_width = content_width - NoteItemWidget.bookmarkIndent()
        end
        local note_lines = NoteItemWidget.cutLines(wrapText(self.note.user_note, note_face, note_text_width),
            NoteItemWidget.noteLinesMax(), note_face, note_text_width)
        local note_text_group = VerticalGroup:new{ align = "left" }
        for li, line in ipairs(note_lines) do
            local ls = NoteItemWidget.lineSpacing()
            if li > 1 and ls > 0 then table.insert(note_text_group, VerticalSpan:new{ width = ls }) end
            local line_widget = markw(TextWidget:new{
                text = line, face = note_face, fgcolor = BlitBuffer.COLOR_BLACK,
            }, line, note_face)
            if ls < 0 then
                local lsz = line_widget:getSize()
                line_widget = NoteItemWidget.LineBox:new{ w = lsz.w, h = math.max(2, lsz.h + ls), dy = math.floor(ls / 2), line_widget }
            end
            table.insert(note_text_group, line_widget)
        end

                
        local col = is_bookmark and NoteItemWidget.bookmarkColumn()
        local note_row = (is_bookmark and not bm_pencil) and note_text_group or bm_pencil and HorizontalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = col, h = note_icon:getSize().h }, note_icon },
            HorizontalSpan:new{ width = NoteItemWidget.bookmarkIndent() - col },
            note_text_group,
        } or HorizontalGroup:new{
            note_icon,
            HorizontalSpan:new{ width = icon_margin },
            note_text_group,
        }
        table.insert(note_content, LeftContainer:new{
            dimen = Geom:new{ w = inner_width, h = note_row:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = note_x }, note_row },
        })
    end

    

    self.dimen.h = note_content:getSize().h
    self[1] = HorizontalGroup:new{
        HorizontalSpan:new{ width = h_margin }, note_content, HorizontalSpan:new{ width = h_margin },
    }

end
-- How a date is written, set apart for the list and for the annotation sheet:
--   year: "relevant" (Today, Yesterday, 3 Feb, and 3 Feb 2025 for another year) or "always" (3 Feb 2026)
--   time: "never", "recent" (only for today and yesterday: Today, 14:05) or "always" (3 Feb, 14:05)
NoteItemWidget.DATE_DEFAULTS = { list = { year = "relevant", time = "never" }, sheet = { year = "always", time = "always" } }
function NoteItemWidget.dateStyle(where)
    local d = NoteItemWidget.DATE_DEFAULTS[where] or NoteItemWidget.DATE_DEFAULTS.list
    where = NoteItemWidget.DATE_DEFAULTS[where] and where or "list"
    return { year = getSetting("date_year_" .. where, d.year), time = getSetting("date_time_" .. where, d.time) }
end
function NoteItemWidget:formatDate(datetime, style)
    if not datetime or datetime == "" then return nil end
    local year, month, day = datetime:match("(%d+)-(%d+)-(%d+)")
    if not year then return datetime end
    style = style or NoteItemWidget.dateStyle("list")
    local hm = datetime:match("[ T](%d%d?:%d%d)")
    local note_time = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day)})
    local out = NoteItemWidget.shortDate(note_time, style.year == "always")
    local recent = NoteItemWidget._today_start and note_time >= NoteItemWidget._today_start - 86400
    if hm and (style.time == "always" or (style.time == "recent" and recent)) then out = out .. ", " .. NoteItemWidget.clockText(hm) end
    return out
end
-- Month and clock, the same in the list and on the sheet. The month is short ("3 Feb") or long
-- ("3 February"), in KOReader's translation. The clock always follows KOReader's 12-hour clock setting
-- (Settings → Time and date).
function NoteItemWidget.monthName(t, long)
    if long == nil then long = getSetting("date_month", "short") == "long" end
    local en = os.date(long and "%B" or "%b", t)
    local ok, dt = pcall(require, "datetime")
    local tr = ok and type(dt) == "table" and dt[long and "longMonthTranslation" or "shortMonthTranslation"]
    local name = type(tr) == "table" and tr[en]
    return type(name) == "string" and name or en
end
function NoteItemWidget.twelveHour()
    local ko = rawget(_G, "G_reader_settings") -- KOReader's own settings (this file shadows the name)
    return ko and type(ko.isTrue) == "function" and ko:isTrue("twelve_hour_clock") or false
end
-- twelve: force the 12-hour clock (nil: KOReader's setting). The time comes from KOReader, in its
-- language ("14:05", "2:05 PM" or their translation); the plain one below is only used without KOReader.
function NoteItemWidget.clockText(hm, twelve)
    if twelve == nil then twelve = NoteItemWidget.twelveHour() end
    local h, m = hm:match("(%d+):(%d+)")
    if not h then return hm end
    h = tonumber(h)
    -- both clocks as KOReader writes them, in its language (some write 14.05)
    local ok, dt = pcall(require, "datetime")
    if ok and type(dt) == "table" and type(dt.secondsToHour) == "function" then
        local r = dt.secondsToHour(os.time({ year = 2000, month = 1, day = 1, hour = h, min = tonumber(m) }), twelve and true or false)
        if type(r) == "string" then return r end
    end
    if not twelve then return hm end
    local suffix = h < 12 and "AM" or "PM"
    h = h % 12
    if h == 0 then h = 12 end
    return string.format("%d:%s %s", h, m, suffix)
end
-- full: always "3 Feb 2026" (no Today / Yesterday, always the year)
function NoteItemWidget.shortDate(note_time, full)
    local today = os.date("*t")
    local today_key = today.year * 10000 + today.month * 100 + today.day
    if NoteItemWidget._today_key ~= today_key then
        NoteItemWidget._today_key = today_key
        NoteItemWidget._today_start = os.time({ year = today.year, month = today.month, day = today.day })
        -- from the calendar, not ± 24 h: a day with a clock change is 23 or 25 hours long
        NoteItemWidget._tomorrow_start = os.time({ year = today.year, month = today.month, day = today.day + 1 })
        NoteItemWidget._yesterday_start = os.time({ year = today.year, month = today.month, day = today.day - 1 })
    end
    local today_start = NoteItemWidget._today_start
    if full then
        local d = os.date("*t", note_time)
        return tostring(d.day) .. " " .. NoteItemWidget.monthName(note_time) .. " " .. d.year
    end
    -- after today (a device clock that was wrong when it was made): the date, not "Today"
    if note_time >= today_start and note_time < NoteItemWidget._tomorrow_start then return _("Today")
    elseif note_time >= NoteItemWidget._yesterday_start and note_time < today_start then return _("Yesterday")
    else
        -- "3 Feb" this year, "3 Feb 2025" for older ones
        local d = os.date("*t", note_time)
        local day_month = tostring(d.day) .. " " .. NoteItemWidget.monthName(note_time)
        if d.year == today.year then return day_month end
        return day_month .. " " .. d.year
    end
end

-- Module exports
M.NoteItemWidget = NoteItemWidget
M.getNoteFaces = getNoteFaces
M.buildInfoText = buildInfoText
M.getHeaderAuthor = getHeaderAuthor
M.HEADER_AUTHOR_GAP = HEADER_AUTHOR_GAP
M.HEADER_LINE_GAP = HEADER_LINE_GAP
M.getHeaderLayout = getHeaderLayout
M.NOTE_ICON_CHAR = NOTE_ICON_CHAR
M.measureNoteHeight = measureNoteHeight
M._note_height_cache = _note_height_cache
M.getLayoutSignature = getLayoutSignature
M.getNoteHeight = getNoteHeight

return M
