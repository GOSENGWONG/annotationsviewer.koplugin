-- anv_text.lua — Annotations Viewer
--
-- Text layout utilities with module-level measure caches: word, line and box
-- sizes, paragraph wrapping/trimming (including non-breaking spaces and
-- justified lines), and readable rendering of filter state. Font faces are
-- passed in by callers.
--
-- Public API (used by other modules):
--   measureTextWidth    width of a text with a given face
--   getWordWidths    cached per-word widths for a face
--   getLineHeight / getBoxHeight    cached line and box heights
--   wrapText / wrapParagraph / trimParagraph    wrap or trim text to a width
--   utf8Prefix    first N bytes cut on a UTF-8 character boundary
--   createJustifiedLine    build a justified text widget
--   filterToString    render filter state as a readable string

local Text = {}

local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local core = require("anv_core")
local _ = require("anv_i18n").gettext

Text._word_width_cache  = setmetatable({}, { __mode = "k" })  -- [face][word] = px
Text._line_height_cache = setmetatable({}, { __mode = "k" })  -- [face] = px
Text._box_height_cache  = setmetatable({}, { __mode = "k" })  -- [face]["w:bold:text"] = px

function Text.measureTextWidth(text, face)
    local tw = TextWidget:new{ text = text, face = face }
    local w = tw:getSize().w
    tw:free()
    return w
end

function Text.getWordWidths(face)
    local fc = Text._word_width_cache[face]
    if not fc then
        fc = {}
        -- Words never contain spaces, so " " is free to hold the width of one space.
        fc[" "] = Text.measureTextWidth("x x", face) - 2 * Text.measureTextWidth("x", face)
        Text._word_width_cache[face] = fc
    end
    return fc
end

-- Height of one TextWidget line in this face (TextWidget height does not depend on the text).
function Text.getLineHeight(face)
    local h = Text._line_height_cache[face]
    if not h then
        local tw = TextWidget:new{ text = "x", face = face }
        h = tw:getSize().h
        tw:free()
        Text._line_height_cache[face] = h
    end
    return h
end

-- Height of a wrapped TextBoxWidget (book title / info row), cached by text and width.
function Text.getBoxHeight(text, face, width, bold)
    local fc = Text._box_height_cache[face]
    if not fc then fc = {}; Text._box_height_cache[face] = fc end
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
function Text.wrapParagraph(text, face, max_width, lines)
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
    local widths = Text.getWordWidths(face)
    local space_w = widths[" "]
    -- a word wider than the column (a long URL) is broken between characters
    local tokens, src = {}, wrapTokens(text)
    for t = 1, #src do
        local tok = src[t]
        local word = tok[1]
        local ww = widths[word]
        if not ww then ww = Text.measureTextWidth(word, face); widths[word] = ww end
        if ww <= max_width or not word:find("[^\128-\191].*[^\128-\191]") then
            table.insert(tokens, tok)
        else
            local piece, joined = "", tok[2]
            for ch in word:gmatch("[^\128-\191][\128-\191]*") do
                if piece ~= "" and Text.measureTextWidth(piece .. ch, face) > max_width then
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
            ww = Text.measureTextWidth(word, face)
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
                local exact = Text.measureTextWidth(current_line .. sep .. word, face)
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
Text.NBSP = "\194\160"
-- First max_bytes bytes of s, cut on a UTF-8 character boundary: never a half character, and
-- never dropping a whole character that fits. Lua strings are byte strings here.
function Text.utf8Prefix(s, max_bytes)
    if #s <= max_bytes then return s end
    local used = 0
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local n = b < 0x80 and 1 or (b < 0xE0 and 2 or (b < 0xF0 and 3 or 4))
        if used + n > max_bytes then break end
        used, i = used + n, i + n
    end
    return s:sub(1, used)
end
function Text.trimParagraph(p)
    local changed = true
    while changed do
        changed = false
        local t = p:gsub("^%s+", ""):gsub("%s+$", "")
        if t:sub(1, 2) == Text.NBSP then t = t:sub(3); changed = true end
        if t:sub(-2) == Text.NBSP then t = t:sub(1, -3); changed = true end
        p = t
    end
    return p
end
function Text.wrapText(text, face, max_width)
    local lines, para_end = {}, {}
    for paragraph in (text:gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        paragraph = Text.trimParagraph(paragraph)
        if paragraph ~= "" then
            Text.wrapParagraph(paragraph, face, max_width, lines)
            para_end[#lines] = true
        end
    end
    return lines, para_end
end
function Text.createJustifiedLine(text, face, target_width, fgcolor)
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
function Text.filterToString(filter, skip_presence)
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

return Text
