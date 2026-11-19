-- anv_sort.lua — Annotations Viewer
--
-- Sorting logic: SortState parses, validates, stores and describes
-- multi-level sort modes, with a separate mode per tab. SORT_COMPARATORS
-- lazily builds a table.sort comparator for any mode.
--
-- Public API (used by other modules):
--   SortState    sort-mode state: get/set, getFor/setFor, parse/encode,
--                snapshot/restore, view/normView, revalidate, describe,
--                allowedAfter, keyName/dirName, QUICK_BOOK
--   SORT_COMPARATORS    mode -> table.sort comparator (built lazily)
--   STYLE_NAMES    localized highlight-style names
--   normalizeBookTitle    normalized title for title sorting
--   compareByPosition    position-based comparator
--   sortModeLabel    readable label for a sort mode

local Sort = {}

local core = require("anv_core")
local _ = require("anv_i18n").gettext

Sort.SORT_MODES = {
    date_newest = { label = _("Newest First") },
    date_oldest = { label = _("Oldest First") },
    author_asc = { label = _("A to Z (by Date)") },
    author_desc = { label = _("Z to A (by Date)") },
    author_location_asc = { label = _("Location: Begin to End") },
    author_location_desc = { label = _("Location: End to Begin") },
    book_asc = { label = _("A to Z (by Date)") },
    book_desc = { label = _("Z to A (by Date)") },
    book_location_asc = { label = _("Location: Begin to End") },
    book_location_desc = { label = _("Location: End to Begin") },
    filename_asc = { label = _("A to Z (by Date)") },
    filename_desc = { label = _("Z to A (by Date)") },
    filename_location_asc = { label = _("Location: Begin to End") },
    filename_location_desc = { label = _("Location: End to Begin") },
    opened_recent = { label = _("Last opened book first") },
    opened_oldest = { label = _("Longest unopened book first") },
}

-- Sorting compares titles many times; normalise each title only once.
Sort._normalized_title_cache = {}
Sort._lower_cache = {}
function Sort.lowerCached(str)
    str = str or ""
    local l = Sort._lower_cache[str]
    if not l then l = str:lower(); Sort._lower_cache[str] = l end
    return l
end
local normalizeBookTitleUncached
function Sort.normalizeBookTitle(title)
    if not title then return "" end
    local n = Sort._normalized_title_cache[title]
    if not n then
        n = normalizeBookTitleUncached(title)
        Sort._normalized_title_cache[title] = n
    end
    return n
end
normalizeBookTitleUncached = function(title)
    local normalized = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("^the%s+", ""):gsub("^a%s+", ""):gsub("^an%s+", "")
    return normalized
end

-- Where a note sits in its book: page first, then the exact spot. EPUB-like books
-- keep an xpointer text ("/body/DocFragment[3]/body/p[12]/text().5") in pos0, PDFs a
-- table with x/y; neither is a number, so compare their digit runs one by one.
function Sort.positionKey(n)
    local key = { tonumber(n.page) or 0 }
    local p = n.pos0
    if type(p) == "string" then
        for d in p:gmatch("%d+") do key[#key + 1] = tonumber(d) or 0 end
    elseif type(p) == "table" then
        key[#key + 1] = tonumber(p.y) or 0
        key[#key + 1] = tonumber(p.x) or 0
    end
    return key
end
function Sort.compareByPosition(a, b, reverse)
    -- KOReader keeps a book's annotations in reading order, so the place in that list
    -- is the most reliable position (an xpointer alone can't tell h2[1] from p[2])
    local oa, ob = tonumber(a.order), tonumber(b.order)
    if oa and ob and oa ~= ob then
        if reverse then return oa > ob else return oa < ob end
    end
    local ka, kb = Sort.positionKey(a), Sort.positionKey(b)
    for i = 1, math.max(#ka, #kb) do
        local x, y = ka[i] or -1, kb[i] or -1
        if x ~= y then
            if reverse then return x > y else return x < y end
        end
    end
    return false
end

-- A sort order is a rule: up to three levels "key:direction" joined by commas, for example
-- "author:asc,book:asc,pos:asc". The old fixed names (author_location_asc, ...) still work and are
-- translated to rules. Whatever the levels leave tied is settled by: book A-Z, newest first, position.
Sort.SortState = { opened = {}, cache = {} }
Sort.SortState.LEGACY = {
    date_newest = "date:desc", date_oldest = "date:asc",
    author_asc = "author:asc", author_desc = "author:desc",
    author_location_asc = "author:asc,book:asc,pos:asc", author_location_desc = "author:asc,book:asc,pos:desc",
    book_asc = "book:asc", book_desc = "book:desc",
    book_location_asc = "book:asc,pos:asc", book_location_desc = "book:asc,pos:desc",
    filename_asc = "file:asc", filename_desc = "file:desc",
    filename_location_asc = "file:asc,pos:asc", filename_location_desc = "file:asc,pos:desc",
    opened_recent = "opened:desc", opened_oldest = "opened:asc",
}
Sort.SortState.KEYS = { date = true, opened = true, author = true, book = true, file = true, pos = true, chapter = true }
-- Parse a rule (or an old name) into { {key=, dir=}, ... }; nil when it is not valid.
function Sort.SortState.parse(mode)
    if type(mode) ~= "string" then return nil end
    mode = Sort.SortState.LEGACY[mode] or mode
    local levels = {}
    for tok in mode:gmatch("[^,]+") do
        local key, dir = tok:match("^(%a+):(%a+)$")
        if not (key and Sort.SortState.KEYS[key] and (dir == "asc" or dir == "desc")) then return nil end
        levels[#levels + 1] = { key = key, dir = dir }
    end
    if #levels == 0 or #levels > 3 then return nil end
    return levels
end
-- The all-annotations list and the one-book list each remember their own order. A book list that
-- never had its own order set starts in reading order (first highlight in the book first).
-- The Bookmarks tab has an order of its own too (bm_tab: the list is on that tab); until one is
-- set it follows the annotations' order.
function Sort.SortState.get(single) return Sort.SortState.getFor(single, Sort.SortState.bm_tab) end
function Sort.SortState.set(single, mode) Sort.SortState.setFor(single, Sort.SortState.bm_tab, mode) end
-- bm: the order of the Bookmarks tab (else of the annotation tabs)
function Sort.SortState.getFor(single, bm)
    if bm then
        local own = core.getSetting(single and "sort_mode_book_bm" or "sort_mode_bm", nil)
        if own then return own end
    end
    if single then return core.getSetting("sort_mode_book", nil) or "book:asc,pos:asc" end
    return core.getSetting("sort_mode", "date_newest")
end
function Sort.SortState.setFor(single, bm, mode)
    core.setSetting((single and "sort_mode_book" or "sort_mode") .. (bm and "_bm" or ""), mode)
end
-- All four sort orders as stored, for Cancel: nil for the Bookmarks tab means "follow the
-- annotation order", and has to come back as nil, not as a copy of that order.
Sort.SortState.SETTING_KEYS = { "sort_mode", "sort_mode_bm", "sort_mode_book", "sort_mode_book_bm" }
function Sort.SortState.snapshot()
    local snap = {}
    for i = 1, #Sort.SortState.SETTING_KEYS do snap[i] = core.getSetting(Sort.SortState.SETTING_KEYS[i], nil) end
    return snap
end
-- Puts them back; true when something changed.
function Sort.SortState.restore(snap)
    local changed = false
    for i = 1, #Sort.SortState.SETTING_KEYS do
        if core.getSetting(Sort.SortState.SETTING_KEYS[i], nil) ~= snap[i] then
            core.setSetting(Sort.SortState.SETTING_KEYS[i], snap[i])
            changed = true
        end
    end
    return changed
end
function Sort.SortState.encode(levels)
    local parts = {}
    for _, l in ipairs(levels) do parts[#parts + 1] = l.key .. ":" .. l.dir end
    return table.concat(parts, ",")
end
-- Keys that still do something after the levels chosen so far.
function Sort.SortState.allowedAfter(prev, single)
    -- one book: every highlight has the same author, title and file, so only date and place count
    if single then
        if not prev then return { "date", "pos", "chapter" } end
        if prev.key == "chapter" then return { "date", "pos" } end
        return prev.key == "date" and { "pos" } or {}
    end
    if not prev then return { "date", "opened", "author", "book", "file", "pos" } end
    if prev.key == "pos" then return {} end
    if prev.key == "date" then return { "author", "book", "file" } end -- a day, then the books of that day
    if prev.key == "author" then return { "opened", "book", "file", "date", "pos" } end
    return { "date", "pos" } -- book, file name and last opened already single out a book
end
-- The rule as it applies to a view: in one book only its date or place part counts.
function Sort.SortState.view(mode, single)
    local levels = Sort.SortState.parse(mode) or Sort.SortState.parse("date:desc")
    if not single then
        -- a rule saved for one book (chapter) or edited by hand: keep what makes sense here
        local out = Sort.SortState.revalidate(levels, false)
        if #out == 0 then out = Sort.SortState.parse("date:desc") end
        return out
    end
    local first = levels[1].key
    if first == "date" or first == "chapter" or first == "pos" then
        local keep = {}
        for _, l in ipairs(levels) do
            if l.key == "date" or l.key == "chapter" or l.key == "pos" then keep[#keep + 1] = l end
        end
        local out = Sort.SortState.revalidate(keep, true)
        -- a chapter on its own: inside a chapter the highlights follow the book
        if out[#out].key == "chapter" then out[#out + 1] = { key = "pos", dir = "asc" } end
        return out
    end
    -- older rules (book, author ...): only the place part counts, else the date part
    for _, l in ipairs(levels) do
        if l.key == "pos" then return { { key = "pos", dir = l.dir } } end
    end
    for _, l in ipairs(levels) do
        if l.key == "date" then return { { key = "date", dir = l.dir } } end
    end
    return Sort.SortState.parse("date:desc")
end
function Sort.SortState.normView(mode, single)
    return Sort.SortState.encode(Sort.SortState.view(mode, single))
end
function Sort.SortState.cmp3(x, y) if x < y then return -1 elseif x > y then return 1 end return 0 end
function Sort.SortState.keyCmp(key, a, b)
    if key == "date" then return Sort.SortState.cmp3(a.datetime or "", b.datetime or "")
    elseif key == "opened" then return Sort.SortState.cmp3(Sort.SortState.opened[a.book_path or ""] or 0, Sort.SortState.opened[b.book_path or ""] or 0)
    elseif key == "author" then return Sort.SortState.cmp3(Sort.lowerCached(a.book_authors), Sort.lowerCached(b.book_authors))
    elseif key == "book" then return Sort.SortState.cmp3(Sort.normalizeBookTitle(a.book_title), Sort.normalizeBookTitle(b.book_title))
    elseif key == "file" then return Sort.SortState.cmp3(Sort.lowerCached(a.book_filename), Sort.lowerCached(b.book_filename))
    elseif key == "chapter" then return Sort.SortState.cmp3(a.chapter_rank or 0, b.chapter_rank or 0) end
    return 0
end
function Sort.SortState.posCmp(a, b, dir)
    local c = Sort.SortState.keyCmp("book", a, b)
    if c == 0 then c = Sort.SortState.cmp3(a.book_path or "", b.book_path or "") end
    if c ~= 0 then return c end
    local pc = 0
    if Sort.compareByPosition(a, b) then pc = -1 elseif Sort.compareByPosition(b, a) then pc = 1 end
    return dir == "desc" and -pc or pc
end
function Sort.SortState.build(mode)
    local levels = Sort.SortState.parse(mode)
    if not levels then return nil end
    local id = Sort.SortState.encode(levels)
    if Sort.SortState.cache[id] then return Sort.SortState.cache[id] end
    local day_only = {}
    for n, l in ipairs(levels) do
        if l.key == "date" and levels[n + 1] then day_only[n] = true end
    end
    local f = function(a, b)
        for n, l in ipairs(levels) do
            local c
            if l.key == "pos" then c = Sort.SortState.posCmp(a, b, l.dir)
            elseif day_only[n] then
                c = Sort.SortState.cmp3((a.datetime or ""):sub(1, 10), (b.datetime or ""):sub(1, 10))
                if l.dir == "desc" then c = -c end
            else
                c = Sort.SortState.keyCmp(l.key, a, b)
                if l.dir == "desc" then c = -c end
            end
            if c ~= 0 then return c < 0 end
        end
        local c = Sort.SortState.keyCmp("book", a, b)
        if c == 0 then c = Sort.SortState.cmp3(a.book_path or "", b.book_path or "") end
        if c ~= 0 then return c < 0 end
        c = -Sort.SortState.keyCmp("date", a, b)
        if c ~= 0 then return c < 0 end
        return Sort.SortState.posCmp(a, b, "asc") < 0
    end
    Sort.SortState.cache[id] = f
    return f
end
Sort.SORT_COMPARATORS = setmetatable({}, { __index = function(_, mode) return Sort.SortState.build(mode) end })
Sort.SORT_CATEGORY_LABELS = { author = _("Author"), book = _("Book"), filename = _("Filename") }
Sort.SORT_SHORT_LABELS = {
    date_newest = _("Newest first"), date_oldest = _("Oldest first"),
    asc = _("A–Z"), desc = _("Z–A"),
    location_asc = _("start to end"), location_desc = _("end to start"),
    opened_recent = _("Last opened first"), opened_oldest = _("Longest unopened first"),
}
-- Names and direction words of the rule levels (shared by the tab row label and the sort dropdown)
Sort.SortState.KEY_NAMES = { date = _("Date"), opened = _("Last opened book"), author = _("Author"), book = _("Book"),
    file = _("Filename"), pos = _("Place in book"), chapter = _("Chapter") }
Sort.SortState.DIR_NAMES = {
    date = { asc = _("Oldest first"), desc = _("Newest first") },
    opened = { asc = _("Longest ago first"), desc = _("Most recent first") },
    author = { asc = _("Author A to Z"), desc = _("Author Z to A") },
    book = { asc = _("Title A to Z"), desc = _("Title Z to A") },
    file = { asc = _("Filename A to Z"), desc = _("Filename Z to A") },
    pos = { asc = _("Start of book first"), desc = _("End of book first") },
    chapter = { asc = _("From the start"), desc = _("From the end") },
}
Sort.SortState.QUICK_BOOK = {
    { _("Newest"), "date:desc" }, { _("Oldest"), "date:asc" },
    { _("Position"), "pos:asc" }, { _("Reverse position"), "pos:desc" },
    { _("Chapter, newest first"), "chapter:asc,date:desc" }, { _("Chapter, oldest first"), "chapter:asc,date:asc" },
}
function Sort.SortState.keyName(key, single)
    if single and key == "pos" then return _("Position") end
    return Sort.SortState.KEY_NAMES[key]
end
function Sort.SortState.dirName(key, dir, single)
    if single and key == "pos" then return dir == "asc" and _("From the start") or _("From the end") end
    return Sort.SortState.DIR_NAMES[key][dir]
end
Sort.SortState.SHORT = {
    -- the same words as the default order's label, so one order never has two names
    date = { asc = _("Oldest first"), desc = _("Newest first") },
    opened = { asc = _("Opened long ago"), desc = _("Opened recently") },
    author = { asc = _("Authors A–Z"), desc = _("Authors Z–A") },
    book = { asc = _("Titles A–Z"), desc = _("Titles Z–A") },
    file = { asc = _("Filenames A–Z"), desc = _("Filenames Z–A") },
    pos = { asc = _("Start to end"), desc = _("End to start") },
    chapter = { asc = _("Chapters start to end"), desc = _("Chapters end to start") },
}
-- Keep the levels that still make sense in a row: a level goes when its key was already used or
-- does nothing after the level before it, and everything after it goes too.
function Sort.SortState.revalidate(levels, single)
    local out, used = {}, {}
    for n, l in ipairs(levels) do
        local ok = false
        for _, k in ipairs(Sort.SortState.allowedAfter(out[n - 1], single)) do if k == l.key then ok = true end end
        if not ok or used[l.key] or n > 3 then break end
        used[l.key] = true
        out[n] = l
    end
    return out
end
-- One plain sentence per level: what the order is, in words.
function Sort.SortState.describe(levels, single)
    if single then
        local l = levels[1] or { key = "date", dir = "desc" }
        local function place(x)
            return x.dir == "asc" and _("in book order") or _("from the end of the book")
        end
        if l.key == "chapter" then
            local d, p = levels[2], levels[3]
            local head = l.dir == "asc" and _("Chapters from the start of the book")
                or _("Chapters from the end of the book")
            if not d then return head .. "." end
            if d.key == "pos" then
                return head .. (d.dir == "asc" and _(", highlights in book order within each chapter.")
                    or _(", highlights from the end of each chapter."))
            end
            local out = head .. (d.dir == "desc" and _(", newest days first within each chapter")
                or _(", oldest days first within each chapter"))
            if p then out = out .. "; " .. _("the same day ") .. place(p) end
            return out .. "."
        end
        if l.key == "pos" then
            return l.dir == "asc" and _("Highlights by position in the book, from the start.")
                or _("Highlights by position in the book, from the end.")
        end
        local out = l.dir == "desc" and _("Newest highlights first") or _("Oldest highlights first")
        if levels[2] then out = out .. "; " .. _("the same day ") .. place(levels[2]) end
        return out .. "."
    end
    local eff = {}
    for _, l in ipairs(levels) do eff[#eff + 1] = l end
    local function has(set)
        for _, l in ipairs(eff) do if set[l.key] then return true end end
        return false
    end
    -- position is always inside a book; a book comes first when the level before is not one
    for n, l in ipairs(eff) do
        if l.key == "pos" then
            local prev = eff[n - 1]
            if not prev or prev.key == "author" or prev.key == "date" then table.insert(eff, n, { key = "book", dir = "asc" }) end
            break
        end
    end
    if not has({ book = true, file = true, opened = true, pos = true, date = true }) then
        eff[#eff + 1] = { key = "book", dir = "asc" }
    end
    local last = eff[#eff]
    if last.key ~= "date" and last.key ~= "pos" then eff[#eff + 1] = { key = "date", dir = "desc" } end
    local out = {}
    for n, l in ipairs(eff) do
        local prev = eff[n - 1]
        local lead = ""
        if prev then
            lead = prev.key == "author" and _("Within an author, ") or prev.key == "date" and _("Within a day, ") or _("Within a book, ")
        end
        local d, text = l.dir, nil
        if l.key == "date" then
            if prev then text = d == "desc" and _("newest highlights first") or _("oldest highlights first")
            elseif eff[n + 1] then text = d == "desc" and _("Newest days first") or _("Oldest days first")
            else text = d == "desc" and _("Newest highlights first, across all books") or _("Oldest highlights first, across all books") end
        elseif l.key == "pos" then
            text = d == "asc" and _("from the start to the end") or _("from the end to the start")
        else
            local what = ({
                author = d == "asc" and _("authors A to Z") or _("authors Z to A"),
                opened = d == "desc" and _("books opened most recently first") or _("books opened longest ago first"),
                book = d == "asc" and _("books by title A to Z") or _("books by title Z to A"),
                file = d == "asc" and _("books by filename A to Z") or _("books by filename Z to A"),
            })[l.key]
            text = prev and what or (what:sub(1, 1):upper() .. what:sub(2))
        end
        if prev then text = lead .. text elseif l.key == "pos" then text = _("Books by title A to Z. Within a book, ") .. text end
        out[#out + 1] = text:sub(1, 1):upper() .. text:sub(2) .. "."
    end
    return table.concat(out, " ")
end
function Sort.sortModeLabel(mode, single)
    if single then
        local v = Sort.SortState.view(mode, true)
        local l = v[1]
        if l.key == "date" and v[2] then
            return l.dir == "desc" and _("Newest · position") or _("Oldest · position")
        end
        if l.key == "chapter" then
            if not v[2] or v[2].key == "pos" then return l.dir == "asc" and _("Chapter") or _("Reverse chapter") end
            return v[2].dir == "desc" and _("Chapter · newest") or _("Chapter · oldest")
        end
        if l.key == "pos" then return l.dir == "asc" and _("Position") or _("Reverse position") end
        return Sort.SortState.SHORT.date[l.dir]
    end
    if not Sort.SORT_MODES[mode] then
        -- a rule that can't be read sorts newest first (sortNotesList): say so
        if not Sort.SortState.parse(mode) then mode = "date_newest" else
            local parts = {}
            for _, l in ipairs(Sort.SortState.view(mode, false)) do
                parts[#parts + 1] = Sort.SortState.SHORT[l.key][l.dir]
            end
            return table.concat(parts, " › ")
        end
    end
    if Sort.SORT_SHORT_LABELS[mode] then return Sort.SORT_SHORT_LABELS[mode] end
    local cat, rest = mode:match("^(%a+)_(.+)$")
    return (Sort.SORT_CATEGORY_LABELS[cat] or cat) .. " · " .. (Sort.SORT_SHORT_LABELS[rest] or Sort.SORT_MODES[mode].label)
end

-- Active-filter chips under the tabs: one black chip per filter (tap to remove it),
-- "Clear all", and "N of M" on the right. Laid out over as many rows as needed.
Sort.STYLE_NAMES = { lighten = _("Lighten"), underscore = _("Underline"), strikeout = _("Strikeout"), invert = _("Invert") }

return Sort
