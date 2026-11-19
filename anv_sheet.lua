-- anv_sheet.lua — Annotations Viewer
--
-- The annotation detail sheet. AnnotationSheet renders one note as a card,
-- builds its decorated highlight text and handles rebuild, tap-outside and
-- close. main.lua is its sole constructor.
--
-- Public API (used by other modules):
--   AnnotationSheet    detail-sheet widget class
--   cleanHighlightText    strip markup from highlight text
--   buildHighlightLines    wrap decorated highlight text into lines
--   decoratedText    compose a text widget with its decoration
--   bind    inject the NotesListWidget collaborator

local Sheet = {}

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
local TextViewer = require("ui/widget/textviewer")
local IconButton = require("ui/widget/iconbutton")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local BlitBuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local Device = require("device")
local Input = Device.input
local lfs = require("libs/libkoreader-lfs")
local Font = require("ui/font")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local core = require("anv_core")
local _ = require("anv_i18n").gettext
local text = require("anv_text")
local atoms = require("anv_atoms")
local item = require("anv_item")

local NotesListWidget -- injected by main assembly

-- Annotation sheet: opens from the bottom when an annotation is tapped. Shows the whole
-- highlight in its colour, the note, style and colour choices, and Go to / Copy / Delete.
-- Highlight text as the list draws it: one row per wrapped line, each in the highlight's
-- colour (or underlined / struck through / inverted). Returns the widget and whether the
-- text was cut to max_lines.
function Sheet.cleanHighlightText(str)
    local paras = {}
    for p in ((str or ""):gsub("\r", "") .. "\n"):gmatch("([^\n]*)\n") do
        p = text.trimParagraph(p)
        if p ~= "" then table.insert(paras, p) end
    end
    return table.concat(paras, "\n")
end
-- in_box: the caller paints the colour behind all lines (rounded box), so lines get no
-- background of their own, only the text colour and underline/strikeout.
function Sheet.buildHighlightLines(str, face, width, drawer, color, max_lines, in_box)
    drawer = drawer or "lighten"
    local h_pad, v_pad = Size.padding.small, 1
    local line_width = width - h_pad * 2
    local fg, bg = BlitBuffer.COLOR_BLACK, BlitBuffer.COLOR_WHITE
    if drawer == "invert" then
        fg, bg = BlitBuffer.COLOR_WHITE, BlitBuffer.COLOR_BLACK
    elseif not core.isNoBackgroundStyle(drawer) then
        bg = core.getHighlightColor(color)
    end
    local lines, para_end = text.wrapText(str, face, line_width)
    local cut = max_lines and #lines > max_lines
    if cut then
        local kept = {}
        for i = 1, max_lines do kept[i] = lines[i] end
        kept[max_lines] = item.NoteItemWidget.cutLine(kept[max_lines], "…", face, line_width) .. "…"
        lines = kept
    end
    local justify = core.getJustify() == true
    local group = VerticalGroup:new{ align = "left" }
    for i, line in ipairs(lines) do
        local w
        if justify and i < #lines and not para_end[i] then
            w = text.createJustifiedLine(line, face, line_width, fg)
        else
            w = TextWidget:new{ text = line, face = face, fgcolor = fg }
        end
        local sz = w:getSize()
        local total_w, total_h = sz.w + h_pad * 2, sz.h + v_pad * 2
        if drawer == "strikeout" or drawer == "underscore" then
            local items = { CenterContainer:new{ dimen = Geom:new{ w = total_w, h = total_h }, w } }
            if drawer == "strikeout" then
                table.insert(items, atoms.StrikeoutLineWidget:new{ width = total_w, height = total_h, y_offset = math.floor(total_h / 2) })
            else
                table.insert(items, atoms.UnderlineWidget:new{ width = total_w, height = total_h })
            end
            table.insert(group, OverlapGroup:new{ dimen = Geom:new{ w = total_w, h = total_h }, unpack(items) })
        else
            table.insert(group, FrameContainer:new{
                padding = v_pad, padding_left = h_pad, padding_right = h_pad,
                margin = 0, bordersize = 0, background = (not in_box) and bg or nil, w,
            })
        end
    end
    return group, cut
end

Sheet.AnnotationSheet = InputContainer:extend{
    note = nil, viewer = nil, parent_widget = nil,
}
function Sheet.AnnotationSheet:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
    self:build()
end
-- Rounded-shape row helpers live in anv_atoms, alongside the widgets that draw them.
Sheet.circleInset, Sheet.paintRow = atoms.circleInset, atoms.paintRow

-- Bottom sheet: white panel across the full width, rounded top corners, border on top only.
function Sheet.decoratedText(tw, deco, color)
    if not deco then return tw end
    local sz = tw:getSize()
    local line_h = Size.line.medium
    local line = LineWidget:new{ dimen = Geom:new{ w = sz.w, h = line_h }, background = color }
    if deco == "underline" then
        return VerticalGroup:new{ tw, line }
    end
    -- strikeout: line a little above the middle (x-height middle)
    return OverlapGroup:new{ dimen = Geom:new{ w = sz.w, h = sz.h }, tw,
        VerticalGroup:new{ VerticalSpan:new{ width = math.floor(sz.h * 0.55) }, line } }
end

function Sheet.AnnotationSheet:build()
    local note, viewer, parent = self.note, self.viewer, self.parent_widget
    local nw = core.NoteWrapper:new(note)
    local W, H = Screen:getWidth(), Screen:getHeight()
    -- tap outside: the whole of the current screen (also after a rotation)
    self.ges_events.TapOutside = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
    -- bottom sheet as in the mockup: full width (in landscape no wider than the list column)
    local sheet_w = W
    if W > H then sheet_w = math.min(W, math.floor(H * 1.1)) end
    local P = Screen:scaleBySize(28)
    local inner = sheet_w - P * 2
    local gap = Screen:scaleBySize(18)
    local label_gap = Screen:scaleBySize(8)
    -- KOReader's own border sizes (Size.*): scaled for the screen's DPI like all its dialogs
    local thick = Size.border.thick   -- 2px at 160dpi
    local thin = Size.border.button   -- 1.5px at 160dpi
    local LIGHT = core.COLORS.line
    local MUTED = core.COLORS.muted
    local label_face = Font:getFace("cfont", 11)
    local group = VerticalGroup:new{ align = "left" }
    local function sectionLabel(text, right)
        local lbl = TextWidget:new{ text = text, face = label_face, bold = true, fgcolor = MUTED }
        if not right then return lbl end
        local d = Geom:new{ w = inner, h = math.max(lbl:getSize().h, right:getSize().h) }
        return OverlapGroup:new{ dimen = d, allow_mirroring = false,
            LeftContainer:new{ dimen = d, lbl }, RightContainer:new{ dimen = d, right } }
    end
    local function actionButton(text, callback, primary, width)
        local tw = TextWidget:new{ text = text, face = Font:getFace("cfont", 15), bold = primary,
            max_width = width - Screen:scaleBySize(12),
            fgcolor = primary and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK }
        local height = Screen:scaleBySize(48)
        local bw = primary and 0 or thin
        return atoms.TapBox:new{
            FrameContainer:new{
                bordersize = bw, radius = Screen:scaleBySize(8), padding = 0, margin = 0,
                background = primary and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                CenterContainer:new{ dimen = Geom:new{ w = width - bw * 2, h = height - bw * 2 }, tw },
            },
            callback = callback,
        }
    end

    -- 1. book title, info line, close
    local close_btn = IconButton:new{
        icon = "close", width = Screen:scaleBySize(22), height = Screen:scaleBySize(22),
        padding = Screen:scaleBySize(11), allow_flash = false,
        callback = function() self:onClose() end, show_parent = self,
    }
    local close_w = close_btn:getSize().w
    local text_w = inner - close_w + Screen:scaleBySize(10)
    local meta = {}
    local authors = nw:getDisplayAuthors()
    if authors and authors ~= "Unknown" then table.insert(meta, ((note.book_authors or authors):gsub("\n", ", "))) end
    if note.chapter and note.chapter ~= "" then table.insert(meta, note.chapter) end
    -- KOReader's page number (EPUB positions aren't numbers, so its label is used when there), then the date
    local page_no = note.page_label
    if page_no == nil and tonumber(note.page) and tonumber(note.page) > 0 then page_no = tonumber(note.page) end
    if page_no ~= nil and page_no ~= "" then table.insert(meta, _("page") .. " " .. tostring(page_no)) end
    local date_text = item.NoteItemWidget:formatDate(note.datetime, item.NoteItemWidget.dateStyle("sheet"))
    if date_text then table.insert(meta, date_text) end
    local head = VerticalGroup:new{ align = "left",
        TextBoxWidget:new{ text = note.book_title or _("Annotation"), face = core.getFaceOr(core.SERIF_FONT, 20, "cfont"),
            bold = true, width = text_w },
    }
    if #meta > 0 then
        table.insert(head, VerticalSpan:new{ width = Screen:scaleBySize(3) })
        table.insert(head, TextBoxWidget:new{ text = table.concat(meta, " · "), face = Font:getFace("cfont", 12),
            fgcolor = MUTED, width = text_w })
    end
    -- close button pulled up and right like the mockup (-8px / -10px)
    table.insert(group, HorizontalGroup:new{ align = "top", head,
        HorizontalSpan:new{ width = inner - text_w - close_w + Screen:scaleBySize(10) },
        VerticalGroup:new{ close_btn } })
    table.insert(group, VerticalSpan:new{ width = gap - Screen:scaleBySize(8) })

    -- 2. the highlight in a rounded box: filled with its colour (Lighten) or black (Invert),
    -- or white with a light outline (Underline/Strikeout, whose lines are drawn on the text).
    -- Long ones are cut and open in full on tap.
    if nw:hasHighlightedText() then
        local drawer = note.drawer or "lighten"
        local no_fill = core.isNoBackgroundStyle(drawer)
        local fill
        if drawer == "invert" then
            fill = BlitBuffer.COLOR_BLACK
        elseif not no_fill then
            -- same colour value and the same drawing call (paintRectRGB32) as the list's lines,
            -- so the screen turns it into exactly the same shade there and here
            fill = core.getHighlightColor(note.color)
        end
        local quote_text = Sheet.cleanHighlightText(note.highlighted_text)
        local content_face = select(3, item.getNoteFaces())
        local max_lines = math.max(3, math.floor(H * 0.28 / (text.getLineHeight(content_face) + 2)))
        local pad_v, pad_h = Screen:scaleBySize(10), Screen:scaleBySize(12)
        local ob = Size.border.thin
        -- same outer size for every style: the outline (when shown) takes the place of padding
        local bw = no_fill and ob or 0
        local lines, cut = Sheet.buildHighlightLines(quote_text, content_face, inner - (pad_h + ob) * 2,
            drawer, note.color, max_lines, true)
        local box = atoms.RoundedBox:new{
            true_color = not no_fill and drawer ~= "invert",
            width = inner, fill = fill or BlitBuffer.COLOR_WHITE, radius = Screen:scaleBySize(6),
            border = bw, border_color = LIGHT, pad_x = pad_h + ob, pad_y = pad_v + ob,
            lines,
        }
        table.insert(group, cut and atoms.TapBox:new{ box, callback = function()
            NotesListWidget.showDialog(TextViewer:new{ title = note.book_title or _("Annotation"), text = quote_text })
        end } or box)
        if cut then
            table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            table.insert(group, TextWidget:new{ text = _("Tap the highlight to read all of it"),
                face = Font:getFace("cfont", 12), fgcolor = MUTED })
        end
        table.insert(group, VerticalSpan:new{ width = gap })
    end

    -- 3. note, with an underlined Edit / Add note link
    local has_note = nw:hasUserNote()
    local link = TextWidget:new{ text = has_note and _("Edit") or _("Add note"), face = Font:getFace("cfont", 13) }
    local edit_link = atoms.TapBox:new{
        Sheet.decoratedText(link, "underline", BlitBuffer.COLOR_BLACK),
        callback = function()
            viewer:editNote(note, parent, function() self:rebuild() end)
        end,
    }
    table.insert(group, sectionLabel(_("YOUR NOTE"), edit_link))
    table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
    if has_note then
        table.insert(group, TextBoxWidget:new{
            text = note.user_note, face = Font:getFace("cfont", 15), width = inner, line_height = 0.45,
            height = math.min(Screen:scaleBySize(120), math.floor(H * 0.18)),
            height_adjust = true, height_overflow_show_ellipsis = true,
        })
    else
        table.insert(group, TextWidget:new{ text = _("No note yet."), face = Font:getFace("cfont", 15), fgcolor = MUTED })
    end
    table.insert(group, VerticalSpan:new{ width = gap })

    -- 4 and 5 (style, colour) are for highlights only: a bookmark has neither
    if not note.bookmark then
    -- 4. style: one bordered row of four; Underline/Strikeout labels show their line;
    -- the chosen one is filled black with white bold text
    table.insert(group, sectionLabel(_("STYLE")))
    table.insert(group, VerticalSpan:new{ width = label_gap })
    local current = note.drawer or "lighten"
    local cell_w = math.floor((inner - thin * 2 - thin * 3) / 4)
    local cell_h = Screen:scaleBySize(44)
    local seg = HorizontalGroup:new{}
    local ui_face = Font:getFace("cfont", 14)
    for i, st in ipairs(core.HIGHLIGHT_STYLES) do
        local key = st[1]
        local on = (current == key)
        if i > 1 then
            table.insert(seg, LineWidget:new{ dimen = Geom:new{ w = thin, h = cell_h }, background = BlitBuffer.COLOR_BLACK })
        end
        local color = on and BlitBuffer.COLOR_WHITE or BlitBuffer.COLOR_BLACK
        local tw = TextWidget:new{ text = st[2], face = ui_face, bold = on, fgcolor = color,
            max_width = cell_w - Screen:scaleBySize(24) }
        local deco = (key == "underscore" and "underline") or (key == "strikeout" and "strike") or nil
        local label = HorizontalGroup:new{ align = "center", Sheet.decoratedText(tw, deco, color) }
        table.insert(seg, atoms.TapBox:new{
            FrameContainer:new{
                bordersize = 0, padding = 0, margin = 0,
                background = on and BlitBuffer.COLOR_BLACK or BlitBuffer.COLOR_WHITE,
                CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, label },
            },
            callback = function()
                if not on then
                    viewer:setHighlightField(note, "drawer", key, parent)
                    self:rebuild()
                end
            end,
        })
    end
    table.insert(group, atoms.RoundedOutline:new{ radius = Screen:scaleBySize(8), border = thin, seg })
    table.insert(group, VerticalSpan:new{ width = gap })

    -- 5. colour: white rounded chips with a colour dot and the name; the chosen one has a
    -- thick black border and bold name. Widths are worked out for the bold version so
    -- choosing a colour never reflows the rows.
    table.insert(group, sectionLabel(_("COLOUR")))
    table.insert(group, VerticalSpan:new{ width = label_gap })
    local cur_color = nw:getNormalizedColor()
    local chip_h = Screen:scaleBySize(36)
    local chip_gap = Screen:scaleBySize(8)
    local dot = Screen:scaleBySize(16)
    local chip_face = Font:getFace("cfont", 13)
    local rows = VerticalGroup:new{ align = "left" }
    local row, row_w = HorizontalGroup:new{}, 0
    for _i, c in ipairs(ReaderHighlight.highlight_colors) do
        local key, name = c[2], item.NoteItemWidget.colorLabel(c[2])
        local on = (cur_color == key)
        local measured = TextWidget:new{ text = name, face = chip_face, bold = true }
        local widest = measured:getSize().w
        measured:free()
        local label = HorizontalGroup:new{ align = "center",
            atoms.Pill:new{ width = dot, height = dot, border = 0, true_color = true,
                fill = key == "gray" and BlitBuffer.COLOR_GRAY or core.getHighlightColor(key) },
            HorizontalSpan:new{ width = Screen:scaleBySize(6) },
            TextWidget:new{ text = name, face = chip_face, bold = on },
        }
        -- the same space on both sides: dot and name sit in the middle of the chip
        local pad = Screen:scaleBySize(12)
        local chip_w = pad * 2 + dot + Screen:scaleBySize(6) + widest
        local chip = atoms.TapBox:new{
            atoms.Pill:new{
                width = chip_w, height = chip_h,
                label, -- Pill centres its child
                fill = BlitBuffer.COLOR_WHITE,
                border = on and thick or thin,
                border_color = on and BlitBuffer.COLOR_BLACK or LIGHT,
            },
            callback = function()
                if not on then
                    viewer:setHighlightField(note, "color", key, parent)
                    self:rebuild()
                end
            end,
        }
        if row_w > 0 and row_w + chip_gap + chip_w > inner then
            table.insert(rows, row)
            table.insert(rows, VerticalSpan:new{ width = chip_gap })
            row, row_w = HorizontalGroup:new{}, 0
        end
        if row_w > 0 then table.insert(row, HorizontalSpan:new{ width = chip_gap }); row_w = row_w + chip_gap end
        table.insert(row, chip)
        row_w = row_w + chip_w
    end
    if row_w > 0 then table.insert(rows, row) end
    table.insert(group, rows)
    table.insert(group, VerticalSpan:new{ width = gap + Screen:scaleBySize(4) })
    end -- not a bookmark

    -- 6. actions: Go to (twice as wide) and Delete
    local btn_gap = Screen:scaleBySize(10)
    local btn_row = HorizontalGroup:new{}
    local can_open = note.book_path and lfs.attributes(note.book_path, "mode") ~= nil
    local unit = math.floor((inner - btn_gap) / 3)
    if can_open then
        local goto_text = _("Go to highlight")
        if note.bookmark then
            goto_text = page_no and (_("Go to page") .. " " .. tostring(page_no)) or _("Go to bookmark")
        end
        table.insert(btn_row, actionButton(goto_text, function()
            self:onClose()
            UIManager:close(parent)
            viewer:openBookAtNote(note)
        end, true, inner - btn_gap - unit))
        table.insert(btn_row, HorizontalSpan:new{ width = btn_gap })
    end
    table.insert(btn_row, actionButton(_("Delete"), function()
        -- the card opens over the sheet: Cancel goes back to it, Delete closes both
        viewer:confirmDelete(note, parent, function() self:onClose() end)
    end, false, can_open and unit or inner))
    table.insert(group, btn_row)

    -- Bookmarks: step to the previous / next one in the list without closing the sheet
    if note.bookmark and parent and parent.filtered_notes then
        local list, idx = parent.filtered_notes, nil
        for i, n in ipairs(list) do if n == note then idx = i; break end end
        if idx and #list > 1 then
            local function go(i)
                self.note = list[i]
                self:rebuild()
            end
            table.insert(group, VerticalSpan:new{ width = Screen:scaleBySize(12) })
            table.insert(group, LineWidget:new{ dimen = Geom:new{ w = inner, h = Size.line.medium }, background = core.COLORS.line })
            table.insert(group, NotesListWidget.navBar{
                width = inner, label = string.format("%d / %d", idx, #list),
                has_prev = idx > 1, has_next = idx < #list,
                first = function() go(1) end, prev = function() go(idx - 1) end,
                next = function() go(idx + 1) end, last = function() go(#list) end,
            })
        end
    end

    self.sheet = atoms.SheetFrame:new{
        -- Size.border.window: the outline KOReader uses on its own dialogs and buttons
        width = sheet_w, radius = Screen:scaleBySize(14), border = Size.border.window,
        pad_x = P, pad_top = Screen:scaleBySize(18), pad_bottom = Screen:scaleBySize(18), -- same as screen footers
        group,
    }
    local sheet_h = self.sheet:getSize().h
    if self[1] and self[1].free then self[1]:free() end -- release the previous tree on rebuild
    self[1] = BottomContainer:new{
        dimen = Geom:new{ w = W, h = H },
        CenterContainer:new{ dimen = Geom:new{ w = W, h = sheet_h }, self.sheet },
    }
end
function Sheet.AnnotationSheet:rebuild()
    self:build()
    UIManager:setDirty(self, "ui")
end
function Sheet.AnnotationSheet:onTapOutside(_, ges)
    local d = self.sheet and self.sheet.dimen
    if d and ges and ges.pos and ges.pos:intersectWith(d) then return true end
    self:onClose()
    return true
end
function Sheet.AnnotationSheet:onClose()
    UIManager:close(self, "ui", self.sheet and self.sheet.dimen)
    return true
end

function Sheet.bind(deps)
    if deps.NotesListWidget then NotesListWidget = deps.NotesListWidget end
end

return Sheet
