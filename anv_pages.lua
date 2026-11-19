-- anv_pages.lua — Annotations Viewer
--
-- Full-screen pages and modal states, plus the helpers that build them:
-- headers, footers, buttons, previews, pagination and row lines. main.lua
-- mounts several of these onto NoteItemWidget and NotesListWidget.
--
-- Public API (used by other modules):
--   FilterScreen / SS / SubPage / ListPicker / SortPicker    full-screen widgets
--   States    modal state widgets (Card, loading, confirmDelete, exported, menu, sortMenu, noMatch)
--   TextMark    text mark widget mounted onto NoteItemWidget
--   splitPages    split rows across pages
--   watchResize    react to a widget resize
--   bind    inject the list, viewer and item collaborators

local Pages = {}

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local BlitBuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Device = require("device")
local Input = Device.input
local logger = require("logger")
local FontList = require("fontlist")
local lfs = require("libs/libkoreader-lfs")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local BD = require("ui/bidi")
local core = require("anv_core")
local _ = require("anv_i18n").gettext
local sort = require("anv_sort")
local text = require("anv_text")
local atoms = require("anv_atoms")
local item = require("anv_item")
local sheet = require("anv_sheet")
local exportmod = require("anv_export")
local data = require("anv_data")

local NotesListWidget  -- injected by main assembly
local AllNotesViewer   -- injected by main assembly
-- anv_list requires anv_pages; resolve this helper only when a gesture actually fires.
local _gesture_forwarder
local function _forwardGestureToPlugin(ges_event, from)
    if not _gesture_forwarder then _gesture_forwarder = require("anv_list")._forwardGestureToPlugin end
    return _gesture_forwarder(ges_event, from)
end
local _tracked_classes = {}

-- A tick (or ✕) drawn with plain white strokes, so it shows on every device (no icon file, no font glyph)
Pages.Glyph = WidgetContainer:extend{ kind = "check", size = 18 }
function Pages.Glyph:getSize() return Geom:new{ w = self.size, h = self.size } end
function Pages.Glyph:paintTo(bb, x, y)
    local s = self.size
    local t = math.max(2, Screen:scaleBySize(2))
    local function stroke(x1, y1, x2, y2)
        local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1))
        for i = 0, steps do
            local f = steps > 0 and i / steps or 0
            local px, py = x + math.floor(x1 + (x2 - x1) * f), y + math.floor(y1 + (y2 - y1) * f)
            bb:paintRect(px, py, t, t, BlitBuffer.COLOR_WHITE)
        end
    end
    if self.kind == "check" then
        stroke(s * 0.12, s * 0.52, s * 0.38, s * 0.78)
        stroke(s * 0.38, s * 0.78, s * 0.88, s * 0.2)
    else
        stroke(s * 0.2, s * 0.2, s * 0.8, s * 0.8)
        stroke(s * 0.8, s * 0.2, s * 0.2, s * 0.8)
    end
end
-- KOReader's own "check" / "close" icon in white. KOReader icons are black on white, so the icon is
-- painted onto a white scratch buffer, inverted by hand and copied over: this does not depend on
-- IconWidget's `invert` flag or its alpha handling, which is what showed up as white boxes before.
-- If the icon file is missing (or comes out blank) the drawn Glyph above is used instead.
Pages.IconMark = WidgetContainer:extend{ icon = "check", size = 18 }
function Pages.IconMark:init()
    self.iw = IconWidget:new{ icon = self.icon, width = self.size, height = self.size }
    self.glyph = Pages.Glyph:new{ kind = self.icon == "close" and "close" or "check", size = self.size }
    self.missing = tostring(self.iw.file or ""):find("icon-not-found", 1, true) ~= nil
    if self.missing then logger.warn("AnnotationsViewer: icon '" .. self.icon .. "' not found, drawing it instead") end
end
function Pages.IconMark:getSize() return Geom:new{ w = self.size, h = self.size } end
function Pages.IconMark:paintTo(bb, x, y)
    if self.missing then return self.glyph:paintTo(bb, x, y) end
    local n = self.size
    local tmp = BlitBuffer.new(n, n, bb:getType())
    tmp:fill(BlitBuffer.COLOR_WHITE)
    self.iw:paintTo(tmp, 0, 0)
    -- blank (all white) result: nothing visible from the icon, draw the tick ourselves
    local dark = false
    for yy = 0, n - 1, 2 do
        for xx = 0, n - 1, 2 do
            if tmp:getPixel(xx, yy):getColor8().a < 200 then dark = true; break end
        end
        if dark then break end
    end
    if not dark then tmp:free(); return self.glyph:paintTo(bb, x, y) end
    tmp:invertRect(0, 0, n, n)
    bb:blitFrom(tmp, x, y, 0, 0, n, n)
    tmp:free()
end
-- The ✓ / ✕ text characters (what KOReader's own CheckMark widget uses), centred on the ink: the
-- character is drawn once on a scratch buffer, its real outline measured, and the dark pixels are then
-- painted in white so that the outline sits exactly in the middle of the box (a font's own metrics
-- leave glyphs off-centre). No glyph in the font (blank result) -> KOReader's icon is used instead.
Pages.TextMark = WidgetContainer:extend{ icon = "check", size = 18 }
function Pages.TextMark:init()
    self.char = self.icon == "close" and "\226\156\149" or "\226\156\147" -- ✕ / ✓
    self.fallback = Pages.IconMark:new{ icon = self.icon, size = self.size }
end
function Pages.TextMark:getSize() return Geom:new{ w = self.size, h = self.size } end
function Pages.TextMark:measure(bbtype)
    local n = self.size
    local m = n * 3
    local tmp = BlitBuffer.new(m, m, bbtype)
    tmp:fill(BlitBuffer.COLOR_WHITE)
    local face = Font:getFace("cfont", self.icon == "close" and 15 or 18)
    local tw = TextWidget:new{ text = self.char, face = face, bold = true }
    tw:paintTo(tmp, 0, 0)
    tw:free()
    local dots, x0, x1, y0, y1 = {}, m, -1, m, -1
    for yy = 0, m - 1 do
        for xx = 0, m - 1 do
            local g = tmp:getPixel(xx, yy):getColor8().a
            if g < 200 then
                table.insert(dots, { xx, yy, 255 - g })
                if xx < x0 then x0 = xx end; if xx > x1 then x1 = xx end
                if yy < y0 then y0 = yy end; if yy > y1 then y1 = yy end
            end
        end
    end
    tmp:free()
    if #dots == 0 then self.dots = false; return end
    local ox = math.floor((n - (x1 - x0 + 1)) / 2) - x0
    local oy = math.floor((n - (y1 - y0 + 1)) / 2) - y0
    self.dots = {}
    for _, d in ipairs(dots) do
        local px, py = d[1] + ox, d[2] + oy
        if px >= 0 and py >= 0 and px < n and py < n then
            table.insert(self.dots, { px, py, BlitBuffer.Color8(d[3]) })
        end
    end
end
function Pages.TextMark:paintTo(bb, x, y)
    if self.dots == nil then self:measure(bb:getType()) end
    if not self.dots then return self.fallback:paintTo(bb, x, y) end
    for _, d in ipairs(self.dots) do bb:paintRect(x + d[1], y + d[2], 1, 1, d[3]) end
end
function Pages.header(owner, title, on_back, right_items, no_back, on_close)
    local W = Screen:getWidth()
    local side = Screen:scaleBySize(8)
    local d = Geom:new{ w = W, h = core.TOPBAR_HEIGHT }
    local right = HorizontalGroup:new{ align = "center" }
    for _i, it in ipairs(right_items or {}) do table.insert(right, it) end
    table.insert(right, atoms.newHeaderButton("close", on_close or on_back, owner, nil, false))
    table.insert(right, HorizontalSpan:new{ width = side })
    local right_w = right:getSize().w
    local left_w = side + core.HEADER_ICON_SIZE + core.HEADER_ICON_PAD * 2 + side
    -- no_back: pages that only have ✕ (the empty-list page) start the title at the edge
    local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = side + (no_back and side or 0) } }
    if not no_back then
        table.insert(left, atoms.newHeaderButton(BD.mirroredUILayout() and "chevron.right" or "chevron.left", on_back, owner, nil, false))
        table.insert(left, HorizontalSpan:new{ width = side })
    end
    table.insert(left, TextWidget:new{ text = title, face = core.getFaceOr(core.SERIF_FONT, 21, "cfont"), bold = true,
        max_width = W - left_w - right_w - side })
    return VerticalGroup:new{
        OverlapGroup:new{ dimen = d, allow_mirroring = false,
            LeftContainer:new{ dimen = d, left },
            RightContainer:new{ dimen = d, right },
        },
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line },
    }
end
-- Shared bottom bar: line, then Cancel (1/3) and the main button (2/3), 48 high, same padding
-- everywhere.
Pages.BUTTON_H = Screen:scaleBySize(48)
Pages.FOOTER_TOP, Pages.FOOTER_BOTTOM = Screen:scaleBySize(12), Screen:scaleBySize(18)
function Pages.button(text, primary, width, callback)
    local tw = TextWidget:new{ text = text, face = Font:getFace("cfont", 15), bold = primary,
        max_width = width - Screen:scaleBySize(12), fgcolor = primary and BlitBuffer.COLOR_WHITE or core.COLORS.ink }
    return atoms.TapBox:new{ atoms.RoundedBox:new{ width = width, radius = Screen:scaleBySize(8),
        fill = primary and core.COLORS.ink or BlitBuffer.COLOR_WHITE, border = primary and 0 or Size.border.button,
        border_color = core.COLORS.ink, pad_x = 0, pad_y = 0,
        CenterContainer:new{ dimen = Geom:new{ w = width, h = Pages.BUTTON_H }, tw } }, callback = callback }
end
function Pages.footer(cancel_cb, primary_text, primary_cb)
    local W = Screen:getWidth()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local gap = Screen:scaleBySize(10)
    local bw1 = math.floor((inner - gap) / 3)
    return VerticalGroup:new{
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line },
        VerticalSpan:new{ width = Pages.FOOTER_TOP },
        HorizontalGroup:new{ HorizontalSpan:new{ width = P },
            Pages.button(_("Cancel"), false, bw1, cancel_cb),
            HorizontalSpan:new{ width = gap },
            Pages.button(primary_text, true, inner - gap - bw1, primary_cb) },
        VerticalSpan:new{ width = Pages.FOOTER_BOTTOM },
    }
end
-- Live sample of the list for the Text / Spacing pages: two real annotations drawn with the
-- current settings, clipped to a fixed height so the page below does not move.
Pages.PreviewClip = WidgetContainer:extend{ w = 0, h = 0 }
function Pages.PreviewClip:getSize() return Geom:new{ w = self.w, h = self.h } end
function Pages.PreviewClip:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local buf = BlitBuffer.new(self.w, self.h, bb:getType())
    buf:fill(BlitBuffer.COLOR_WHITE)
    self[1]:paintTo(buf, 0, 0)
    bb:blitFrom(buf, x, y, 0, 0, self.w, self.h)
    buf:free()
    if core.isScrollbarStyle() and not self.no_bar then -- the list's scrollbar: thin track and an outlined thumb, as a sample
        local cx = self.w - core.SB_STRIP_WIDTH - core.SB_MARGIN_RIGHT + math.floor(core.SB_STRIP_WIDTH / 2)
        local top, bot = Screen:scaleBySize(10), self.h - Screen:scaleBySize(10)
        bb:paintRect(x + cx, y + top, Size.line.thin, bot - top, BlitBuffer.COLOR_BLACK)
        local tw, th = core.SB_THUMB_WIDTH, math.floor((bot - top) / 3)
        bb:paintRect(x + cx - math.floor(tw / 2), y + top, tw, th, BlitBuffer.COLOR_WHITE)
        bb:paintBorder(x + cx - math.floor(tw / 2), y + top, tw, th, Size.border.default, BlitBuffer.COLOR_BLACK, math.floor(tw / 2))
    end
end
function Pages.preview(list, h, mark_gap, bookmarks)
    local W = Screen:getWidth()
    local samples = bookmarks and {
        -- the Bookmarks page: bookmarks as they show in the list, one with a note, one with a long chapter
        { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter One", bookmark = true,
          page_label = 12, datetime = "2026-01-09 10:12:00", highlighted_text = "",
          user_note = "Duis aute irure dolor in reprehenderit in voluptate velit esse." },
        { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter Two", bookmark = true,
          page_label = 27, datetime = "2026-01-11 08:40:00", highlighted_text = "" },
        { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", bookmark = true, page_label = 41,
          chapter = "Chapter Three: Excepteur sint occaecat cupidatat non proident, sunt in culpa",
          datetime = "2026-01-14 21:03:00", highlighted_text = "" },
    } or {
        { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter One",
          datetime = "2026-01-09 10:12:00", drawer = "lighten", color = "yellow",
          highlighted_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
          user_note = "Duis aute irure dolor in reprehenderit in voluptate velit esse." },
        { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter One",
          datetime = "2026-01-09 10:20:00", drawer = "lighten", color = "blue",
          highlighted_text = "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum." },
    }
    local g = VerticalGroup:new{ align = "left" }
    local top = core.getTopPadding()
    local first_h
    if top > 0 then table.insert(g, VerticalSpan:new{ width = top }) end
    -- same width and centring as the real list
    local avail = item.NoteItemWidget.listAvail(W)
    local nw = item.NoteItemWidget.columnWidth(avail, W, Screen:getHeight())
    local x_off = math.floor((avail - nw) / 2) + item.NoteItemWidget.scrollInset()
    for i, n in ipairs(samples) do
        if i > 1 then table.insert(g, VerticalSpan:new{ width = item.NoteItemWidget.gapAbove(n, true) }) end
        local ok, wdg = pcall(function()
            return item.NoteItemWidget:new{ width = nw, note = n, show_parent = list, skip_title = i > 1 }
        end)
        if ok then
            table.insert(g, x_off > 0 and HorizontalGroup:new{ HorizontalSpan:new{ width = x_off }, wdg } or wdg)
            if i == 1 then first_h = wdg:getSize().h end
        end
    end
    -- Spacing page: end the preview just after the top of the second note, so the gap between the
    -- notes can be judged from the sliver of the next one. Text page: tall enough for the whole first
    -- annotation with its note (a bigger or taller note font is not cut off). Bookmarks: all of them.
    -- Never more than half the screen.
    local max_h = math.floor(Screen:getHeight() * 0.5)
    if bookmarks then
        h = math.min(max_h, g:getSize().h + Screen:scaleBySize(12))
    elseif mark_gap and first_h then
        h = math.min(max_h, top + first_h + core.getNoteSpacing() + Screen:scaleBySize(28))
    elseif first_h then
        h = math.min(max_h, math.max(h, top + first_h + Screen:scaleBySize(12)))
    end
    return VerticalGroup:new{ align = "left",
        Pages.PreviewClip:new{ w = W, h = h, g },
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line } }
end
-- Export page: the start of the file as it will be written (the first annotations of the list, or
-- Lorem ipsum when the list is empty), in a fixed-width font, cut off at h.
function Pages.exportPreview(list, h)
    local W = Screen:getWidth()
    local o = exportmod.options()
    local notes = {}
    -- the first three, long texts cut short (the preview only shows the start anyway)
    for i, n in ipairs(list.filtered_notes or {}) do
        if i > 3 then break end
        local c = {}
        for k, v in pairs(n) do c[k] = v end
        for k in pairs({ highlighted_text = true, user_note = true }) do
            if type(c[k]) == "string" and #c[k] > 400 then c[k] = text.utf8Prefix(c[k], 400) .. "…" end
        end
        table.insert(notes, c)
    end
    if #notes == 0 then
        notes = {
            { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter One", page_label = 12,
              datetime = "2026-01-09 10:12:00", drawer = "lighten", color = "yellow", tags = { "lorem" },
              highlighted_text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore.",
              user_note = "Duis aute irure dolor in reprehenderit." },
            { book_title = "Lorem Ipsum", book_authors = "Dolor Sit", chapter = "Chapter Two", page_label = 27,
              datetime = "2026-01-11 08:40:00", drawer = "underscore", color = "blue",
              highlighted_text = "Excepteur sint occaecat cupidatat non proident." },
        }
    end
    local text
    if o.files == "book" then
        local f = exportmod.files(notes, o, list.exportFilterLabel and list:exportFilterLabel() or "", "20260109-101200")[1]
        text = f and f.text or ""
    else
        text = exportmod.build(notes, o, list.exportFilterLabel and list:exportFilterLabel() or "")
    end
    local P = Screen:scaleBySize(24)
    local box = TextBoxWidget:new{ text = text, face = Font:getFace("scfont", 13), width = W - P * 2 }
    local top = Screen:scaleBySize(10)
    local g = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = top },
        HorizontalGroup:new{ HorizontalSpan:new{ width = P }, box } }
    -- end on a whole line, never half of one
    local lh = tonumber(box.line_height_px)
    if lh and lh > 0 and g:getSize().h + top > h then
        h = top + math.max(1, math.floor((h - top * 2) / lh)) * lh
    end
    h = math.min(h, g:getSize().h + top)
    return VerticalGroup:new{ align = "left",
        Pages.PreviewClip:new{ w = W, h = h, no_bar = true, g },
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line } }
end
-- Menus, sheets and dropdowns sit above the list: pass the gestures they don't use on to the
-- KOReader gestures plugin, as the list does (corner taps, edge swipes, ...).
function Pages.forwardGestures(cls)
    table.insert(_tracked_classes, cls)
    if NotesListWidget then NotesListWidget.trackWindow(cls) end
    function cls:onGesture(ev)
        if self.toast then return false end -- toasts let everything through anyway
        if InputContainer.onGesture(self, ev) then return true end
        return _forwardGestureToPlugin(ev, self)
    end
end
Pages.forwardGestures(sheet.AnnotationSheet)
-- Full-screen pages: rebuild for the new size when the screen was rotated.
function Pages.watchResize(cls)
    function cls:paintTo(bb, x, y)
        local W, H = Screen:getWidth(), Screen:getHeight()
        if self.dimen and (self.dimen.w ~= W or self.dimen.h ~= H) and not self._resize_pending then
            self._resize_pending = true
            UIManager:nextTick(function()
                self._resize_pending = nil
                self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
                if self.rebuild then self:rebuild() else self:build() end
                -- the whole screen: a popup (the sheet) moved, and what was under its old place
                -- must be drawn again too
                UIManager:setDirty("all", "full")
            end)
        end
        InputContainer.paintTo(self, bb, x, y)
    end
end
Pages.watchResize(sheet.AnnotationSheet) -- the sheet follows a rotation
-- ✕ on a sub page: close it and every page under it, back to the list.
function Pages.exitAll(w)
    local first = true
    while w do
        UIManager:close(w, first and "flashui" or nil)
        first = false
        w = w.parent_screen or w.parent
    end
end
-- Full-screen pages are paged like the list, with the same Prev / Next bar instead of a scrollbar:
-- `rows` (a VerticalGroup) is cut into pages of whole rows that fit `avail` high; the first
-- `opts.fixed` rows stay on every page; `opts.left` pads the rows on the left. The page number is
-- kept in owner.page_idx, so rebuilding after a change stays on the same page.
-- Which rows go on which page: { first, last } per page (rows 1..fixed on every page). A heading
-- (keep_with_next) never ends a page; a block taller than a page is split into its rows, which
-- gives a new rows list (returned as the second value).
-- Pieces shared by the full-screen pages (P: side padding, inner: width between the paddings).
-- a thin grey line between rows
function Pages.rowLine(P, inner)
    return HorizontalGroup:new{ HorizontalSpan:new{ width = P },
        LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.thin }, background = core.COLORS.line_light } }
end
-- a widget indented by P, with space above and below
function Pages.padded(widget, P, top, bottom)
    local g = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = top or 0 } }
    if Pages.isColumn(widget) then -- each row indented on its own, so a tall column can be split over pages
        for k = 1, #widget do table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = P }, widget[k] }) end
    else
        table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = P }, widget })
    end
    table.insert(g, VerticalSpan:new{ width = bottom or 0 })
    return g
end
-- section titles as in the mockup: small caps-style grey label with a black line under it. Returns
-- a function for one page build (the first title has less space above it).
function Pages.sectionBars(P, inner)
    local first_section = true
    return function(text)
        local top = Screen:scaleBySize(first_section and 10 or 20)
        first_section = false
        local bar = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = top },
            HorizontalGroup:new{ HorizontalSpan:new{ width = P }, VerticalGroup:new{ align = "left",
                TextWidget:new{ text = text, face = Font:getFace("cfont", 11), bold = true, fgcolor = core.COLORS.muted },
                VerticalSpan:new{ width = Screen:scaleBySize(6) },
                LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.medium }, background = core.COLORS.ink } } } }
        bar.keep_with_next = true -- Page.paged never leaves a heading alone at the end of a page
        return bar
    end
end
-- A column of rows that can be split over pages: a left-aligned VerticalGroup
function Pages.isColumn(r)
    if type(r) ~= "table" or r.align ~= "left" then return false end
    local mt = getmetatable(r)
    while mt and mt.__index do
        if mt.__index == VerticalGroup then return true end
        mt = type(mt.__index) == "table" and getmetatable(mt.__index) or nil
    end
    return false
end
function Pages.splitPages(rows, avail, bar_h, fixed_n)
    local n = #rows
    local fixed_h, total = 0, 0
    for i = 1, math.min(fixed_n, n) do fixed_h = fixed_h + rows[i]:getSize().h end
    for i = 1, n do total = total + rows[i]:getSize().h end
    local pages = {}
    if total <= avail then
        -- paged() draws rows 1..fixed_n itself; the page range starts after them so fixed rows
        -- aren't painted twice when everything fits on one page.
        pages[1] = { first = fixed_n + 1, last = n }
    else
        local cap = avail - bar_h - fixed_h
        -- a block taller than a page is split into its own rows, so it can't run under the footer
        -- only a column of rows (a VerticalGroup) can be split
        local function splittable(r)
            return r:getSize().h > cap and #r > 1 and Pages.isColumn(r)
        end
        local split = false
        for i = fixed_n + 1, n do
            if splittable(rows[i]) then split = true; break end
        end
        if split then
            local flat = {}
            local function add(r)
                if splittable(r) then
                    for k = 1, #r do add(r[k]) end
                else
                    flat[#flat + 1] = r
                end
            end
            for i = 1, n do
                if i <= fixed_n then flat[#flat + 1] = rows[i] else add(rows[i]) end
            end
            rows, n = flat, #flat
        end
        local cur, h = nil, 0
        for i = fixed_n + 1, n do
            local rh = rows[i]:getSize().h
            if not cur or (h + rh > cap and h > 0) then
                local start = i
                if cur and i > 1 and rows[i - 1].keep_with_next and cur.last == i - 1 and cur.first < i - 1 then
                    -- a heading would end the page: it moves to the next one with its rows
                    cur.last = i - 2
                    start = i - 1
                    h = rows[start]:getSize().h
                else
                    h = 0
                end
                cur = { first = start, last = start }
                table.insert(pages, cur)
            end
            cur.last = i
            h = h + rh
        end
        if #pages == 0 then pages[1] = { first = n + 1, last = n } end
    end
    return pages, rows
end
function Pages.paged(owner, W, avail, rows, opts)
    opts = opts or {}
    local fixed_n = opts.fixed or 0
    local n
    local bar_h = core.FOOTER_BAR_HEIGHT + Size.line.medium
    local function wrap(g)
        if opts.left then return HorizontalGroup:new{ HorizontalSpan:new{ width = opts.left }, g } end
        return g
    end
    local pages
    pages, rows = Pages.splitPages(rows, avail, bar_h, fixed_n)
    n = #rows
    local count = #pages
    if count == 1 and owner.ges_events then owner.ges_events.PagedSwipe = nil end
    owner.page_idx = math.max(1, math.min(owner.page_idx or 1, count))
    local pg = pages[owner.page_idx]
    local g = VerticalGroup:new{ align = "left" }
    for i = 1, math.min(fixed_n, n) do table.insert(g, rows[i]) end
    for i = pg.first, pg.last do table.insert(g, rows[i]) end
    local content = wrap(g)
    if count == 1 then return content end

    local function go(p)
        owner.page_idx = p
        if owner.rebuild then owner:rebuild() else owner:build(); UIManager:setDirty(owner, "ui") end
    end
    local cur = owner.page_idx
    local has_prev, has_next = cur > 1, cur < count
    local bar = NotesListWidget.navBar{
        width = W, label = string.format("%d / %d", cur, count), has_prev = has_prev, has_next = has_next,
        first = function() go(1) end, prev = function() go(cur - 1) end,
        next = function() go(cur + 1) end, last = function() go(count) end,
        side = Screen:scaleBySize(2),
    }
    -- left / right swipes and page-turn keys also turn the pages. Always left / right, whatever the
    -- list's swipe setting: these pages turn sideways like KOReader's own menus.
    owner.ges_events = owner.ges_events or {}
    owner.ges_events.PagedSwipe = { GestureRange:new{ ges = "swipe",
        range = Geom:new{ x = 0, y = 0, w = W, h = Screen:getHeight() } } }
    owner.onPagedSwipe = function(_self, _args, ges)
        local d = ges and BD.flipDirectionIfMirroredUILayout(ges.direction)
        if d == "west" then
            if has_next then go(cur + 1) end
            return true
        elseif d == "east" then
            if has_prev then go(cur - 1) end
            return true
        end
    end
    if Device:hasKeys() then
        owner.key_events = owner.key_events or {}
        owner.key_events.PagedNext = { { Input.group.PgFwd } }
        owner.key_events.PagedPrev = { { Input.group.PgBack } }
        owner.onPagedNext = function() if has_next then go(cur + 1) end return true end
        owner.onPagedPrev = function() if has_prev then go(cur - 1) end return true end
    end
    local used = content:getSize().h
    return VerticalGroup:new{ align = "left", content,
        VerticalSpan:new{ width = math.max(0, avail - bar_h - used) },
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.medium }, background = core.COLORS.line },
        bar }
end
function Pages.countText(n, list)
    if list and list:tabKey() == "bookmarks" then
        return n == 1 and _("Show 1 bookmark") or string.format(_("Show %d bookmarks"), n)
    end
    return n == 1 and _("Show 1 annotation") or string.format(_("Show %d annotations"), n)
end

-- States board: loading, no annotations, nothing matches, delete confirmation, export done.
-- Kept in one table (NotesListWidget.States) so the code outside this block can call it.
Pages.States = {}

-- Text as separate single-line TextWidgets (same rendering as the tabs, so small grey text is
-- not drawn lighter than elsewhere on some devices); centred or left aligned within width.
function Pages.States.lines(str, face, width, color, bold, centered)
    local g = VerticalGroup:new{ align = centered and "center" or "left" }
    for _i, l in ipairs((text.wrapText(str, face, width))) do
        table.insert(g, TextWidget:new{ text = l, face = face, fgcolor = color, bold = bold })
    end
    if not centered then return g end
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = g:getSize().h }, g }
end
function Pages.States.title(text, size, width, centered)
    return Pages.States.lines(text, core.getFaceOr(core.SERIF_FONT, size, "cfont"), width, core.COLORS.ink, true, centered)
end

-- Popup card: white box with KOReader's window border and rounded corners, at the centre or
-- the bottom. modal: tap outside / Back closes it. toast: never blocks the screen under it
-- (taps go through) and closes itself after `timeout` seconds.
Pages.States.Card = InputContainer:extend{
    anchor = "center", build = nil, modal = false, toast = false, timeout = nil, cancel_cb = nil,
    width = nil, pad_h = nil, pad_v = nil, left = nil, top = nil, -- for the ☰ menu: own size and place
}
function Pages.States.Card:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.screen_w, self.screen_h = W, H
    local col_w = W > H and math.min(W, math.floor(H * 1.1)) or W
    local margin = Screen:scaleBySize(14)
    local bw = Size.border.window
    local pad = Screen:scaleBySize(16) + bw
    local pad_x, pad_y = self.pad_h or pad, self.pad_v or pad
    local box_w = self.width or (col_w - margin * 2)
    self.box = atoms.RoundedBox:new{ width = box_w, fill = BlitBuffer.COLOR_WHITE, radius = Screen:scaleBySize(10),
        border = bw, border_color = core.COLORS.ink, pad_x = pad_x, pad_y = pad_y, self.build(box_w - pad_x * 2, self) }
    local box_h = self.box:getSize().h
    self.box_x = self.left or math.floor((W - box_w) / 2)
    if self.top then
        self.box_y = self.top
    elseif self.anchor == "bottom" then
        self.box_y = H - box_h - Screen:scaleBySize(16)
    else
        self.box_y = math.floor((H - box_h) / 2)
    end
    -- only the card's own area is repainted when it appears or goes away
    self.dimen = Geom:new{ x = self.box_x, y = self.box_y, w = box_w, h = box_h }
    self[1] = self.box
    self.ges_events = {}
    if self.modal then
        self.ges_events.TapOutside = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
        if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    end
end
function Pages.States.Card:paintTo(bb)
    -- the screen was rotated: build the card again for the new size and place
    if (self.screen_w ~= Screen:getWidth() or self.screen_h ~= Screen:getHeight()) and not self._resize_pending then
        self._resize_pending = true
        UIManager:nextTick(function()
            self._resize_pending = nil
            if not UIManager:isWidgetShown(self) then return end -- closed in the meantime
            -- a card placed by hand (the ☰ menu, the sort card) would be in the wrong place: it closes
            if self.left or self.top then return self:onClose() end
            if self.timeout_cb then UIManager:unschedule(self.timeout_cb) end
            self:init()
            if self.timeout then self:onShow() end
            UIManager:setDirty("all", "full") -- also where the card was before
        end)
    end
    self.box:paintTo(bb, self.box_x, self.box_y)
end
function Pages.States.Card:onShow()
    if self.timeout then
        self.timeout_cb = function() UIManager:close(self, "ui", self.dimen) end -- only its own area
        UIManager:scheduleIn(self.timeout, self.timeout_cb)
    end
end
function Pages.States.Card:onCloseWidget()
    if self.timeout_cb then UIManager:unschedule(self.timeout_cb) end
end
Pages.forwardGestures(Pages.States.Card) -- after onShow / onCloseWidget, which it wraps
function Pages.States.Card:onTapOutside(_arg, ges)
    if ges and ges.pos and ges.pos:intersectWith(self.dimen) then return true end
    return self:onClose()
end
-- Back, tap outside, Cancel: closes, then cancel_cb (e.g. back to the menu it came from).
function Pages.States.Card:onClose()
    local cb = self.cancel_cb
    self.cancel_cb = nil
    UIManager:close(self, "ui")
    if cb then cb() end
    return true
end
-- A choice was made: closes without cancel_cb.
function Pages.States.Card:dismiss()
    self.cancel_cb = nil
    return self:onClose()
end
function Pages.States.Card:show()
    UIManager:show(self, "ui", self.dimen)
    return self
end

-- Shown over the library while the first open reads the books.
function Pages.States.loading()
    local card = Pages.States.Card:new{ build = function(w)
        return VerticalGroup:new{ align = "center",
            Pages.States.title(_("Loading annotations…"), 17, w, true),
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            Pages.States.lines(_("Reading your books. Only the first time after starting KOReader."),
                Font:getFace("cfont", 13), w, core.COLORS.muted, false, true),
        }
    end }
    card:show()
    UIManager:forceRePaint()
    return card
end

-- Delete confirmation: shows the highlight that will go, and says when its note goes too.
function Pages.States.confirmDelete(note, on_delete)
    local nw = core.NoteWrapper:new(note)
    local has_text = nw:hasHighlightedText()
    Pages.States.Card:new{ modal = true, build = function(w, card)
        local g = VerticalGroup:new{ align = "left" }
        local title = has_text and _("Delete this highlight?") or _("Delete this annotation?")
        if note.bookmark then title = _("Delete this bookmark?") end
        table.insert(g, Pages.States.title(title, 17, w))
        if note.bookmark then -- which one: "Page 34 · Chapter Two"
            local where = { item.NoteItemWidget.pageText(note) }
            if note.chapter and note.chapter ~= "" then table.insert(where, note.chapter) end
            if #where > 0 then
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
                table.insert(g, Pages.States.lines(table.concat(where, " · "), Font:getFace("cfont", 14), w, core.COLORS.ink, true, false))
            end
        end
        if has_text then
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
            local drawer = note.drawer or "lighten"
            local no_fill = core.isNoBackgroundStyle(drawer)
            local fill
            if drawer == "invert" then fill = BlitBuffer.COLOR_BLACK
            elseif not no_fill then fill = core.getHighlightColor(note.color) end
            local face = select(3, item.getNoteFaces())
            local pad_h, pad_v, ob = Screen:scaleBySize(10), Screen:scaleBySize(8), Size.border.thin
            local lines = sheet.buildHighlightLines(sheet.cleanHighlightText(note.highlighted_text), face,
                w - (pad_h + ob) * 2, drawer, note.color, 2, true)
            table.insert(g, atoms.RoundedBox:new{ width = w, fill = fill or BlitBuffer.COLOR_WHITE,
                true_color = not no_fill and drawer ~= "invert",
                radius = Screen:scaleBySize(6), border = no_fill and ob or 0, border_color = core.COLORS.line,
                pad_x = pad_h + ob, pad_y = pad_v + ob, lines })
        end
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
        table.insert(g, Pages.States.lines(nw:hasUserNote()
            and _("Your note on it is deleted too. This can’t be undone.") or _("This can’t be undone."),
            Font:getFace("cfont", 13), w, core.COLORS.muted, false, false))
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(14) })
        local gap = Screen:scaleBySize(10)
        local bw = math.floor((w - gap) / 2)
        table.insert(g, HorizontalGroup:new{
            Pages.button(_("Cancel"), false, bw, function() card:onClose() end),
            HorizontalSpan:new{ width = gap },
            Pages.button(_("Delete"), true, w - gap - bw, function() card:onClose(); on_delete() end),
        })
        return g
    end }:show()
end

-- Export done: a note at the bottom that closes itself; the list under it stays usable.
-- path: the file, or the folder when there are several files; copied: put on the clipboard instead.
function Pages.States.exported(count, path, bookmarks, n_files, copied)
    local rel = path
    local ok, DataStorage = pcall(require, "datastorage")
    if ok and path then
        local dir = DataStorage:getDataDir()
        local name = dir:match("([^/\\]+)[/\\]*$")
        if not name or name == "." then name = "koreader" end
        if path:sub(1, #dir) == dir then rel = name .. path:sub(#dir + 1) end
    end
    Pages.States.Card:new{ anchor = "bottom", toast = true, timeout = 5, build = function(w)
        local icon_s = Screen:scaleBySize(18)
        local gap = Screen:scaleBySize(8)
        local title
        if copied then
            title = bookmarks and (count == 1 and _("Copied 1 bookmark") or string.format(_("Copied %d bookmarks"), count))
                or (count == 1 and _("Copied 1 annotation") or string.format(_("Copied %d annotations"), count))
        else
            title = count == 1 and _("Exported 1 annotation") or string.format(_("Exported %d annotations"), count)
            if bookmarks then
                title = count == 1 and _("Exported 1 bookmark") or string.format(_("Exported %d bookmarks"), count)
            end
        end
        local sub = rel
        if copied then sub = _("to the clipboard")
        elseif n_files and n_files > 1 then sub = string.format(_("%d files in %s"), n_files, tostring(rel)) end
        return VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ align = "center",
                IconWidget:new{ icon = "check", width = icon_s, height = icon_s },
                HorizontalSpan:new{ width = gap },
                TextWidget:new{ text = title, face = Font:getFace("cfont", 15), bold = true, max_width = w - icon_s - gap } },
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            TextWidget:new{ text = tostring(sub or ""), face = Font:getFace("cfont", 12), fgcolor = core.COLORS.muted, max_width = w },
        }
    end }:show()
end

-- The ☰ menu: a card under the button with an icon, a label and a short status on each row.
-- (Filters and sort are behind the funnel button and the tab row.)
function Pages.States.menu(list)
    local W = Screen:getWidth()
    local af = list.active_filter or {}
    local items = {}
    if not list.single_book then
        local n_books = list:offeredCount("books", "books_exclude", NotesListWidget.bookKeys)
        local filtered = (af.books and next(af.books)) or (af.books_exclude and next(af.books_exclude))
        table.insert(items, { icon = "book.opened", label = _("Books"),
            value = filtered and _("Filtered") or string.format(_("All %d"), n_books),
            cb = function() list:showBookPicker(function() end) end })
    end
    if #items > 0 then table.insert(items, "line") end -- (no line at the top of the one-book menu)
    table.insert(items, { icon = "move.up", label = _("Export"), chevron = true,
        value = string.format(_("%d shown"), #(list.filtered_notes or {})), cb = function() list:showExportPage() end })
    table.insert(items, { icon = "cre.render.reload", label = _("Reload annotations"),
        cb = function() list.viewer:reloadAnnotations(list) end })
    table.insert(items, "line")
    table.insert(items, { icon = "appbar.settings", label = _("Settings"), chevron = true,
        cb = function() list:showSettingsMenu() end })
    local bw = Size.border.window
    Pages.States.Card:new{ modal = true, width = math.min(Screen:scaleBySize(330), W - Screen:scaleBySize(20)),
        left = Screen:scaleBySize(10), top = core.TOPBAR_HEIGHT + Screen:scaleBySize(4),
        pad_h = bw, pad_v = bw + Screen:scaleBySize(6),
        build = function(w, card)
            local g = VerticalGroup:new{ align = "left" }
            local side, icon_s, gap = Screen:scaleBySize(16), Screen:scaleBySize(22), Screen:scaleBySize(14)
            for _i, it in ipairs(items) do
                if it == "line" then
                    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
                    table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                        LineWidget:new{ dimen = Geom:new{ w = w - side * 2, h = Size.line.thin }, background = core.COLORS.line_light } })
                    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
                else
                    local icon = IconWidget:new{ icon = it.icon, width = icon_s, height = icon_s }
                    local value = it.value and TextWidget:new{ text = it.value, face = Font:getFace("cfont", 12),
                        fgcolor = core.COLORS.muted, max_width = math.floor(w * 0.35) }
                    local right = HorizontalGroup:new{ align = "center" }
                    if value then table.insert(right, value) end
                    if it.chevron then
                        table.insert(right, IconWidget:new{ icon = "chevron.right",
                            width = Screen:scaleBySize(16), height = Screen:scaleBySize(16) })
                    end
                    table.insert(right, HorizontalSpan:new{ width = side })
                    local label_w = w - side - icon_s - gap - right:getSize().w - gap
                    local d = Geom:new{ w = w, h = Screen:scaleBySize(50) }
                    local cb = it.cb
                    table.insert(g, atoms.TapBox:new{ OverlapGroup:new{ dimen = d, allow_mirroring = false,
                        LeftContainer:new{ dimen = d, HorizontalGroup:new{ align = "center",
                            HorizontalSpan:new{ width = side }, icon, HorizontalSpan:new{ width = gap },
                            TextWidget:new{ text = it.label, face = Font:getFace("cfont", 15), max_width = label_w } } },
                        RightContainer:new{ dimen = d, right } },
                        callback = function() card:onClose(); cb() end })
                end
            end
            return g
        end }:show()
end

-- Sort order as a dropdown card under the sort label: up to three levels (sort by, then by, then by).
-- Each level is a row of chips for the keys that still make sense plus a two-part bar for the
-- direction, and a sentence at the bottom says in words what the order is.
-- Sort chips as wide as their text; each row is filled to the edge by sharing out what is left.
-- items = { { label, on, callback } }; the chosen one gets a thick black outline.
function Pages.States.sortChips(g, side, inner, items)
    local thin, thick = Size.border.button, Size.border.thick
    local gap = Screen:scaleBySize(8)
    local chip_h = Screen:scaleBySize(36)
    local face = Font:getFace("cfont", 13)
        local widths = {}
    for i, it in ipairs(items) do
        widths[i] = TextWidget:new{ text = it.label, face = face, bold = true }:getSize().w + Screen:scaleBySize(26)
    end
    local rows, row, row_w = {}, {}, 0
    for i in ipairs(items) do
        if #row > 0 and row_w + gap + widths[i] > inner then
            rows[#rows + 1] = row; row, row_w = {}, 0
        end
        row_w = row_w + (#row > 0 and gap or 0) + widths[i]
        row[#row + 1] = i
    end
    if #row > 0 then rows[#rows + 1] = row end
    for _, r in ipairs(rows) do
        local used = (#r - 1) * gap
        for _, i in ipairs(r) do used = used + widths[i] end
        -- rows may stretch to the edge, but a chip never gets narrower than its text. One wider
        -- than the row says so (the sort card then uses the menu); on the full pages it gets the
        -- whole row, as wide as it can be on the screen.
        local extra, rg = math.max(0, inner - used), HorizontalGroup:new{ HorizontalSpan:new{ width = side } }
        for k, i in ipairs(r) do
            local it = items[i]
            if widths[i] > inner then Pages.States.chip_overflow = true end
            local cw = math.min(inner, widths[i] + math.floor(extra / #r) + (k == #r and extra % #r or 0))
            local color = BlitBuffer.COLOR_BLACK
            if k > 1 then table.insert(rg, HorizontalSpan:new{ width = gap }) end
            table.insert(rg, atoms.TapBox:new{
                atoms.Pill:new{ width = cw, height = chip_h, fill = BlitBuffer.COLOR_WHITE,
                    border = it.on and thick or thin, border_color = it.on and core.COLORS.ink or core.COLORS.line,
                    TextWidget:new{ text = it.label, face = face, bold = it.on, fgcolor = color,
                        max_width = cw - Screen:scaleBySize(8) } },
                callback = it.callback })
        end
        table.insert(g, rg)
        table.insert(g, VerticalSpan:new{ width = gap })
    end
end

-- The Sort by / Then by / And then by rows: per level a row of key chips (as wide as their text,
-- each row filled to the edge; the chosen one has a thick black outline) and a two-part direction
-- bar. Used by the sort card and by the Filter & sort page. Appends to group g.
-- o = { width, side, single, levels, apply = function(new_levels), heading = function(text) }
function Pages.States.sortLevels(g, o)
    local side, inner, single, levels = o.side, o.width, o.single, o.levels
    local thin = Size.border.button
    local bar_h = Screen:scaleBySize(38)
    local face = Font:getFace("cfont", 13)
    local heading = o.heading
    local function chipRows(items) Pages.States.sortChips(g, side, inner, items) end
    -- two joined halves in one outline, the chosen one black
    local function directionBar(lv, on_flip)
        local cell_h = bar_h
        local cell_w = math.floor((inner - thin * 2 - thin) / 2)
        local cells = {}
        for _, dir in ipairs({ "asc", "desc" }) do
            local on = lv.dir == dir
            if lv.key == "date" or lv.key == "opened" then dir = dir == "asc" and "desc" or "asc"; on = lv.dir == dir end
            table.insert(cells, atoms.TapBox:new{
                FrameContainer:new{ bordersize = 0, padding = 0, margin = 0,
                    background = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                    CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h },
                        TextWidget:new{ text = sort.SortState.dirName(lv.key, dir, single), face = face, bold = on,
                            max_width = cell_w - Screen:scaleBySize(8),
                            fgcolor = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK } } },
                callback = function() if not on then on_flip() end end })
        end
        local seg = HorizontalGroup:new{}
        for i, c in ipairs(cells) do
            if i > 1 then table.insert(seg, LineWidget:new{ dimen = Geom:new{ w = thin, h = cell_h }, background = BlitBuffer.COLOR_BLACK }) end
            table.insert(seg, c)
        end
        table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
            atoms.RoundedOutline:new{ radius = Screen:scaleBySize(8), border = thin, seg } })
    end
    local titles = { _("Sort by"), _("Then by"), _("And then by") }
    for n = 1, 3 do
        local prev = levels[n - 1]
        local allowed = sort.SortState.allowedAfter(prev, single)
        if (n == 1 or prev) and #allowed > 0 then
            heading(titles[n])
            local lv = levels[n]
            local function upto(k)
                local c = {}
                for x = 1, k do c[x] = levels[x] end
                return c
            end
            local keys = {}
            if n > 1 then keys[1] = { label = _("None"), on = lv == nil, callback = function() if lv then o.apply(upto(n - 1)) end end } end
            for _, k in ipairs(allowed) do
                keys[#keys + 1] = { label = sort.SortState.keyName(k, single), on = lv ~= nil and lv.key == k,
                    callback = function()
                        if lv and lv.key == k then return end
                        local c = upto(n - 1)
                        c[n] = { key = k, dir = (k == "date" or k == "opened") and "desc" or "asc" }
                        for x = n + 1, #levels do c[x] = levels[x] end
                        o.apply(c)
                    end }
            end
            chipRows(keys)
            if lv then
                directionBar(lv, function()
                    local c = upto(#levels)
                    c[n] = { key = lv.key, dir = lv.dir == "asc" and "desc" or "asc" }
                    o.apply(c)
                end)
            end
        end
    end
end

-- The usual orders, one tap each: on the sort card and on the Sort page.
function Pages.States.quickPicks(single)
    return single and sort.SortState.QUICK_BOOK or {
        { _("Newest"), "date:desc" }, { _("Oldest"), "date:asc" }, { _("Book A–Z"), "book:asc" },
        { _("Author A–Z"), "author:asc" }, { _("Last opened book"), "opened:desc" },
        { _("In book order"), "book:asc,pos:asc" },
    }
end
function Pages.States.sortMenu(list, on_done)
    local W = Screen:getWidth()
    local single = list.single_book
    local current = sort.SortState.get(single)
    local levels = sort.SortState.view(current, single)
    local function apply(new_levels, card)
        card:onClose()
        sort.SortState.set(single, sort.SortState.encode(sort.SortState.revalidate(new_levels, single)))
        list:applySort()
        list:refresh()
        if on_done then on_done() end
        Pages.States.sortMenu(list, on_done)
    end
    local quick = Pages.States.quickPicks(single)
    local card_w = math.min(Screen:scaleBySize(360), W - Screen:scaleBySize(20))
    local bw = Size.border.window
    local too_tall = false
    local sort_card = Pages.States.Card:new{ modal = true, width = card_w,
        left = W - card_w - Screen:scaleBySize(10),
        top = list.topbar_height + Screen:scaleBySize(4),
        pad_h = bw, pad_v = bw + Screen:scaleBySize(4),
        build = function(w, card)
            -- tier 0: everything; 1: without the quick picks; 2: also without the sentence.
            -- (The chips themselves never change size.)
            -- The first tier that fits the screen is used.
            local function make(tier, lvls)
            local levels = lvls or levels
            local g = VerticalGroup:new{ align = "left" }
            local side = Screen:scaleBySize(16)
            local inner = w - side * 2
            local thin = Size.border.button
            local function heading(text)
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                    TextWidget:new{ text = text:upper(), face = Font:getFace("cfont", 11), bold = true, fgcolor = core.COLORS.muted } })
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            end
            local encoded = sort.SortState.encode(levels)
            if tier < 1 then
                heading(_("Quick picks"))
                local items = {}
                for _, q in ipairs(quick) do
                    items[#items + 1] = { label = q[1], on = sort.SortState.encode(sort.SortState.parse(q[2])) == encoded,
                        callback = function() apply(sort.SortState.parse(q[2]), card) end }
                end
                Pages.States.sortChips(g, side, inner, items)
                -- a line between the usual orders and building your own
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                    LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.medium }, background = core.COLORS.line } })
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            end
            Pages.States.sortLevels(g, { width = inner, side = side, single = single, levels = levels,
                heading = heading, apply = function(c) apply(c, card) end })
            if tier < 2 then
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(12) })
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                    FrameContainer:new{ bordersize = thin, color = core.COLORS.line, radius = Screen:scaleBySize(8),
                        padding = Screen:scaleBySize(8), margin = 0,
                        TextBoxWidget:new{ text = sort.SortState.describe(levels, single), face = Font:getFace("cfont", 13),
                            width = inner - Screen:scaleBySize(16) - thin * 2 } } })
            end
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
            return g
            end
            local avail = Screen:getHeight() - list.topbar_height - Screen:scaleBySize(20) - (bw + Screen:scaleBySize(4)) * 2
            -- Which version to use is decided on the fullest card there can be (three levels, all
            -- with a direction), so picking a different order never swaps the card for the menu or back.
            local fullest = sort.SortState.parse(single and "chapter:asc,date:desc,pos:asc" or "author:asc,book:asc,pos:asc")
            local use = 2
            for tier = 0, 2 do
                if make(tier, fullest):getSize().h <= avail then use = tier; break end
            end
            local g = make(use)
            Pages.States.chip_overflow = false
            if make(use, fullest):getSize().h > avail then too_tall = true end
            -- a chip wider than the card (big font, narrow screen): the menu, as chips never shrink
            if Pages.States.chip_overflow then too_tall = true end
            return g
        end }
    -- still too tall for this screen: a plain menu instead (one row per level)
    if too_tall then Pages.States.sortList(list, on_done) else sort_card:show() end
end

-- The sort order as a menu, for screens too small for the chip card: a row per level that opens a
-- list of keys, and a row under it that flips the direction.
-- on_cancel: Back / tap outside (the sort menu opens again)
function Pages.States.chooseCard(list, title, options, on_cancel)
    local W = Screen:getWidth()
    local card_w = math.min(Screen:scaleBySize(360), W - Screen:scaleBySize(20))
    local bw = Size.border.window
    Pages.States.Card:new{ modal = true, width = card_w, cancel_cb = on_cancel,
        left = W - card_w - Screen:scaleBySize(10), top = list.topbar_height + Screen:scaleBySize(4),
        pad_h = bw, pad_v = bw + Screen:scaleBySize(4),
        build = function(w, card)
            local g = VerticalGroup:new{ align = "left" }
            local side = Screen:scaleBySize(16)
            table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                TextWidget:new{ text = title:upper(), face = Font:getFace("cfont", 11), bold = true, fgcolor = core.COLORS.muted } })
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            for _, o in ipairs(options) do
                local d = Geom:new{ w = w - side * 2, h = Screen:scaleBySize(46) }
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side }, atoms.TapBox:new{
                    LeftContainer:new{ dimen = d, TextWidget:new{ text = (o.on and "✓ " or "") .. o.label,
                        face = Font:getFace("cfont", 15), bold = o.on, max_width = d.w } },
                    callback = function() card:dismiss(); o.callback() end } })
            end
            return g
        end }:show()
end
function Pages.States.sortList(list, on_done)
    local W = Screen:getWidth()
    local single = list.single_book
    local levels = sort.SortState.view(sort.SortState.get(single), single)
    local function apply(new_levels)
        sort.SortState.set(single, sort.SortState.encode(sort.SortState.revalidate(new_levels, single)))
        list:applySort()
        list:refresh()
        if on_done then on_done() end
        Pages.States.sortList(list, on_done)
    end
    local function upto(k)
        local c = {}
        for x = 1, k do c[x] = levels[x] end
        return c
    end
    local card_w = math.min(Screen:scaleBySize(360), W - Screen:scaleBySize(20))
    local bw = Size.border.window
    local quick = Pages.States.quickPicks(single)
    Pages.States.Card:new{ modal = true, width = card_w,
        left = W - card_w - Screen:scaleBySize(10), top = list.topbar_height + Screen:scaleBySize(4),
        pad_h = bw, pad_v = bw + Screen:scaleBySize(4),
        build = function(w, card)
            local g = VerticalGroup:new{ align = "left" }
            local side = Screen:scaleBySize(16)
            local inner = w - side * 2
            local function row(label, value, callback)
                local d = Geom:new{ w = inner, h = Screen:scaleBySize(46) }
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side }, atoms.TapBox:new{
                    OverlapGroup:new{ dimen = d, allow_mirroring = false,
                        LeftContainer:new{ dimen = d, TextWidget:new{ text = label, face = Font:getFace("cfont", 15),
                            max_width = math.floor(inner * 0.4) } },
                        RightContainer:new{ dimen = d, TextWidget:new{ text = value, face = Font:getFace("cfont", 14), bold = true,
                            max_width = math.floor(inner * 0.58) } } },
                    callback = function() card:dismiss(); callback() end } })
                table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = side },
                    LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.thin }, background = core.COLORS.line_light } })
            end
            row(_("Quick picks"), sort.sortModeLabel(sort.SortState.get(single), single) .. " ›", function()
                local opts, now = {}, sort.SortState.encode(levels)
                for _, q in ipairs(quick) do
                    opts[#opts + 1] = { label = q[1], on = sort.SortState.encode(sort.SortState.parse(q[2])) == now,
                        callback = function() apply(sort.SortState.parse(q[2])) end }
                end
                Pages.States.chooseCard(list, _("Quick picks"), opts, function() Pages.States.sortList(list, on_done) end)
            end)
            local titles = { _("Sort by"), _("Then by"), _("And then by") }
            for n = 1, 3 do
                local prev = levels[n - 1]
                local allowed = sort.SortState.allowedAfter(prev, single)
                if (n == 1 or prev) and #allowed > 0 then
                    local lv = levels[n]
                    row(titles[n], (lv and sort.SortState.keyName(lv.key, single) or _("None")) .. " ›", function()
                        local opts = {}
                        if n > 1 then
                            opts[1] = { label = _("None"), on = lv == nil, callback = function() apply(upto(n - 1)) end }
                        end
                        for _, k in ipairs(allowed) do
                            opts[#opts + 1] = { label = sort.SortState.keyName(k, single), on = lv ~= nil and lv.key == k,
                                callback = function()
                                    if lv and lv.key == k then return Pages.States.sortList(list, on_done) end
                                    local c = upto(n - 1)
                                    c[n] = { key = k, dir = (k == "date" or k == "opened") and "desc" or "asc" }
                                    for x = n + 1, #levels do c[x] = levels[x] end
                                    apply(c)
                                end }
                        end
                        Pages.States.chooseCard(list, titles[n], opts, function() Pages.States.sortList(list, on_done) end)
                    end)
                    if lv then
                        row("", sort.SortState.dirName(lv.key, lv.dir, single) .. " ⇅", function()
                            local c = upto(#levels)
                            c[n] = { key = lv.key, dir = lv.dir == "asc" and "desc" or "asc" }
                            apply(c)
                        end)
                    end
                end
            end
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
            return g
        end }:show()
end

-- Centre of the list when filters (or the tab) leave nothing: what happened, and one tap to undo.
function Pages.States.noMatch(list, width, height)
    local filtered = #list:getFilterChips() > 0
    local col_w = math.min(width, math.floor(Screen:getHeight() * 1.1)) - Screen:scaleBySize(22) * 2
    if #(list.notes_list or {}) == 0 then
        -- no annotations at all: the list's own title bar stays, the body explains
        local icon_s = Screen:scaleBySize(44)
        return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, VerticalGroup:new{ align = "center",
            IconWidget:new{ icon = "edit", width = icon_s, height = icon_s },
            VerticalSpan:new{ width = Screen:scaleBySize(12) },
            Pages.States.title(_("No annotations yet"), 18, col_w, true),
            VerticalSpan:new{ width = Screen:scaleBySize(10) },
            Pages.States.lines(list.single_book and _("Highlight a passage in this book and it shows up here.")
                or _("Highlight a passage in any book and it shows up here."),
                Font:getFace("cfont", 13), col_w, core.COLORS.muted, false, true),
        } }
    end
    local g = VerticalGroup:new{ align = "center",
        Pages.States.title(filtered and _("Nothing matches") or _("Nothing here"), 18, col_w, true),
        VerticalSpan:new{ width = Screen:scaleBySize(12) },
    }
    local hidden = list.tab_totals and list.tab_totals[list:tabKey()] or #(list.notes_list or {})
    local bm_tab = list:tabKey() == "bookmarks"
    local body = bm_tab and _("No bookmarks in this view.") or _("No annotations in this view.")
    if filtered then
        body = (bm_tab and _("No bookmarks fit these filters.") or _("No annotations fit these filters.")) .. " "
            .. (hidden == 1 and _("1 is hidden.") or string.format(_("%d are hidden."), hidden))
    end
    table.insert(g, Pages.States.lines(body, Font:getFace("cfont", 13), col_w, core.COLORS.muted, false, true))
    if filtered then
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(14) })
        table.insert(g, Pages.button(_("Clear filters"), true, Screen:scaleBySize(170), function() list:clearFilters() end))
    end
    return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, g }
end

function Pages.deepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = Pages.deepCopy(v) end
    return c
end
Pages.FilterScreen = InputContainer:extend{ list = nil, helpers = nil, covers_fullscreen = true }
Pages.watchResize(Pages.FilterScreen)
Pages.forwardGestures(Pages.FilterScreen)
function Pages.FilterScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.saved_filter = Pages.deepCopy(self.list.active_filter or {})
    self.saved_sorts = sort.SortState.snapshot() -- a saved filter can change the other tab's order too
    if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    self:build()
end
function Pages.FilterScreen:rebuild()
    self:build()
    UIManager:setDirty(self, "ui")
end
function Pages.FilterScreen:changed()
    self.list.current_page = 1
    self.list:refresh()
    self:rebuild()
end
function Pages.FilterScreen:build()
    local list = self.list
    list.active_filter = list.active_filter or {}
    local af = list.active_filter
    data.normalizeColorStyle(af)
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local thin = Size.border.button
    local MUTED = core.COLORS.muted
    local face15 = Font:getFace("cfont", 15)
    local face14 = Font:getFace("cfont", 14)
    local face13 = Font:getFace("cfont", 13)
    local function underlined(text, face)
        local tw = TextWidget:new{ text = text, face = face }
        return VerticalGroup:new{ tw, LineWidget:new{ dimen = Geom:new{ w = tw:getSize().w, h = Size.line.medium },
            background = BlitBuffer.COLOR_BLACK } }
    end
    local function rowLine() return Pages.rowLine(P, inner) end
    local function padded(widget, top, bottom) return Pages.padded(widget, P, top, bottom) end
    local sectionBar = Pages.sectionBars(P, inner)
    local function labelRow(left, right)
        local d = Geom:new{ w = inner, h = math.max(left:getSize().h, right and right:getSize().h or 0) }
        return OverlapGroup:new{ dimen = d, allow_mirroring = false,
            LeftContainer:new{ dimen = d, left }, right and RightContainer:new{ dimen = d, right } or nil }
    end
    -- chip: black with white bold text when on; white with a border when off. Width is
    -- always that of the "on" (bold) version so choosing never reflows the rows.
    local function chip(text, on, callback, opts)
        opts = opts or {}
        local h = opts.h or Screen:scaleBySize(34)
        -- opts.single: one of a single choice (saved filters): a thick black outline when chosen,
        -- as on the annotation sheet; black fill is for chips of which several can be on
        local filled = on and not opts.single
        local color = filled and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK
        local widest = TextWidget:new{ text = text, face = face13, bold = true }:getSize().w
        local tw = TextWidget:new{ text = text, face = face13, bold = on, fgcolor = color }
        local label = sheet.decoratedText(tw, opts.deco, color)
        local content = HorizontalGroup:new{ align = "center" }
        local extra = 0
        local dots = opts.dots or (opts.dot and { opts.dot }) or {}
        for _i, dname in ipairs(dots) do
            table.insert(content, atoms.Pill:new{ width = Screen:scaleBySize(12), height = Screen:scaleBySize(12), border = 0, true_color = true,
                fill = dname == "gray" and BlitBuffer.COLOR_GRAY or core.getHighlightColor(dname) })
            table.insert(content, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
            extra = extra + Screen:scaleBySize(18)
        end
        table.insert(content, label)
        local w = math.max(widest + extra + Screen:scaleBySize(28), opts.w or 0) -- opts.w: stretch to this width
        return { w = w, widget = atoms.TapBox:new{
            atoms.Pill:new{ width = w, height = h, fill = filled and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                border = filled and 0 or (on and Size.border.thick or thin),
                border_color = on and core.COLORS.ink or core.COLORS.line, content },
            callback = callback, hold_callback = opts.hold,
        } }
    end
    local function flow(items, gap)
        gap = gap or Screen:scaleBySize(8)
        local rows = VerticalGroup:new{ align = "left" }
        local row, row_w = HorizontalGroup:new{}, 0
        for _i, it in ipairs(items) do
            if row_w > 0 and row_w + gap + it.w > inner then
                table.insert(rows, row); table.insert(rows, VerticalSpan:new{ width = gap })
                row, row_w = HorizontalGroup:new{}, 0
            end
            if row_w > 0 then table.insert(row, HorizontalSpan:new{ width = gap }); row_w = row_w + gap end
            table.insert(row, it.widget); row_w = row_w + it.w
        end
        if row_w > 0 then table.insert(rows, row) end
        return rows
    end
    local function setSummary(inc, exc, total)
        local n_inc, n_exc = 0, 0
        for _k in pairs(inc or {}) do n_inc = n_inc + 1 end
        for _k in pairs(exc or {}) do n_exc = n_exc + 1 end
        if n_inc == 0 and n_exc == 0 then return _("Any"), false end
        local parts = {}
        if n_inc > 0 then table.insert(parts, total and string.format(_("%d of %d"), n_inc, total) or string.format(_("%d chosen"), n_inc)) end
        if n_exc > 0 then table.insert(parts, string.format(_("%d hidden"), n_exc)) end
        return table.concat(parts, ", "), true
    end
    local function navRow(label, value, active, callback)
        local h = Screen:scaleBySize(50)
        local right = HorizontalGroup:new{ align = "center",
            TextWidget:new{ text = value, face = face15, bold = active, fgcolor = active and BlitBuffer.COLOR_BLACK or MUTED,
                max_width = math.floor(inner * 0.55) },
            HorizontalSpan:new{ width = Screen:scaleBySize(6) },
            IconWidget:new{ icon = "chevron.right", width = Screen:scaleBySize(16), height = Screen:scaleBySize(16) } }
        local d = Geom:new{ w = inner, h = h }
        return VerticalGroup:new{ align = "left",
            atoms.TapBox:new{ HorizontalGroup:new{ HorizontalSpan:new{ width = P },
                OverlapGroup:new{ dimen = d, allow_mirroring = false,
                    LeftContainer:new{ dimen = d, TextWidget:new{ text = label, face = face15 } },
                    RightContainer:new{ dimen = d, right } },
                HorizontalSpan:new{ width = P } }, callback = callback },
            rowLine(),
        }
    end

    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, sectionBar(_("FILTER")))
    -- books / tags / chapters (the existing pickers: tap an item to show only it, again to hide it)
    local book_count = list:offeredCount("books", "books_exclude", NotesListWidget.bookKeys)
    if not list.single_book then
        local v, on = setSummary(af.books, af.books_exclude, book_count)
        table.insert(body, navRow(_("Books"), v, on, function() self.helpers.books() end))
        -- authors, series, language: only when some book has one (or a filter is on)
        local labels = { authors = _("Authors"), series = _("Series"), languages = _("Language") }
        for i = 1, #NotesListWidget.META_KINDS do
            local kind = NotesListWidget.META_KINDS[i]
            local exc = kind .. "_exclude"
            local has_value = false
            for ni = 1, #list.notes_list do
                local vals = NotesListWidget.metaValues(list.notes_list[ni], kind)
                for j = 1, #vals do
                    if vals[j] ~= "" then has_value = true end
                end
            end
            local filtered = (type(af[kind]) == "table" and next(af[kind])) or (type(af[exc]) == "table" and next(af[exc]))
            if has_value or filtered then
                local count = list:offeredCount(kind, exc, function(n) return NotesListWidget.metaValues(n, kind) end)
                local mv, mon = setSummary(af[kind], af[exc], count)
                table.insert(body, navRow(labels[kind], mv, mon, function() self.helpers.meta(kind) end))
            end
        end
    end
    do
        local v, on = setSummary(af.tags, af.tags_exclude)
        table.insert(body, navRow(_("Tags"), v, on, function() self.helpers.tags() end))
    end
    if self.helpers.chapters_available() then
        local v, on = setSummary(af.chapters, af.chapters_exclude)
        table.insert(body, navRow(_("Chapters"), v, on, function() self.helpers.chapters() end))
    end

    -- (What shows - all, with a note, without, bookmarks - is the tab row's job, not a filter:
    -- filters apply to every tab, so there is no "Notes" row here.)

    -- colour & style: chips for all colours and styles; "Hide these instead" flips
    -- between showing only these and hiding these. Not on the Bookmarks tab: bookmarks have no
    -- colour or style, so these would do nothing there.
    if list:tabKey() ~= "bookmarks" then
        local items = {}
        -- setting: only offer colours/styles that some highlight uses (off = offer all)
        local only_used = core.getSetting("hide_unused_cs", false) == true
        local used = {}
        if only_used then
            for _i, n in ipairs(list.notes_list) do
                local nw = core.NoteWrapper:new(n)
                local c, d = nw:getNormalizedColor(), nw:getNormalizedDrawer()
                if c then used["color:" .. c] = true end
                if d then used["style:" .. d] = true end
            end
        end
        -- shown: all, or (setting) only used ones, plus whatever is currently chosen
        local function offered(key) return not only_used or used[key] or (af.cs and af.cs[key]) end
        local function toggle(key)
            af.cs = af.cs or {}
            if af.cs[key] then af.cs[key] = nil else af.cs[key] = true end
            if not next(af.cs) then af.cs, af.cs_exclude = nil, nil end
            self:changed()
        end
        for _i, hc in ipairs(ReaderHighlight.highlight_colors) do
            local key = "color:" .. hc[2]
            if offered(key) then
                table.insert(items, chip(item.NoteItemWidget.colorLabel(hc[2]), af.cs and af.cs[key], function() toggle(key) end, { dot = hc[2] }))
            end
        end
        -- the styles on a row of their own, stretched to equal widths across it; natural widths
        -- (wrapping) when they would not fit side by side
        local styles = {}
        for n = 1, #core.HIGHLIGHT_STYLES do
            local st = core.HIGHLIGHT_STYLES[n]
            if offered("style:" .. st[1]) then table.insert(styles, st) end
        end
        local gap = Screen:scaleBySize(8)
        local function styleChips(w)
            local list = {}
            for n = 1, #styles do
                local st = styles[n]
                local key = "style:" .. st[1]
                local deco = (st[1] == "underscore" and "underline") or (st[1] == "strikeout" and "strike") or nil
                list[n] = chip(st[2], af.cs and af.cs[key], function() toggle(key) end, { deco = deco, w = w })
            end
            return list
        end
        local each = #styles > 0 and math.floor((inner - gap * (#styles - 1)) / #styles) or 0
        local style_items = styleChips(each)
        for n = 1, #style_items do
            if style_items[n].w > each then style_items = styleChips(nil); break end
        end
        local flip = atoms.TapBox:new{ underlined(af.cs_exclude and _("Show only these instead") or _("Hide these instead"), face13),
            callback = function()
                af.cs_exclude = not af.cs_exclude
                if af.cs and next(af.cs) then self:changed() else self:rebuild() end
            end }
        table.insert(body, padded(VerticalGroup:new{ align = "left",
            labelRow(TextWidget:new{ text = af.cs_exclude and _("Hide colour & style") or _("Colour & style"), face = face15 }, flip),
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            flow(items),
            (#items > 0 and #style_items > 0) and VerticalSpan:new{ width = gap } or nil,
            #style_items > 0 and flow(style_items) or nil,
        }, Screen:scaleBySize(14), Screen:scaleBySize(14)))
        table.insert(body, rowLine())
    end

    -- text contains: the search box (highlights and notes); more text filters below it
    do
        local q = af.search_any
        local field_h = Screen:scaleBySize(42)
        local field_text = TextWidget:new{ text = (q and q ~= "") and q or _("Search highlights and notes"), face = face14,
            fgcolor = (q and q ~= "") and BlitBuffer.COLOR_BLACK or MUTED, max_width = inner - Screen:scaleBySize(24) }
        local field = atoms.TapBox:new{
            atoms.RoundedBox:new{ width = inner, radius = Screen:scaleBySize(8), border = thin, border_color = BlitBuffer.COLOR_BLACK,
                fill = BlitBuffer.COLOR_WHITE, pad_x = Screen:scaleBySize(12), pad_y = math.floor((field_h - field_text:getSize().h) / 2),
                field_text },
            callback = function() list:showSearchDialog(function() self:rebuild() end) end,
        }
        local more_active = false
        for _i, k in ipairs({ "search_highlight", "search_highlight_exclude", "search_note", "search_note_exclude" }) do
            if af[k] and af[k] ~= "" then more_active = true end
        end
        local more = atoms.TapBox:new{ underlined((more_active and "✓ " or "") .. _("More text filters"), face13),
            callback = function() self:showTextFilters() end }
        table.insert(body, padded(VerticalGroup:new{ align = "left",
            labelRow(TextWidget:new{ text = _("Text contains"), face = face15 }, more),
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            field,
        }, Screen:scaleBySize(14), Screen:scaleBySize(14)))
    end

    -- sort: one row, drawn like the Books and Tags rows; the value is the same label the list shows
    -- next to the tabs ("Titles A–Z › Start to end"). A tap opens the Sort page (SortPicker), where
    -- Then by / And then by are set. The quick picks stay on the sort card in the tab row.
    table.insert(body, sectionBar(_("SORT")))
    do
        local single = list.single_book
        table.insert(body, navRow(_("Sort by"), sort.sortModeLabel(sort.SortState.get(single), single), true,
            function() list:showSortPicker(function() self:rebuild() end) end))
    end

    -- saved filters: the current filters and sort order under a name, one tap to bring them back
    table.insert(body, sectionBar(_("SAVED FILTERS")))
    do
        local presets = core.getSetting("filter_presets", {})
        local function same(a, b)
            if type(a) ~= type(b) then return false end
            if type(a) ~= "table" then return a == b end
            for k, v in pairs(a) do if k ~= "notes_presence" and not same(v, b[k]) then return false end end
            for k in pairs(b) do if k ~= "notes_presence" and a[k] == nil then return false end end
            return true
        end
        local chips = {}
        -- A saved filter keeps both sort orders: the annotation tabs' (sort) and the Bookmarks
        -- tab's (sort_bm); each tab gets its own back. (Filters saved before kept one order, from
        -- the kind of tab they were saved on: p.bm.) The filters apply on every tab.
        local single = list.single_book
        local function sortsOf(p)
            if p.bm then return nil, p.sort end
            return p.sort, p.sort_bm
        end
        local function sortHere(p)
            local a, b = sortsOf(p)
            if sort.SortState.bm_tab then return b end
            return a
        end
        for i, p in ipairs(presets) do
            local here = sortHere(p)
            -- compared the way it applies (an old or broken saved filter is cleaned up on applying)
            local pf = Pages.deepCopy(p.filter) or {}
            data.normalizeColorStyle(pf)
            NotesListWidget.dropStaleSearchOptions(pf)
            local on = same(pf, list.active_filter or {}) and (not here
                or sort.SortState.normView(here, single) == sort.SortState.normView(sort.SortState.get(single), single))
            table.insert(chips, chip(p.name, on, function()
                local presence = list.active_filter and list.active_filter.notes_presence
                list.active_filter = Pages.deepCopy(p.filter) or {}
                list.active_filter.notes_presence = presence
                local a, b = sortsOf(p)
                if a then sort.SortState.setFor(single, false, a) end
                if b then sort.SortState.setFor(single, true, b) end
                if a or b then list:applySort() end
                self:changed()
            end, { single = true, hold = function()
                local ConfirmBox = require("ui/widget/confirmbox")
                NotesListWidget.showDialog(ConfirmBox:new{
                    text = string.format(_("Delete the saved filter “%s”?"), p.name),
                    ok_text = _("Delete"),
                    ok_callback = function()
                        table.remove(presets, i)
                        core.setSetting("filter_presets", presets)
                        self:rebuild()
                    end })
            end }))
        end
        if #presets == 0 then
            table.insert(body, padded(TextWidget:new{ text = _("Nothing saved yet."), face = face13, fgcolor = core.COLORS.muted },
                Screen:scaleBySize(12), Screen:scaleBySize(4)))
        else
            table.insert(body, padded(flow(chips), Screen:scaleBySize(14), Screen:scaleBySize(6)))
            table.insert(body, padded(TextWidget:new{ text = _("Hold one to delete it."),
                face = Font:getFace("cfont", 12), fgcolor = core.COLORS.muted },
                0, Screen:scaleBySize(4)))
        end
        local save_tw = TextWidget:new{ text = _("Save current filters…"), face = face13 }
        table.insert(body, padded(atoms.TapBox:new{ VerticalGroup:new{ save_tw, LineWidget:new{
                dimen = Geom:new{ w = save_tw:getSize().w, h = Size.line.medium }, background = BlitBuffer.COLOR_BLACK } },
            callback = function()
                local InputDialog = require("ui/widget/inputdialog")
                local dlg
                local function save()
                    local name = (dlg:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                    if name == "" then name = string.format(_("Filter %d"), #presets + 1) end
                    local copy = Pages.deepCopy(list.active_filter) or {}
                    copy.notes_presence = nil
                    table.insert(presets, { name = name, filter = copy, sort = sort.SortState.getFor(list.single_book, false),
                        sort_bm = sort.SortState.getFor(list.single_book, true) })
                    core.setSetting("filter_presets", presets)
                    UIManager:close(dlg)
                    self:rebuild()
                end
                dlg = InputDialog:new{ title = _("Save filters"), input = "", input_hint = _("Name"),
                    description = _("Saves the filters and the sort orders (annotations and bookmarks) as they are now."),
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
                        { text = _("Save"), is_enter_default = true, callback = save } } } }
                NotesListWidget.showDialog(dlg)
                dlg:onShowKeyboard()
            end }, Screen:scaleBySize(14), Screen:scaleBySize(14)))
    end

    -- title bar and bottom bar, shared with the pickers
    local header = Pages.header(self, _("Filter & sort"), function() self:onClose() end, {
        atoms.TapBox:new{ CenterContainer:new{ dimen = Geom:new{
            w = Screen:scaleBySize(90), h = core.TOPBAR_HEIGHT }, underlined(_("Reset all"), face14) },
            callback = function()
                -- clears the filters; the tab stays (as "Clear all" next to the filter chips)
                local presence = list.active_filter and list.active_filter.notes_presence
                list.active_filter = { notes_presence = presence }
                self:changed()
            end },
    }, true)
    local footer = Pages.footer(function() self:onClose() end, Pages.countText(#(list.filtered_notes or {}), list),
        function() self:onDone() end)

    -- body scrolls when it doesn't fit (landscape, small screens)
    local avail = H - header:getSize().h - footer:getSize().h
    local body_widget = Pages.paged(self, W, avail, body)
    self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = BlitBuffer.COLOR_WHITE,
        OverlapGroup:new{ dimen = Geom:new{ w = W, h = H }, allow_mirroring = false,
            VerticalGroup:new{ align = "left", header, body_widget },
            BottomContainer:new{ dimen = Geom:new{ w = W, h = H }, footer },
        },
    }
end
function Pages.FilterScreen:showTextFilters()
    local ButtonDialog = require("ui/widget/buttondialog")
    local af = self.list.active_filter or {}
    local dialog
    local function entry(field, is_exclude, label, title, hint)
        local key = is_exclude and (field .. "_exclude") or field
        local on = af[key] and af[key] ~= ""
        return { text = (on and "✓ " or "") .. label, callback = function()
            UIManager:close(dialog)
            self.helpers.text(field, title, hint, is_exclude)
        end }
    end
    dialog = ButtonDialog:new{
        title = _("Text filters"),
        buttons = {
            { entry("search_highlight", false, _("Highlight contains"), _("Filter by Highlight Text"), _("Words in highlighted text…")) },
            { entry("search_highlight", true, _("Highlight doesn't contain"), _("Exclude by Highlight Text"), _("Words in highlighted text…")) },
            { entry("search_note", false, _("Note contains"), _("Filter by Note Text"), _("Words in your notes…")) },
            { entry("search_note", true, _("Note doesn't contain"), _("Exclude by Note Text"), _("Words in your notes…")) },
            { { text = _("Close"), callback = function() UIManager:close(dialog) end } },
        },
    }
    NotesListWidget.showDialog(dialog)
end
function Pages.FilterScreen:onDone()
    self.list.filter_screen = nil
    UIManager:close(self, "flashui")
    return true
end
function Pages.FilterScreen:onClose()
    -- Cancel: put filters and sort back as they were
    self.list.active_filter = self.saved_filter
    if sort.SortState.restore(self.saved_sorts) then self.list:applySort() end
    self.list:refresh()
    return self:onDone()
end

-- Settings: one full-screen page (Text / List / Pages / Filter) instead of the chain of button
-- dialogs. Every setting is still here; changes apply straight away. The list-of-numbers
-- settings (font sizes, margins, spacing) and the typeface picker keep their own dialogs.
Pages.SS = InputContainer:extend{ list = nil, page = nil, parent_screen = nil, covers_fullscreen = true }
Pages.watchResize(Pages.SS)
function Pages.SS:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    self:build()
end
function Pages.SS:rebuild()
    self:build()
    UIManager:setDirty(self, "ui")
end
-- a changed setting: redraw the list behind, then this page
function Pages.SS:changed()
    self.list:refresh()
    self:rebuild()
end
function Pages.SS:onClose()
    UIManager:close(self, "flashui")
    -- a sub page: the Settings page under it redraws with the new values
    if self.page and self.list.settings_screen then self.list.settings_screen:rebuild() end
    return true
end
function Pages.SS:onCloseWidget()
    if self.list.settings_screen == self then self.list.settings_screen = nil end
end
Pages.forwardGestures(Pages.SS) -- after onCloseWidget, which it wraps
function Pages.SS:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local thin = Size.border.button
    local MUTED = core.COLORS.muted
    local face15, face13 = Font:getFace("cfont", 15), Font:getFace("cfont", 13)
    local face12 = Font:getFace("cfont", 12)
    local function rowLine() return Pages.rowLine(P, inner) end
    local sectionBar = Pages.sectionBars(P, inner)
    local function padded(widget, top, bottom) return Pages.padded(widget, P, top, bottom) end
    -- label (with an optional grey line under it) on the left, a control on the right
    local function row(label, sub, control, callback)
        local ctl_w = control and control:getSize().w or 0
        local left = TextWidget:new{ text = label, face = face15, max_width = inner - ctl_w - Screen:scaleBySize(12) }
        if sub then
            left = VerticalGroup:new{ align = "left", left, VerticalSpan:new{ width = Screen:scaleBySize(2) },
                TextWidget:new{ text = sub, face = face12, fgcolor = MUTED, max_width = inner - ctl_w - Screen:scaleBySize(12) } }
        end
        local d = Geom:new{ w = inner, h = Screen:scaleBySize(sub and 58 or 50) }
        local line = HorizontalGroup:new{ HorizontalSpan:new{ width = P },
            OverlapGroup:new{ dimen = d, allow_mirroring = false,
                LeftContainer:new{ dimen = d, left },
                control and RightContainer:new{ dimen = d, control } or nil },
            HorizontalSpan:new{ width = P } }
        return VerticalGroup:new{ align = "left", callback and atoms.TapBox:new{ line, callback = callback } or line, rowLine() }
    end
    local function navRow(label, value, callback)
        local right = HorizontalGroup:new{ align = "center" }
        if value and value ~= "" then
            table.insert(right, TextWidget:new{ text = value, face = face15, fgcolor = MUTED, max_width = math.floor(inner * 0.5) })
            table.insert(right, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
        end
        table.insert(right, IconWidget:new{ icon = "chevron.right", width = Screen:scaleBySize(16), height = Screen:scaleBySize(16) })
        return row(label, nil, right, callback)
    end
    -- on/off switch: black track with a white knob on the right when on
    local function toggle(label, sub, key, getter, after)
        local on = getter() == true
        local sw_w, sw_h, knob, m = Screen:scaleBySize(50), Screen:scaleBySize(28), Screen:scaleBySize(20), Screen:scaleBySize(4)
        local track = atoms.Pill:new{ width = sw_w, height = sw_h, fill = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
            border = on and 0 or thin, border_color = BlitBuffer.COLOR_BLACK }
        local k = atoms.Pill:new{ width = knob, height = knob, border = 0, fill = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK }
        k.overlap_offset = { on and (sw_w - knob - m) or m, math.floor((sw_h - knob) / 2) }
        local sw = OverlapGroup:new{ dimen = Geom:new{ w = sw_w, h = sw_h }, allow_mirroring = false, track, k }
        return row(label, sub, sw, function() core.setSetting(key, not on); if after then after() end; self:changed() end)
    end
    local function outlineCells(cells, cell_h)
        local seg = HorizontalGroup:new{}
        for i, c in ipairs(cells) do
            if i > 1 then table.insert(seg, LineWidget:new{ dimen = Geom:new{ w = thin, h = cell_h }, background = BlitBuffer.COLOR_BLACK }) end
            table.insert(seg, c)
        end
        return atoms.RoundedOutline:new{ radius = Screen:scaleBySize(8), border = thin, seg }
    end
    -- step/default given: the number can be tapped to open the number dialog (type a value)
    local function stepper(label, sub, key, value, min, max, step, default)
        step = step or 1
        local h = Screen:scaleBySize(36)
        local function cell(text, w, cb, bold)
            return atoms.TapBox:new{ CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
                TextWidget:new{ text = text, face = face15, bold = bold } }, callback = cb }
        end
        local function set(v) v = math.max(min, math.min(max, v)); if v ~= value then core.setSetting(key, v); self:changed() end end
        local ctl = outlineCells({ cell("−", Screen:scaleBySize(44), function() set(value - step) end),
            cell(tostring(value), Screen:scaleBySize(48), default and function()
                self.list:showSpinSetting(label, key, default, min, max, step, function() self:rebuild() end)
            end or nil, true),
            cell("+", Screen:scaleBySize(44), function() set(value + step) end) }, h)
        return row(label, sub, ctl)
    end
    -- options side by side in one rounded outline, the chosen one black
    local function segment(label, options, current, pick)
        local n = #options
        local cell_h = Screen:scaleBySize(40)
        local cell_w = math.floor((inner - thin * 2 - thin * (n - 1)) / n)
        local cells = {}
        for _i, opt in ipairs(options) do
            local on = (current == opt[1])
            table.insert(cells, atoms.TapBox:new{
                FrameContainer:new{ bordersize = 0, padding = 0, margin = 0,
                    background = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                    CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h },
                        TextWidget:new{ text = opt[2], face = face13, bold = on,
                            max_width = cell_w - Screen:scaleBySize(8),
                            fgcolor = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK } } },
                callback = function() if not on then pick(opt[1]) end end })
        end
        return VerticalGroup:new{ align = "left",
            padded(VerticalGroup:new{ align = "left", TextWidget:new{ text = label, face = face15 },
                VerticalSpan:new{ width = Screen:scaleBySize(8) }, outlineCells(cells, cell_h) },
                Screen:scaleBySize(12), Screen:scaleBySize(14)),
            rowLine() }
    end
    -- which of date / author / chapter are on: small chips on the right (black when on)
    local function fieldChips(label, sub, getter, key)
        local active = {}
        for f in getter():gmatch("[^,]+") do active[f] = true end
        local chips = HorizontalGroup:new{ align = "center" }
        for i, f in ipairs({ { "date", _("Date") }, { "author", _("Author") }, { "chapter", _("Chapter") } }) do
            local on = active[f[1]]
            local text = f[2]
            local widest = TextWidget:new{ text = f[2], face = face13, bold = true }:getSize().w
            local w = widest + Screen:scaleBySize(20)
            local color = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK
            if i > 1 then table.insert(chips, HorizontalSpan:new{ width = Screen:scaleBySize(6) }) end
            table.insert(chips, atoms.TapBox:new{
                atoms.Pill:new{ width = w, height = Screen:scaleBySize(32), fill = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                    border = on and 0 or thin, border_color = core.COLORS.line,
                    TextWidget:new{ text = text, face = face13, bold = on, fgcolor = color } },
                callback = function()
                    if on then active[f[1]] = nil else active[f[1]] = true end
                    local parts = {}
                    for _j, k in ipairs({ "date", "author", "chapter" }) do if active[k] then table.insert(parts, k) end end
                    core.setSetting(key, #parts > 0 and table.concat(parts, ",") or "date")
                    self:changed()
                end })
        end
        return row(label, sub, chips)
    end
    local list = self.list

    local body = VerticalGroup:new{ align = "left" }
    local function add(w) table.insert(body, w) end

    local function fontRow(label, key, getter)
        return navRow(label, Pages.SubPage.fontName(getter()), function()
            UIManager:show(Pages.SubPage:new{ list = list, parent = self, font_key = key, title = label })
        end)
    end
    local function numberRows(menu_key)
        for _i, st in ipairs(core.SPIN_MENUS[menu_key].settings) do
            add(stepper((st.label:gsub(":%s*$", "")), nil, st.key, st.getter(), st.min, st.max, st.step, st.default))
        end
    end
    if self.page == "text" then
        add(sectionBar(_("FONTS")))
        add(fontRow(_("Title font"), "title_font", core.getTitleFont))
        add(fontRow(_("Info font"), "info_font", core.getInfoFont))
        add(navRow(_("Author font"), core.getSetting("author_font", nil) and Pages.SubPage.fontName(core.getSetting("author_font", nil))
                or _("Same as info"), function()
            UIManager:show(Pages.SubPage:new{ list = list, parent = self, font_key = "author_font", title = _("Author font") })
        end))
        add(fontRow(_("Content font"), "content_font", core.getContentFont))
        add(navRow(_("Note font"), core.getSetting("note_font", nil) and Pages.SubPage.fontName(core.getSetting("note_font", nil))
                or _("Same as content"), function()
            UIManager:show(Pages.SubPage:new{ list = list, parent = self, font_key = "note_font", title = _("Note font") })
        end))
        add(sectionBar(_("SIZES")))
        numberRows("font_size")
        local info_size = core.getInfoFontSize()
        add(stepper(_("Author size"), _("Same as the info size until you change it"), "author_font_size",
            core.getSetting("author_font_size", nil) or info_size, 8, 48, 1, info_size))
        local content_size = core.getContentFontSize()
        add(stepper(_("Note size"), _("Same as the content size until you change it"), "note_font_size",
            core.getSetting("note_font_size", nil) or content_size, 8, 48, 1, content_size))
        add(stepper(_("Lines per highlight"), _("Longer ones end with “…”; tap to read all"), "truncate_lines", core.getTruncateLines(), 1, 20))
        add(stepper(_("Lines per note"), _("Longer notes end with “…”; tap to read all"),
            "truncate_note_lines", item.NoteItemWidget.noteLinesMax(), 1, 20))
        add(toggle(_("Justify text"), nil, "justify", core.getJustify))
        add(sectionBar(_("CAPITALS")))
        local case_opts = { { "normal", _("As written") }, { "upper", _("CAPITALS") } }
        add(segment(_("Book and chapter titles"), case_opts, core.getSetting("title_case", "normal"),
            function(v) core.setSetting("title_case", v); self:changed() end))
        add(segment(_("Chapter · date line"), case_opts, core.getSetting("info_case", "normal"),
            function(v) core.setSetting("info_case", v); self:changed() end))
        add(segment(_("Author name"), { { "upper", _("CAPITALS") }, { "normal", _("As written") } },
            core.getSetting("author_case", "upper"), function(v) core.setSetting("author_case", v); self:changed() end))
    elseif self.page == "spacing" then
        -- grouped by where the space is, in the order an annotation is drawn: page, between annotations,
        -- the heading, the highlight text, the note
        local function rowsFor(keys)
            local by_key = {}
            for _, menu in ipairs({ "margins", "section_margin" }) do
                for _, st in ipairs(core.SPIN_MENUS[menu].settings) do by_key[st.key] = st end
            end
            for _, key in ipairs(keys) do
                local st = by_key[key]
                add(stepper((st.label:gsub(":%s*$", "")), nil, st.key, st.getter(), st.min, st.max, st.step, st.default))
            end
        end
        add(sectionBar(_("PAGE")))
        rowsFor({ "top_padding", "h_margin", "landscape_width_pct" })
        add(sectionBar(_("BETWEEN ANNOTATIONS")))
        rowsFor({ "note_spacing" })
        add(sectionBar(_("BOOK HEADING")))
        rowsFor({ "title_margin", "info_margin" })
        add(sectionBar(_("HIGHLIGHT TEXT")))
        rowsFor({ "text_margin", "line_spacing" })
        add(sectionBar(_("YOUR NOTE")))
        rowsFor({ "note_offset", "note_indent" })
    elseif self.page == "bookmarks" then
        -- only what is a bookmark's own; fonts, capitals, margins and the note are the annotations'
        add(sectionBar(_("BOOKMARK LINE")))
        add(navRow(_("Font"), core.getSetting("bm_font", nil) and Pages.SubPage.fontName(core.getSetting("bm_font", nil))
                or _("Same as info"), function()
            UIManager:show(Pages.SubPage:new{ list = list, parent = self, font_key = "bm_font", title = _("Bookmark font") })
        end))
        local info_size = core.getInfoFontSize()
        add(stepper(_("Text size"), _("Same as the info size until you change it"), "bm_line_size",
            core.getSetting("bm_line_size", nil) or info_size, 8, 48, 1, info_size))
        add(segment(_("Date"), { { "sort", _("When sorted by date") }, { "always", _("Always") }, { "never", _("Never") } },
            item.NoteItemWidget.bmDate(), function(v) core.setSetting("bm_date", v); self:changed() end))
        add(sectionBar(_("NOTE")))
        add(toggle(_("Icon before the note"), nil, "bm_note_icon", item.NoteItemWidget.bmNoteIcon))
        add(sectionBar(_("SPACING")))
        add(stepper(_("Between bookmarks"), nil, "bm_spacing",
            core.getSetting("bm_spacing", item.NoteItemWidget.DEFAULT_BM_SPACING), 0, 100, 2, item.NoteItemWidget.DEFAULT_BM_SPACING))
    elseif self.page == "dates" then
        -- how dates are written: the month for every date (the clock is KOReader's own setting),
        -- then year and time for the list and for the annotation sheet, each its own
        add(sectionBar(_("DATE FORMAT")))
        local sample_t = os.time({ year = 2026, month = 9, day = 3, hour = 14 })
        add(segment(_("Month"), { { "short", "3 " .. item.NoteItemWidget.monthName(sample_t, false) },
                { "long", "3 " .. item.NoteItemWidget.monthName(sample_t, true) } }, core.getSetting("date_month", "short"),
            function(v) core.setSetting("date_month", v); self:changed() end))
        -- above a highlight: always, or only when the order goes by date (bookmarks: Bookmarks page)
        add(sectionBar(_("ABOVE HIGHLIGHTS")))
        add(segment(_("Show the date"), { { "sort", _("When sorted by date") }, { "always", _("Always") } },
            core.getSetting("info_date_when", "always"), function(v) core.setSetting("info_date_when", v); self:changed() end))
        local places = { { "list", _("IN THE LIST") }, { "sheet", _("ON THE ANNOTATION SHEET") } }
        for n = 1, #places do
            local place = places[n]
            local where = place[1]
            local st = item.NoteItemWidget.dateStyle(where)
            add(sectionBar(place[2]))
            add(segment(_("Year"), { { "relevant", _("When not this year") }, { "always", _("Always") } }, st.year,
                function(v) core.setSetting("date_year_" .. where, v); self:changed() end))
            add(segment(_("Time"), { { "never", _("Never") }, { "recent", _("Today and yesterday") }, { "always", _("Always") } }, st.time,
                function(v) core.setSetting("date_time_" .. where, v); self:changed() end))
        end
    elseif self.page == "info" then
        add(sectionBar(_("INFO ROW")))
        add(toggle(_("Show book / info row"), nil, "show_info", core.getShowInfo))
        add(fieldChips(_("Info row shows"), nil, core.getInfoFields, "info_fields"))
        add(toggle(_("Title on each page"), nil, "repeat_title_on_page", core.getRepeatTitleOnPage))
        add(toggle(_("Chapter headings in one book"), _("Heading above each chapter when you open a single book"), "chapter_headings", item.NoteItemWidget.showHeadings))
        add(toggle(_("Chapter heading on each page"), nil, "repeat_chapter_on_page", item.NoteItemWidget.repeatChapter))
        add(toggle(_("Chapter / date on each page"), nil, "repeat_info_on_page", core.getRepeatInfoOnPage))
        add(toggle(_("Hide duplicate book header"), nil, "hide_dup_title", core.getHideDupTitle))
        add(toggle(_("Hide duplicate info header"), nil, "hide_dup_info", core.getHideDupInfo))
        add(fieldChips(_("Duplicate check"), _("Repeated info is hidden when these match"), core.getDedupInfoFields, "dedup_info_fields"))
    elseif self.page == "export" then
        local o = exportmod.options()
        local function pick(key) return function(v) core.setSetting("export_" .. key, v); self:rebuild() end end
        local function opt(key) return function() return exportmod.options()[key] end end
        local function onOff(label, sub, key) return toggle(label, sub, "export_" .. key, opt(key)) end
        add(sectionBar(_("FORMAT")))
        add(segment(_("File type"), { { "md", _("Markdown") }, { "txt", _("Plain text") } }, o.format, pick("format")))
        add(sectionBar(_("INCLUDE")))
        add(onOff(_("Title and filter at the top"), nil, "header"))
        add(onOff(_("Author"), _("After the book title"), "author"))
        add(segment(_("Chapter"), { { "line", _("In the info line") }, { "heading", _("As headings") }, { "none", _("Leave out") } },
            o.chapter, pick("chapter")))
        add(segment(_("Date"), { { "date", _("Date") }, { "datetime", _("Date and time") }, { "none", _("Leave out") } },
            o.date, pick("date")))
        if o.date ~= "none" then
            local sample_t = os.time({ year = 2026, month = 9, day = 3, hour = 14 })
            add(segment(_("Date format"), { { "iso", "2026-09-03" },
                    { "long", "3 " .. item.NoteItemWidget.monthName(sample_t) .. " 2026" } }, o.date_style, pick("date_style")))
        end
        -- the smaller parts as chips under one label (black when on; several can be on)
        do
            local chips = HorizontalGroup:new{ align = "center" }
            local parts = { { "page", _("Page") }, { "notes", _("Notes") }, { "style", _("Colour and style") }, { "tags", _("Tags") } }
            for i = 1, #parts do
                local key, text = parts[i][1], parts[i][2]
                local on = o[key] == true
                local w = TextWidget:new{ text = text, face = face13, bold = true }:getSize().w + Screen:scaleBySize(20)
                if i > 1 then table.insert(chips, HorizontalSpan:new{ width = Screen:scaleBySize(6) }) end
                table.insert(chips, atoms.TapBox:new{
                    atoms.Pill:new{ width = w, height = Screen:scaleBySize(32), fill = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                        border = on and 0 or thin, border_color = core.COLORS.line,
                        TextWidget:new{ text = text, face = face13, bold = on, fgcolor = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK } },
                    callback = function() core.setSetting("export_" .. key, not on); self:rebuild() end })
            end
            add(VerticalGroup:new{ align = "left",
                padded(VerticalGroup:new{ align = "left", TextWidget:new{ text = _("Also include"), face = face15 },
                    VerticalSpan:new{ width = Screen:scaleBySize(8) }, chips }, Screen:scaleBySize(12), Screen:scaleBySize(14)),
                rowLine() })
        end
        add(sectionBar(_("ORDER")))
        add(segment(_("Books"), { { "book", _("Each book once") }, { "list", _("As in the list") } }, o.group, pick("group")))
        if o.format == "md" then
            add(sectionBar(_("STYLE")))
            add(segment(_("Highlight"), { { "quote", _("Quote") }, { "italic", _("Italic") }, { "plain", _("Plain") } },
                o.highlight, pick("highlight")))
            add(segment(_("Note"), { { "bold", _("Bold label") }, { "quote", _("Quote") }, { "italic", _("Italic") } },
                o.note_style, pick("note_style")))
        end
        add(sectionBar(_("FILES")))
        add(segment(_("Files"), { { "one", _("One file") }, { "book", _("One per book") } }, o.files, pick("files")))
        add(onOff(_("Date and time in the file name"), _("Off: exporting again replaces the file"), "name_date"))
        add(navRow(_("Folder"), exportmod.shortDir(), function()
            local start = exportmod.dir()
            if lfs.attributes(start, "mode") ~= "directory" then start = require("datastorage"):getDataDir() end
            UIManager:show(require("ui/widget/pathchooser"):new{
                select_directory = true, select_file = false, show_files = false, path = start,
                onConfirm = function(path) core.setSetting("export_dir", path); self:rebuild() end,
            })
        end))
    else
        add(sectionBar(_("LIST")))
        add(navRow(_("Text"), _("Fonts, sizes, capitals"),
            function() UIManager:show(Pages.SS:new{ list = list, page = "text", parent_screen = self }, "flashui") end))
        add(navRow(_("Spacing"), _("Margins, lines, notes"),
            function() UIManager:show(Pages.SS:new{ list = list, page = "spacing", parent_screen = self }, "flashui") end))
        do
            local names = {}
            local active = {}
            for f in core.getInfoFields():gmatch("[^,]+") do active[f] = true end
            for _i, f in ipairs({ { "date", _("Date") }, { "author", _("Author") }, { "chapter", _("Chapter") } }) do
                if active[f[1]] then table.insert(names, f[2]) end
            end
            add(navRow(_("Info row and repeats"), core.getShowInfo() and table.concat(names, " · ") or _("Off"),
                function() UIManager:show(Pages.SS:new{ list = list, page = "info", parent_screen = self }, "flashui") end))
        end
        add(navRow(_("Dates"), item.NoteItemWidget:formatDate(os.date("%Y-%m-%d 14:05:00", os.time() - 40 * 86400)) or "",
            function() UIManager:show(Pages.SS:new{ list = list, page = "dates", parent_screen = self }, "flashui") end))
        add(navRow(_("Bookmarks"), _("Line size, date, spacing"),
            function() UIManager:show(Pages.SS:new{ list = list, page = "bookmarks", parent_screen = self }, "flashui") end))
        add(toggle(_("Counts on tabs"), nil, "show_total", core.getShowTotalNotes))

        add(sectionBar(_("PAGES")))
        add(segment(_("Page controls"), { { "default", _("Prev / Next") }, { "scrollbar", _("Scrollbar") },
            { "scrollbar_chevrons", _("Scrollbar + buttons") } }, core.getPaginationStyle(),
            function(v) core.setSetting("pagination_style", v); self:changed() end))
        add(toggle(_("Marks on the scrollbar"), _("Where a new book, author, month or chapter starts, by sort order"), "sb_book_marks", core.getScrollbarBookMarks))
        add(segment(_("Swipe to turn pages"), { { "both", _("Both") }, { "horizontal", _("Horizontal") },
            { "vertical", _("Vertical") }, { "disabled", _("Off") } }, core.getSwipeSetting(),
            function(v) core.setSetting("swipe_direction", v); self:changed() end))

        add(sectionBar(_("EXPORT")))
        add(navRow(_("Export"), NotesListWidget.Export.summary(),
            function() UIManager:show(Pages.SS:new{ list = list, page = "export", parent_screen = self }, "flashui") end))

        add(sectionBar(_("KOREADER")))
        add(toggle(_("KOReader's Bookmarks open here"), _("Its menu entries, gestures and Bookmarks buttons open the Bookmarks tab here"),
            "take_over_bookmarks", AllNotesViewer.takeOverOn))

        add(sectionBar(_("FILTER")))
        add(toggle(_("Only offer used colours and styles"), nil, "hide_unused_cs",
            function() return core.getSetting("hide_unused_cs", false) == true end))
    end

    local titles = { text = _("Text"), spacing = _("Spacing"), info = _("Info row and repeats"), bookmarks = _("Bookmarks"), dates = _("Dates"),
        export = _("Export") }
    local right_items
    if self.page == "text" or self.page == "spacing" or self.page == "bookmarks" or self.page == "export" then
        local keys = ({ text = { "font_size" }, spacing = { "margins", "section_margin" } })[self.page] or {}
        right_items = { atoms.TapBox:new{ CenterContainer:new{ dimen = Geom:new{ w = Screen:scaleBySize(90), h = core.TOPBAR_HEIGHT },
                (function()
                    local tw = TextWidget:new{ text = _("Reset"), face = Font:getFace("cfont", 14) }
                    return VerticalGroup:new{ tw, LineWidget:new{ dimen = Geom:new{ w = tw:getSize().w, h = Size.line.medium },
                        background = BlitBuffer.COLOR_BLACK } }
                end)() },
            callback = function()
                for _i, key in ipairs(keys) do
                    for _j, st in ipairs(core.SPIN_MENUS[key].settings) do core.setSetting(st.key, st.default) end
                end
                if self.page == "export" then
                    for k in pairs(NotesListWidget.Export.DEFAULTS) do core.setSetting("export_" .. k, nil) end
                    core.setSetting("export_dir", nil)
                end
                if self.page == "bookmarks" then
                    core.setSetting("bm_line_size", nil); core.setSetting("bm_spacing", nil); core.setSetting("bm_date", nil)
                    core.setSetting("bm_note_icon", nil); core.setSetting("bm_font", nil)
                end
                if self.page == "text" then
                    core.setSetting("title_font", nil); core.setSetting("info_font", nil); core.setSetting("content_font", nil)
                    core.setSetting("note_font", nil); core.setSetting("note_font_size", nil)
                    core.setSetting("author_font", nil); core.setSetting("author_font_size", nil); core.setSetting("author_case", "upper")
                    core.setSetting("title_case", "normal"); core.setSetting("info_case", "normal")
                    core.setSetting("truncate_lines", core.getDefaultTruncateLines())
                    core.setSetting("truncate_note_lines", item.NoteItemWidget.DEFAULT_NOTE_LINES)
                    core.setSetting("justify", false)
                end
                self:changed()
            end } }
    end
    -- opened from ☰ → Export: a page of its own (only ✕), with Copy / Export at the bottom
    local header = Pages.header(self, titles[self.page] or _("Settings"), function() self:onClose() end, right_items,
        not self.page or self.export_action, function() Pages.exitAll(self) end)
    local top_group = VerticalGroup:new{ align = "left", header }
    if self.page == "text" or self.page == "spacing" or self.page == "bookmarks" or self.page == "dates" then
        table.insert(top_group, Pages.preview(self.list, math.floor(H * 0.26), self.page == "spacing", self.page == "bookmarks"))
    elseif self.page == "export" then
        table.insert(top_group, Pages.exportPreview(self.list, math.floor(H * 0.26)))
    end
    local footer
    if self.export_action then
        local n = #(list.filtered_notes or {})
        local bm = NotesListWidget.Export.allBookmarks(list.filtered_notes or {})
        local label = n == 0 and _("Nothing to export") or bm and (n == 1 and _("Export 1 bookmark") or string.format(_("Export %d bookmarks"), n))
            or (n == 1 and _("Export 1 annotation") or string.format(_("Export %d annotations"), n))
        local P2 = Screen:scaleBySize(24)
        local inner2 = W - P2 * 2
        local gap = Screen:scaleBySize(10)
        local bw1 = math.floor((inner2 - gap) / 3)
        footer = VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line },
            VerticalSpan:new{ width = Pages.FOOTER_TOP },
            HorizontalGroup:new{ HorizontalSpan:new{ width = P2 },
                Pages.button(_("Copy"), false, bw1, function() self:onClose(); list:copyList() end),
                HorizontalSpan:new{ width = gap },
                Pages.button(label, true, inner2 - gap - bw1, function() self:onClose(); list:exportList() end) },
            VerticalSpan:new{ width = Pages.FOOTER_BOTTOM },
        }
    end
    local avail = H - top_group:getSize().h - (footer and footer:getSize().h or 0)
    local body_widget = Pages.paged(self, W, avail, body)
    self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = BlitBuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", top_group, body_widget, footer } }
end
-- Font list behind the three font rows of Settings: a sample line in the chosen font on top
-- (fixed height, so the page does not jump between fonts), then every font to tap.
Pages.SubPage = InputContainer:extend{ list = nil, parent = nil, font_key = nil, title = "", covers_fullscreen = true }
Pages.watchResize(Pages.SubPage)
Pages.forwardGestures(Pages.SubPage)
function Pages.SubPage:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    self:build()
end
function Pages.SubPage:rebuild()
    self:build()
    UIManager:setDirty(self, "ui")
end
function Pages.SubPage:onClose()
    UIManager:close(self, "flashui")
    if self.parent then self.parent:rebuild() end -- the page with the font rows shows the new name
    self.list:showSettingsMenu()
    return true
end
function Pages.SubPage.fontName(path)
    if not path or path == "" then return _("Default") end
    return path:match("([^/\\]+)$") or path
end
function Pages.SubPage:build()
    local list = self.list
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local face15 = Font:getFace("cfont", 15)
    local function rowLine() return Pages.rowLine(P, inner) end
    local current = core.getSetting(self.font_key, nil)
    local body = VerticalGroup:new{ align = "left" }
    local box_h = Screen:scaleBySize(64)
    local sample = TextWidget:new{ text = _("The quick brown fox jumps over the lazy dog."),
        face = core.getFaceOr(current, 20, "cfont"), max_width = inner - Screen:scaleBySize(28) }
    table.insert(body, VerticalSpan:new{ width = Screen:scaleBySize(14) })
    table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = P },
        atoms.RoundedBox:new{ width = inner, radius = Screen:scaleBySize(8), border = Size.border.button, border_color = core.COLORS.line,
            fill = BlitBuffer.COLOR_WHITE, pad_x = 0, pad_y = 0,
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = box_h }, sample } } })
    table.insert(body, VerticalSpan:new{ width = Screen:scaleBySize(14) })
    table.insert(body, rowLine())
    local fonts, seen = {}, {}
    for _i, font_path in ipairs(FontList:getFontList()) do
        -- key on the full path: two directories may ship the same file name, and the current
        -- font is matched by path below
        if not seen[font_path] then
            seen[font_path] = true
            table.insert(fonts, { name = font_path:match("([^/\\]+)$") or font_path, path = font_path })
        end
    end
    table.sort(fonts, function(a, b) return a.name:lower() < b.name:lower() end)
    table.insert(fonts, 1, { name = _("Default"), path = nil })
    for _i, f in ipairs(fonts) do
        local on = (f.path == nil and (current == nil or current == "")) or (f.path ~= nil and current == f.path)
        local d = Geom:new{ w = inner, h = Screen:scaleBySize(46) }
        local mark = on and TextWidget:new{ text = "✓", face = Font:getFace("cfont", 17), bold = true } or nil
        local line = HorizontalGroup:new{ HorizontalSpan:new{ width = P },
            OverlapGroup:new{ dimen = d, allow_mirroring = false,
                LeftContainer:new{ dimen = d, TextWidget:new{ text = f.name,
                    face = face15, bold = on, max_width = inner - Screen:scaleBySize(40) } },
                mark and RightContainer:new{ dimen = d, mark } or nil },
            HorizontalSpan:new{ width = P } }
        table.insert(body, VerticalGroup:new{ align = "left", atoms.TapBox:new{ line, callback = function()
            core.setSetting(self.font_key, f.path)
            list:refresh(); self:rebuild()
        end }, rowLine() })
    end
    local header = Pages.header(self, self.title, function() self:onClose() end, nil, false, function()
        Pages.exitAll(self); self.list:refresh()
    end)
    local avail = H - header:getSize().h
    local body_widget = Pages.paged(self, W, avail, body, { fixed = 4 })
    self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0,
        background = BlitBuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", header, body_widget } }
end

-- Full-screen picker for Books, Chapters and Tags (BookFilter / ChapterFilter boards).
-- Books, Chapters and Tags: the same "Only these" / "Hide these" switch and checkboxes. A tap marks
-- an item with the switch's side (✓ only, ✕ hide) or clears it.
-- Changes count live ("Show N annotations"); Cancel / ‹ / ✕ put the filter back.
Pages.ListPicker = InputContainer:extend{
    list = nil, title = "", items = nil, inc_key = nil, exc_key = nil,
    mode_labels = nil, search_hint = nil, on_done = nil,
    covers_fullscreen = true,
}
Pages.watchResize(Pages.ListPicker)
Pages.forwardGestures(Pages.ListPicker)
function Pages.ListPicker:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local af = self.list.active_filter or {}
    self.list.active_filter = af
    self.saved_inc = Pages.deepCopy(af[self.inc_key])
    self.saved_exc = Pages.deepCopy(af[self.exc_key])
    if self.inc_key == "books" then -- changing the books clears the chapters; Cancel brings them back
        self.saved_chapters, self.saved_chapters_exc = Pages.deepCopy(af.chapters), Pages.deepCopy(af.chapters_exclude)
    end
    self.query = ""
    -- One side at a time: the marked items are either the only ones shown or the hidden ones.
    -- A filter from before that has both keeps its "only" side: with "only these" set, the
    -- hidden ones were not shown anyway, so the list stays the same.
    local has_inc = af[self.inc_key] and next(af[self.inc_key])
    if has_inc then af[self.exc_key] = nil end
    self.mode = has_inc and "inc" or ((af[self.exc_key] and next(af[self.exc_key])) and "exc" or "inc")
    if self.inc_key == "books" then self.books_sig = self:booksSig() end
    if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    self:build()
end
function Pages.ListPicker:state(key)
    local af = self.list.active_filter
    if af[self.inc_key] and af[self.inc_key][key] then return "inc" end
    if af[self.exc_key] and af[self.exc_key][key] then return "exc" end
    return nil
end
function Pages.ListPicker:set(key, st)
    local af = self.list.active_filter
    for _i, k in ipairs({ self.inc_key, self.exc_key }) do
        if af[k] then af[k][key] = nil; if not next(af[k]) then af[k] = nil end end
    end
    if st then
        local k = (st == "inc") and self.inc_key or self.exc_key
        af[k] = af[k] or {}
        af[k][key] = true
    end
end
-- which books are chosen, as one string (a search in the picker changes nothing there)
function Pages.ListPicker:booksSig()
    local af, parts = self.list.active_filter or {}, {}
    local keys = { "books", "books_exclude" }
    for n = 1, 2 do
        local k = keys[n]
        local names = {}
        for name in pairs(af[k] or {}) do names[#names + 1] = name end
        table.sort(names)
        parts[#parts + 1] = k .. ":" .. table.concat(names, "\0")
    end
    return table.concat(parts, "\1")
end
function Pages.ListPicker:changed()
    if self.inc_key == "books" then
        local sig = self:booksSig()
        if sig ~= self.books_sig then NotesListWidget.booksChanged(self.list.active_filter) end
        self.books_sig = sig
    end
    self.list:applyFilter() -- count only; the list is redrawn when the picker closes
    self:build()
    UIManager:setDirty(self, "ui")
end
function Pages.ListPicker:visibleItems()
    if self.query == "" then return self.items end
    local lower = item.NoteItemWidget.lower
    local q = lower(self.query)
    local out = {}
    for _i, it in ipairs(self.items) do
        if lower((it.title or "") .. " " .. (it.subtitle or "")):find(q, 1, true) then table.insert(out, it) end
    end
    return out
end
function Pages.ListPicker:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local thin = Size.border.button
    local face13, face14, face15 = Font:getFace("cfont", 13), Font:getFace("cfont", 14), Font:getFace("cfont", 15)
    local function underlined(text)
        local tw = TextWidget:new{ text = text, face = face13 }
        return VerticalGroup:new{ tw, LineWidget:new{ dimen = Geom:new{ w = tw:getSize().w, h = Size.line.medium }, background = core.COLORS.ink } }
    end
    local visible = self:visibleItems()

    local header = Pages.header(self, self.title, function() self:onClose() end, nil, false, function()
        self:onClose()
        if self.list.filter_screen then self.list.filter_screen:onClose() end
    end)

    -- controls: mode switch, search, "N of M selected", Clear
    local controls = VerticalGroup:new{ align = "left" }
    do
        local seg = HorizontalGroup:new{}
        local cell_h = Screen:scaleBySize(40)
        local cell_w = math.floor((inner - thin * 3) / 2)
        for i, m in ipairs({ { "inc", self.mode_labels[1] }, { "exc", self.mode_labels[2] } }) do
            local on = (self.mode == m[1])
            if i > 1 then table.insert(seg, LineWidget:new{ dimen = Geom:new{ w = thin, h = cell_h }, background = core.COLORS.ink }) end
            table.insert(seg, atoms.TapBox:new{
                FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = on and core.COLORS.ink or BlitBuffer.COLOR_WHITE,
                    CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h },
                        TextWidget:new{ text = m[2], face = face14, bold = on, max_width = cell_w - Screen:scaleBySize(8),
                            fgcolor = on and BlitBuffer.COLOR_WHITE or core.COLORS.ink } } },
                callback = function()
                    if self.mode == m[1] then return end
                    -- everything marked moves to the other side
                    local chosen = {}
                    for _i, it in ipairs(self.items) do
                        if self:state(it.key) then table.insert(chosen, it.key) end
                    end
                    self.mode = m[1]
                    for _i, key in ipairs(chosen) do self:set(key, m[1]) end
                    self:changed()
                end,
            })
        end
        table.insert(controls, atoms.RoundedOutline:new{ radius = Screen:scaleBySize(8), border = thin, seg })
        table.insert(controls, VerticalSpan:new{ width = Screen:scaleBySize(12) })
    end
    if self.search_hint then
        local has_q = self.query ~= ""
        local qtext = TextWidget:new{ text = has_q and self.query or self.search_hint, face = face14,
            fgcolor = has_q and core.COLORS.ink or core.COLORS.muted, max_width = inner - Screen:scaleBySize(60) }
        local field_h = Screen:scaleBySize(42)
        table.insert(controls, atoms.TapBox:new{
            atoms.RoundedBox:new{ width = inner, radius = Screen:scaleBySize(8), border = thin, border_color = core.COLORS.line,
                fill = BlitBuffer.COLOR_WHITE, pad_x = Screen:scaleBySize(12), pad_y = math.floor((field_h - qtext:getSize().h) / 2),
                HorizontalGroup:new{ align = "center",
                    IconWidget:new{ icon = "appbar.search", width = Screen:scaleBySize(18), height = Screen:scaleBySize(18) },
                    HorizontalSpan:new{ width = Screen:scaleBySize(8) }, qtext } },
            callback = function() self:askQuery() end,
        })
        table.insert(controls, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    end
    local n_sel = 0
    for _i, it in ipairs(self.items) do if self:state(it.key) then n_sel = n_sel + 1 end end
    local d = Geom:new{ w = inner, h = Screen:scaleBySize(32) }
    local links = HorizontalGroup:new{ align = "center" }
    table.insert(links, atoms.TapBox:new{ underlined(_("Clear")), callback = function()
        for _i, it in ipairs(self.items) do self:set(it.key, nil) end
        self:changed()
    end })
    table.insert(controls, OverlapGroup:new{ dimen = d, allow_mirroring = false,
        LeftContainer:new{ dimen = d, TextWidget:new{ text = string.format(_("%d of %d selected"), n_sel, #self.items),
            face = face13, fgcolor = core.COLORS.muted } },
        RightContainer:new{ dimen = d, links } })
    local top = VerticalGroup:new{ align = "left", header,
        HorizontalGroup:new{ HorizontalSpan:new{ width = P }, VerticalGroup:new{ align = "left",
            -- same space above the switch as between the switch and the search field
            VerticalSpan:new{ width = Screen:scaleBySize(12) }, controls,
            VerticalSpan:new{ width = Screen:scaleBySize(6) } } },
        LineWidget:new{ dimen = Geom:new{ w = W, h = Size.line.thin }, background = core.COLORS.line } }

    -- rows (grouped when items have a group, e.g. chapters by book)
    local rinner = inner
    local rows = VerticalGroup:new{ align = "left" }
    local box = Screen:scaleBySize(24)
    local last_group
    for _i, it in ipairs(visible) do
        if it.group and it.group ~= last_group then
            last_group = it.group
            local gd = Geom:new{ w = rinner, h = Screen:scaleBySize(40) }
            local group_name = it.group
            -- the book's heading and its line as one row, kept with its first chapter
            local hd = VerticalGroup:new{ align = "left", OverlapGroup:new{ dimen = gd, allow_mirroring = false,
                LeftContainer:new{ dimen = gd, TextWidget:new{ text = group_name, face = core.getFaceOr(core.SERIF_FONT, 17, "cfont"), bold = true,
                    max_width = rinner - Screen:scaleBySize(60) } },
                RightContainer:new{ dimen = gd, atoms.TapBox:new{ underlined(_("All")), callback = function()
                    for _j, x in ipairs(self.items) do if x.group == group_name then self:set(x.key, self.mode or "inc") end end
                    self:changed()
                end } } },
                LineWidget:new{ dimen = Geom:new{ w = rinner, h = Size.line.thin }, background = core.COLORS.line_light } }
            hd.keep_with_next = true
            table.insert(rows, hd)
        end
        local st = self:state(it.key)
        local mark
        if st == "exc" then
            mark = atoms.RoundedBox:new{ width = box, radius = Screen:scaleBySize(5), fill = core.COLORS.ink, pad_x = 0, pad_y = 0,
                CenterContainer:new{ dimen = Geom:new{ w = box, h = box },
                    Pages.TextMark:new{ icon = "close", size = Screen:scaleBySize(16) } } }
        elseif st then
            mark = atoms.RoundedBox:new{ width = box, radius = Screen:scaleBySize(5), fill = core.COLORS.ink, pad_x = 0, pad_y = 0,
                CenterContainer:new{ dimen = Geom:new{ w = box, h = box },
                    Pages.TextMark:new{ icon = "check", size = Screen:scaleBySize(18) } } }
        else
            mark = atoms.RoundedBox:new{ width = box, radius = Screen:scaleBySize(5), border = Size.border.button, border_color = core.COLORS.ink,
                fill = BlitBuffer.COLOR_WHITE, pad_x = 0, pad_y = 0, VerticalSpan:new{ width = box } }
        end
        local count = TextWidget:new{ text = tostring(it.count or ""), face = face13, fgcolor = core.COLORS.muted }
        local text_w = rinner - box - Screen:scaleBySize(14) * 2 - count:getSize().w
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = it.title, face = it.serif and core.getFaceOr(core.SERIF_FONT, 17, "cfont") or face15,
                bold = it.serif, max_width = text_w } }
        if it.subtitle and it.subtitle ~= "" then
            table.insert(texts, TextWidget:new{ text = it.subtitle, face = Font:getFace("cfont", 12),
                fgcolor = core.COLORS.muted, max_width = text_w })
        end
        local pad = Screen:scaleBySize(12)
        local row_h = math.max(box, texts:getSize().h) + pad * 2
        local rd = Geom:new{ w = rinner, h = row_h }
        local key = it.key
        table.insert(rows, atoms.TapBox:new{ OverlapGroup:new{ dimen = rd, allow_mirroring = false,
            LeftContainer:new{ dimen = rd, HorizontalGroup:new{ align = "center", mark,
                HorizontalSpan:new{ width = Screen:scaleBySize(14) }, texts } },
            RightContainer:new{ dimen = rd, count } },
            callback = function()
                -- tap: clear a marked item, or mark it with the switch's side
                -- (not `x and nil or y`: nil is false in Lua, that always gives y)
                if self:state(key) then self:set(key, nil) else self:set(key, self.mode) end
                self:changed()
            end })
        table.insert(rows, LineWidget:new{ dimen = Geom:new{ w = rinner, h = Size.line.thin }, background = core.COLORS.line_light })
    end
    if #visible == 0 then
        table.insert(rows, VerticalSpan:new{ width = Screen:scaleBySize(24) })
        -- with a search: nothing matches it; without one there is nothing to pick from
        local empty = _("Nothing found.")
        if self.query == "" then
            empty = ({ books = _("No books"), chapters = _("No chapters"), tags = _("No tags") })[self.inc_key] or empty
        end
        table.insert(rows, TextWidget:new{ text = empty, face = face14, fgcolor = core.COLORS.muted })
    end

    local footer = Pages.footer(function() self:onClose() end, Pages.countText(#(self.list.filtered_notes or {}), self.list),
        function() self:onDone() end)

    local avail = H - top:getSize().h - footer:getSize().h
    local body = Pages.paged(self, W, avail, rows, { left = P })
    self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0, background = BlitBuffer.COLOR_WHITE,
        OverlapGroup:new{ dimen = Geom:new{ w = W, h = H }, allow_mirroring = false,
            VerticalGroup:new{ align = "left", top, body },
            BottomContainer:new{ dimen = Geom:new{ w = W, h = H }, footer } } }
end
function Pages.ListPicker:askQuery()
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = self.search_hint, input = self.query,
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Clear"), callback = function() UIManager:close(dialog); self.query = ""; self.page_idx = 1; self:changed() end },
            { text = _("Search"), is_enter_default = true, callback = function()
                self.query = dialog:getInputText() or ""; self.page_idx = 1
                UIManager:close(dialog)
                self:changed()
            end },
        }},
    }
    NotesListWidget.showDialog(dialog)
    dialog:onShowKeyboard()
end
function Pages.ListPicker:onDone()
    UIManager:close(self, "flashui")
    self.list.current_page = 1
    self.list:refresh()
    if self.on_done then self.on_done() end
    return true
end
function Pages.ListPicker:onClose()
    local af = self.list.active_filter
    af[self.inc_key] = self.saved_inc
    af[self.exc_key] = self.saved_exc
    if self.inc_key == "books" then af.chapters, af.chapters_exclude = self.saved_chapters, self.saved_chapters_exc end
    self.list:applyFilter()
    UIManager:close(self, "flashui")
    if self.on_done then self.on_done() end
    return true
end

-- Sort page, opened from the Sort row on Filter & sort: the page frame of the Books / Tags pickers
-- (same header, footer and paging) around the sort card's levels: per level a row of key chips and
-- a two-part direction bar, and the order in words underneath. Then by / And then by appear when
-- the level before allows them.
-- Changes show straight away; Cancel / ‹ / ✕ put the old order back.
Pages.SortPicker = InputContainer:extend{ list = nil, on_done = nil, covers_fullscreen = true }
Pages.watchResize(Pages.SortPicker)
Pages.forwardGestures(Pages.SortPicker)
function Pages.SortPicker:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.saved_sorts = sort.SortState.snapshot()
    if Device:hasKeys() then self.key_events.Close = { { Input.group.Back } } end
    self:build()
end
function Pages.SortPicker:changed()
    self.list:applySort()
    self.list:applyFilter()
    self:build()
    UIManager:setDirty(self, "ui")
end
function Pages.SortPicker:build()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local P = Screen:scaleBySize(24)
    local inner = W - P * 2
    local thin = Size.border.button
    local face14 = Font:getFace("cfont", 14)
    local single = self.list.single_book
    local levels = sort.SortState.view(sort.SortState.get(single), single)
    local function apply(c)
        sort.SortState.set(single, sort.SortState.encode(sort.SortState.revalidate(c, single)))
        self:changed()
    end
    -- as the sort card: the quick picks, a line, the chip rows and direction bars per level, then
    -- the order in a sentence
    local rows = VerticalGroup:new{ align = "left" }
    local function heading(text)
        -- one row, kept with what follows (Page.paged never ends a page with it)
        local hd = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = Screen:scaleBySize(14) },
            TextWidget:new{ text = text:upper(), face = Font:getFace("cfont", 11), bold = true, fgcolor = core.COLORS.muted },
            VerticalSpan:new{ width = Screen:scaleBySize(6) } }
        hd.keep_with_next = true
        table.insert(rows, hd)
    end
    heading(_("Quick picks"))
    local encoded = sort.SortState.encode(levels)
    local picks = {}
    for i, q in ipairs(NotesListWidget.States.quickPicks(single)) do
        picks[i] = { label = q[1], on = sort.SortState.encode(sort.SortState.parse(q[2])) == encoded,
            callback = function() apply(sort.SortState.parse(q[2])) end }
    end
    NotesListWidget.States.sortChips(rows, 0, inner, picks)
    table.insert(rows, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(rows, LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.medium }, background = core.COLORS.line })
    NotesListWidget.States.sortLevels(rows, { width = inner, side = 0, single = single, levels = levels,
        heading = heading, apply = apply })
    table.insert(rows, VerticalSpan:new{ width = Screen:scaleBySize(16) })
    table.insert(rows, FrameContainer:new{ bordersize = thin, color = core.COLORS.line, radius = Screen:scaleBySize(8),
        padding = Screen:scaleBySize(10), margin = 0,
        TextBoxWidget:new{ text = sort.SortState.describe(levels, single), face = face14,
            width = inner - Screen:scaleBySize(20) - thin * 2 } })

    local header = Pages.header(self, _("Sort"), function() self:onClose() end, nil, false, function()
        self:onClose()
        if self.list.filter_screen then self.list.filter_screen:onClose() end
    end)
    local footer = Pages.footer(function() self:onClose() end, Pages.countText(#(self.list.filtered_notes or {}), self.list),
        function() self:onDone() end)
    local avail = H - header:getSize().h - footer:getSize().h
    local body = Pages.paged(self, W, avail, rows, { left = P })
    self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0, background = BlitBuffer.COLOR_WHITE,
        OverlapGroup:new{ dimen = Geom:new{ w = W, h = H }, allow_mirroring = false,
            VerticalGroup:new{ align = "left", header, body },
            BottomContainer:new{ dimen = Geom:new{ w = W, h = H }, footer } } }
end
function Pages.SortPicker:onDone()
    UIManager:close(self, "flashui")
    self.list.current_page = 1
    self.list:refresh()
    if self.on_done then self.on_done() end
    return true
end
function Pages.SortPicker:onClose()
    if sort.SortState.restore(self.saved_sorts) then self.list:applySort() end
    self.list:applyFilter()
    UIManager:close(self, "flashui")
    if self.on_done then self.on_done() end
    return true
end

function Pages.bind(deps)
    if deps.NotesListWidget then NotesListWidget = deps.NotesListWidget end
    if deps.AllNotesViewer then AllNotesViewer = deps.AllNotesViewer end
    if not NotesListWidget then return end
    for _, cls in ipairs(_tracked_classes) do NotesListWidget.trackWindow(cls) end
end

return Pages
