local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local gettext = require("gettext")
local _ = gettext

local Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")

local MathPuzzleScreen = InputContainer:extend({
  plugin = nil,
  mode = nil,
  question_count = 10,
  focused_idx = 1,
  round_correct = 0,
  round_wrong = 0,
})

function MathPuzzleScreen:init()
  local Screen = Device.screen
  self.dimen = Geom:new({
    x = 0,
    y = 0,
    w = Screen:getWidth(),
    h = Screen:getHeight(),
  })
  self.covers_fullscreen = true

  if not self.mode then
    self.mode = Generator.getModeById("add_sub_100")
  end

  if not self.problems then
    self.problems = Generator.generateProblems(self.mode, self.question_count)
  end

  self.start_time = (self.plugin and self.plugin.session_start_time)
    or os.time()
  self.font_face = Font:getFace("cfont")

  self.input_buttons = {}
  self.input_fields = self.input_buttons
  self.mark_widgets = {}
  self.expr_widgets = {}

  self:buildUI()
  self:startTicker()
end

function MathPuzzleScreen:getFormattedTime()
  local start_time = (self.plugin and self.plugin.session_start_time)
    or self.start_time
    or os.time()
  local elapsed = math.max(0, os.time() - start_time)
  local mins = math.floor(elapsed / 60)
  local secs = elapsed % 60
  return string.format("%02d:%02d", mins, secs)
end

function MathPuzzleScreen:getHeaderStatsText()
  local session_correct = (self.plugin and self.plugin.session_correct) or 0
  local session_wrong = (self.plugin and self.plugin.session_wrong) or 0
  local total_attempted = session_correct + session_wrong
  local score_str = "-"
  if total_attempted > 0 then
    local pct = math.floor((session_correct / total_attempted) * 100)
    score_str = string.format("%d%%", pct)
  end
  return string.format(
    _("Correct: %d  ·  Wrong: %d  ·  Score: %s  ·  Time: %s"),
    session_correct,
    session_wrong,
    score_str,
    self:getFormattedTime()
  )
end

function MathPuzzleScreen:startTicker()
  if self._ticker_action then
    return
  end
  self._ticker_action = function()
    if self.title_bar then
      self.title_bar:setSubTitle(self:getHeaderStatsText())
    end
    UIManager:scheduleIn(1, self._ticker_action)
  end
  UIManager:scheduleIn(1, self._ticker_action)
end

function MathPuzzleScreen:stopTicker()
  if self._ticker_action then
    UIManager:unschedule(self._ticker_action)
    self._ticker_action = nil
  end
end

function MathPuzzleScreen:selectField(idx)
  if idx < 1 then
    idx = 1
  elseif idx > #self.problems then
    idx = #self.problems
  end

  local prev_idx = self.focused_idx
  self.focused_idx = idx

  if self.input_buttons[prev_idx] then
    self:updateInputButton(prev_idx)
  end
  if self.input_buttons[idx] then
    self:updateInputButton(idx)
  end

  UIManager:setDirty(self, function()
    return "ui", self.dimen
  end)
end

function MathPuzzleScreen:updateInputButton(idx)
  local btn = self.input_buttons[idx]
  if not btn then
    return
  end
  local prob = self.problems[idx]
  local is_focused = (idx == self.focused_idx)
  local val = prob.user_answer or ""
  local display_text = val ~= "" and val or (is_focused and "_" or " ")

  Button.setText(btn, display_text, btn.width)
  btn.bordersize = is_focused and Size.border.bold or Size.border.thin
  btn.background = is_focused and Blitbuffer.COLOR_LIGHT_GRAY
    or Blitbuffer.COLOR_WHITE
end

function MathPuzzleScreen:inputDigit(digit_char)
  local prob = self.problems[self.focused_idx]
  if not prob then
    return
  end
  local current = prob.user_answer or ""
  if #current < 6 then
    prob.user_answer = current .. digit_char
    self:updateInputButton(self.focused_idx)
    UIManager:setDirty(self, function()
      return "ui", self.dimen
    end)
  end
end

function MathPuzzleScreen:backspace()
  local prob = self.problems[self.focused_idx]
  if not prob then
    return
  end
  local current = prob.user_answer or ""
  if #current > 0 then
    prob.user_answer = current:sub(1, -2)
    self:updateInputButton(self.focused_idx)
    UIManager:setDirty(self, function()
      return "ui", self.dimen
    end)
  end
end

function MathPuzzleScreen:nextField()
  if self.focused_idx < #self.problems then
    self:selectField(self.focused_idx + 1)
  else
    self:checkAnswers()
  end
end

function MathPuzzleScreen:prevField()
  if self.focused_idx > 1 then
    self:selectField(self.focused_idx - 1)
  end
end

function MathPuzzleScreen:onFieldEnter(_)
  self:nextField()
end

function MathPuzzleScreen:onKeyDown(key)
  local key_str = tostring(key)
  if key_str:match("^%d$") then
    self:inputDigit(key_str)
    return true
  elseif key_str == "BackSpace" or key_str == "Delete" then
    self:backspace()
    return true
  elseif key_str == "Return" or key_str == "KP_Enter" then
    self:nextField()
    return true
  elseif key_str == "Tab" then
    self:nextField()
    return true
  elseif key_str == "Up" or key_str == "Left" then
    self:prevField()
    return true
  elseif key_str == "Down" or key_str == "Right" then
    self:nextField()
    return true
  end
  return false
end

function MathPuzzleScreen:buildUI()
  local Screen = Device.screen
  local screen_w = Screen:getWidth()

  self.input_buttons = {}
  self.input_fields = self.input_buttons
  self.mark_widgets = {}
  self.expr_widgets = {}

  self.title_bar = TitleBar:new({
    width = screen_w,
    title = self.mode.title,
    subtitle = self:getHeaderStatsText(),
    fullscreen = true,
    show_parent = self,
    left_icon = "chevron.left",
    left_icon_tap_callback = function()
      self:showModeMenu()
    end,
    close_callback = function()
      UIManager:close(self)
    end,
  })

  local col_gap = Screen:scaleBySize(20)
  local idx_width = Screen:scaleBySize(26)
  local expr_width = Screen:scaleBySize(110)
  local input_width = Screen:scaleBySize(70)
  local mark_width = Screen:scaleBySize(70)
  local row_padding = Screen:scaleBySize(4)

  local half = math.ceil(#self.problems / 2)
  local left_col = VerticalGroup:new({ align = "left" })
  local right_col = VerticalGroup:new({ align = "left" })

  local function buildRow(i)
    local prob = self.problems[i]
    local idx_widget = TextWidget:new({
      text = string.format("%2d.", i),
      face = self.font_face,
      width = idx_width,
      alignment = "right",
    })

    local expr_widget = TextWidget:new({
      text = prob.text,
      face = self.font_face,
      width = expr_width,
      alignment = "right",
    })
    table.insert(self.expr_widgets, expr_widget)

    local is_focused = (i == self.focused_idx)
    local val = prob.user_answer or ""
    local display_text = val ~= "" and val or (is_focused and "_" or " ")

    local input_btn = Button:new({
      text = display_text,
      width = input_width,
      bordersize = is_focused and Size.border.bold or Size.border.thin,
      background = is_focused and Blitbuffer.COLOR_LIGHT_GRAY
        or Blitbuffer.COLOR_WHITE,
      padding_v = Screen:scaleBySize(2),
      padding_h = Screen:scaleBySize(4),
      margin = 0,
      callback = function()
        self:selectField(i)
      end,
    })

    input_btn.getText = function()
      return prob.user_answer or ""
    end
    input_btn.setText = function(_, txt)
      prob.user_answer = tostring(txt)
      self:updateInputButton(i)
    end

    self.input_buttons[i] = input_btn

    local mark_text = ""
    if prob.checked then
      if prob.is_correct then
        mark_text = " ✓"
      else
        mark_text = string.format(" ✗ (%d)", prob.answer)
      end
    end

    local mark_widget = TextWidget:new({
      text = mark_text,
      face = self.font_face,
      width = mark_width,
      alignment = "left",
    })
    self.mark_widgets[i] = mark_widget

    return HorizontalGroup:new({
      idx_widget,
      HorizontalSpan:new({ width = Screen:scaleBySize(4) }),
      expr_widget,
      HorizontalSpan:new({ width = Screen:scaleBySize(6) }),
      input_btn,
      HorizontalSpan:new({ width = Screen:scaleBySize(6) }),
      mark_widget,
    })
  end

  for i = 1, half do
    table.insert(left_col, buildRow(i))
    if i < half then
      table.insert(left_col, VerticalSpan:new({ height = row_padding }))
    end
  end

  for i = half + 1, #self.problems do
    table.insert(right_col, buildRow(i))
    if i < #self.problems then
      table.insert(right_col, VerticalSpan:new({ height = row_padding }))
    end
  end

  local columns_group = HorizontalGroup:new({
    align = "top",
    left_col,
    HorizontalSpan:new({ width = col_gap }),
    right_col,
  })

  local keypad_width = math.min(screen_w, Screen:scaleBySize(580))
  local keypad_table = ButtonTable:new({
    width = keypad_width,
    buttons = {
      {
        {
          text = "1",
          callback = function()
            self:inputDigit("1")
          end,
        },
        {
          text = "2",
          callback = function()
            self:inputDigit("2")
          end,
        },
        {
          text = "3",
          callback = function()
            self:inputDigit("3")
          end,
        },
        {
          text = "4",
          callback = function()
            self:inputDigit("4")
          end,
        },
        {
          text = "5",
          callback = function()
            self:inputDigit("5")
          end,
        },
        {
          text = "⌫",
          callback = function()
            self:backspace()
          end,
        },
      },
      {
        {
          text = "6",
          callback = function()
            self:inputDigit("6")
          end,
        },
        {
          text = "7",
          callback = function()
            self:inputDigit("7")
          end,
        },
        {
          text = "8",
          callback = function()
            self:inputDigit("8")
          end,
        },
        {
          text = "9",
          callback = function()
            self:inputDigit("9")
          end,
        },
        {
          text = "0",
          callback = function()
            self:inputDigit("0")
          end,
        },
        {
          text = _("Next ❯"),
          callback = function()
            self:nextField()
          end,
        },
      },
      {
        {
          text = _("Check"),
          callback = function()
            self:checkAnswers()
          end,
        },
        {
          text = _("New"),
          callback = function()
            self:generateNewProblems()
          end,
        },
        {
          text = _("Modes"),
          callback = function()
            self:showModeMenu()
          end,
        },
        {
          text = _("Close"),
          callback = function()
            UIManager:close(self)
          end,
        },
      },
    },
  })

  local main_layout = VerticalGroup:new({
    align = "center",
    self.title_bar,
    VerticalSpan:new({ height = Screen:scaleBySize(12) }),
    columns_group,
    VerticalSpan:new({ height = Screen:scaleBySize(16) }),
    keypad_table,
    VerticalSpan:new({ height = Screen:scaleBySize(12) }),
  })

  self[1] = main_layout
end

function MathPuzzleScreen:checkAnswers()
  local result = Generator.checkAnswers(self.problems)

  for i, prob in ipairs(self.problems) do
    if prob.is_correct then
      self.mark_widgets[i]:setText(" ✓")
    else
      self.mark_widgets[i]:setText(string.format(" ✗ (%d)", prob.answer))
    end
  end

  if self.plugin then
    local prev_correct = self.round_correct or 0
    local prev_wrong = self.round_wrong or 0
    self.round_correct = result.correct_count
    self.round_wrong = result.total - result.correct_count

    self.plugin.session_correct = (self.plugin.session_correct or 0)
      - prev_correct
      + self.round_correct
    self.plugin.session_wrong = (self.plugin.session_wrong or 0)
      - prev_wrong
      + self.round_wrong
  end

  if self.title_bar then
    self.title_bar:setSubTitle(self:getHeaderStatsText())
  end

  UIManager:setDirty(self, function()
    return "ui", self.dimen
  end)
end

function MathPuzzleScreen:generateNewProblems()
  self.round_correct = 0
  self.round_wrong = 0
  self.problems = Generator.generateProblems(self.mode, self.question_count)
  self.focused_idx = 1
  self:buildUI()

  UIManager:setDirty(self, function()
    return "ui", self.dimen
  end)
end

function MathPuzzleScreen:setMode(mode)
  self.mode = mode
  self.round_correct = 0
  self.round_wrong = 0
  self.problems = Generator.generateProblems(self.mode, self.question_count)
  self.focused_idx = 1
  self:buildUI()

  UIManager:setDirty(self, function()
    return "ui", self.dimen
  end)
end

function MathPuzzleScreen:showModeMenu()
  if self.plugin and self.plugin.showModeSelection then
    self.plugin:showModeSelection(self)
  end
end

function MathPuzzleScreen:onClose()
  self:onExit()
  if self.plugin then
    self.plugin.screen = nil
  end
end

function MathPuzzleScreen:onExit()
  self:stopTicker()
end

return MathPuzzleScreen
