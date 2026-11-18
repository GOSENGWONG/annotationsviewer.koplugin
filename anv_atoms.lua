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

-- true-colour widgets need anv_item at paint time (item loads later).
local _item_for_paint
local function itemForPaint()
    if not _item_for_paint then _item_for_paint = require("anv_item").NoteItemWidget end
    return _item_for_paint
end

local StrikeoutLineWidget = InputContainer:extend{ width = nil, height = nil, y_offset = nil }
function StrikeoutLineWidget:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function StrikeoutLineWidget:paintTo(bb, x, y)
    bb:paintRect(x, y + (self.y_offset or math.floor(self.height / 2)), self.width, Size.line.medium, BlitBuffer.COLOR_BLACK)
end
local UnderlineWidget = InputContainer:extend{ width = nil, height = nil }
function UnderlineWidget:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function UnderlineWidget:paintTo(bb, x, y)
    bb:paintRect(x, y + self.height - Size.line.medium, self.width, Size.line.medium, BlitBuffer.COLOR_BLACK)
end
local TapBox = InputContainer:extend{ callback = nil }
function TapBox:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapBox = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    if self.hold_callback then
        self.ges_events.HoldBox = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } }
    end
end
function TapBox:onTapBox(_, ges)
    if self.callback then self.callback(ges) end
    return true
end
function TapBox:onHoldBox(_, ges)
    if self.hold_callback then self.hold_callback(ges) end
    return true
end

-- Header icon button: a KOReader icon by name, or (file) one of the plugin's icons,
-- falling back to the named icon if that file is missing.
local function newHeaderButton(icon, callback, show_parent, file, allow_flash)
    local btn = IconButton:new{
        icon = icon,
        width = HEADER_ICON_SIZE, height = HEADER_ICON_SIZE,
        padding = HEADER_ICON_PAD,
        callback = callback,
        show_parent = show_parent,
        allow_flash = allow_flash ~= false,
    }
    if file and lfs.attributes(file, "mode") == "file" then
        local img = IconWidget:new{ file = file, width = HEADER_ICON_SIZE, height = HEADER_ICON_SIZE }
        btn.image:free()
        btn.image = img
        btn.horizontal_group[2] = img
        btn:update()
    end
    return btn
end

-- Row-by-row helpers for rounded shapes we draw ourselves (exact control over corners).
local function circleInset(r, row) -- distance in from the edge of a radius-r corner on this row
    local dy = r - row - 0.5
    if dy <= 0 then return 0 end
    if dy >= r then return r end
    return math.ceil(r - math.sqrt(r * r - dy * dy))
end
local function paintRow(bb, x, y, w, color)
    if w <= 0 then return end
    if BlitBuffer.isColor8(color) then bb:paintRect(x, y, w, 1, color) else bb:paintRectRGB32(x, y, w, 1, color) end
end

-- Fully rounded chip filled with a colour. Draws its own fill row by row, because
-- FrameContainer's rounded fill leaves square colour corners outside the border on colour screens.
local Pill = InputContainer:extend{ width = 0, height = 0, fill = nil, border = 1, border_color = nil }
function Pill:getSize() return Geom:new{ w = self.width, h = self.height } end
function Pill:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local w, h = self.width, self.height
    local r = math.floor(h / 2)
    if self.fill then
        local rgb = not BlitBuffer.isColor8(self.fill)
        for row = 0, h - 1 do
            local dy = math.abs(row + 0.5 - h / 2)
            local inset = math.ceil(r - math.sqrt(math.max(0, r * r - dy * dy)))
            if rgb then
                bb:paintRectRGB32(x + inset, y + row, w - inset * 2, 1, self.fill)
            else
                bb:paintRect(x + inset, y + row, w - inset * 2, 1, self.fill)
            end
        end
    end
    if self.border > 0 then
        bb:paintBorder(x, y, w, h, self.border, self.border_color or BlitBuffer.COLOR_BLACK, r,
            G_reader_settings:nilOrTrue("anti_alias_ui"))
    end
    if self[1] then
        local cs = self[1]:getSize()
        self[1]:paintTo(bb, x + math.floor((w - cs.w) / 2), y + math.floor((h - cs.h) / 2))
    end
end

-- Colour & style filter: a set of "color:<key>" / "style:<drawer>" entries in af.cs, and
-- af.cs_exclude to hide them instead of showing only them. Older saved filters used a single
-- af.type/af.value (and type_exclude/value_exclude); they are moved into the set here.
local SheetFrame = InputContainer:extend{ width = 0, radius = 0, border = 2, pad_x = 0, pad_top = 0, pad_bottom = 0 }
function SheetFrame:getSize()
    return Geom:new{ w = self.width, h = self[1]:getSize().h + self.pad_top + self.pad_bottom + self.border }
end
function SheetFrame:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local w, h, r, bw = size.w, size.h, self.radius, self.border
    -- The rounded top is drawn with KOReader's own (anti-aliased) rounded fill and border on
    -- a scratch copy of the strip under it. That rounded box is wider than the sheet (by
    -- `ext` on each side), so the corners curve on past the sheet's edges instead of ending
    -- in a short upright line; only the visible middle and top rows are copied back.
    -- narrower than the screen (landscape): real corners and outlined sides instead
    local narrow = w < Screen:getWidth()
    local ext = narrow and 0 or math.floor(r * 0.3)
    local band_h = math.min(h, r * 2 + bw * 2)
    local tmp = BlitBuffer.new(w + ext * 2, band_h, bb:getType())
    tmp:fill(BlitBuffer.COLOR_WHITE)
    tmp:blitFrom(bb, ext, 0, x, y, w, band_h)
    tmp:paintRoundedRect(0, 0, w + ext * 2, band_h, BlitBuffer.COLOR_WHITE, r)
    tmp:paintBorder(0, 0, w + ext * 2, band_h, bw, BlitBuffer.COLOR_BLACK, r, G_reader_settings:nilOrTrue("anti_alias_ui"))
    bb:blitFrom(tmp, x, y, ext, 0, w, r)
    tmp:free()
    bb:paintRect(x, y + r, w, h - r, BlitBuffer.COLOR_WHITE)
    if narrow then
        bb:paintRect(x, y + r, bw, h - r, BlitBuffer.COLOR_BLACK)
        bb:paintRect(x + w - bw, y + r, bw, h - r, BlitBuffer.COLOR_BLACK)
    end
    self[1]:paintTo(bb, x + self.pad_x, y + bw + self.pad_top)
end

-- Box with rounded corners, filled row by row (so a colour fill looks the same on colour
-- and black-and-white screens, with no square colour corners), optional outline, padded child.
local RoundedBox = InputContainer:extend{ width = 0, fill = nil, radius = 0, border = 0, border_color = nil, pad_x = 0, pad_y = 0 }
function RoundedBox:getSize()
    return Geom:new{ w = self.width, h = self[1]:getSize().h + self.pad_y * 2 }
end
function RoundedBox:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local w, h, r = size.w, size.h, self.radius
    if self.fill then
        for row = 0, h - 1 do
            local o = 0
            if row < r then o = circleInset(r, row) elseif row >= h - r then o = circleInset(r, h - 1 - row) end
            paintRow(bb, x + o, y + row, w - o * 2, self.fill)
        end
    end
    if self.border > 0 then
        bb:paintBorder(x, y, w, h, self.border, self.border_color or BlitBuffer.COLOR_BLACK, r,
            G_reader_settings:nilOrTrue("anti_alias_ui"))
    end
    self[1]:paintTo(bb, x + self.pad_x, y + self.pad_y)
end

-- Draws its child, then a rounded border over it, cutting the child's corners to the curve
-- (so a filled first/last segment follows the rounded corner, like CSS overflow:hidden).
local RoundedOutline = InputContainer:extend{ radius = 0, border = 2, color = nil }
function RoundedOutline:getSize()
    local cs = self[1]:getSize()
    return Geom:new{ w = cs.w + self.border * 2, h = cs.h + self.border * 2 }
end
function RoundedOutline:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local w, h, r = size.w, size.h, self.radius
    self[1]:paintTo(bb, x + self.border, y + self.border)
    for row = 0, r - 1 do
        local o = circleInset(r, row)
        paintRow(bb, x, y + row, o, BlitBuffer.COLOR_WHITE)
        paintRow(bb, x + w - o, y + row, o, BlitBuffer.COLOR_WHITE)
        paintRow(bb, x, y + h - 1 - row, o, BlitBuffer.COLOR_WHITE)
        paintRow(bb, x + w - o, y + h - 1 - row, o, BlitBuffer.COLOR_WHITE)
    end
    bb:paintBorder(x, y, w, h, self.border, self.color or BlitBuffer.COLOR_BLACK, r,
        G_reader_settings:nilOrTrue("anti_alias_ui"))
end

-- Text with an underline or a line through it, as a single widget.
-- Pill / RoundedBox with `true_color = true` keep their colours in night mode (see paintTrue).
do
    local function trueColor(cls)
        local base = cls.paintTo
        function cls:paintTo(bb, x, y)
            if not self.true_color or not Screen.night_mode then return base(self, bb, x, y) end
            local size = self:getSize()
            itemForPaint().paintTrue(bb, x, y, size.w, size.h, function(b, xx, yy) base(self, b, xx, yy) end)
            self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
        end
    end
    trueColor(Pill)
    trueColor(RoundedBox)
end

-- Module exports
M.StrikeoutLineWidget = StrikeoutLineWidget
M.UnderlineWidget = UnderlineWidget
M.TapBox = TapBox
M.newHeaderButton = newHeaderButton
M.Pill = Pill
M.SheetFrame = SheetFrame
M.RoundedBox = RoundedBox
M.RoundedOutline = RoundedOutline
M.circleInset = circleInset
M.paintRow = paintRow

return M
