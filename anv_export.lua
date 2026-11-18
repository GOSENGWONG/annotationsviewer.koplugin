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

local STYLE_NAMES = require("anv_sort").STYLE_NAMES

-- Formatting a long date uses anv_item (which loads later); resolve it lazily.
local _item_for_date
local function NIW()
    if not _item_for_date then _item_for_date = require("anv_item").NoteItemWidget end
    return _item_for_date
end

local Export = {}
Export.DEFAULTS = {
    format = "md",        -- "md" | "txt"
    header = true,        -- "Annotations" title and the filter line at the top
    author = true,        -- author after the book title
    chapter = "line",     -- "line" (in the info line) | "heading" | "none"
    date = "date",        -- "date" | "datetime" | "none"
    date_style = "iso",   -- "iso" (2026-01-09) | "long" (9 Jan 2026)
    page = true,
    notes = true,         -- your notes
    style = false,        -- colour and style of the highlight
    tags = false,
    group = "book",       -- "book" (each book once, in the order it first shows) | "list" (as in the list)
    highlight = "quote",  -- Markdown: "quote" | "italic" | "plain"
    note_style = "bold",  -- Markdown: "bold" ("Note:" label) | "quote" | "italic"
    files = "one",        -- "one" | "book" (a file per book)
    name_date = true,     -- date and time in the file name (off: exporting again replaces the file)
}
function Export.options()
    local o = {}
    for k, v in pairs(Export.DEFAULTS) do
        local s = getSetting("export_" .. k, nil)
        if s == nil or type(s) ~= type(v) then o[k] = v else o[k] = s end
    end
    return o
end
-- the text split into lines (no \r), without empty lines at the end
function Export.lines(text)
    local out = {}
    for line in (tostring(text or ""):gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do table.insert(out, line) end
    while #out > 0 and not out[#out]:find("%S") do out[#out] = nil end
    return out
end
-- Markdown: a title, chapter, tag or filter can't turn into emphasis, a link or code
function Export.esc(s, md)
    s = tostring(s or "")
    if not md then return s end
    return (s:gsub("([\\`%*_%[%]<>])", "\\%1"))
end
-- the books in the order they first show; with group "list" a book starts again whenever the list
-- goes to another book and back
function Export.groups(notes, by_book)
    local groups, index = {}, {}
    for i = 1, #notes do
        local n = notes[i]
        local key = n.book_path or n.book_title or ""
        local g
        if by_book then g = index[key]
        else
            g = groups[#groups]
            if g and g.key ~= key then g = nil end
        end
        if not g then
            g = { key = key, title = n.book_title, authors = n.book_authors, notes = {} }
            table.insert(groups, g)
            if by_book then index[key] = g end
        end
        table.insert(g.notes, n)
    end
    return groups
end
function Export.dateText(datetime, o)
    if o.date == "none" or not datetime or datetime == "" then return nil end
    local with_time = o.date == "datetime"
    if o.date_style == "long" then
        return NIW():formatDate(datetime, { year = "always", time = with_time and "always" or "never" })
    end
    local d = datetime:match("^%d+%-%d+%-%d+")
    if not d then return datetime end
    local hm = with_time and datetime:match("[ T](%d%d?:%d%d)")
    return hm and (d .. " " .. hm) or d
end
function Export.authorsText(authors)
    if not authors or authors == "" or authors == "Unknown" then return nil end
    return (tostring(authors):gsub("%s*\n%s*", ", "))
end
-- One book (a group) as lines appended to out.
function Export.addBook(out, g, o)
    local md = o.format ~= "txt"
    local title = Export.esc(g.title or _("Unknown book"), md)
    local authors = o.author and Export.authorsText(g.authors)
    local heading = title .. (authors and (" — " .. Export.esc(authors, md)) or "")
    if md then table.insert(out, "## " .. heading)
    else
        table.insert(out, heading)
        table.insert(out, string.rep("=", math.max(3, #(heading:gsub("[\128-\191]", "")))))
    end
    table.insert(out, "")
    local current_chapter
    for i = 1, #g.notes do
        local note = g.notes[i]
        local chapter = note.chapter ~= "" and note.chapter or nil
        if o.chapter == "heading" and chapter and chapter ~= current_chapter then
            current_chapter = chapter
            if md then table.insert(out, "### " .. Export.esc(chapter, md))
            else
                table.insert(out, chapter)
                table.insert(out, string.rep("-", math.max(3, #(chapter:gsub("[\128-\191]", "")))))
            end
            table.insert(out, "")
        end
        local meta = {}
        if note.bookmark then table.insert(meta, _("Bookmark")) end
        local date = Export.dateText(note.datetime, o)
        if date then table.insert(meta, date) end
        if o.chapter == "line" and chapter then table.insert(meta, Export.esc(chapter, md)) end
        if o.page then
            -- the page number as KOReader shows it (an EPUB position is not a page number)
            local page_no = note.page_label
            if page_no == nil and tonumber(note.page) then page_no = tonumber(note.page) end
            if page_no ~= nil and page_no ~= "" then table.insert(meta, _("page") .. " " .. Export.esc(page_no, md)) end
        end
        if o.style and not note.bookmark then
            if note.color and note.color ~= "" then table.insert(meta, Export.esc(colorName(note.color:lower()), md)) end
            local drawer = note.drawer and note.drawer:lower()
            if drawer and drawer ~= "" then table.insert(meta, Export.esc(STYLE_NAMES[drawer] or drawer, md)) end
        end
        if #meta > 0 then
            local line = table.concat(meta, " · ")
            table.insert(out, md and ("*" .. line .. "*") or line)
        end
        local text = Export.lines(note.highlighted_text)
        if table.concat(text):find("%S") then
            if md and o.highlight == "quote" then
                for j = 1, #text do
                    local line = text[j]
                    table.insert(out, line == "" and ">" or ("> " .. line))
                end
            elseif md and o.highlight == "italic" then
                local parts = {}
                for j = 1, #text do
                    local line = text[j]
                    local t = line:match("^%s*(.-)%s*$")
                    table.insert(parts, t ~= "" and ("*" .. t:gsub("%*", "\\*") .. "*") or "")
                end
                table.insert(out, (table.concat(parts, "  \n"):gsub("  \n  \n", "\n\n")))
            else
                table.insert(out, (table.concat(text, md and "  \n" or "\n")))
            end
        end
        local user_note = o.notes and Export.lines(note.user_note) or {}
        if table.concat(user_note):find("%S") then
            table.insert(out, "")
            local label = _("Note") .. ":"
            if not md then
                table.insert(out, label .. " " .. table.concat(user_note, "\n"))
            elseif o.note_style == "quote" then
                for j, line in ipairs(user_note) do
                    table.insert(out, j == 1 and ("> **" .. label .. "** " .. line) or (line == "" and ">" or ("> " .. line)))
                end
            elseif o.note_style == "italic" then
                local parts = {}
                for j = 1, #user_note do
                    local line = user_note[j]
                    local t = line:match("^%s*(.-)%s*$")
                    table.insert(parts, t ~= "" and ("*" .. t:gsub("%*", "\\*") .. "*") or "")
                end
                table.insert(out, "**" .. label .. "** " .. table.concat(parts, "  \n"))
            else
                table.insert(out, "**" .. label .. "** " .. table.concat(user_note, "  \n"))
            end
        end
        if o.tags then
            local tags = NoteWrapper:new(note):getTags()
            if type(tags) == "table" and #tags > 0 then
                local esc = {}
                for j, t in ipairs(tags) do esc[j] = Export.esc(t, md) end
                table.insert(out, "")
                table.insert(out, md and ("**" .. _("Tags") .. ":** " .. table.concat(esc, ", "))
                    or (_("Tags") .. ": " .. table.concat(esc, ", ")))
            end
        end
        table.insert(out, "")
    end
end
-- The whole text of one file. header: the title and filter line on top (not in a file per book).
function Export.build(notes, o, filter_label, header)
    o = o or Export.options()
    if header == nil then header = o.header end
    local md = o.format ~= "txt"
    local out = {}
    if header then
        local title = Export.allBookmarks(notes) and _("Bookmarks") or _("Annotations")
        if md then table.insert(out, "# " .. title) else table.insert(out, title:upper()) end
        if filter_label and filter_label ~= "" then
            local line = _("Filter") .. ": " .. Export.esc(filter_label, md)
            table.insert(out, md and ("_" .. line .. "_") or line)
        end
        table.insert(out, "")
    end
    local groups = Export.groups(notes, o.group ~= "list")
    for k = 1, #groups do Export.addBook(out, groups[k], o) end
    return table.concat(out, "\n")
end
-- the old one: Markdown with the default options (tests)
function Export.notesToMarkdown(notes, filter_label)
    local o = {}
    for k, v in pairs(Export.DEFAULTS) do o[k] = v end
    return Export.build(notes, o, filter_label, true)
end
-- A safe file name: no characters a file system refuses, at most ~80 bytes (whole characters),
-- the date and time added when asked, and " (2)" when the name is already used in this export.
function Export.fileName(base, o, used, stamp)
    base = tostring(base or ""):gsub("[%c/\\:%*%?\"<>|]", "_")
    base = base:gsub("^[%s%.]+", ""):gsub("[%s%.]+$", "")
    if #base > 80 then base = base:sub(1, 80):gsub("[\192-\255][\128-\191]*$", "") end
    if base == "" then base = "annotations" end
    if o.name_date then base = base .. "-" .. (stamp or os.date("%Y%m%d-%H%M%S")) end
    local name, i = base, 2
    used = used or {}
    while used[name:lower()] do name = base .. " (" .. i .. ")"; i = i + 1 end
    used[name:lower()] = true
    return name .. (o.format == "txt" and ".txt" or ".md")
end
-- The files of an export: { { name =, text = } , ... }
function Export.files(notes, o, filter_label, stamp)
    local used, files = {}, {}
    if o.files == "book" then
        local groups = Export.groups(notes, true)
        for k = 1, #groups do
            local g = groups[k]
            local out = {}
            Export.addBook(out, g, o)
            table.insert(files, { name = Export.fileName(g.title or "annotations", o, used, stamp),
                text = table.concat(out, "\n"), count = #g.notes })
        end
        return files
    end
    local groups = Export.groups(notes, true)
    local base = #groups == 1 and groups[1].title or (Export.allBookmarks(notes) and "bookmarks" or "annotations")
    return { { name = Export.fileName(base, o, used, stamp), text = Export.build(notes, o, filter_label), count = #notes } }
end
-- The folder files go to: the chosen one, or koreader/exports.
function Export.defaultDir()
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir() .. "/exports"
end
function Export.dir()
    local d = getSetting("export_dir", nil)
    if type(d) ~= "string" or d == "" then d = Export.defaultDir() end
    return d
end
-- the folder as it is shown on the Export page: "koreader/exports", or the chosen folder
function Export.shortDir()
    local d = Export.dir()
    local ok, DataStorage = pcall(require, "datastorage")
    if ok then
        local data = DataStorage:getDataDir()
        local name = data:match("([^/\\]+)[/\\]*$")
        if not name or name == "." then name = "koreader" end
        if d:sub(1, #data) == data then return name .. d:sub(#data + 1) end
    end
    return d
end
-- the Export row on the Settings page: "Markdown · one file"
function Export.summary()
    local o = Export.options()
    return (o.format == "txt" and _("Plain text") or _("Markdown")) .. " · " .. (o.files == "book" and _("One per book") or _("One file"))
end
-- Writes the files; returns the file (the folder when there are several) and the number of files,
-- or nil and the error (saying how many were written already, for a file per book).
function Export.write(notes, o, filter_label)
    local dir = Export.dir()
    if lfs.attributes(dir, "mode") ~= "directory" then
        local ok, err = lfs.mkdir(dir)
        if not ok and lfs.attributes(dir, "mode") ~= "directory" then return nil, tostring(err or dir) end
    end
    local files = Export.files(notes, o, filter_label, os.date("%Y%m%d-%H%M%S")) -- one time for every file
    local first
    for i = 1, #files do
        local f = files[i]
        local path = dir .. "/" .. f.name
        local file, err = io.open(path, "w")
        local ok = file ~= nil
        if file then
            ok, err = file:write(f.text)
            local cok, cerr = file:close() -- a full card often only fails here
            if ok then ok, err = cok, cerr end
        end
        if not ok then
            local msg = tostring(err or path)
            if i > 1 then msg = msg .. "\n" .. string.format(_("%d of %d files were written."), i - 1, #files) end
            return nil, msg
        end
        first = first or path
    end
    return #files == 1 and first or dir, #files
end

-- The filter of the list in plain words, for the top of an export: the tab, then each filter
-- as its chip says it, with every book, chapter and tag named.
function Export.allBookmarks(notes)
    if #notes == 0 then return false end
    for i = 1, #notes do
        local n = notes[i]
        if not n.bookmark then return false end
    end
    return true
end


-- Module exports
M.Export = Export

return M
