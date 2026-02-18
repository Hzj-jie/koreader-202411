local Device = require("device")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local T = require("ffi/util").template

local page_turns_tap_zones_sub_items = {} -- build the Tap zones submenu
local tap_zones = {
  left_right = gettext("Left / right"),
  top_bottom = gettext("Top / bottom"),
  bottom_top = gettext("Bottom / top"),
}

if
  tap_zones[(G_reader_settings:read("page_turns_tap_zones") or "left_right")]
  == nil
then
  -- Legacy configuration
  G_reader_settings:delete("page_turns_tap_zones")
end

local function genTapZonesMenu(tap_zones_type)
  table.insert(page_turns_tap_zones_sub_items, {
    text = tap_zones[tap_zones_type],
    checked_func = function()
      return (G_reader_settings:read("page_turns_tap_zones") or "left_right")
        == tap_zones_type
    end,
    callback = function()
      G_reader_settings:save(
        "page_turns_tap_zones",
        tap_zones_type,
        "left_right"
      )
      ReaderUI.instance.view:setupTouchZones()
    end,
  })
end
genTapZonesMenu("left_right")
genTapZonesMenu("top_bottom")
genTapZonesMenu("bottom_top")

-- Returns percentage rather than decimal.
local function getForwardTapZone()
  return math.floor(
    (G_reader_settings:read("page_turns_tap_zone_forward_size_ratio") or 0.6)
      * 100
  )
end

table.insert(page_turns_tap_zones_sub_items, {
  text_func = function()
    local forward_zone = getForwardTapZone()
    return T(
      gettext(
        "Backward / forward tap zone size: %1\xE2\x80\xAF% / %2\xE2\x80\xAF%"
      ),
      100 - forward_zone,
      forward_zone
    )
  end,
  keep_menu_open = true,
  callback = function(touchmenu_instance)
    local is_left_right = G_reader_settings:read("page_turns_tap_zones")
      == "left_right"
    local forward_zone = getForwardTapZone()
    UIManager:show(require("ui/widget/spinwidget"):new({
      title_text = is_left_right and gettext("Tap zone width")
        or gettext("Tap zone height"),
      info_text = (
        is_left_right and gettext("Percentage of screen width")
        or gettext("Percentage of screen height")
      )
        .. " "
        -- Need localization
        .. gettext("to move forward.")
        .. "\n"
        .. gettext("Tapping the rest area will move backward."),
      value = forward_zone,
      value_min = 20,
      value_max = 80,
      value_hold_step = 5,
      unit = "%",
      callback = function(new_value)
        G_reader_settings:save(
          "page_turns_tap_zone_forward_size_ratio",
          new_value * (1 / 100),
          0.6
        )
        ReaderUI.instance.view:setupTouchZones()
        if touchmenu_instance then
          touchmenu_instance:updateItems()
        end
      end,
    }))
  end,
})

local PageTurns = {
  text = gettext("Page turns"),
  sub_item_table = {
    {
      text = gettext("With taps"),
      checked_func = function()
        return G_reader_settings:nilOrFalse("page_turns_disable_tap")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("page_turns_disable_tap")
      end,
    },
    {
      text = gettext("With swipes"),
      checked_func = function()
        return G_reader_settings:nilOrFalse("page_turns_disable_swipe")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("page_turns_disable_swipe")
      end,
    },
    {
      text_func = function()
        local tap_zones_type = G_reader_settings:read("page_turns_tap_zones")
          or "left_right"
        return T(gettext("Tap zones: %1"), tap_zones[tap_zones_type]:lower())
      end,
      enabled_func = function()
        return G_reader_settings:nilOrFalse("page_turns_disable_tap")
      end,
      sub_item_table = page_turns_tap_zones_sub_items,
      separator = true,
    },
    {
      text_func = function()
        local text = gettext("Invert page turn taps and swipes")
        if G_reader_settings:isTrue("inverse_reading_order") then
          text = text .. "   ★"
        end
        return text
      end,
      checked_func = function()
        return ReaderUI.instance.view.inverse_reading_order
      end,
      callback = function()
        ReaderUI.instance.view:onToggleReadingOrder()
      end,
      hold_callback = function(touchmenu_instance)
        local inverse_reading_order =
          G_reader_settings:isTrue("inverse_reading_order")
        local MultiConfirmBox = require("ui/widget/multiconfirmbox")
        UIManager:show(MultiConfirmBox:new({
          text = inverse_reading_order
              and gettext(
                "The default (★) for newly opened books is right-to-left (RTL) page turning.\n\nWould you like to change it?"
              )
            or gettext(
              "The default (★) for newly opened books is left-to-right (LTR) page turning.\n\nWould you like to change it?"
            ),
          choice1_text_func = function()
            return inverse_reading_order and gettext("LTR")
              or gettext("LTR (★)")
          end,
          choice1_callback = function()
            G_reader_settings:makeFalse("inverse_reading_order")
            if touchmenu_instance then
              touchmenu_instance:updateItems()
            end
          end,
          choice2_text_func = function()
            return inverse_reading_order and gettext("RTL (★)")
              or gettext("RTL")
          end,
          choice2_callback = function()
            G_reader_settings:makeTrue("inverse_reading_order")
            if touchmenu_instance then
              touchmenu_instance:updateItems()
            end
          end,
        }))
      end,
    },
    {
      text = gettext("Also invert document-related dialogs"),
      checked_func = function()
        return G_reader_settings:isTrue("invert_ui_layout_mirroring")
      end,
      enabled_func = function()
        return ReaderUI.instance.view.inverse_reading_order
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("invert_ui_layout_mirroring")
      end,
      help_text = gettext(
        [[
When enabled the UI direction for the Table of Contents, Book Map, and Page Browser dialogs will follow the page turn direction instead of the default UI direction.]]
      ),
      separator = true,
    },
    Device:canDoSwipeAnimation() and {
      text = gettext("Page turn animations"),
      checked_func = function()
        return G_reader_settings:isTrue("swipe_animations")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("swipe_animations")
      end,
    } or nil, -- must be the last item
  },
}

return PageTurns
