--[[--
A customizable number picker.

Example:
    local NumberPickerWidget = require("ui/widget/numberpickerwidget")
    local numberpicker = NumberPickerWidget:new{
        -- for floating point (decimals), use something like "%.2f"
        precision = "%02d",
        value = 0,
        value_min = 0,
        value_max = 23,
        value_step = 1,
        value_hold_step = 4,
        wrap = true,
    }
--]]

local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local NumberPickerWidget = FocusManager:extend({
  spinner_face = Font:getFace("smalltfont"),
  precision = "%02d",
  width = nil,
  height = nil,
  value = 0,
  value_min = 0,
  value_max = 23,
  value_step = 1,
  value_hold_step = 4,
  value_table = nil,
  value_index = nil,
  wrap = true,
  -- in case we need calculate number of days in a given month and year
  date_month = nil,
  date_year = nil,
  -- on update signal to the caller and pass updated value
  picker_updated_callback = nil,
  unit = "",
})

function NumberPickerWidget:init()
  self.screen_width = Screen:getWidth()
  self.screen_height = Screen:getHeight()
  self.width = self.width
    or math.floor(math.min(self.screen_width, self.screen_height) * 0.2)
  if self.value_table then
    self.value_index = self.value_index or 1
    self.value = self.value_table[self.value_index]
  end
  self.layout = {}

  -- Widget layout
  local bordersize = Size.border.default
  local margin = Size.margin.default
  local button_up = Button:new({
    text = "▲",
    bordersize = bordersize,
    margin = margin,
    radius = 0,
    text_font_size = 24,
    width = self.width,
    show_parent = self.show_parent,
    callback = function()
      if self.date_month and self.date_year then
        self.value_max = self:getDaysInMonth(
          self.date_month:getValue(),
          self.date_year:getValue()
        )
      end
      self.value = self:changeValue(
        self.value,
        self.value_step,
        self.value_max,
        self.value_min,
        self.wrap
      )
      self:update()
    end,
    hold_callback = function()
      if self.date_month and self.date_year then
        self.value_max = self:getDaysInMonth(
          self.date_month:getValue(),
          self.date_year:getValue()
        )
      end
      self.value = self:changeValue(
        self.value,
        self.value_hold_step,
        self.value_max,
        self.value_min,
        self.wrap
      )
      self:update()
    end,
  })
  table.insert(self.layout, { button_up })
  local button_down = Button:new({
    text = "▼",
    bordersize = bordersize,
    margin = margin,
    radius = 0,
    text_font_size = 24,
    width = self.width,
    show_parent = self.show_parent,
    callback = function()
      if self.date_month and self.date_year then
        self.value_max = self:getDaysInMonth(
          self.date_month:getValue(),
          self.date_year:getValue()
        )
      end
      self.value = self:changeValue(
        self.value,
        self.value_step * -1,
        self.value_max,
        self.value_min,
        self.wrap
      )
      self:update()
    end,
    hold_callback = function()
      if self.date_month and self.date_year then
        self.value_max = self:getDaysInMonth(
          self.date_month:getValue(),
          self.date_year:getValue()
        )
      end
      self.value = self:changeValue(
        self.value,
        self.value_hold_step * -1,
        self.value_max,
        self.value_min,
        self.wrap
      )
      self:update()
    end,
  })
  table.insert(self.layout, { button_down })

  local empty_space = VerticalSpan:new({ width = Size.padding.large })

  self.formatted_value = self.value
  if not self.value_table then
    self.formatted_value = string.format(self.precision, self.formatted_value)
  end

  local input_dialog
  local callback_input = nil
  if self.value_table == nil then
    callback_input = function()
      if self.date_month and self.date_year then
        self.value_max = self:getDaysInMonth(
          self.date_month:getValue(),
          self.date_year:getValue()
        )
      end
      input_dialog = InputDialog:new({
        title = _("Enter number"),
        input_hint = T(
          "%1 (%2 - %3)",
          self.formatted_value,
          self.value_min,
          self.value_max
        ),
        input_type = "number",
        buttons = {
          {
            {
              text = _("Cancel"),
              id = "close",
              callback = function()
                UIManager:close(input_dialog)
              end,
            },
            {
              text = _("OK"),
              is_enter_default = true,
              callback = function()
                local input_text = input_dialog:getInputText()
                local input_value = tonumber(input_text)
                local turn_off_checks = false

                -- if the first character of the input string is ":" turn off min-max checks
                if
                  input_text:match("^:")
                  and G_reader_settings:isTrue("debug_verbose")
                then
                  turn_off_checks = true -- turn off checks
                  input_text = input_text:gsub("^:", "") -- shorten input
                  input_value = tonumber(input_text) -- try to get value
                end

                -- if the input text starts with `=`, try to evaluate the expression
                -- only allow `math.*` and no other functions to be safe here.
                if input_text:match("^=") then
                  local function evaluate_string(code)
                    -- only execute if there are no chars (except math.xxx) and no {[]} in the user input
                    local check_code = code:gsub("math%.%a*", "")
                    if check_code:find("[%a%[%]%{%}]") then
                      return nil
                    end
                    code = code:gsub("^=", "return ")
                    local env = { math = math } -- restrict to only math functions
                    local func, dummy = load(code, "user_sandbox", nil, env)
                    if func then
                      return pcall(func)
                    end
                  end
                  local dummy
                  dummy, input_value = evaluate_string(input_text)
                  input_value = dummy and tonumber(input_value)
                end

                if turn_off_checks then
                  if not input_value then
                    return
                  end
                  if
                    input_value < self.value_min
                    or input_value > self.value_max
                  then
                    UIManager:show(InfoMessage:new({
                      text = T(
                        _(
                          "ATTENTION:\nPrefixing the input with ':' disables sanity checks!\nThis value should be in the range of %1 - %2.\nUndefined behavior may occur."
                        ),
                        self.value_min,
                        self.value_max
                      ),
                    }))
                  end
                  self.value = input_value
                  self:update()
                  UIManager:close(input_dialog)
                  return
                end

                if
                  input_value
                  and input_value >= self.value_min
                  and input_value <= self.value_max
                then
                  self.value = input_value
                  self:update()
                  UIManager:close(input_dialog)
                elseif input_value and input_value < self.value_min then
                  UIManager:show(InfoMessage:new({
                    text = T(
                      _("This value should be %1 or more."),
                      self.value_min
                    ),
                    timeout = 2,
                  }))
                elseif input_value and input_value > self.value_max then
                  UIManager:show(InfoMessage:new({
                    text = T(
                      _("This value should be %1 or less."),
                      self.value_max
                    ),
                    timeout = 2,
                  }))
                else
                  UIManager:show(InfoMessage:new({
                    text = _("Invalid value. Please enter a valid value."),
                    timeout = 2,
                  }))
                end
              end,
            },
          },
        },
      })
      UIManager:show(input_dialog)
      input_dialog:onShowKeyboard()
    end
  end

  local unit = ""
  if self.unit then
    if self.unit == "°" then
      unit = self.unit
    elseif self.unit ~= "" then
      unit = "\u{202F}" .. self.unit -- use Narrow No-Break Space (NNBSP) here
    end
  end
  self.text_value = Button:new({
    text = tostring(self.formatted_value) .. unit,
    bordersize = 0,
    padding = 0,
    text_font_face = self.spinner_face.font,
    text_font_size = self.spinner_face.orig_size,
    width = self.width,
    show_parent = self.show_parent,
    callback = callback_input,
  })
  if callback_input then
    table.insert(self.layout, 2, { self.text_value })
  end

  local widget_spinner = VerticalGroup:new({
    align = "center",
    button_up,
    empty_space,
    self.text_value,
    empty_space,
    button_down,
  })

  self.frame = FrameContainer:new({
    bordersize = 0,
    padding = Size.padding.default,
    CenterContainer:new({
      align = "center",
      dimen = Geom:new({
        w = widget_spinner:getSize().w,
        h = widget_spinner:getSize().h,
      }),
      widget_spinner,
    }),
  })
  self.dimen = self.frame:getSize()
  self[1] = self.frame
  self:refocusWidget()
  UIManager:setDirty(self.show_parent, function()
    return "ui", self.dimen
  end)
end

--[[--
Update.
--]]
function NumberPickerWidget:update()
  self.formatted_value = self.value
  if not self.value_table then
    self.formatted_value = string.format(self.precision, self.formatted_value)
  end

  self.text_value:setText(tostring(self.formatted_value), self.width)

  self:refocusWidget()
  UIManager:setDirty(self.show_parent, function()
    return "ui", self.dimen
  end)
  if self.picker_updated_callback then
    self.picker_updated_callback(self.value, self.value_index)
  end
end

--[[--
Change value.
--]]
function NumberPickerWidget:changeValue(value, step, max, min, wrap)
  if self.value_index then
    self.value_index = self.value_index + step
    if self.value_index > #self.value_table then
      self.value_index = wrap and 1 or #self.value_table
    elseif self.value_index < 1 then
      self.value_index = wrap and #self.value_table or 1
    end
    value = self.value_table[self.value_index]
  else
    value = value + step
    if value > max then
      value = wrap and min or max
    elseif value < min then
      value = wrap and max or min
    end
  end
  return value
end

--[[--
Get days in month.
--]]
function NumberPickerWidget:getDaysInMonth(month, year)
  local days_in_month = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  local days = days_in_month[month]
  -- check for leap year
  if month == 2 then
    if year % 4 == 0 then
      if year % 100 == 0 then
        if year % 400 == 0 then
          days = 29
        end
      else
        days = 29
      end
    end
  end
  return days
end

--[[--
Get value.
--]]
function NumberPickerWidget:getValue()
  return self.value, self.value_index
end

return NumberPickerWidget
