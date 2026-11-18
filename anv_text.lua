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

local _word_width_cache = setmetatable({}, { __mode = "k" })  -- [face][word] = px
local _line_height_cache = setmetatable({}, { __mode = "k" }) -- [face] = px
local _box_height_cache = setmetatable({}, { __mode = "k" })  -- [face]["w:bold:text"] = px

local function measureTextWidth(text, face)
    local tw = TextWidget:new{ text = text, face = face }
    local w = tw:getSize().w
    tw:free()
    return w
end

local function getWordWidths(face)
    local fc = _word_width_cache[face]
    if not fc then
        fc = {}
        -- Words never contain spaces, so " " is free to hold the width of one space.
        fc[" "] = measureTextWidth("x x", face) - 2 * measureTextWidth("x", face)
        _word_width_cache[face] = fc
    end
    return fc
end

-- Height of one TextWidget line in this face (TextWidget height does not depend on the text).
local function getLineHeight(face)
    local h = _line_height_cache[face]
    if not h then
        local tw = TextWidget:new{ text = "x", face = face }
        h = tw:getSize().h
        tw:free()
        _line_height_cache[face] = h
    end
    return h
end

-- Height of a wrapped TextBoxWidget (book title / info row), cached by text and width.
local function getBoxHeight(text, face, width, bold)
    local fc = _box_height_cache[face]
    if not fc then fc = {}; _box_height_cache[face] = fc end
    local key = width .. (bold and ":b:" or ":n:") .. text
    local h = fc[key]
    if not h then
        local tb = TextBoxWidget:new{ text = text, face = face, width = width, alignment = "left", bold = bold }
        h = tb:getSize().h
        tb:free()
        fc[key] = h
    end
    return h
end

-- Greedy word wrap. Same result as measuring every candidate line, but word widths are
-- measured once per face and summed; only lines that end up within the rounding error of
-- max_width are measured for real, so the line breaks are unchanged.
local function wrapParagraph(text, face, max_width, lines)
-- Words to wrap: split at spaces; Chinese / Japanese / Korean text has none, so such words are
-- cut into their characters with KOReader's util.splitToWords (the pieces join without a space).
    -- closing punctuation never starts a line: it stays with the character before it
    local closing = "。，、；：？！）」』】》〉〕］｝”’…"
    local function wrapTokens(txt)
        local tokens = {}
        for word in txt:gmatch("%S+") do
            if word:find("[\227-\237\239\240]") then -- also 4-byte characters (CJK beyond U+20000)
                for i, piece in ipairs(require("util").splitToWords(word)) do
                    if i > 1 and closing:find(piece, 1, true) then
                        tokens[#tokens][1] = tokens[#tokens][1] .. piece
                    else
                        table.insert(tokens, { piece, i > 1 })
                    end
                end
            else
                table.insert(tokens, { word, false })
            end
        end
        return tokens
    end
    local widths = getWordWidths(face)
    local space_w = widths[" "]
    -- a word wider than the column (a long URL) is broken between characters
    local tokens, src = {}, wrapTokens(text)
    for t = 1, #src do
        local tok = src[t]
        local word = tok[1]
        local ww = widths[word]
        if not ww then ww = measureTextWidth(word, face); widths[word] = ww end
        if ww <= max_width or not word:find("[^\128-\191].*[^\128-\191]") then
            table.insert(tokens, tok)
        else
            local piece, joined = "", tok[2]
            for ch in word:gmatch("[^\128-\191][\128-\191]*") do
                if piece ~= "" and measureTextWidth(piece .. ch, face) > max_width then
                    table.insert(tokens, { piece, joined })
                    piece, joined = "", true
                end
                piece = piece .. ch
            end
            if piece ~= "" then table.insert(tokens, { piece, joined }) end
        end
    end
    local current_line, current_w, words_since_exact = "", 0, 0
    for _t, tok in ipairs(tokens) do
        local word, joined = tok[1], tok[2]
        local sep, sep_w = joined and "" or " ", joined and 0 or space_w
        local ww = widths[word]
        if not ww then
            ww = measureTextWidth(word, face)
            widths[word] = ww
        end
        if current_line == "" then
            current_line, current_w, words_since_exact = word, ww, 0
        else
            local est = current_w + sep_w + ww
            -- each summed width can be off by about a pixel of rounding
            local slack = 2 + words_since_exact
            local fits
            if est <= max_width - slack then
                fits = true
                current_w = est
                words_since_exact = words_since_exact + 1
            elseif est > max_width + slack then
                fits = false
            else
                local exact = measureTextWidth(current_line .. sep .. word, face)
                fits = exact <= max_width
                if fits then current_w, words_since_exact = exact, 0 end
            end
            if fits then
                current_line = current_line .. sep .. word
            else
                table.insert(lines, current_line)
                current_line, current_w, words_since_exact = word, ww, 0
            end
        end
    end
    if current_line ~= "" then table.insert(lines, current_line) end
end

-- Wraps text to max_width, keeping the text's paragraph breaks (blank lines are dropped).
-- Returns the lines and a set of line numbers that end a paragraph (not to be justified).
-- Strip spaces (including no-break spaces) from both ends of a paragraph; books often
-- leave them in front of a line, which then shows as a stray indent.
local NBSP = "\194\160"
local function trimParagraph(p)
    local changed = true
    while changed do
        changed = false
        local t = p:gsub("^%s+", ""):gsub("%s+$", "")
        if t:sub(1, 2) == NBSP then t = t:sub(3); changed = true end
        if t:sub(-2) == NBSP then t = t:sub(1, -3); changed = true end
        p = t
    end
    return p
end
local function wrapText(text, face, max_width)
    local lines, para_end = {}, {}
    for paragraph in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        paragraph = trimParagraph(paragraph)
        if paragraph ~= "" then
            wrapParagraph(paragraph, face, max_width, lines)
            para_end[#lines] = true
        end
    end
    return lines, para_end
end
local function createJustifiedLine(text, face, target_width, fgcolor)
    local words = {}
    for word in text:gmatch("%S+") do table.insert(words, word) end
    if #words <= 1 then
        return TextWidget:new{ text = text, face = face, fgcolor = fgcolor }
    end
    local total_word_width = 0
    local word_widgets = {}
    for _, word in ipairs(words) do
        local tw = TextWidget:new{ text = word, face = face, fgcolor = fgcolor }
        total_word_width = total_word_width + tw:getSize().w
        table.insert(word_widgets, tw)
    end
    -- a line that is far shorter than the column (end of a truncated highlight) is not stretched
    local natural = TextWidget:new{ text = text, face = face }
    local natural_w = natural:getSize().w
    natural:free()
    if natural_w < target_width * 0.8 then
        for _, w in ipairs(word_widgets) do w:free() end
        return TextWidget:new{ text = text, face = face, fgcolor = fgcolor }
    end
    local available_space = target_width - total_word_width
    local gaps = #words - 1
    if gaps <= 0 or available_space <= 0 then
        for _, w in ipairs(word_widgets) do w:free() end
        return TextWidget:new{ text = text, face = face, fgcolor = fgcolor }
    end
    local space_per_gap = math.floor(available_space / gaps)
    local extra_space = available_space - (space_per_gap * gaps)
    local hg = HorizontalGroup:new{}
    for i, tw in ipairs(word_widgets) do
        table.insert(hg, tw)
        if i < #word_widgets then
            local gap = space_per_gap
            if extra_space > 0 then
                gap = gap + 1
                extra_space = extra_space - 1
            end
            table.insert(hg, HorizontalSpan:new{ width = gap })
        end
    end
    return hg
end
-- Text of the active-filter label shown under the title; "" means no filter is shown.
local function filterToString(filter, skip_presence)
    if not filter then return "" end
    local parts = {}
    -- Colour / style
    if type(filter.cs) == "table" and next(filter.cs) then
        local names = {}
        for k in pairs(filter.cs) do
            local t, v
            if type(k) == "string" then t, v = k:match("^(%a+):(.+)$") end -- a broken key is left out
            local name
            if t == "color" then name = core.colorName(v) end
            if v and filter.cs[k] == true then table.insert(names, name or (v:sub(1, 1):upper() .. v:sub(2))) end
        end
        table.sort(names)
        if #names > 0 then table.insert(parts, (filter.cs_exclude and "C≠ " or "C: ") .. table.concat(names, ", ")) end
    end
    -- Books include / exclude
    if filter.books and next(filter.books) then
        local books = {}
        for k in pairs(filter.books) do table.insert(books, k) end
        table.sort(books)
        table.insert(parts, "B: " .. table.concat(books, ", "))
    end
    if filter.books_exclude and next(filter.books_exclude) then
        local books = {}
        for k in pairs(filter.books_exclude) do table.insert(books, k) end
        table.sort(books)
        table.insert(parts, "B≠ " .. table.concat(books, ", "))
    end
    -- Tags include / exclude
    if filter.tags and next(filter.tags) then
        local tags = {}
        for k in pairs(filter.tags) do table.insert(tags, k) end
        table.sort(tags)
        table.insert(parts, "T: " .. table.concat(tags, ", "))
    end
    if filter.tags_exclude and next(filter.tags_exclude) then
        local tags = {}
        for k in pairs(filter.tags_exclude) do table.insert(tags, k) end
        table.sort(tags)
        table.insert(parts, "T≠ " .. table.concat(tags, ", "))
    end
    -- Authors, series, language include / exclude
    local meta_kinds = { "authors", "series", "languages" } -- as NotesListWidget.META_KINDS (defined later)
    for i = 1, 3 do
        local kind = meta_kinds[i]
        local letter = kind:sub(1, 1):upper()
        for pi = 1, 2 do
            local k = pi == 1 and kind or (kind .. "_exclude")
            if type(filter[k]) == "table" and next(filter[k]) then
                local names = {}
                for v in pairs(filter[k]) do table.insert(names, v == "" and _("None") or v) end
                table.sort(names)
                table.insert(parts, letter .. (pi == 1 and ": " or "≠ ") .. table.concat(names, ", "))
            end
        end
    end
    -- Highlight text include / exclude
    if filter.search_highlight and filter.search_highlight ~= "" then
        local mode = filter.search_highlight_mode or "all"
        local mode_str = mode == "any" and " (any word)" or mode == "phrase" and " (phrase)" or ""
        local case_str = filter.search_highlight_case and " [Aa]" or ""
        table.insert(parts, "H: \"" .. filter.search_highlight .. "\"" .. mode_str .. case_str)
    end
    if filter.search_highlight_exclude and filter.search_highlight_exclude ~= "" then
        local mode = filter.search_highlight_exclude_mode or "all"
        local mode_str = mode == "any" and " (any word)" or mode == "phrase" and " (phrase)" or ""
        local case_str = filter.search_highlight_exclude_case and " [Aa]" or ""
        table.insert(parts, "H≠ \"" .. filter.search_highlight_exclude .. "\"" .. mode_str .. case_str)
    end
    -- Note text include / exclude
    if filter.search_note and filter.search_note ~= "" then
        local mode = filter.search_note_mode or "all"
        local mode_str = mode == "any" and " (any word)" or mode == "phrase" and " (phrase)" or ""
        local case_str = filter.search_note_case and " [Aa]" or ""
        table.insert(parts, "N: \"" .. filter.search_note .. "\"" .. mode_str .. case_str)
    end
    if filter.search_note_exclude and filter.search_note_exclude ~= "" then
        local mode = filter.search_note_exclude_mode or "all"
        local mode_str = mode == "any" and " (any word)" or mode == "phrase" and " (phrase)" or ""
        local case_str = filter.search_note_exclude_case and " [Aa]" or ""
        table.insert(parts, "N≠ \"" .. filter.search_note_exclude .. "\"" .. mode_str .. case_str)
    end
    -- Chapters include / exclude
    if filter.chapters and next(filter.chapters) then
        local chs = {}
        for k in pairs(filter.chapters) do table.insert(chs, k) end
        table.sort(chs)
        table.insert(parts, "Ch: " .. table.concat(chs, ", "))
    end
    if filter.chapters_exclude and next(filter.chapters_exclude) then
        local chs = {}
        for k in pairs(filter.chapters_exclude) do table.insert(chs, k) end
        table.sort(chs)
        table.insert(parts, "Ch≠ " .. table.concat(chs, ", "))
    end
    if filter.search_any and filter.search_any ~= "" then
        local case_str = filter.search_any_case and " [Aa]" or ""
        table.insert(parts, _("Search: ") .. "\"" .. filter.search_any .. "\"" .. case_str)
    end
    -- the tabs already show this, so the header row can leave it out
    if not skip_presence then
        if filter.notes_presence == "only" then
            table.insert(parts, _("Notes only"))
        elseif filter.notes_presence == "exclude" then
            table.insert(parts, _("Without notes"))
        elseif filter.notes_presence == "bookmarks" then
            table.insert(parts, _("Bookmarks"))
        end
    end
    return #parts > 0 and table.concat(parts, "; ") or ""
end

-- Wraps a widget so a tap on it calls callback(ges).

-- Module exports
M._word_width_cache = _word_width_cache
M._line_height_cache = _line_height_cache
M._box_height_cache = _box_height_cache
M.measureTextWidth = measureTextWidth
M.getWordWidths = getWordWidths
M.getLineHeight = getLineHeight
M.getBoxHeight = getBoxHeight
M.wrapParagraph = wrapParagraph
M.NBSP = NBSP
M.trimParagraph = trimParagraph
M.wrapText = wrapText
M.createJustifiedLine = createJustifiedLine
M.filterToString = filterToString

return M
