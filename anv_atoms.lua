-- anv_atoms.lua — Annotations Viewer
--
-- Low-level widgets and drawing primitives shared by note items, the detail
-- sheet and full-screen pages: strike/underline strokes, tap boxes, pills,
-- header buttons and rounded boxes/outlines.
--
-- Public API (used by other modules):
--   StrikeoutLineWidget   widget drawing a strikeout stroke
--   UnderlineWidget       widget drawing an underline stroke
--   TapBox                tap/hold container with callbacks
--   newHeaderButton       build an icon button, plugin icon or KOReader icon
--   Pill                  rounded capsule widget with border
--   SheetFrame            rounded frame widget with padding
--   RoundedBox            filled rounded rectangle widget
--   RoundedOutline        rounded border-only widget
--   circleInset           corner inset for a row of a rounded shape
--   paintRow              paint one horizontal row of a rounded shape

local Atoms = {}

local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local IconButton = require("ui/widget/iconbutton")
local IconWidget = require("ui/widget/iconwidget")
local BlitBuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local core = require("anv_core")

-- true-colour widgets need anv_item at paint time (item loads later).
local _item_for_paint
local function itemForPaint()
    if not _item_for_paint then _item_for_paint = require("anv_item").NoteItemWidget end
    return _item_for_paint
end

Atoms.StrikeoutLineWidget = InputContainer:extend{ width = nil, height = nil, y_offset = nil }
function Atoms.StrikeoutLineWidget:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function Atoms.StrikeoutLineWidget:paintTo(bb, x, y)
    bb:paintRect(x, y + (self.y_offset or math.floor(self.height / 2)), self.width, Size.line.medium, BlitBuffer.COLOR_BLACK)
end
Atoms.UnderlineWidget = InputContainer:extend{ width = nil, height = nil }
function Atoms.UnderlineWidget:init() self.dimen = Geom:new{ w = self.width, h = self.height } end
function Atoms.UnderlineWidget:paintTo(bb, x, y)
    bb:paintRect(x, y + self.height - Size.line.medium, self.width, Size.line.medium, BlitBuffer.COLOR_BLACK)
end
Atoms.TapBox = InputContainer:extend{ callback = nil }
function Atoms.TapBox:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapBox = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    if self.hold_callback then
        self.ges_events.HoldBox = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } }
    end
end
function Atoms.TapBox:onTapBox(_, ges)
    if self.callback then self.callback(ges) end
    return true
end
function Atoms.TapBox:onHoldBox(_, ges)
    if self.hold_callback then self.hold_callback(ges) end
    return true
end

-- Header icon button: a KOReader icon by name, or (file) one of the plugin's icons,
-- falling back to the named icon if that file is missing.
function Atoms.newHeaderButton(icon, callback, show_parent, file, allow_flash)
    local btn = IconButton:new{
        icon = icon,
        width = core.HEADER_ICON_SIZE, 
        height = core.HEADER_ICON_SIZE,
        padding = core.HEADER_ICON_PAD,
        callback = callback,
        show_parent = show_parent,
        allow_flash = allow_flash ~= false,
    }
    if file and lfs.attributes(file, "mode") == "file" then
        local img = IconWidget:new{ file = file, width = core.HEADER_ICON_SIZE, height = core.HEADER_ICON_SIZE }
        btn.image:free()
        btn.image = img
        btn.horizontal_group[2] = img
        btn:update()
    end
    return btn
end

-- Row-by-row helpers for rounded shapes we draw ourselves (exact control over corners).
function Atoms.circleInset(r, row) -- distance in from the edge of a radius-r corner on this row
    local dy = r - row - 0.5
    if dy <= 0 then return 0 end
    if dy >= r then return r end
    return math.ceil(r - math.sqrt(r * r - dy * dy))
end
function Atoms.paintRow(bb, x, y, w, color)
    if w <= 0 then return end
    if BlitBuffer.isColor8(color) then bb:paintRect(x, y, w, 1, color) else bb:paintRectRGB32(x, y, w, 1, color) end
end

-- Fully rounded chip filled with a colour. Draws its own fill row by row, because
-- FrameContainer's rounded fill leaves square colour corners outside the border on colour screens.
Atoms.Pill = InputContainer:extend{ width = 0, height = 0, fill = nil, border = 1, border_color = nil }
function Atoms.Pill:getSize() return Geom:new{ w = self.width, h = self.height } end
function Atoms.Pill:paintTo(bb, x, y)
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
            core.getAntiAlias())
    end
    if self[1] then
        local cs = self[1]:getSize()
        self[1]:paintTo(bb, x + math.floor((w - cs.w) / 2), y + math.floor((h - cs.h) / 2))
    end
end

Atoms.SheetFrame = InputContainer:extend{ width = 0, radius = 0, border = 2, pad_x = 0, pad_top = 0, pad_bottom = 0 }
function Atoms.SheetFrame:getSize()
    return Geom:new{ w = self.width, h = self[1]:getSize().h + self.pad_top + self.pad_bottom + self.border }
end
function Atoms.SheetFrame:paintTo(bb, x, y)
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
    tmp:paintBorder(0, 0, w + ext * 2, band_h, bw, BlitBuffer.COLOR_BLACK, r, core.getAntiAlias())
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
Atoms.RoundedBox = InputContainer:extend{ width = 0, fill = nil, radius = 0, border = 0, border_color = nil, pad_x = 0, pad_y = 0 }
function Atoms.RoundedBox:getSize()
    return Geom:new{ w = self.width, h = self[1]:getSize().h + self.pad_y * 2 }
end
function Atoms.RoundedBox:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local w, h, r = size.w, size.h, self.radius
    if self.fill then
        for row = 0, h - 1 do
            local o = 0
            if row < r then o = Atoms.circleInset(r, row) elseif row >= h - r then o = Atoms.circleInset(r, h - 1 - row) end
            Atoms.paintRow(bb, x + o, y + row, w - o * 2, self.fill)
        end
    end
    if self.border > 0 then
        bb:paintBorder(x, y, w, h, self.border, self.border_color or BlitBuffer.COLOR_BLACK, r,
            core.getAntiAlias())
    end
    self[1]:paintTo(bb, x + self.pad_x, y + self.pad_y)
end

-- Draws its child, then a rounded border over it, cutting the child's corners to the curve
-- (so a filled first/last segment follows the rounded corner, like CSS overflow:hidden).
Atoms.RoundedOutline = InputContainer:extend{ radius = 0, border = 2, color = nil }
function Atoms.RoundedOutline:getSize()
    local cs = self[1]:getSize()
    return Geom:new{ w = cs.w + self.border * 2, h = cs.h + self.border * 2 }
end
function Atoms.RoundedOutline:paintTo(bb, x, y)
    local size = self:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
    local w, h, r = size.w, size.h, self.radius
    self[1]:paintTo(bb, x + self.border, y + self.border)
    for row = 0, r - 1 do
        local o = Atoms.circleInset(r, row)
        Atoms.paintRow(bb, x, y + row, o, BlitBuffer.COLOR_WHITE)
        Atoms.paintRow(bb, x + w - o, y + row, o, BlitBuffer.COLOR_WHITE)
        Atoms.paintRow(bb, x, y + h - 1 - row, o, BlitBuffer.COLOR_WHITE)
        Atoms.paintRow(bb, x + w - o, y + h - 1 - row, o, BlitBuffer.COLOR_WHITE)
    end
    bb:paintBorder(x, y, w, h, self.border, self.color or BlitBuffer.COLOR_BLACK, r,
        core.getAntiAlias())
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
    trueColor(Atoms.Pill)
    trueColor(Atoms.RoundedBox)
end

return Atoms
