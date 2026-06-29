--[[
User patch: Skim widget — location history instead of bookmark jumps
===================================================================

Repurposes the three "bookmark" buttons in the Skim dialog
(frontend/ui/widget/skimtowidget.lua) so that a TAP navigates the
location history, while a LONG-PRESS keeps the original bookmark action:

    button            tap (new)                       long-press
    ---------------   -----------------------------   -----------------------
    prev-bookmark  →  Previous location  (↺ U+21BA)   Previous bookmark
    bookmark-toggle→  Add current page to history(⊕)  see below (mode-dependent)
    next-bookmark  →  Next location      (↻ U+21BB)   Next bookmark

The Previous/Next location buttons are greyed out and ignore taps when
there is nothing to go back / forward to (empty location stack), but
their LONG-PRESS (previous/next bookmark) still works while greyed.

In BOTH layouts, long-pressing the page-number (centre) button opens a
page-overview widget (Book Map or Page Browser; see USER CONFIG). Getting
back to the page Skim was opened from is done via the Previous-location
button / location history.

The remaining long-press behaviour differs by layout, so that nothing is lost:

  FULL (centred) mode:
    add-to-history long-press → Bookmark current page

  COMPACT (top/bottom) mode:
    The "return to opening page" button (which showed a ↺ that would clash
    with the new Previous-location ↺) becomes a dedicated bookmark button:
        tap        → Bookmark current page
        long-press → Open bookmarks
    add-to-history long-press → Back to the page Skim was opened from

The location history used here is KOReader's normal back/forward stack
(ReaderLink), so these buttons integrate with the existing
swipe-back / go-back-link behaviour.

This patch replaces SkimToWidget:init and SkimToWidget:update wholesale,
so it is tied to the KOReader version it was written against
(v2026.03). If the Skim widget changes in a future update, refresh this
patch from the new skimtowidget.lua.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Math = require("optmath")
local MovableContainer = require("ui/widget/container/movablecontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local Screen = Device.screen

local SkimToWidget = require("ui/widget/skimtowidget")

-- ============================================================================
-- USER CONFIGURATION
-- ----------------------------------------------------------------------------
-- Long-pressing the page-number (centre) button opens a page-overview
-- widget (in both full and compact modes). Choose which one here:
--     "bookmap"     -> Book Map
--     "pagebrowser" -> Page Browser (thumbnail grid)
-- To switch, change the value below to the other string. This is the ONLY
-- line you need to edit for that option.
local PAGE_LONGPRESS_ACTION = "bookmap"
-- ============================================================================

function SkimToWidget:init()
    if self.ui.paging then -- "page" view
        self.ui.paging:enterSkimMode()
    end

    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapProgress = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0, y = 0,
                    w = screen_width,
                    h = screen_height,
                }
            },
        }
    end

    -- nil for default center full mode; "top" and "bottom" for compact mode
    local skim_dialog_position = G_reader_settings:readSetting("skim_dialog_position")
    local full_mode = not skim_dialog_position

    local frame_border_size = Size.border.window
    local button_span_unit_width = Size.span.horizontal_small
    local button_font_size, button_height, frame_padding, frame_width, inner_width, nb_buttons, larger_span_units, progress_bar_height
    if full_mode then
        button_font_size = nil -- use default
        button_height = nil
        frame_padding = Size.padding.fullscreen -- large padding for airy feeling
        frame_width = math.floor(math.min(screen_width, screen_height) * 0.95)
        inner_width = frame_width - 2 * (frame_border_size + frame_padding)
        nb_buttons = 5 -- with the middle one separated a bit more from the others
        larger_span_units = 3 -- 3 x small span width
        progress_bar_height = Size.item.height_big
    else
        button_font_size = 16
        button_height = Screen:scaleBySize(32)
        frame_padding = Size.padding.default
        frame_width = screen_width + 2 * frame_border_size -- hide side borders
        inner_width = frame_width - 2 * frame_padding
        nb_buttons = 11 -- in equal distances
        larger_span_units = 1
        progress_bar_height = Screen:scaleBySize(36)
    end
    local nb_span_units = (nb_buttons - 1) - 2 + 2 * larger_span_units
    local button_width = math.floor((inner_width - nb_span_units * button_span_unit_width) * (1 / nb_buttons))
    -- Update inner_width (possibly smaller because of math.floor())
    inner_width = nb_buttons * button_width + nb_span_units * button_span_unit_width

    self.curr_page = self.ui:getCurrentPage()
    self.page_count = self.ui.document:getPageCount()

    -- Determine if we need to invert the button functionality and labels
    local invert_buttons = self.ui.view:shouldInvertBiDiLayoutMirroring()

    self.progress_bar = ProgressWidget:new{
        width = inner_width,
        height = progress_bar_height,
        percentage = self.curr_page / self.page_count,
        ticks = self.ui.toc:getTocTicksFlattened(),
        tick_width = Size.line.medium,
        last = self.page_count,
        alt = self.ui.document.flows,
        initial_pos_marker = true,
        invert_direction = invert_buttons,
    }

    -- Bottom row buttons
    local button_minus = Button:new{
        text = "-1",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 1)
        end,
    }
    local button_minus_ten = Button:new{
        text = "-10",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page - 10)
        end,
    }
    local button_plus = Button:new{
        text = "+1",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 1)
        end,
    }
    local button_plus_ten = Button:new{
        text = "+10",
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            self:goToPage(self.curr_page + 10)
        end,
    }
    self.current_page_text = Button:new{
        text_func = function()
            if self.ui.pagemap and self.ui.pagemap:wantsPageLabels() then
                return self.ui.pagemap:getCurrentPageLabel(true)
            end
            return tostring(self.curr_page)
        end,
        text_font_size = button_font_size,
        radius = 0,
        padding = 0,
        bordersize = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self.callback_switch_to_goto()
        end,
        hold_callback = function()
            -- Both modes: open the configured page-overview widget.
            -- (Back to the opening page is still reachable via the
            -- Previous-location button / location history.)
            self:showPageOverview()
        end,
    }

    -- Icons (see header). Plain Unicode circular arrows for prev/next
    -- location (resolved from the regular UI font), FontAwesome plus-circle
    -- from the bundled nerdfont for "add to history", and the FontAwesome
    -- bookmark glyphs for the compact-mode bookmark button.
    local bookmark_enabled_text = "\u{F02E}" -- filled bookmark
    local bookmark_disabled_text = "\u{F097}" -- empty bookmark

    -- In COMPACT mode this button (formerly "return to opening page") becomes
    -- a dedicated bookmark toggle. In full mode it is created but not shown.
    self.button_orig_page = Button:new{
        text_func = function()
            return self.ui.view.dogear_visible and bookmark_enabled_text or bookmark_disabled_text
        end,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self.ui:handleEvent(Event:new("ToggleBookmark"))
            self:update()
        end,
        hold_callback = function()
            self.ui:handleEvent(Event:new("ShowBookmark"))
            UIManager:close(self)
        end,
    }
    local button_orig_page = self.button_orig_page

    -- Top row buttons
    local chapter_prev_text = "\u{2595}\u{25C1}\u{2002}" -- ▕◁ (right one eighth block, white left-pointing triangle, en space)
    local chapter_next_text = "\u{2002}\u{25B7}\u{258F}" -- ▷▏ (en space, white right-pointing triangle, left one eighth block)
    local location_prev_text = "\u{21BA}" -- ↺ Anticlockwise Open Circle Arrow = previous location
    local location_next_text = "\u{21BB}" -- ↻ Clockwise Open Circle Arrow = next location
    local add_history_text = "\u{F055}" -- plus-circle = add current page to location history
    if BD.mirroredUILayout() then
        chapter_prev_text = BD.ltr(chapter_next_text)
        -- (We need this trick to keep BiDi from reordering chapter_next_text's leading space in RTL)
        chapter_next_text = "\u{2002}" .. BD.ltr("\u{2595}\u{25C1}")
    end
    if invert_buttons then
        chapter_next_text, chapter_prev_text = chapter_prev_text, chapter_next_text
        location_next_text, location_prev_text = location_prev_text, location_next_text
    end
    local button_chapter_next = Button:new{
        text = chapter_next_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getNextChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(self.page_count)
        end,
    }
    local button_chapter_prev = Button:new{
        text = chapter_prev_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        callback = function()
            local page = self.ui.toc:getPreviousChapter(self.curr_page)
            if page and page >= 1 and page <= self.page_count then
                self:goToPage(page)
            end
        end,
        hold_callback = function()
            self:goToPage(1)
        end,
    }
    -- Former "next bookmark" button: tap = next location, long-press = next bookmark.
    -- Greyed out (tap disabled) when the forward location stack is empty;
    -- allow_hold_when_disabled keeps the "next bookmark" long-press working.
    local button_bookmark_next = Button:new{
        text = location_next_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        enabled_func = function()
            local stack = self.ui.link.forward_location_stack
            return stack ~= nil and #stack > 0
        end,
        allow_hold_when_disabled = true,
        callback = function()
            self:goToNextLocation()
        end,
        hold_callback = function()
            self:goToByEvent("GotoNextBookmarkFromPage")
        end,
    }
    -- Former "previous bookmark" button: tap = previous location, long-press = previous bookmark.
    -- Greyed out (tap disabled) when the back location stack is empty;
    -- allow_hold_when_disabled keeps the "previous bookmark" long-press working.
    local button_bookmark_prev = Button:new{
        text = location_prev_text,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        vsync = true,
        enabled_func = function()
            local stack = self.ui.link.location_stack
            return stack ~= nil and #stack > 0
        end,
        allow_hold_when_disabled = true,
        callback = function()
            self:goToPrevLocation()
        end,
        hold_callback = function()
            self:goToByEvent("GotoPreviousBookmarkFromPage")
        end,
    }
    -- Former "bookmark toggle" button: tap = add current page to history, long-press = bookmark current page
    self.button_bookmark_toggle = Button:new{
        text_func = function()
            return add_history_text
        end,
        text_font_size = button_font_size,
        radius = 0,
        width = button_width,
        height = button_height,
        show_parent = self,
        callback = function()
            self:addCurrentLocationToHistory()
        end,
        hold_callback = function()
            if full_mode then
                -- Full mode: bookmark current page (no dedicated bookmark button here)
                self.ui:handleEvent(Event:new("ToggleBookmark"))
                self:update()
            else
                -- Compact mode: back to the page Skim was opened from
                -- (bookmarking is handled by the dedicated bookmark button)
                self:goToOrigPage()
            end
        end,
    }

    local small_button_span = HorizontalSpan:new{ width = button_span_unit_width }
    local large_button_span = HorizontalSpan:new{ width = button_span_unit_width * larger_span_units }
    local top_row_span, bottom_row_span, top_buttons_row, bottom_buttons_row, radius
    if full_mode then
        top_row_span = VerticalSpan:new{ width = Size.padding.fullscreen }
        bottom_row_span = top_row_span
        top_buttons_row = HorizontalGroup:new{
            align = "center",
            button_chapter_prev,
            small_button_span,
            button_bookmark_prev,
            large_button_span,
            self.button_bookmark_toggle,
            large_button_span,
            button_bookmark_next,
            small_button_span,
            button_chapter_next,
        }
        bottom_buttons_row = HorizontalGroup:new{
            align = "center",
            button_minus_ten,
            small_button_span,
            button_minus,
            large_button_span,
            self.current_page_text,
            large_button_span,
            button_plus,
            small_button_span,
            button_plus_ten,
        }
        radius = Size.radius.window
        if invert_buttons then
            util.arrayReverse(top_buttons_row)
            util.arrayReverse(bottom_buttons_row)
        end
    else
        top_row_span = VerticalSpan:new{ width = Size.padding.default }
        top_buttons_row = HorizontalGroup:new{
            align = "center",
            button_chapter_prev,
            small_button_span,
            button_chapter_next,
            small_button_span,
            button_bookmark_prev,
            small_button_span,
            button_bookmark_next,
            small_button_span,
            self.button_bookmark_toggle,
            small_button_span,
            self.current_page_text,
            small_button_span,
            button_orig_page,
            small_button_span,
            button_minus_ten,
            small_button_span,
            button_plus_ten,
            small_button_span,
            button_minus,
            small_button_span,
            button_plus,
        }
        if invert_buttons then
            util.arrayReverse(top_buttons_row)
        end
        if skim_dialog_position == "top" then
            bottom_row_span, bottom_buttons_row = top_row_span, top_buttons_row
            top_buttons_row = VerticalSpan:new{ width = 0 }
            top_row_span = top_buttons_row
        end
    end

    self.skimto_frame = FrameContainer:new{
        margin = 0,
        bordersize = frame_border_size,
        padding = frame_padding,
        radius = radius,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            top_buttons_row,
            top_row_span,
            self.progress_bar,
            bottom_row_span,
            bottom_buttons_row,
        }
    }
    self.movable = MovableContainer:new{
        self.skimto_frame,
    }
    self[1] = WidgetContainer:new{
        align = skim_dialog_position or "center",
        dimen = Geom:new{
            x = 0, y = 0,
            w = screen_width,
            h = screen_height,
        },
        self.movable,
    }

    if Device:hasDPad() then
        if full_mode then
            self.layout = {
                { button_chapter_prev, button_bookmark_prev, self.button_bookmark_toggle, button_bookmark_next, button_chapter_next },
                { button_minus_ten, button_minus, self.current_page_text, button_plus, button_plus_ten },
            }
        else
            self.layout = {
                { button_chapter_prev, button_chapter_next, button_bookmark_prev, button_bookmark_next, self.button_bookmark_toggle,
                  self.current_page_text, button_orig_page, button_minus_ten, button_plus_ten, button_minus, button_plus },
            }
        end
        -- Invert D-Pad navigation layout to match visual button order
        if invert_buttons then
            if full_mode then
                util.arrayReverse(self.layout[1])
                util.arrayReverse(self.layout[2])
            else
                util.arrayReverse(self.layout[1])
            end
        end
        self:moveFocusTo(1, 1)
    end
    if Device:hasKeyboard() then
        self.key_events.QKey = { { "Q" }, event = "FirstRowKeyPress", args =    0 }
        self.key_events.WKey = { { "W" }, event = "FirstRowKeyPress", args = 0.11 }
        self.key_events.EKey = { { "E" }, event = "FirstRowKeyPress", args = 0.22 }
        self.key_events.RKey = { { "R" }, event = "FirstRowKeyPress", args = 0.33 }
        self.key_events.TKey = { { "T" }, event = "FirstRowKeyPress", args = 0.44 }
        self.key_events.YKey = { { "Y" }, event = "FirstRowKeyPress", args = 0.55 }
        self.key_events.UKey = { { "U" }, event = "FirstRowKeyPress", args = 0.66 }
        self.key_events.IKey = { { "I" }, event = "FirstRowKeyPress", args = 0.77 }
        self.key_events.OKey = { { "O" }, event = "FirstRowKeyPress", args = 0.88 }
        self.key_events.PKey = { { "P" }, event = "FirstRowKeyPress", args =    1 }
    end
end

function SkimToWidget:update()
    if self.curr_page <= 0 then
        self.curr_page = 1
    end
    if self.curr_page > self.page_count then
        self.curr_page = self.page_count
    end
    self.progress_bar.percentage = self.curr_page / self.page_count
    self.current_page_text:setText(self.current_page_text:text_func(), self.current_page_text.width)
    self.button_bookmark_toggle:setText(self.button_bookmark_toggle:text_func(), self.button_bookmark_toggle.width)
    -- Keep the compact-mode bookmark button's filled/empty icon in sync
    if self.button_orig_page then
        self.button_orig_page:setText(self.button_orig_page:text_func(), self.button_orig_page.width)
    end
    -- Repaint the frame so the Previous/Next location buttons re-evaluate their
    -- enabled_func (grey state) even when no navigation event triggers a redraw
    -- (e.g. after "add current page to history").
    if self.skimto_frame.dimen then
        UIManager:setDirty(self, function()
            return "ui", self.skimto_frame.dimen
        end)
    end
    self:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK)
end

-- New: navigate the location history (KOReader's back/forward link stack).
-- onGoBackLink() already pushes the current location onto the forward stack
-- when it differs, so we don't add the origin ourselves here.
function SkimToWidget:goToPrevLocation()
    self.ui.link:onGoBackLink(true) -- show "Location history is empty." if nothing to go back to
    self.curr_page = self.ui:getCurrentPage()
    self:update()
end

function SkimToWidget:goToNextLocation()
    self.ui.link:onGoForwardLink()
    self.curr_page = self.ui:getCurrentPage()
    self:update()
end

function SkimToWidget:addCurrentLocationToHistory()
    -- adds the current location and shows a confirmation notification
    self.ui.link:onAddCurrentLocationToStack(true)
    -- refresh so the Previous/Next location buttons update their grey state
    -- (the back stack just grew and the forward stack was cleared)
    self:update()
end

-- Long-press on the page-number button opens a page-overview widget (both
-- modes). Which one is controlled by PAGE_LONGPRESS_ACTION at the top of this
-- file. The Skim dialog is closed afterwards so the overview takes over.
function SkimToWidget:showPageOverview()
    if PAGE_LONGPRESS_ACTION == "pagebrowser" then
        self.ui:handleEvent(Event:new("ShowPageBrowser"))
    else
        self.ui:handleEvent(Event:new("ShowBookMap"))
    end
    UIManager:close(self)
end
