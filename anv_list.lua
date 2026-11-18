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
local item = require("anv_item")
local sheet = require("anv_sheet")
local exportmod = require("anv_export")
local data = require("anv_data")
local pages = require("anv_pages")
local SortState = sort.SortState
local SORT_COMPARATORS = sort.SORT_COMPARATORS
local STYLE_NAMES = sort.STYLE_NAMES
local sortModeLabel = sort.sortModeLabel
local compareByPosition = sort.compareByPosition
local normalizeBookTitle = sort.normalizeBookTitle
local wrapText = text.wrapText
local Pill = atoms.Pill
local TapBox = atoms.TapBox
local newHeaderButton = atoms.newHeaderButton
local NoteItemWidget = item.NoteItemWidget
local getLayoutSignature = item.getLayoutSignature
local getNoteHeight = item.getNoteHeight
local AnnotationSheet = sheet.AnnotationSheet
local Export = exportmod.Export
local normalizeColorStyle = data.normalizeColorStyle
local colorStyleMatches = data.colorStyleMatches
local FilterScreen = pages.FilterScreen
local SS = pages.SS
local ListPicker = pages.ListPicker
local SortPicker = pages.SortPicker
local Page = pages.Page
local AllNotesViewer -- injected by main assembly

local NotesListWidget = InputContainer:extend{
    width = nil, height = nil, notes_list = nil, filtered_notes = nil,
    viewer = nil, current_page = 1, pages = nil, active_filter = nil,
    single_book = false,
    covers_fullscreen = true,
}
-- Sizes that depend on the screen and on whether a filter row is shown.
function NotesListWidget:computeLayout()
    NoteItemWidget.list_single = self.single_book and true or false -- whose sort order decides the dates
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local chips, chips_h = self:buildFilterChips(self.width)
    self.chips_height = chips_h
    self._layout_chips = { w = self.width, widget = chips } -- the header uses these (built once per page)
    self.topbar_height = self.single_book and TOPBAR_BOOK_HEIGHT or TOPBAR_HEIGHT
    self.title_height = self.topbar_height + TABS_HEIGHT + chips_h
    local pag_style = getPaginationStyle()
    -- scrollbar column: its left edge (sb_x) and the middle of the track
    self.sb_x = self.width - SB_STRIP_WIDTH - SB_MARGIN_RIGHT
    self.sb_track_center = self.sb_x + math.floor(SB_STRIP_WIDTH / 2)
    if isScrollbarStyle(pag_style) then
        -- both scrollbar styles draw their controls in the side strip, not in a bottom bar
        self.footer_height = 0
    else
        self.footer_height = FOOTER_BAR_HEIGHT + Size.line.medium
    end
    self.content_height = self.height - self.title_height - self.footer_height - getTopPadding()
    self:setNoteColumn()
end
-- Width given to each annotation, and how far it is pushed right (landscape column). With a
-- scrollbar style the column stops at the scrollbar, unless the list fits on one page (no_scrollbar,
-- set by calculatePages): then there is no scrollbar and the annotations use the full width.
function NotesListWidget:setNoteColumn()
    local no_sb = self.no_scrollbar
    local avail = NoteItemWidget.listAvail(self.width, no_sb)
    self.note_width = NoteItemWidget.columnWidth(avail, self.width, self.height)
    self.note_x_offset = math.floor((avail - self.note_width) / 2) + NoteItemWidget.scrollInset(no_sb)
end
function NotesListWidget:init()
    NotesListWidget._current = self
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    
    self:computeLayout()
    self:syncSortTab()
    self:applyFilter()
    -- A book (or library) with bookmarks but no highlights or notes opens on the Bookmarks tab
    -- instead of an empty list. Only when it opens: init runs again on rotation, and then the
    -- tab you chose stays.
    local first_init = not self._opened
    self._opened = true
    if first_init and not (self.active_filter and self.active_filter.notes_presence)
            and self.tab_totals.all == 0 and self.tab_totals.bookmarks > 0 then
        self.active_filter = self.active_filter or {}
        self.active_filter.notes_presence = "bookmarks"
        self:syncSortTab()
        self:applyFilter()
    end
    self:calculatePages()
    if Device:hasKeys() then
        self.key_events.GotoPrevPage = { { Input.group.PgBack } }
        self.key_events.GotoNextPage = { { Input.group.PgFwd } }
        self.key_events.Close = { { Input.group.Back } }  
    end
    -- swipes follow the plugin's own "Swipe to turn pages" setting; updatePage sets them
    self.ges_events = {}
    
    self:updatePage()
    self.initial_update = true
end
-- A search that was cleared leaves no "Exact Phrase" / "Case-Sensitive" behind: they would come
-- back with the next search, and end up in saved filters.
NotesListWidget.SEARCH_FIELDS = { "search_any", "search_highlight", "search_highlight_exclude", "search_note", "search_note_exclude" }
function NotesListWidget.dropStaleSearchOptions(af)
    if type(af) ~= "table" then return end
    for i = 1, #NotesListWidget.SEARCH_FIELDS do
        local k = NotesListWidget.SEARCH_FIELDS[i]
        if af[k] == nil or af[k] == "" then
            af[k], af[k .. "_mode"], af[k .. "_case"] = nil, nil, nil
        end
    end
end
-- Filters on the book's metadata: authors, series and language. Each has an "only these" key and
-- a "hide these" key (kind .. "_exclude"), as books and tags. A book without a value counts as ""
-- (shown as "None").
NotesListWidget.META_KINDS = { "authors", "series", "languages" }
function NotesListWidget.metaValues(note, kind)
    if kind == "authors" then
        local out = {}
        local a = note.book_authors
        if type(a) == "string" and a ~= "Unknown" then
            for name in a:gmatch("[^\n]+") do
                name = name:match("^%s*(.-)%s*$")
                if name ~= "" then out[#out + 1] = name end
            end
        end
        if #out == 0 then out[1] = "" end
        return out
    end
    local v
    if kind == "series" then v = note.book_series else v = note.book_language end
    return { type(v) == "string" and v or "" }
end
function NotesListWidget.metaLabel(v) return v == "" and _("None") or v end
-- whether a note passes the author / series / language filters
function NotesListWidget.metaMatches(af, note)
    for i = 1, #NotesListWidget.META_KINDS do
        local kind = NotesListWidget.META_KINDS[i]
        local inc, exc = af[kind], af[kind .. "_exclude"]
        local has_inc, has_exc = type(inc) == "table" and next(inc) ~= nil, type(exc) == "table" and next(exc) ~= nil
        if has_inc or has_exc then
            local vals, any = NotesListWidget.metaValues(note, kind), false
            for k = 1, #vals do
                if has_exc and exc[vals[k]] then return false end
                if has_inc and inc[vals[k]] then any = true end
            end
            if has_inc and not any then return false end
        end
    end
    return true
end
-- The chapter filter names chapters of the books chosen when it was set ("Chapter 1" of book A):
-- with other books it would pick their chapters of that name, so it goes when the books change.
function NotesListWidget.booksChanged(af)
    if type(af) ~= "table" then return end
    af.chapters, af.chapters_exclude = nil, nil
end
function NotesListWidget:applyFilter()
    local function textMatches(raw, query, mode, case_sensitive)
        local text = case_sensitive and raw or NoteItemWidget.lower(raw)
        local q    = case_sensitive and query or NoteItemWidget.lower(query)
        if mode == "phrase" then
            return text:find(q, 1, true) ~= nil
        elseif mode == "any" then
            for word in q:gmatch("%S+") do
                if text:find(word, 1, true) then return true end
            end
            return false
        else -- "all"
            for word in q:gmatch("%S+") do
                if not text:find(word, 1, true) then return false end
            end
            return true
        end
    end
    normalizeColorStyle(self.active_filter)
    NotesListWidget.dropStaleSearchOptions(self.active_filter)
    -- the lowered texts are kept between searches; a very large library starts afresh now and then
    if NoteItemWidget._lower_n > 100000 then NoteItemWidget._lower, NoteItemWidget._lower_n = {}, 0 end
    self.filtered_notes = {}
    -- counts: what each tab shows with the filters; totals: what it would show without them
    local counts = { all = 0, highlights = 0, notes = 0, bookmarks = 0 }
    local totals = { all = 0, highlights = 0, notes = 0, bookmarks = 0 }
    for _, note in ipairs(self.notes_list) do
        local match = true
        local is_bm = note.bookmark == true
        if self.active_filter then
            local af = self.active_filter
            -- Books include / exclude
            if af.books and next(af.books) then
                match = af.books[note.book_title] == true
            end
            if match and af.books_exclude and next(af.books_exclude) then
                if af.books_exclude[note.book_title] then match = false end
            end
            -- Authors, series, language
            if match then match = NotesListWidget.metaMatches(af, note) end
            -- Tags include / exclude
            if match and af.tags and next(af.tags) then
                local nw = NoteWrapper:new(note)
                local found = false
                for _, tag in ipairs(nw:getTags()) do
                    if af.tags[tag] then found = true; break end
                end
                match = found
            end
            if match and af.tags_exclude and next(af.tags_exclude) then
                local nw = NoteWrapper:new(note)
                for _, tag in ipairs(nw:getTags()) do
                    if af.tags_exclude[tag] then match = false; break end
                end
            end
            -- Chapters include / exclude
            if match and af.chapters and next(af.chapters) then
                match = note.chapter and af.chapters[note.chapter] == true
            end
            if match and af.chapters_exclude and next(af.chapters_exclude) then
                if note.chapter and af.chapters_exclude[note.chapter] then match = false end
            end
            -- Colour / style (bookmarks have neither, so these don't apply to them)
            if match and af.cs and next(af.cs) and not is_bm then
                match = colorStyleMatches(af, note)
            end
            -- Highlight text include / exclude (bookmarks have no highlighted text)
            if match and af.search_highlight and af.search_highlight ~= "" and not is_bm then
                match = textMatches(note.highlighted_text or "", af.search_highlight,
                    af.search_highlight_mode or "all", af.search_highlight_case == true)
            end
            if match and af.search_highlight_exclude and af.search_highlight_exclude ~= "" then
                if textMatches(note.highlighted_text or "", af.search_highlight_exclude,
                    af.search_highlight_exclude_mode or "all", af.search_highlight_exclude_case == true) then
                    match = false
                end
            end
            -- Note text include / exclude
            if match and af.search_note and af.search_note ~= "" then
                match = textMatches(note.user_note or "", af.search_note,
                    af.search_note_mode or "all", af.search_note_case == true)
            end
            if match and af.search_note_exclude and af.search_note_exclude ~= "" then
                if textMatches(note.user_note or "", af.search_note_exclude,
                    af.search_note_exclude_mode or "all", af.search_note_exclude_case == true) then
                    match = false
                end
            end
            -- Search box: highlight or note text
            if match and af.search_any and af.search_any ~= "" then
                local case = af.search_any_case == true
                match = textMatches(note.highlighted_text or "", af.search_any, "all", case)
                    or textMatches(note.user_note or "", af.search_any, "all", case)
            end
        end
        -- Notes presence (the tab) last, so the tab counts can be taken before it.
        -- Bookmarks only show in their own tab; All, Highlights and Notes leave them out.
        local has_note = note.user_note ~= nil and note.user_note ~= ""
        local tab = is_bm and "bookmarks" or (has_note and "notes" or "highlights")
        totals[tab] = totals[tab] + 1
        if not is_bm then totals.all = totals.all + 1 end
        if match then
            counts[tab] = counts[tab] + 1
            if not is_bm then counts.all = counts.all + 1 end
            local presence = self.active_filter and self.active_filter.notes_presence
            if presence == "bookmarks" then
                match = is_bm
            elseif is_bm then
                match = false
            elseif presence == "only" then
                match = has_note
            elseif presence == "exclude" then
                match = not has_note
            end
        end
        if match then table.insert(self.filtered_notes, note) end
    end
    self.tab_counts = counts
    self.tab_totals = totals
end
-- The Bookmarks tab keeps its own order: when the list moves onto or off that tab, the order of
-- that tab is used (and the list sorted again when it differs).
function NotesListWidget:syncSortTab()
    local bm = self:tabKey() == "bookmarks"
    if (SortState.bm_tab or false) == bm then return end
    local before = SortState.get(self.single_book)
    SortState.bm_tab = bm
    if SortState.get(self.single_book) ~= before then self:applySort() end
end
-- Key of the open tab in tab_counts / tab_totals.
function NotesListWidget:tabKey()
    local presence = self.active_filter and self.active_filter.notes_presence
    return ({ only = "notes", exclude = "highlights", bookmarks = "bookmarks" })[presence or ""] or "all"
end
-- Scrollbar marks follow the sort order: a mark where the group changes. Books (or authors) when
-- sorted by book / author / file, months when sorted by date, chapters in one book sorted by location.
-- levels: the parsed order (paginate passes it, so it isn't parsed again for every annotation)
function NotesListWidget.markKey(note, single, levels)
    levels = levels or SortState.view(SortState.get(single), single) -- the order the list really has
    local by = levels[1].key
    if single then
        for _, l in ipairs(levels) do
            if l.key == "pos" or l.key == "chapter" then return note.chapter or "" end
        end
        return (note.datetime or ""):sub(1, 7)
    end
    if by == "date" then return (note.datetime or ""):sub(1, 7) end
    if by == "author" then return note.book_authors or "" end
    return note.book_title or ""
end
-- Splits the list into pages. With a scrollbar style it first measures at the width beside the
-- scrollbar; when everything fits on one page there is no scrollbar, so it measures again at the
-- full width (wider annotations are never taller, so it still fits on one page).
function NotesListWidget:calculatePages()
    local sb = isScrollbarStyle()
    if sb and self.no_scrollbar then self.no_scrollbar = nil; self:setNoteColumn() end
    self:paginate()
    if sb and self.total_pages <= 1 then
        self.no_scrollbar = true
        self:setNoteColumn()
        self:paginate()
        if self.total_pages > 1 then -- should not happen, but then the scrollbar is needed after all
            self.no_scrollbar = nil
            self:setNoteColumn()
            self:paginate()
        end
    end
end
function NotesListWidget:paginate()
    self.pages = {}
    local mark_levels = SortState.view(SortState.get(self.single_book), self.single_book)
    local current_page_notes, current_height = {}, 0
    
    local available_content_height = self.content_height
    -- An annotation that would end within a few pixels of the bottom goes to the next page
    -- (and shows here faded and cut off), so a page never ends flush with the screen edge.
    local end_gap = 3
    local effective_content_height = available_content_height - end_gap
    
    local dedup_prev_title = nil
    local dedup_prev_info_key = nil
    local dedup_fields = getDedupInfoFields()
    local note_width = self.note_width
    -- pages on which a new group starts (book, author, month or chapter, by sort order), for the scrollbar marks
    self.book_start_pages = {}
    local prev_mark_key
    NoteItemWidget.measure_hide_chapter = (self.single_book and NoteItemWidget.showHeadings()) and true or false
    local layout_sig = getLayoutSignature(note_width)
    local prev_chapter = nil
    for i, note in ipairs(self.filtered_notes) do
        local is_first_on_page = (#current_page_notes == 0)
        local skip_title, skip_info = getHeaderSkips(note, is_first_on_page, dedup_prev_title, dedup_prev_info_key, dedup_fields)
        if self.single_book then skip_title = true end
        local item_height = getNoteHeight(note, note_width, skip_title, skip_info, layout_sig)
        local has_ch = self.single_book and NoteItemWidget.showHeadings() and note.chapter and note.chapter ~= ""
        if has_ch and ((is_first_on_page and NoteItemWidget.repeatChapter()) or note.chapter ~= prev_chapter) then item_height = item_height + NoteItemWidget.headingHeight(note.chapter, note_width) end
        local spacing = 0
        if not is_first_on_page then
            spacing = NoteItemWidget.gapAbove(note, skip_title)
        end
        local next_height = current_height + spacing + item_height
        if next_height <= effective_content_height then
            current_height = next_height
            table.insert(current_page_notes, i)
        else
            if #current_page_notes > 0 then table.insert(self.pages, current_page_notes) end
            -- Re-measure as first on the new page: the repeat options may bring headers back
            current_page_notes = {i}
            local st, si = getHeaderSkips(note, true, dedup_prev_title, dedup_prev_info_key, dedup_fields)
            if self.single_book then st = true end
            -- as updatePage draws it: the heading at the top of a page only when the chapter
            -- changes here, or when it is repeated on each page
            local heading = has_ch and (NoteItemWidget.repeatChapter() or note.chapter ~= prev_chapter)
            current_height = getNoteHeight(note, note_width, st, si, layout_sig) + (heading and NoteItemWidget.headingHeight(note.chapter, note_width) or 0)
        end
        prev_chapter = note.chapter
        local mark_key = NotesListWidget.markKey(note, self.single_book, mark_levels)
        if i > 1 and mark_key ~= prev_mark_key then
            self.book_start_pages[#self.pages + 1] = true
        end
        prev_mark_key = mark_key
        dedup_prev_title = note.book_title
        dedup_prev_info_key = getNoteInfoKey(note, dedup_fields)
    end
    if #current_page_notes > 0 then table.insert(self.pages, current_page_notes) end
    if #self.pages == 0 then self.pages = {{}} end
    self.total_pages = #self.pages
end
-- The Prev / Next bar: "|‹ ‹ Prev" left, the label ("1 / 4") in the middle, "Next › ›|" right.
-- Holding Prev / Next jumps to the first / last. Used under the list, on paged menu pages and in
-- the bookmark sheet. o = { width, label, has_prev, has_next, first, prev, next, last, side }
function NotesListWidget.navBar(o)
    local cl, cr, cf, clast = "chevron.left", "chevron.right", "chevron.first", "chevron.last"
    if BD.mirroredUILayout() then cl, cr, cf, clast = cr, cl, clast, cf end
    local face = Font:getFace("cfont", 13)
    local icon = Screen:scaleBySize(20)
    local function pageButton(text, icon_name, icon_first, enabled, cb, hold_cb)
        local tw = TextWidget:new{ text = text, face = face, bold = enabled, fgcolor = enabled and COLORS.ink or COLORS.disabled }
        local iw = IconWidget:new{ icon = icon_name, width = icon, height = icon, dim = not enabled }
        local row = icon_first and HorizontalGroup:new{ align = "center", iw, HorizontalSpan:new{ width = Screen:scaleBySize(4) }, tw }
            or HorizontalGroup:new{ align = "center", tw, HorizontalSpan:new{ width = Screen:scaleBySize(4) }, iw }
        return TapBox:new{ CenterContainer:new{ dimen = Geom:new{ w = row:getSize().w + Screen:scaleBySize(20), h = FOOTER_BAR_HEIGHT }, row },
            callback = function() if enabled then cb() end end,
            hold_callback = function() if enabled then hold_cb() end end }
    end
    -- first / last: icon only, next to Prev / Next
    local function jumpButton(icon_name, enabled, cb)
        local iw = IconWidget:new{ icon = icon_name, width = icon, height = icon, dim = not enabled }
        return TapBox:new{ CenterContainer:new{ dimen = Geom:new{ w = icon + Screen:scaleBySize(20), h = FOOTER_BAR_HEIGHT }, iw },
            callback = function() if enabled then cb() end end }
    end
    local bd = Geom:new{ w = o.width, h = FOOTER_BAR_HEIGHT }
    local side = o.side or 0
    return OverlapGroup:new{ dimen = bd, allow_mirroring = false,
        LeftContainer:new{ dimen = bd, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
            jumpButton(cf, o.has_prev, o.first),
            pageButton(_("Prev"), cl, true, o.has_prev, o.prev, o.first) } },
        CenterContainer:new{ dimen = bd, TextWidget:new{ text = o.label, face = face, bold = true } },
        RightContainer:new{ dimen = bd, HorizontalGroup:new{
            pageButton(_("Next"), cr, false, o.has_next, o.next, o.last),
            jumpButton(clast, o.has_next, o.last),
            HorizontalSpan:new{ width = side } } } }
end
-- The scrollbar strip on the right of the list: one class, made once; each page turn makes an
-- instance with that page's numbers (strip_x, track_h, marks, ...).
NotesListWidget.ScrollStrip = InputContainer:extend{}
function NotesListWidget.ScrollStrip:init()
    self.dimen = Geom:new{ x = self.strip_x, y = self.strip_y, w = self.strip_w, h = self.strip_h }
    self.ges_events = { TapStrip = { GestureRange:new{ ges = "tap",
        range = Geom:new{ x = self.strip_x, y = self.strip_y, w = self.strip_w + SB_MARGIN_RIGHT, h = self.strip_h } } } }
end
function NotesListWidget.ScrollStrip:getSize() return Geom:new{ w = self.strip_w, h = self.strip_h } end
function NotesListWidget.ScrollStrip:pageY(p) -- top of the thumb when page p is shown
    return math.floor((p - 1) / (self.total - 1) * self.travel + 0.5)
end
function NotesListWidget.ScrollStrip:onTapStrip(_, ges)
    if not ges or not ges.pos then return end
    local list, btn_h, track_y, track_h = self.list, self.btn_h, self.track_y, self.track_h
    local y = ges.pos.y - self.strip_y
    if self.has_chevrons and y < btn_h then
        if self.up_enabled then list:onGotoPrevPage() end
    elseif self.has_chevrons and y >= self.strip_h - btn_h then
        if self.dn_enabled then list:onGotoNextPage() end
    elseif y >= track_y and y < track_y + track_h then
        local rel = (y - track_y) / track_h
        local page = math.max(1, math.min(self.total, math.ceil(rel * self.total)))
        if page ~= list.current_page then
            list.current_page = page
            list:updatePage()
        end
    end
    return true
end
function NotesListWidget.ScrollStrip:paintTo(bb, x, y)
    local strip_w, icon_size, track_h, thumb_h = self.strip_w, self.icon_size, self.track_h, self.thumb_h
    -- thumb and track positions exactly as before the redesign
    local thumb_x = x + math.floor((strip_w - SB_THUMB_WIDTH) / 2)
    local track_x = thumb_x + math.floor((SB_THUMB_WIDTH - SB_TRACK_WIDTH) / 2)
    local icon_x = x + math.floor((strip_w - icon_size) / 2)
    if self.up_icon then self.up_icon:paintTo(bb, icon_x, y) end
    local ty = y + self.track_y
    -- a very small screen or big chevrons: no room for the thumb, so no track either
    local room = track_h >= thumb_h
    if room then bb:paintRect(track_x, ty, SB_TRACK_WIDTH, track_h, COLORS.ink) end
    -- same overhang on both sides of the track, so the notch is centred on it
    local mark_x = track_x - SB_MARK_OVERHANG
    local mark_w = SB_TRACK_WIDTH + SB_MARK_OVERHANG * 2
    local marks = room and self.marks or {}
    for i = 1, #marks do
        local p = marks[i]
        if p > 1 then -- the top of the track already marks page 1
            bb:paintRect(mark_x, ty + self:pageY(p) + math.floor(thumb_h / 2), mark_w, SB_MARK_HEIGHT, COLORS.ink)
        end
    end
    if room then
        local thumb_y = ty + self:pageY(self.list.current_page)
        local radius = math.floor(SB_THUMB_WIDTH / 2)
        bb:paintRoundedRect(thumb_x, thumb_y, SB_THUMB_WIDTH, thumb_h, BlitBuffer.COLOR_WHITE, radius)
        -- Size.border.default = 1px at 160dpi, scaled up on denser screens like the thumb itself
        bb:paintBorder(thumb_x, thumb_y, SB_THUMB_WIDTH, thumb_h, Size.border.default, BlitBuffer.COLOR_BLACK, radius)
    end
    local lw = self.page_label:getSize().w
    self.page_label:paintTo(bb, track_x - math.floor(lw / 2), ty + track_h + Screen:scaleBySize(6))
    if self.dn_icon then self.dn_icon:paintTo(bb, icon_x, y + self.strip_h - icon_size) end
end
function NotesListWidget:createFooter()
    local style = getPaginationStyle()

    if isScrollbarStyle(style) then
        -- Slim scrollbar in a strip on the right: outline thumb, page number underneath,
        -- marks where books start; "Scrollbar + Buttons" adds up/down arrows at the ends.
        if self.total_pages <= 1 then return VerticalGroup:new{} end
        local self_ref = self
        local has_chevrons = (style == "scrollbar_chevrons")
        local strip_w = SB_STRIP_WIDTH
        local strip_x = self.sb_x
        local strip_y = self.title_height + SB_MARGIN_V_TOP
        local strip_h = self.height - strip_y - SB_MARGIN_V_BOTTOM
        local btn_h = has_chevrons and strip_w or 0 -- square arrow buttons, as before
        local page_label = TextWidget:new{
            text = string.format("%d/%d", self.current_page, self.total_pages),
            face = Font:getFace("cfont", 12), bold = true,
            fgcolor = COLORS.muted,
            max_width = strip_w + SB_MARGIN_RIGHT,
        }
        local label_h = page_label:getSize().h + Screen:scaleBySize(6)
        local track_y = btn_h                         -- relative to strip_y
        local track_h = strip_h - btn_h * 2 - label_h
        local total = self.total_pages
        local thumb_h = math.max(Screen:scaleBySize(16), math.floor(track_h / total))
        local travel = track_h - thumb_h
        local up_enabled = self.current_page > 1
        local dn_enabled = self.current_page < total
        local icon_size = Screen:scaleBySize(32)
        local up_icon, dn_icon
        if has_chevrons then
            up_icon = IconWidget:new{ icon = "chevron.up", width = icon_size, height = icon_size, dim = not up_enabled }
            dn_icon = IconWidget:new{ icon = "chevron.up", rotation_angle = 180, width = icon_size, height = icon_size, dim = not dn_enabled }
        end
        local marks = {}
        if getScrollbarBookMarks() then
            for p in pairs(self.book_start_pages or {}) do table.insert(marks, p) end
        end
        local strip = NotesListWidget.ScrollStrip:new{ list = self_ref, strip_x = strip_x, strip_y = strip_y,
            strip_w = strip_w, strip_h = strip_h, btn_h = btn_h, has_chevrons = has_chevrons, up_enabled = up_enabled,
            dn_enabled = dn_enabled, track_y = track_y, track_h = track_h, total = total, thumb_h = thumb_h,
            travel = travel, icon_size = icon_size, up_icon = up_icon, dn_icon = dn_icon, marks = marks, page_label = page_label }
        return VerticalGroup:new{
            VerticalSpan:new{ width = strip_y },
            HorizontalGroup:new{ HorizontalSpan:new{ width = strip_x }, strip },
        }
    else
        -- Bottom bar as in the mockup: thin line on top, "‹ Prev" left, "1 / 4" centred,
        -- "Next ›" right, with first / last page buttons on the outside (holding Prev / Next
        -- also jumps to the first / last page).
        local function goFirst() self.current_page = 1; self:updatePage() end
        local function goLast() self.current_page = self.total_pages; self:updatePage() end
        local bar = NotesListWidget.navBar{
            width = self.width, label = string.format("%d / %d", self.current_page, self.total_pages),
            has_prev = self.current_page > 1, has_next = self.current_page < self.total_pages,
            first = goFirst, prev = function() self:onGotoPrevPage() end,
            next = function() self:onGotoNextPage() end, last = goLast,
            side = Screen:scaleBySize(12) - Screen:scaleBySize(10), -- mockup padding minus the button's own
        }
        return BottomContainer:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            FrameContainer:new{
                width = self.width, padding = 0, margin = 0, bordersize = 0,
                background = BlitBuffer.COLOR_WHITE,
                VerticalGroup:new{
                    LineWidget:new{ dimen = Geom:new{ w = self.width, h = Size.line.medium }, background = COLORS.line },
                    bar,
                },
            },
        }
    end
end
-- Label for the sort button in the tab row, e.g. "Newest first" or "Book · A to Z (by Date)".
local function colorName(key) return NoteItemWidget.colorLabel(key) end
-- full: every name (sorted), for the filter line of an export; otherwise "3 books" when there are several
local function setLabel(set, many, full)
    local keys = {}
    for k in pairs(set) do table.insert(keys, k) end
    if #keys == 1 then return keys[1] end
    if full then table.sort(keys); return table.concat(keys, ", ") end
    return string.format(many, #keys)
end
local CHIP_HEIGHT = Screen:scaleBySize(32)
local CHIP_GAP = Screen:scaleBySize(8)
local CHIPS_PAD_TOP, CHIPS_PAD_BOTTOM = Screen:scaleBySize(6), Screen:scaleBySize(6)

-- full: chips name every book, chapter and tag (the export's filter line)
function NotesListWidget:getFilterChips(full)
    local af = self.active_filter or {}
    local chips = {}
    -- prefix: shown before the colour dot ("Hide ● Yellow")
    local function add(label, clear, colors, prefix)
        table.insert(chips, { label = label, clear = clear, colors = colors, prefix = prefix })
    end
    local function quoted(t) return "“" .. t .. "”" end
    normalizeColorStyle(af)
    if af.cs and next(af.cs) then
        local keys = {}
        for k in pairs(af.cs) do table.insert(keys, k) end
        table.sort(keys)
        local prefix = af.cs_exclude and _("Hide") or nil
        for _i, k in ipairs(keys) do
            local t, v = k:match("^(%a+):(.+)$")
            local function clear() af.cs[k] = nil; if not next(af.cs) then af.cs, af.cs_exclude = nil, nil end end
            if t == "color" then
                add(colorName(v), clear, { v }, prefix)
            else
                add((prefix and (prefix .. " ") or "") .. (STYLE_NAMES[v] or v), clear)
            end
        end
    end
    if af.books and next(af.books) then add(setLabel(af.books, _("%d books"), full), function() af.books = nil; NotesListWidget.booksChanged(af) end) end
    if af.books_exclude and next(af.books_exclude) then
        add(_("Hide") .. " " .. setLabel(af.books_exclude, _("%d books"), full), function() af.books_exclude = nil; NotesListWidget.booksChanged(af) end)
    end
    do
        local many = { authors = _("%d authors"), series = _("%d series"), languages = _("%d languages") }
        for i = 1, #NotesListWidget.META_KINDS do
            local kind = NotesListWidget.META_KINDS[i]
            local pair = { kind, kind .. "_exclude" }
            for pi = 1, 2 do
                local k = pair[pi]
                if type(af[k]) == "table" and next(af[k]) then
                    local named = {} -- "" is "None"
                    for v in pairs(af[k]) do named[NotesListWidget.metaLabel(v)] = true end
                    local label = setLabel(named, many[kind], full)
                    if k ~= kind then label = _("Hide") .. " " .. label end
                    add(label, function() af[k] = nil end)
                end
            end
        end
    end
    if af.chapters and next(af.chapters) then add(setLabel(af.chapters, _("%d chapters"), full), function() af.chapters = nil end) end
    if af.chapters_exclude and next(af.chapters_exclude) then
        add(_("Hide") .. " " .. setLabel(af.chapters_exclude, _("%d chapters"), full), function() af.chapters_exclude = nil end)
    end
    if af.tags and next(af.tags) then add(setLabel(af.tags, _("%d tags"), full), function() af.tags = nil end) end
    if af.tags_exclude and next(af.tags_exclude) then
        add(_("Hide") .. " " .. setLabel(af.tags_exclude, _("%d tags"), full), function() af.tags_exclude = nil end)
    end
    if af.search_any and af.search_any ~= "" then add(quoted(af.search_any), function() af.search_any = nil end) end
    if af.search_highlight and af.search_highlight ~= "" then
        add(_("Highlight:") .. " " .. quoted(af.search_highlight), function() af.search_highlight = nil end)
    end
    if af.search_highlight_exclude and af.search_highlight_exclude ~= "" then
        add(_("Highlight not:") .. " " .. quoted(af.search_highlight_exclude), function() af.search_highlight_exclude = nil end)
    end
    if af.search_note and af.search_note ~= "" then
        add(_("Note:") .. " " .. quoted(af.search_note), function() af.search_note = nil end)
    end
    if af.search_note_exclude and af.search_note_exclude ~= "" then
        add(_("Note not:") .. " " .. quoted(af.search_note_exclude), function() af.search_note_exclude = nil end)
    end
    return chips
end

-- Builds the chips area for width w. Returns the widget (nil when no filters) and its height.
function NotesListWidget:buildFilterChips(w)
    local chips = self:getFilterChips()
    if #chips == 0 then return nil, 0 end
    local side = Screen:scaleBySize(24)
    local face = Font:getFace("cfont", 13)
    local small = Font:getFace("cfont", 12)
    local count_w = TextWidget:new{ text = string.format(_("%d of %d"), 9999, 9999), face = small }:getSize().w + Screen:scaleBySize(8)
    local avail = w - side * 2
    local items = {}
    for _i, c in ipairs(chips) do
        local content = HorizontalGroup:new{ align = "center" }
        if c.prefix then
            table.insert(content, TextWidget:new{ text = c.prefix, face = face, fgcolor = BlitBuffer.COLOR_WHITE })
            table.insert(content, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
        end
        if c.colors then
            for _j, key in ipairs(c.colors) do
                table.insert(content, Pill:new{ width = Screen:scaleBySize(10), height = Screen:scaleBySize(10), border = 0, true_color = true,
                    fill = key == "gray" and BlitBuffer.COLOR_GRAY or getHighlightColor(key) })
                table.insert(content, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
            end
        end
        table.insert(content, TextWidget:new{ text = c.label, face = face, fgcolor = BlitBuffer.COLOR_WHITE,
            max_width = math.floor(avail * 0.6) })
        table.insert(content, HorizontalSpan:new{ width = Screen:scaleBySize(4) })
        -- a white ✕ on the black chip: the font character, centred (the icon showed as a white square on e-ink)
        table.insert(content, NoteItemWidget.TextMark:new{ icon = "close", size = Screen:scaleBySize(14) })
        local chip_w = content:getSize().w + Screen:scaleBySize(20)
        table.insert(items, { w = chip_w, widget = TapBox:new{
            Pill:new{ width = chip_w, height = CHIP_HEIGHT, fill = BlitBuffer.COLOR_BLACK, border = 0, content },
            callback = function()
                c.clear()
                self.current_page = 1
                self:refresh()
            end,
        } })
    end
    local clear = TextWidget:new{ text = _("Clear all"), face = face }
    local clear_sz = clear:getSize()
    local clear_w = clear_sz.w + Screen:scaleBySize(16)
    table.insert(items, { w = clear_w, widget = TapBox:new{
        CenterContainer:new{ dimen = Geom:new{ w = clear_w, h = CHIP_HEIGHT }, VerticalGroup:new{ clear,
            LineWidget:new{ dimen = Geom:new{ w = clear_sz.w, h = Size.line.medium }, background = BlitBuffer.COLOR_BLACK } } },
        callback = function() self:clearFilters() end,
    } })
    -- flow into rows; the first row keeps room for the count on the right
    local rows = VerticalGroup:new{ align = "left" }
    local row, row_w, limit = HorizontalGroup:new{ align = "center" }, 0, avail - count_w
    local n_rows = 1
    for _i, it in ipairs(items) do
        if row_w > 0 and row_w + CHIP_GAP + it.w > limit then
            table.insert(rows, row)
            table.insert(rows, VerticalSpan:new{ width = CHIP_GAP })
            row, row_w, limit = HorizontalGroup:new{ align = "center" }, 0, avail
            n_rows = n_rows + 1
        end
        if row_w > 0 then table.insert(row, HorizontalSpan:new{ width = CHIP_GAP }); row_w = row_w + CHIP_GAP end
        table.insert(row, it.widget)
        row_w = row_w + it.w
    end
    table.insert(rows, row)
    local h = CHIPS_PAD_TOP + n_rows * CHIP_HEIGHT + (n_rows - 1) * CHIP_GAP + CHIPS_PAD_BOTTOM + Size.line.thin
    local count = TextWidget:new{
        text = string.format(_("%d of %d"), #(self.filtered_notes or {}),
            self.tab_totals and self.tab_totals[self:tabKey()] or #(self.notes_list or {})),
        face = small, fgcolor = COLORS.muted,
    }
    local first_row = Geom:new{ w = avail, h = CHIP_HEIGHT }
    local area = VerticalGroup:new{ align = "left",
        VerticalSpan:new{ width = CHIPS_PAD_TOP },
        HorizontalGroup:new{ HorizontalSpan:new{ width = side },
            OverlapGroup:new{ dimen = Geom:new{ w = avail, h = rows:getSize().h }, allow_mirroring = false,
                rows,
                RightContainer:new{ dimen = first_row, count },
            },
        },
        VerticalSpan:new{ width = CHIPS_PAD_BOTTOM },
        HorizontalGroup:new{ HorizontalSpan:new{ width = side },
            LineWidget:new{ dimen = Geom:new{ w = avail, h = Size.line.thin }, background = COLORS.line } },
    }
    return area, h
end

-- Top bar, tab row and (when filters are on) the active-filter row. Height is self.title_height.
function NotesListWidget:buildHeader()
    local w = self.width
    local side = Screen:scaleBySize(8)
    local h_pad = getHMargin() + Size.padding.default
    if h_pad > Screen:scaleBySize(24) then h_pad = Screen:scaleBySize(24) end
    local header = VerticalGroup:new{ align = "left" }

    -- 1. top bar
    local title
    local bar_h = self.topbar_height or TOPBAR_HEIGHT
    if self.single_book then
        -- one book: its title, and the author underneath (no counts: the tabs show those)
        local first = self.notes_list and self.notes_list[1] or {}
        local book_title = self.book_title or first.book_title or _("Annotations")
        local authors = first.book_authors and NoteWrapper:new(first):getDisplayAuthors()
        local sub = (authors and authors ~= "" and authors ~= "Unknown") and authors or nil
        local max_w = math.floor(w * 0.55)
        local t = TextWidget:new{ text = book_title, face = getFaceOr(SERIF_FONT, 19, "cfont"), bold = true, max_width = max_w }
        local st = TextWidget:new{ text = sub or "", face = Font:getFace("cfont", 14), fgcolor = COLORS.muted, max_width = max_w }
        -- Text boxes include room for descenders and line gap; placing the second line from
        -- the title's baseline keeps the two lines close together, like in the mockup.
        local cap = math.floor(Screen:scaleBySize(14) * 0.72)
        local sub_y = t:getBaseline() + Screen:scaleBySize(5) - (st:getBaseline() - cap)
        local tsz, ssz = t:getSize(), st:getSize()
        st.overlap_offset = { 0, sub_y }
        title = sub and OverlapGroup:new{ allow_mirroring = false,
            dimen = Geom:new{ w = math.max(tsz.w, ssz.w), h = math.max(tsz.h, sub_y + ssz.h) }, t, st } or t
    else
        title = TextWidget:new{
            text = _("Annotations"), face = getFaceOr(SERIF_FONT, 21, "cfont"), bold = true,
            max_width = math.floor(w / 2),
        }
    end
    local right = HorizontalGroup:new{ align = "center" }
    table.insert(right, newHeaderButton("appbar.search", function() self:showSearchDialog() end, self))
    do -- the filter button is always there (the badge shows how many filters are on)
        local fbtn = newHeaderButton("appbar.settings", function() self:showFilterMenu() end, self,
            pluginIcon("appbar.filter"))
        local n = #self:getFilterChips()
        if n > 0 then
            -- small black badge with the number of active filters, top right of the icon
            local d = Screen:scaleBySize(16)
            local num = TextWidget:new{ text = tostring(n), face = Font:getFace("cfont", 10), bold = true, fgcolor = BlitBuffer.COLOR_WHITE }
            local badge = Pill:new{ width = d, height = d, fill = BlitBuffer.COLOR_BLACK, border = 0, num }
            local bs = fbtn:getSize()
            badge.overlap_offset = { bs.w - d - Screen:scaleBySize(4), Screen:scaleBySize(4) }
            fbtn = OverlapGroup:new{ dimen = Geom:new{ w = bs.w, h = bs.h }, allow_mirroring = false, fbtn, badge }
        end
        table.insert(right, fbtn)
    end
    table.insert(right, newHeaderButton("close", function() self:onClose() end, self, nil, false))
    table.insert(right, HorizontalSpan:new{ width = side })
    local bar_dimen = Geom:new{ w = w, h = bar_h }
    table.insert(header, OverlapGroup:new{
        dimen = bar_dimen, allow_mirroring = false,
        LeftContainer:new{ dimen = bar_dimen, HorizontalGroup:new{
            align = "center",
            HorizontalSpan:new{ width = side },
            newHeaderButton("appbar.menu", function() self:showMainMenu() end, self),
            -- same space between icon and title as between the screen edge and the icon
            HorizontalSpan:new{ width = side },
            title,
        } },
        RightContainer:new{ dimen = bar_dimen, right },
    })

    -- 2. tabs: All / Highlights (no note) / Notes / Bookmarks, plus the sort button.
    local counts = self.tab_counts or { all = 0, highlights = 0, notes = 0, bookmarks = 0 }
    local presence = self.active_filter and self.active_filter.notes_presence
    local show_counts = getShowTotalNotes()
    local tab_face = Font:getFace("cfont", 15)
    local line_h = Size.line.thin
    local underline_h = Screen:scaleBySize(2)
    local row_h = TABS_HEIGHT - line_h
    local tabs = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = h_pad } }
    local tab_list = {
        { key = nil,       label = _("All"),        n = counts.all },
        { key = "exclude", label = _("Highlights"), n = counts.highlights },
        { key = "only",    label = _("Notes"),      n = counts.notes },
        { key = "bookmarks", label = _("Bookmarks"), n = counts.bookmarks or 0 },
    }
    for i, tab in ipairs(tab_list) do
        local active = (presence == tab.key)
        local text = tab.label .. (show_counts and ("  " .. tab.n) or "")
        local tw = TextWidget:new{
            text = text, face = tab_face, bold = active,
            fgcolor = active and COLORS.ink or COLORS.muted,
        }
        -- every tab is as wide as its bold (chosen) text, so nothing moves when another tab is chosen
        local tab_w = active and tw:getSize().w or TextWidget:new{ text = text, face = tab_face, bold = true }:getSize().w
        local box = VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = tab_w, h = row_h - underline_h }, tw },
            active and LineWidget:new{ dimen = Geom:new{ w = tab_w, h = underline_h }, background = BlitBuffer.COLOR_BLACK }
                or VerticalSpan:new{ width = underline_h },
        }
        if tab.key == "bookmarks" then
            -- Bookmarks are not annotations: a dot sets that tab apart from the three before it
            local dot_gap = Screen:scaleBySize(12)
            table.insert(tabs, HorizontalSpan:new{ width = dot_gap })
            table.insert(tabs, CenterContainer:new{ dimen = Geom:new{ w = Screen:scaleBySize(8), h = row_h - underline_h },
                TextWidget:new{ text = "•", face = tab_face, fgcolor = COLORS.muted } })
            table.insert(tabs, HorizontalSpan:new{ width = dot_gap })
        elseif i > 1 then
            table.insert(tabs, HorizontalSpan:new{ width = Screen:scaleBySize(20) })
        end
        table.insert(tabs, TapBox:new{ box, callback = function() self:setNotesPresence(tab.key) end })
    end
    -- The tabs keep their size; the sort label gets the room that is left. When that is too
    -- little for a readable label (four tabs on a narrow screen), only the arrow is shown.
    local arrow_size = Screen:scaleBySize(14)
    local sort_room = w - tabs:getSize().w - h_pad - math.floor(h_pad / 2) - arrow_size - Screen:scaleBySize(3 + 16)
    local sort_label = HorizontalGroup:new{ align = "center" }
    if sort_room >= Screen:scaleBySize(48) then
        table.insert(sort_label, TextWidget:new{
            text = sortModeLabel(SortState.get(self.single_book), self.single_book),
            face = Font:getFace("cfont", 13), fgcolor = COLORS.muted,
            max_width = math.min(math.floor(w * 0.4), sort_room),
        })
        table.insert(sort_label, HorizontalSpan:new{ width = Screen:scaleBySize(3) })
    end
    table.insert(sort_label, IconWidget:new{ icon = "chevron.up", rotation_angle = 180, width = arrow_size, height = arrow_size })
    local sort_btn = TapBox:new{
        CenterContainer:new{ dimen = Geom:new{ w = sort_label:getSize().w + h_pad, h = row_h }, sort_label },
        callback = function() self:showSortMenu() end,
    }
    local tabs_dimen = Geom:new{ w = w, h = row_h }
    table.insert(header, OverlapGroup:new{
        dimen = tabs_dimen, allow_mirroring = false,
        LeftContainer:new{ dimen = tabs_dimen, tabs },
        RightContainer:new{ dimen = tabs_dimen, HorizontalGroup:new{ sort_btn, HorizontalSpan:new{ width = math.floor(h_pad / 2) } } },
    })
    table.insert(header, LineWidget:new{ dimen = Geom:new{ w = w, h = line_h }, background = COLORS.line })

    -- 3. active-filter chips (the tab is not repeated here)
    local lc = self._layout_chips
    self._layout_chips = nil
    local chips
    if lc and lc.w == w then chips = lc.widget else chips = self:buildFilterChips(w) end
    if chips then table.insert(header, chips) end
    return header
end

function NotesListWidget:setNotesPresence(key)
    self.active_filter = self.active_filter or {}
    if self.active_filter.notes_presence == key then return end
    self.active_filter.notes_presence = key
    self.current_page = 1
    self:refresh()
end

-- Remove all filters except the tab that is selected.
function NotesListWidget:clearFilters()
    local presence = self.active_filter and self.active_filter.notes_presence
    self.active_filter = { notes_presence = presence }
    self.current_page = 1
    self:refresh()
end

function NotesListWidget:showSearchDialog(on_done)
    local InputDialog = require("ui/widget/inputdialog")
    local af = self.active_filter or {}
    local dialog
    local buttons
    local run
    function run(text)
        UIManager:close(dialog)
        self.active_filter = self.active_filter or {}
        self.active_filter.search_any = (text and text ~= "") and text or nil
        self.current_page = 1
        self:refresh()
        if on_done then on_done() end
    end
    buttons = {{
        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
        { text = _("Clear"), callback = function() run(nil) end },
        { text = _("Search"), is_enter_default = true, callback = function() run(dialog:getInputText()) end },
    }}
    dialog = InputDialog:new{
        title = _("Search annotations"),
        input = af.search_any or "",
        input_hint = _("Words in highlights or notes"),
        buttons = buttons,
    }
    NotesListWidget.showDialog(dialog)
    dialog:onShowKeyboard()
end

function NotesListWidget:updatePage()
    self:computeLayout()
    local pag_style = getPaginationStyle()
    local header = self:buildHeader()

    local notes_group = VerticalGroup:new{ align = "left" }
    local top_padding = getTopPadding()
    if top_padding > 0 then
        table.insert(notes_group, VerticalSpan:new{ width = top_padding })
    end
    local x_offset = self.note_x_offset or 0
    local function place(widget)
        if x_offset > 0 then
            return HorizontalGroup:new{ HorizontalSpan:new{ width = x_offset }, widget }
        end
        return widget
    end

    local page_indices = self.pages[self.current_page] or {}
    local prev_chapter = nil
    local last_note_widget = nil
    -- vertical extent of each drawn annotation (relative to the top of the notes area),
    -- used by onTap() to find what was tapped
    local tap_rows = {}
    local row_y = top_padding
    local dedup_fields = getDedupInfoFields()
    local note_width = self.note_width
    -- determine dedup state from last note of previous page
    local dedup_prev_title = nil
    local dedup_prev_info_key = nil
    do
        local prev_page = self.pages[self.current_page - 1]
        if prev_page and #prev_page > 0 then
            local prev_note = self.filtered_notes[prev_page[#prev_page]]
            if prev_note then
                dedup_prev_title = prev_note.book_title
                dedup_prev_info_key = getNoteInfoKey(prev_note, dedup_fields)
                prev_chapter = prev_note.chapter -- a continued chapter gets no heading (unless repeated)
            end
        end
    end
    for i, idx in ipairs(page_indices) do
        local note = self.filtered_notes[idx]
        if note then
            local is_first_on_page = (i == 1)
            local skip_title, skip_info = getHeaderSkips(note, is_first_on_page, dedup_prev_title, dedup_prev_info_key, dedup_fields)
            if self.single_book then skip_title = true end
            if not is_first_on_page then
                local gap = NoteItemWidget.gapAbove(note, skip_title)
                table.insert(notes_group, VerticalSpan:new{ width = gap })
                row_y = row_y + gap
            end
            if self.single_book and NoteItemWidget.showHeadings() and note.chapter and note.chapter ~= "" and ((is_first_on_page and NoteItemWidget.repeatChapter()) or note.chapter ~= prev_chapter) then
                table.insert(notes_group, place(NoteItemWidget.chapterHeading(note.chapter, note_width)))
                row_y = row_y + NoteItemWidget.headingHeight(note.chapter, note_width)
            end
            prev_chapter = note.chapter
            local note_widget = NoteItemWidget:new{ width = note_width, note = note, show_parent = self, skip_title = skip_title, skip_info = skip_info }
            table.insert(notes_group, place(note_widget))
            table.insert(tap_rows, { top = row_y, bottom = row_y + note_widget.dimen.h, note = note })
            row_y = row_y + note_widget.dimen.h
            if i == #page_indices then last_note_widget = note_widget end
            dedup_prev_title = note.book_title
            dedup_prev_info_key = getNoteInfoKey(note, dedup_fields)
        end
    end

    -- Last page of a filtered list: say how many annotations the filters hide, with a way back
    if #page_indices > 0 and self.current_page == self.total_pages then
        local active = false
        for k, v in pairs(self.active_filter or {}) do
            if k ~= "notes_presence" and v and (type(v) ~= "table" or next(v)) then active = true end
        end
        local tab = self:tabKey()
        local hidden = (self.tab_totals and self.tab_totals[tab] or #self.notes_list) - #self.filtered_notes
        if active and hidden > 0 then
            local used = 0
            for _i, w in ipairs(notes_group) do if w.getSize then used = used + w:getSize().h end end
            local face = Font:getFace("cfont", 13)
            local hidden_text = hidden == 1 and _("1 more annotation is hidden by filters") or _("%d more annotations are hidden by filters")
            if tab == "bookmarks" then
                hidden_text = hidden == 1 and _("1 more bookmark is hidden by filters") or _("%d more bookmarks are hidden by filters")
            end
            local msg = TextWidget:new{ text = string.format(hidden_text, hidden),
                face = face, fgcolor = COLORS.muted, max_width = self.note_width - 2 * getHMargin() }
            local link = TextWidget:new{ text = _("Clear all"), face = face } -- same as "Clear all" by the chips
            local line = LineWidget:new{ dimen = Geom:new{ w = link:getSize().w, h = Size.line.medium }, background = BlitBuffer.COLOR_BLACK }
            local gap = Screen:scaleBySize(16)
            local box_h = gap + msg:getSize().h + Screen:scaleBySize(8) + link:getSize().h + line:getSize().h + gap
            if used + box_h <= self.height - self.title_height - self.footer_height then
                table.insert(notes_group, place(CenterContainer:new{ dimen = Geom:new{ w = self.note_width, h = box_h },
                    VerticalGroup:new{ align = "center", msg, VerticalSpan:new{ width = Screen:scaleBySize(8) },
                        VerticalGroup:new{ link, line } } }))
                table.insert(tap_rows, { top = used + gap + msg:getSize().h, bottom = used + box_h,
                    action = function() self:clearFilters() end })
            end
        end
    end

    -- Filters (or the tab) leave nothing: say so in the middle of the list
    if #page_indices == 0 and NotesListWidget.States then
        notes_group = NotesListWidget.States.noMatch(self, self.width,
            self.height - self.title_height - self.footer_height)
    end

    -- First annotation of the next page, faded and cut off, as a hint that there is more
    if last_note_widget and self.current_page < self.total_pages then
        local next_page_indices = self.pages[self.current_page + 1]
        local next_note = next_page_indices and next_page_indices[1] and self.filtered_notes[next_page_indices[1]]
        if next_note then
            local used_height = 0
            for _i, w in ipairs(notes_group) do
                if w.getSize then used_height = used_height + w:getSize().h end
            end
            local available_height = self.height - self.title_height - self.footer_height - used_height - NoteItemWidget.gapAbove(next_note, true) - 2
            if available_height > 0 then
                local preview_skip_title, preview_skip_info = getHeaderSkips(next_note, false, dedup_prev_title, dedup_prev_info_key, dedup_fields)
                if self.single_book then preview_skip_title = true end
                local preview_widget = NoteItemWidget:new{
                    width = note_width, note = next_note, show_parent = self,
                    is_preview = true, disable_tap = true,
                    skip_title = preview_skip_title, skip_info = preview_skip_info,
                }
                local AlphaContainer = require("ui/widget/container/alphacontainer")
                table.insert(notes_group, VerticalSpan:new{ width = NoteItemWidget.gapAbove(next_note, true) })
                table.insert(notes_group, place(AlphaContainer:new{
                    alpha = 0.2,
                    FrameContainer:new{
                        width = note_width, height = available_height,
                        padding = 0, margin = 0, bordersize = 0,
                        preview_widget,
                    },
                }))
            end
        end
    end

    local footer = self:createFooter()
    self.tap_rows = tap_rows
    self.tap_rows_origin_y = self.title_height
    local list_height = self.height - self.title_height - self.footer_height

    local content = OverlapGroup:new{
        allow_mirroring = false,
        dimen = Geom:new{ w = self.width, h = self.height },
        VerticalGroup:new{
            align = "left",
            header,
            TopContainer:new{ dimen = Geom:new{ w = self.width, h = list_height }, notes_group },
        },
        footer,
    }

    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, margin = 0, bordersize = 0,
        background = BlitBuffer.COLOR_WHITE,
        content,
    }

    self.ges_events = self.ges_events or {}
    local tap_height = self.height - self.title_height - self.footer_height
    -- In scrollbar mode, exclude the scrollbar column so taps/swipes there reach the strip
    local tap_width = self.width
    if isScrollbarStyle(pag_style) and self.sb_x and not self.no_scrollbar then
        tap_width = self.sb_x
    end
    self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = self.title_height, w = tap_width, h = tap_height } } }
    -- Narrow swipe range so the scrollbar column isn't claimed by page-turn swipes
    local swipe_range = Geom:new{ x = 0, y = 0, w = tap_width, h = self.height }
    local swipe_setting = getSwipeSetting()
    local horiz = swipe_setting == "horizontal" or swipe_setting == "both"
    local vert = swipe_setting == "vertical" or swipe_setting == "both"
    self.ges_events.SwipeWest  = horiz and { GestureRange:new{ ges = "swipe", range = swipe_range, direction = "west" } } or nil
    self.ges_events.SwipeEast  = horiz and { GestureRange:new{ ges = "swipe", range = swipe_range, direction = "east" } } or nil
    self.ges_events.SwipeNorth = vert and { GestureRange:new{ ges = "swipe", range = swipe_range, direction = "north" } } or nil
    self.ges_events.SwipeSouth = vert and { GestureRange:new{ ges = "swipe", range = swipe_range, direction = "south" } } or nil

    UIManager:setDirty(self, "ui")
end
function NotesListWidget:showMainMenu()
    NotesListWidget.States.menu(self)
end
-- Export: the list (with its filter and sort) as a Markdown or plain-text file, or onto the
-- clipboard. What goes in is set on the Export page (☰ → Export, or Settings → Export); every
-- option is a setting "export_<name>" with its default here. Export.build turns notes into text.
-- The filter of the list in plain words, for the top of an export: the tab, then each filter
-- as its chip says it, with every book, chapter and tag named.
function NotesListWidget:exportFilterLabel()
    local af = self.active_filter or {}
    local parts = {}
    local tabs = { exclude = _("Highlights"), only = _("Notes"), bookmarks = _("Bookmarks") }
    if af.notes_presence and tabs[af.notes_presence] then table.insert(parts, tabs[af.notes_presence]) end
    local chips = self:getFilterChips(true)
    for k = 1, #chips do
        local c = chips[k]
        table.insert(parts, (c.colors and c.prefix) and (c.prefix .. " " .. c.label) or c.label)
    end
    return table.concat(parts, ", ")
end
-- Writes the annotations currently in the list (with the active filter and sort order) to files
-- with the Export page's options.
function NotesListWidget:exportList()
    local notes = self.filtered_notes or {}
    if #notes == 0 then
        NotesListWidget.showDialog(InfoMessage:new{ text = _("Nothing to export.") })
        return
    end
    local path, n_files = Export.write(notes, Export.options(), self:exportFilterLabel())
    if not path then
        NotesListWidget.showDialog(InfoMessage:new{ text = _("Export failed:") .. " " .. tostring(n_files) })
        return
    end
    NotesListWidget.States.exported(#notes, path, Export.allBookmarks(notes), n_files)
end
-- the old name (kept for anything that still calls it)
function NotesListWidget:exportToMarkdown() self:exportList() end
-- Copies the same text onto the clipboard (all books in one, also with a file per book).
function NotesListWidget:copyList()
    local notes = self.filtered_notes or {}
    if #notes == 0 then
        NotesListWidget.showDialog(InfoMessage:new{ text = _("Nothing to export.") })
        return
    end
    local set = Device.input and Device.input.setClipboardText
    if type(set) ~= "function" then
        NotesListWidget.showDialog(InfoMessage:new{ text = _("This device has no clipboard.") })
        return
    end
    set(Export.build(notes, Export.options(), self:exportFilterLabel()))
    NotesListWidget.States.exported(#notes, nil, Export.allBookmarks(notes), 0, true)
end
function NotesListWidget:showSortMenu(on_done)
    NotesListWidget.States.sortMenu(self, on_done)
end
function NotesListWidget:applySort()
    self:sortNotesList(self.notes_list, SortState.get(self.single_book), self.single_book)
end
function NotesListWidget:sortNotesList(notes_list, sort_mode, single)
    sort_mode = sort_mode or SortState.get(single)
    -- the rule as it applies to this view; one that can't be read sorts newest first, as its label says
    sort_mode = SortState.normView(sort_mode, single)
    local comparator = SORT_COMPARATORS[sort_mode] or SORT_COMPARATORS["date:desc"]
    local levels = SortState.parse(sort_mode)
    local uses_opened, uses_chapter = false, false
    for _, l in ipairs(levels or {}) do
        if l.key == "opened" then uses_opened = true end
        if l.key == "chapter" then uses_chapter = true end
    end
    if uses_chapter then
        -- chapters rank in the order they first show up in the book
        local tmp = {}
        for i, n in ipairs(notes_list) do tmp[i] = n end
        table.sort(tmp, SORT_COMPARATORS["pos:asc"])
        local rank, nxt = {}, 0
        for _, n in ipairs(tmp) do
            local ch = n.chapter or ""
            if not rank[ch] then nxt = nxt + 1; rank[ch] = nxt end
            n.chapter_rank = rank[ch]
        end
    end
    if uses_opened then
        SortState.opened = {}
        for _, item in ipairs(ReadHistory.hist or {}) do
            if item.file then SortState.opened[NotesListWidget.realPath(item.file)] = tonumber(item.time) or 0 end
        end
        -- the list may name a book differently from the history (a link, another mount name)
        local by_path = {}
        for _, n in ipairs(notes_list) do
            local p = n.book_path
            if p and by_path[p] == nil then by_path[p] = SortState.opened[NotesListWidget.realPath(p)] or false end
        end
        for p, t in pairs(by_path) do if t then SortState.opened[p] = t end end
    end
    if comparator then
        table.sort(notes_list, comparator)
    end
    return notes_list
end
function NotesListWidget:showSettingsMenu()
    -- the sub-dialogs (spin settings, typefaces) come back here: rebuild the page if it is open
    if self.settings_screen then
        self.settings_screen:rebuild()
        return
    end
    self.settings_screen = NotesListWidget.SettingsScreen:new{ list = self }
    UIManager:show(self.settings_screen, "flashui")
end
-- The Export page: its options with a preview of the file, and Copy / Export at the bottom.
function NotesListWidget:showExportPage()
    UIManager:show(NotesListWidget.SettingsScreen:new{ list = self, page = "export", export_action = true }, "flashui")
end
function NotesListWidget:showSpinSetting(title, key, default, min, max, step, back_callback)
    NotesListWidget.showDialog(SpinWidget:new{
        title_text = title,
        value = getSetting(key, default), value_min = min, value_max = max, value_step = step,
        default_value = default, ok_text = _("Set"),
        callback = function(spin)
            setSetting(key, spin.value)
            self:refresh()
            if back_callback then back_callback() end
        end,
        cancel_callback = function()
            if back_callback then back_callback() end
        end,
    })
end
function NotesListWidget:showFilterMenu()
    local function ensureFilter()
        if not self.active_filter or type(self.active_filter) ~= "table" then
            self.active_filter = {}
        end
    end


    -- Single-book context: launched from the reader (current book only),
    -- or the book filter is narrowed to exactly one book.
    local function isSingleBookContext()
        if self.single_book then return true end
        local book_filter = self.active_filter and self.active_filter.books
        if book_filter and next(book_filter) then
            local count = 0
            for _ in pairs(book_filter) do count = count + 1 end
            if count == 1 then return true end
        end
        return false
    end

    local function showTextSearchFilter(field_key, dialog_title, hint, is_exclude)
        local InputDialog = require("ui/widget/inputdialog")
        local actual_key = is_exclude and (field_key .. "_exclude") or field_key
        local mode_key = actual_key .. "_mode"
        local case_key = actual_key .. "_case"
        local init_query = (self.active_filter and self.active_filter[actual_key]) or ""
        local init_mode  = (self.active_filter and self.active_filter[mode_key]) or "all"
        local init_case  = (self.active_filter and self.active_filter[case_key]) or false
        local dialog_mode = init_mode
        local dialog_case = init_case
        local input_dialog
        local function rebuildDialog(saved_query)
            if input_dialog then UIManager:close(input_dialog) end
            local function modeBtn(label, m)
                return {
                    text = (dialog_mode == m and "✓ " or "") .. label,
                    callback = function()
                        local q = input_dialog:getInputText()
                        dialog_mode = m
                        rebuildDialog(q)
                    end,
                }
            end
            input_dialog = InputDialog:new{
                title = dialog_title, -- translated by the caller
                input = saved_query,
                input_hint = hint,
                buttons = {
                    {
                        modeBtn(_("All Words"), "all"),
                        modeBtn(_("Any Word"), "any"),
                        modeBtn(_("Exact Phrase"), "phrase"),
                    },
                    {
                        {
                            text = dialog_case and _("Case-Sensitive: On") or _("Case-Sensitive: Off"),
                            callback = function()
                                local q = input_dialog:getInputText()
                                dialog_case = not dialog_case
                                rebuildDialog(q)
                            end,
                        },
                    },
                    {
                        { text = _("Cancel"), callback = function() UIManager:close(input_dialog) end },
                        { text = _("Clear"), callback = function()
                            UIManager:close(input_dialog)
                            if self.active_filter then
                                self.active_filter[actual_key] = nil
                                self.active_filter[mode_key]   = nil
                                self.active_filter[case_key]   = nil
                            end
                            self:refresh()
                            if self.filter_screen then self.filter_screen:rebuild() end
                        end },
                        { text = is_exclude and _("Exclude") or _("Search"), is_enter_default = true, callback = function()
                            local q = input_dialog:getInputText()
                            UIManager:close(input_dialog)
                            ensureFilter()
                            self.active_filter[actual_key] = q ~= "" and q or nil
                            self.active_filter[mode_key]   = dialog_mode
                            self.active_filter[case_key]   = dialog_case
                            self:refresh()
                            if self.filter_screen then self.filter_screen:rebuild() end
                        end },
                    },
                },
            }
            NotesListWidget.showDialog(input_dialog)
            input_dialog:onShowKeyboard()
        end
        rebuildDialog(init_query)
    end

    -- The full-screen "Filter & sort" screen. The pickers it opens (books, tags, chapters, text)
    -- redraw it when they finish.
    local function back() if self.filter_screen then self.filter_screen:rebuild() end end
    self:showFilterScreen{
        books = function() self:showBookPicker(back) end,
        meta = function(kind) self:showMetaPicker(kind, back) end,
        tags = function() self:showTagPicker(back) end,
        chapters = function() self:showChapterPicker(back) end,
        chapters_available = isSingleBookContext,
        text = function(field, title, hint, is_exclude) showTextSearchFilter(field, title, hint, is_exclude) end,
    }
end
function NotesListWidget:refresh()
    self:computeLayout()
    local prev_page = self.current_page or 1
    self:syncSortTab()
    self:applyFilter()
    self:calculatePages()
    self.current_page = math.max(1, math.min(prev_page, self.total_pages or 1))
    self:updatePage()
end
function NotesListWidget:onGotoNextPage()
    if self.current_page < self.total_pages then
        self.current_page = self.current_page + 1
    else
        self.current_page = 1
    end
    self:updatePage()
    return true
end
function NotesListWidget:onGotoPrevPage()
    if self.current_page > 1 then
        self.current_page = self.current_page - 1
    else
        self.current_page = self.total_pages
    end
    self:updatePage()
    return true
end
function NotesListWidget:onSwipeWest()  return self:onGotoNextPage() end
function NotesListWidget:onSwipeNorth() return self:onGotoNextPage() end
function NotesListWidget:onSwipeEast()  return self:onGotoPrevPage() end
function NotesListWidget:onSwipeSouth() return self:onGotoPrevPage() end
-- The plugin's own gesture events: a gesture set to one of these does nothing while the list is
-- open (it would open a second list on top).
NotesListWidget.OWN_EVENTS = { ShowAnnotationsHere = true, ShowBookmarksHere = true, ShowAllAnnotations = true,
    ShowCurrentBookAnnotations = true, ShowAllBookmarksList = true, ShowCurrentBookBookmarksList = true }
-- Actions that leave this screen (file browser, open a book): the list closes first, so it isn't
-- left on top of what comes next.
NotesListWidget.LEAVE_EVENTS = { Home = true, OpenLastDoc = true, OpenNextOrPreviousFileInFolder = true }
-- the list on screen (one at a time); its windows are closed before a leave action
function NotesListWidget:onCloseWidget()
    if NotesListWidget._current == self then NotesListWidget._current = nil end
    flushSettings()
end
-- The plugin's other windows on screen (sheet, cards, full-screen pages, KOReader dialogs shown
-- through showDialog), in the order they were shown, so a leave action can close them all.
NotesListWidget._windows = setmetatable({}, { __mode = "k" })
NotesListWidget._window_n = 0
function NotesListWidget.trackWindow(w)
    if type(w) ~= "table" or w._av_tracked then return end
    w._av_tracked = true
    local on_show, on_close = w.onShow, w.onCloseWidget
    w.onShow = function(self, ...)
        NotesListWidget._window_n = NotesListWidget._window_n + 1
        NotesListWidget._windows[self] = NotesListWidget._window_n
        if on_show then return on_show(self, ...) end
    end
    w.onCloseWidget = function(self, ...)
        NotesListWidget._windows[self] = nil
        if on_close then return on_close(self, ...) end
    end
end
-- Closes every window of the plugin, the newest first, then the list.
function NotesListWidget.closeAll(from)
    local open = {}
    for w, n in pairs(NotesListWidget._windows) do open[#open + 1] = { w = w, n = n } end
    table.sort(open, function(a, b) return a.n > b.n end)
    local done = {}
    for i = 1, #open do UIManager:close(open[i].w); done[open[i].w] = true end
    local w = from -- and anything shown in a way that wasn't tracked: the pages it came from
    while w and w ~= NotesListWidget._current do
        if not done[w] then UIManager:close(w); done[w] = true end
        w = w.parent_screen or w.parent
    end
    if NotesListWidget._current then UIManager:close(NotesListWidget._current) end
end
-- Runs KOReader's gesture action fn() for a gesture the plugin's windows don't use. Its events go
-- to every window (KOReader only sends them to the top one, which is the list), so frontlight,
-- night mode, refresh and the like work. While it runs, KOReader is told that some actions are
-- off: the plugin's own (no second list), and the book's own (Reader: page turns, chapters,
-- bookmarks ...), which would act on the book hidden behind the list. A leave action closes the
-- plugin's windows first. from: the plugin window that got the gesture.
function NotesListWidget.runForwarded(fn, from)
    local Dispatcher = require("dispatcher")
    local orig_send, orig_enabled = UIManager.sendEvent, Dispatcher.isActionEnabled
    local closed = false
    UIManager.sendEvent = function(_um, ev)
        -- a leave action: close the plugin's windows when it is really sent (a QuickMenu only
        -- checks its actions while building the menu)
        local name = type(ev) == "table" and type(ev.handler) == "string" and ev.handler:match("^on(.+)$")
        if name and NotesListWidget.LEAVE_EVENTS[name] and not closed then
            closed = true
            NotesListWidget.closeAll(from)
        end
        return UIManager:broadcastEvent(ev)
    end
    if type(orig_enabled) == "function" then Dispatcher.isActionEnabled = function(d, action)
        if type(action) == "table" then
            if NotesListWidget.OWN_EVENTS[action.event] then return false end
            if action.reader or action.rolling or action.paging then return false end
        end
        return orig_enabled(d, action)
    end end
    local ok, err = pcall(fn)
    UIManager.sendEvent, Dispatcher.isActionEnabled = orig_send, orig_enabled
    if not ok then logger.warn("annotationsviewer: forwarded gesture:", err) end
end
-- Forward an unhandled gesture to the KOReader gestures plugin by directly
-- resolving the canonical gesture name and calling gestureAction(). This
-- bypasses the event-stack limitation where UIManager only propagates events
-- to is_always_active widgets after the top widget.
local function _forwardGestureToPlugin(ges_event, from)
    local g
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then g = ReaderUI.instance.gestures end
    if not g then
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then g = FileManager.instance.gestures end
    end
    if not g then return end

    local sw  = Screen:getWidth()
    local sh  = Screen:getHeight()
    local pos = ges_event.pos
    if not pos then return end
    local x, y = pos.x, pos.y
    local gt  = ges_event.ges
    local dir = ges_event.direction

    local function readZone(key)
        local d = G_defaults:readSetting(key)
        if not d then return nil end
        return { ratio_x = d.x, ratio_y = d.y, ratio_w = d.w, ratio_h = d.h }
    end
    local function inZone(z)
        if not z then return false end
        return x >= z.ratio_x * sw and x < (z.ratio_x + z.ratio_w) * sw
           and y >= z.ratio_y * sh and y < (z.ratio_y + z.ratio_h) * sh
    end

    local candidates = {}

    if gt == "swipe" then
        local is_diag = dir == "northeast" or dir == "northwest"
                     or dir == "southeast" or dir == "southwest"
        if is_diag then
            if ges_event.distance and ges_event.distance <= Screen:scaleBySize(300) then
                candidates[#candidates+1] = "short_diagonal_swipe"
            end
        else
            local le = readZone("DSWIPE_ZONE_LEFT_EDGE")
            local re = readZone("DSWIPE_ZONE_RIGHT_EDGE")
            local te = readZone("DSWIPE_ZONE_TOP_EDGE")
            local be = readZone("DSWIPE_ZONE_BOTTOM_EDGE")
            if inZone(le) then
                if dir == "south" then candidates[#candidates+1] = "one_finger_swipe_left_edge_down"
                elseif dir == "north" then candidates[#candidates+1] = "one_finger_swipe_left_edge_up" end
            elseif inZone(re) then
                if dir == "south" then candidates[#candidates+1] = "one_finger_swipe_right_edge_down"
                elseif dir == "north" then candidates[#candidates+1] = "one_finger_swipe_right_edge_up" end
            elseif inZone(te) then
                if dir == "east" then candidates[#candidates+1] = "one_finger_swipe_top_edge_right"
                elseif dir == "west" then candidates[#candidates+1] = "one_finger_swipe_top_edge_left" end
            elseif inZone(be) then
                if dir == "east" then candidates[#candidates+1] = "one_finger_swipe_bottom_edge_right"
                elseif dir == "west" then candidates[#candidates+1] = "one_finger_swipe_bottom_edge_left" end
            end
        end
    elseif gt == "two_finger_swipe" then
        local map = {
            east="two_finger_swipe_east", west="two_finger_swipe_west",
            north="two_finger_swipe_north", south="two_finger_swipe_south",
            northeast="two_finger_swipe_northeast", northwest="two_finger_swipe_northwest",
            southeast="two_finger_swipe_southeast", southwest="two_finger_swipe_southwest",
        }
        if map[dir] then candidates[#candidates+1] = map[dir] end
    elseif gt == "multiswipe" then
        NotesListWidget.runForwarded(function() g:multiswipeAction(ges_event.multiswipe_directions, ges_event) end, from)
        return true
    elseif gt == "spread" then candidates[#candidates+1] = "spread_gesture"
    elseif gt == "pinch"  then candidates[#candidates+1] = "pinch_gesture"
    elseif gt == "rotate" then
        if dir == "cw"  then candidates[#candidates+1] = "rotate_cw"
        elseif dir == "ccw" then candidates[#candidates+1] = "rotate_ccw" end
    end

    if #candidates == 0 then return end

    local ges_name = candidates[1]
    for _, name in ipairs(candidates) do
        if g.gestures and g.gestures[name] ~= nil then ges_name = name; break end
    end

    NotesListWidget.runForwarded(function() g:gestureAction(ges_name, ges_event) end, from)
    return true
end

-- Show one of KOReader's own dialogs (edit note, confirm, number, buttons ...) and let it pass
-- the gestures it doesn't use on to the KOReader gestures plugin, as the list does.
function NotesListWidget.showDialog(w, ...)
    local IC = require("ui/widget/container/inputcontainer")
    if type(w) == "table" and not w.toast and w.onGesture == IC.onGesture then
        NotesListWidget.trackWindow(w)
        w.onGesture = function(self, ev)
            if IC.onGesture(self, ev) then return true end
            return _forwardGestureToPlugin(ev, self)
        end
    end
    return UIManager:show(w, ...)
end
function NotesListWidget:onGesture(ev)
    -- Let InputContainer handle registered ges_events / touch zones first
    local InputContainer = require("ui/widget/container/inputcontainer")
    if InputContainer.onGesture(self, ev) then return true end
    return _forwardGestureToPlugin(ev, self)
end
function NotesListWidget:onTap(_, ges)
    if not ges or not ges.pos then return end
    -- exclude scrollbar column
    local pag_style = getPaginationStyle()
    if isScrollbarStyle(pag_style) and self.sb_x and not self.no_scrollbar and ges.pos.x >= self.sb_x then
        return
    end
    local tap_y = ges.pos.y
    if tap_y < self.title_height then
        return
    end

    -- Use the positions recorded when the page was drawn
    local rel_y = tap_y - (self.tap_rows_origin_y or self.title_height)
    for _, row in ipairs(self.tap_rows or {}) do
        if rel_y >= row.top and rel_y < row.bottom then
            if row.action then row.action() return true end
            self:onNoteSelected(row.note)
            return true
        end
    end
    return false
end
function NotesListWidget:onNoteSelected(note)
    if self.viewer and self.viewer.showNoteDetails then
        self.viewer:showNoteDetails(note, self)
    end
end
function NotesListWidget:onClose()
    -- full-screen widget: refresh what was underneath, or e-ink keeps showing the list
    UIManager:close(self, "flashui")
    return true
end
-- Screen rotated or window resized: rebuild the layout for the new size and stay on the
-- page that shows the annotation that was at the top before.
function NotesListWidget:onScreenResize()
    local page = self.pages and self.pages[self.current_page]
    local first_idx = page and page[1]
    self.current_page = 1
    self:init()
    if first_idx then
        for p, indices in ipairs(self.pages) do
            if indices[#indices] and indices[#indices] >= first_idx then
                if p ~= self.current_page then
                    self.current_page = p
                    self:updatePage()
                end
                break
            end
        end
    end
    UIManager:setDirty(self, "full")
    return false
end
-- Rotation doesn't always reach this widget as an event, so also check the size whenever
-- we're painted and re-layout (outside the paint) if the screen changed.
function NotesListWidget:paintTo(bb, x, y)
    if (self.width ~= Screen:getWidth() or self.height ~= Screen:getHeight()) and not self._resize_pending then
        self._resize_pending = true
        UIManager:nextTick(function()
            self._resize_pending = nil
            if self.width ~= Screen:getWidth() or self.height ~= Screen:getHeight() then
                self:onScreenResize()
            end
        end)
    end
    InputContainer.paintTo(self, bb, x, y)
end

-- Module-level caches: survive across plugin open/close within the same KOReader session,
-- and are saved to disk (see loadPersistentCache) so they also survive restarts.
-- "mtime" holds a key describing the sidecar's state (modification time and size); an entry
-- is only used while the key still matches.
-- Returns those files, most recent first, or errors when KOReader has no such API (before 2024).
function NotesListWidget.sidecarCandidates(book_path)
    if type(book_path) ~= "string" or book_path == "" or not DocSettings.findSidecarFile then error("no API") end
    local name = DocSettings.getSidecarFilename(book_path)
    local list = {}
    local function add(path, backup)
        local attr = path and lfs.attributes(path)
        if not attr or attr.mode ~= "file" then return false end
        local prev = list[#list]
        -- a backup is never newer than its file (DocSettings buildCandidates)
        if backup and prev and prev.path .. ".old" == path then
            if prev.mtime < attr.modification then prev.mtime = attr.modification end
        end
        table.insert(list, { path = path, mtime = attr.modification, size = attr.size, prio = #list + 1 })
        return true
    end
    local doc_dir = DocSettings:getSidecarDir(book_path, "doc")
    add(doc_dir .. "/" .. name); add(doc_dir .. "/" .. name .. ".old", true)
    add(doc_dir .. "/" .. (book_path:match("([^/]+)$") or "") .. ".lua")
    local dir_dir = DocSettings:getSidecarDir(book_path, "dir")
    add(dir_dir .. "/" .. name); add(dir_dir .. "/" .. name .. ".old", true)
    -- the hash folder when it is in use, as open() does (KOReader reads a few small parts of the
    -- book for its name once and keeps that in memory)
    if DocSettings.isHashLocationEnabled and DocSettings.isHashLocationEnabled() then
        local hash_dir = DocSettings:getSidecarDir(book_path, "hash")
        add(hash_dir .. "/" .. name); add(hash_dir .. "/" .. name .. ".old", true)
    end
    if DocSettings.getHistoryPath then
        local hist = DocSettings:getHistoryPath(book_path)
        if hist ~= "" then add(hist); add(hist .. ".old", true) end
    end
    add(book_path .. ".kpdfview.lua")
    table.sort(list, function(a, b)
        if a.mtime == b.mtime then return a.prio < b.prio end
        return a.mtime > b.mtime
    end)
    return list
end
-- The real path of a file (links followed), or the path itself when that can't be worked out
-- (missing file, no realpath). Kept per path; findAllNotes starts each scan with an empty table.
NotesListWidget._realpaths = {}
function NotesListWidget.realPath(path)
    if type(path) ~= "string" then return path end
    local real = NotesListWidget._realpaths[path]
    if real == nil then
        local ok, ffiutil = pcall(require, "ffi/util")
        local ok_rp, rp = false, nil
        if ok and type(ffiutil) == "table" and ffiutil.realpath then ok_rp, rp = pcall(ffiutil.realpath, path) end
        real = (ok_rp and type(rp) == "string" and rp ~= "") and rp or path
        NotesListWidget._realpaths[path] = real
    end
    return real
end
-- Are these the same book? The open book's path can be written differently from the list's
-- (a link to the folder, /mnt/us and /mnt/base-us on a Kindle, the path KOReader saved earlier).
function NotesListWidget.samePath(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    if a == b then return true end
    if NotesListWidget.realPath(a) == NotesListWidget.realPath(b) then return true end
    -- two mounts of the same storage (no link to follow): the same file on the same device
    local fa, fb = lfs.attributes(a), lfs.attributes(b)
    return fa ~= nil and fb ~= nil and fa.mode == "file" and fa.ino ~= nil and fa.ino ~= 0
        and fa.dev == fb.dev and fa.ino == fb.ino
end
function NotesListWidget:showFilterScreen(helpers)
    if self.filter_screen then UIManager:close(self.filter_screen) end
    self.filter_screen = FilterScreen:new{ list = self, helpers = helpers }
    UIManager:show(self.filter_screen, "flashui")
end
function NotesListWidget:showSortPicker(on_done)
    UIManager:show(SortPicker:new{ list = self, on_done = on_done })
end

-- The pickers count what the open tab is about: bookmarks on the Bookmarks tab, annotations
-- (highlights and notes) on the others. An item with nothing of that kind is left out, unless it
-- is already ticked (so it can still be unticked).
function NotesListWidget:countsHere(n)
    return (n.bookmark == true) == (self:tabKey() == "bookmarks")
end
-- How many entries a picker offers on this tab (what pickerItems keeps): values with something on
-- this tab, plus the ones chosen in the filter. keysOf(note) gives a note's values. Used for the
-- "N of M" / "All M" on Filter & sort and the ☰ menu, so they match the picker.
function NotesListWidget:offeredCount(inc_key, exc_key, keysOf)
    local af = self.active_filter or {}
    local inc, exc = af[inc_key], af[exc_key]
    local seen, count = {}, 0
    for i = 1, #(self.notes_list or {}) do
        local n = self.notes_list[i]
        local here = self:countsHere(n)
        local keys = keysOf(n)
        for j = 1, #keys do
            local k = keys[j]
            if not seen[k] and (here or (type(inc) == "table" and inc[k]) or (type(exc) == "table" and exc[k])) then
                seen[k] = true
                count = count + 1
            end
        end
    end
    return count
end
function NotesListWidget.bookKeys(n) return { n.book_title or _("Unknown") } end
function NotesListWidget:pickerItems(items, inc_key, exc_key)
    local af = self.active_filter or {}
    local out = {}
    for _i, it in ipairs(items) do
        if it.count > 0 or (af[inc_key] and af[inc_key][it.key]) or (af[exc_key] and af[exc_key][it.key]) then
            table.insert(out, it)
        end
    end
    return out
end
function NotesListWidget:showBookPicker(on_done)
    local by_title, items = {}, {}
    for _i, n in ipairs(self.notes_list) do
        local t = n.book_title or _("Unknown")
        local it = by_title[t]
        if not it then
            local a = NoteWrapper:new(n):getDisplayAuthors()
            it = { key = t, title = t, subtitle = (a and a ~= "Unknown") and a or nil, count = 0, serif = true }
            by_title[t] = it
            table.insert(items, it)
        end
        if self:countsHere(n) then it.count = it.count + 1 end
    end
    items = self:pickerItems(items, "books", "books_exclude")
    table.sort(items, function(a, b) return normalizeBookTitle(a.title) < normalizeBookTitle(b.title) end)
    UIManager:show(ListPicker:new{ list = self, title = _("Books"), items = items, inc_key = "books", exc_key = "books_exclude",
        mode_labels = { _("Only these books"), _("Hide these books") }, search_hint = _("Search title or author"), on_done = on_done })
end
-- kind: "authors", "series" or "languages"
function NotesListWidget:showMetaPicker(kind, on_done)
    local seen, items = {}, {}
    for i = 1, #self.notes_list do
        local n = self.notes_list[i]
        local here = self:countsHere(n)
        local vals = NotesListWidget.metaValues(n, kind)
        for j = 1, #vals do
            local v = vals[j]
            local it = seen[v]
            if not it then
                it = { key = v, title = NotesListWidget.metaLabel(v), count = 0 }
                seen[v] = it
                table.insert(items, it)
            end
            if here then it.count = it.count + 1 end
        end
    end
    items = self:pickerItems(items, kind, kind .. "_exclude")
    table.sort(items, function(a, b) -- "None" last
        if (a.key == "") ~= (b.key == "") then return b.key == "" end
        return a.title:lower() < b.title:lower()
    end)
    local texts = {
        authors = { _("Authors"), _("Only these authors"), _("Hide these authors"), _("Search authors") },
        series = { _("Series"), _("Only these series"), _("Hide these series"), nil },
        languages = { _("Language"), _("Only these languages"), _("Hide these languages"), nil },
    }
    local t = texts[kind]
    UIManager:show(ListPicker:new{ list = self, title = t[1], items = items, inc_key = kind, exc_key = kind .. "_exclude",
        mode_labels = { t[2], t[3] }, search_hint = t[4], on_done = on_done })
end
function NotesListWidget:showChapterPicker(on_done)
    local seen, items = {}, {}
    local book_filter = self.active_filter and self.active_filter.books
    for _i, n in ipairs(self.notes_list) do
        if n.chapter and n.chapter ~= "" and (not book_filter or not next(book_filter) or book_filter[n.book_title]) then
            local it = seen[n.chapter]
            if not it then
                it = { key = n.chapter, title = n.chapter, group = n.book_title, count = 0 }
                seen[n.chapter] = it
                table.insert(items, it)
            end
            if self:countsHere(n) then it.count = it.count + 1 end
        end
    end
    items = self:pickerItems(items, "chapters", "chapters_exclude")
    -- grouped by book, chapters in reading order: each chapter by its first annotation in the
    -- book (not by the list's sort, which may be by date)
    local first = {}
    for i = 1, #self.notes_list do
        local n = self.notes_list[i]
        local c = n.chapter
        if c and (not first[c] or compareByPosition(n, first[c])) then first[c] = n end
    end
    table.sort(items, function(a, b)
        if a.group ~= b.group then return normalizeBookTitle(a.group or "") < normalizeBookTitle(b.group or "") end
        local na, nb = first[a.key], first[b.key]
        if na and nb then
            if compareByPosition(na, nb) then return true end
            if compareByPosition(nb, na) then return false end
        end
        return a.title < b.title
    end)
    UIManager:show(ListPicker:new{ list = self, title = _("Chapters"), items = items, inc_key = "chapters", exc_key = "chapters_exclude",
        mode_labels = { _("Only these chapters"), _("Hide these chapters") }, on_done = on_done })
end
function NotesListWidget:showTagPicker(on_done)
    local seen, items = {}, {}
    local book_filter = self.active_filter and self.active_filter.books
    for _i, n in ipairs(self.notes_list) do
        if not book_filter or not next(book_filter) or book_filter[n.book_title] then
            for _j, tag in ipairs(NoteWrapper:new(n):getTags()) do
                if tag ~= "" then
                    local it = seen[tag]
                    if not it then it = { key = tag, title = tag, count = 0 }; seen[tag] = it; table.insert(items, it) end
                    if self:countsHere(n) then it.count = it.count + 1 end
                end
            end
        end
    end
    items = self:pickerItems(items, "tags", "tags_exclude")
    table.sort(items, function(a, b) return a.title:lower() < b.title:lower() end)
    UIManager:show(ListPicker:new{ list = self, title = _("Tags"), items = items, inc_key = "tags", exc_key = "tags_exclude",
        mode_labels = { _("Only these tags"), _("Hide these tags") }, on_done = on_done })
end

-- Module exports
M.NotesListWidget = NotesListWidget
M.colorName = colorName
M.setLabel = setLabel
M.CHIP_HEIGHT = CHIP_HEIGHT
M.CHIP_GAP = CHIP_GAP
M._forwardGestureToPlugin = _forwardGestureToPlugin

function M.bind(deps)
    if deps.AllNotesViewer then AllNotesViewer = deps.AllNotesViewer end
end

return M
