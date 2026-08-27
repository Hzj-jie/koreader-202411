local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
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
local N_ = gettext.ngettext
local T = require("ffi/util").template

local Screen = Device.screen

local Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")

local MathPuzzleScreen = InputContainer:extend({
  name = "mathpuzzle_screen",
  modal = true,
  plugin = nil,
  mode = nil,
  question_count = nil,
  focused_idx = 1,
  round_correct = 0,
  round_wrong = 0,
  is_checked = false,
})

function MathPuzzleScreen:init()
  assert(self.plugin, "MathPuzzleScreen requires a plugin instance")

  self.dimen = Geom:new({
    x = 0,
    y = 0,
    w = Screen:getWidth(),
    h = Screen:getHeight(),
  })

  self.is_checked = false

  if Device:hasKeys() then
    self.key_events.Back = { { Device.input.group.Back } }
  end

  if not self.mode then
    self.mode = Generator.getModeById("add_sub_100")
  end
  self.question_count = self.question_count
    or (self.mode and self.mode.question_count)
    or 10

  if not self.problems then
    self.problems = Generator.generateProblems(self.mode, self.question_count)
  end

  if not self.plugin.session_start_time then
    self.plugin.session_start_time = os.time()
  end

  self:_buildUI()
end

function MathPuzzleScreen:getHeaderStatsText()
  local session_correct = self.plugin.session_correct or 0
  local session_wrong = self.plugin.session_wrong or 0
  local total_attempted = session_correct + session_wrong
  local score_str = "-"
  if total_attempted > 0 then
    local pct = math.floor((session_correct / total_attempted) * 100)
    score_str = string.format("%d%%", pct)
  end
  return string.format(
    _("Correct: %d  ·  Wrong: %d  ·  Score: %s"),
    session_correct,
    session_wrong,
    score_str
  )
end

function MathPuzzleScreen:getTimeText()
  local start_time = self.plugin.session_start_time or os.time()
  local mins = math.floor(math.max(0, os.time() - start_time) / 60)
  return string.format(
    _("Time: %s"),
    T(N_("%1 minute", "%1 minutes", mins), mins)
  )
end

function MathPuzzleScreen:onTimesChange_1M()
  if self.time_widget and self.time_container then
    self.time_widget:setText(self:getTimeText())
    self.time_container:scheduleRepaint()
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
    self:_updateInputButton(prev_idx)
  end
  if self.input_buttons[idx] then
    self:_updateInputButton(idx)
  end
end

function MathPuzzleScreen:_updateInputButton(idx)
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
  if btn.frame then
    btn.frame.bordersize = btn.bordersize
    btn.frame.background = btn.background
  end
  btn:scheduleRepaint()
end

function MathPuzzleScreen:inputDigit(digit_char)
  if
    not self.focused_idx
    or self.focused_idx < 1
    or self.focused_idx > #self.problems
  then
    self.focused_idx = 1
  end
  local prob = self.problems[self.focused_idx]
  if not prob then
    return
  end
  local current = prob.user_answer or ""
  if #current < 6 then
    prob.user_answer = current .. digit_char
    self:_updateInputButton(self.focused_idx)
  end
end

function MathPuzzleScreen:backspace()
  if
    not self.focused_idx
    or self.focused_idx < 1
    or self.focused_idx > #self.problems
  then
    self.focused_idx = 1
  end
  local prob = self.problems[self.focused_idx]
  if not prob then
    return
  end
  local current = prob.user_answer or ""
  if #current > 0 then
    prob.user_answer = current:sub(1, -2)
    self:_updateInputButton(self.focused_idx)
  end
end

function MathPuzzleScreen:nextField()
  if not self.focused_idx or self.focused_idx < 1 then
    self:selectField(1)
  elseif self.focused_idx < #self.problems then
    self:selectField(self.focused_idx + 1)
  else
    self:selectField(1)
  end
end

function MathPuzzleScreen:prevField()
  if not self.focused_idx or self.focused_idx <= 1 then
    self:selectField(#self.problems)
  else
    self:selectField(self.focused_idx - 1)
  end
end

function MathPuzzleScreen:onFieldEnter(_)
  self:nextField()
end

function MathPuzzleScreen:_handleKey(key)
  local key_str
  if type(key) == "table" then
    key_str = key.key or key.symbol or tostring(key)
  else
    key_str = tostring(key)
  end

  if not key_str then
    return false
  end

  if key_str:match("^[0-9/]$") then
    self:inputDigit(key_str)
    return true
  elseif key_str == "BackSpace" or key_str == "Delete" then
    self:backspace()
    return true
  elseif key_str == "Return" or key_str == "KP_Enter" or key_str == "Enter" then
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
  elseif key_str == "Escape" or key_str == "Close" or key_str == "Back" then
    UIManager:close(self)
    return true
  end
  return false
end

function MathPuzzleScreen:onKeyPress(key)
  if self:_handleKey(key) then
    return true
  end
  return InputContainer.onKeyPress(self, key)
end

function MathPuzzleScreen:onKeyRepeat(key)
  if self:_handleKey(key) then
    return true
  end
  return InputContainer.onKeyRepeat(self, key)
end

function MathPuzzleScreen:onTextInput(text)
  if type(text) == "string" and text:match("^[0-9/]$") then
    self:inputDigit(text)
    return true
  end
  return false
end

function MathPuzzleScreen:_buildUI()
  local screen_w = Screen:getWidth()

  self.input_buttons = {}
  self.mark_widgets = {}
  self.mark_containers = {}

  self.title_bar = TitleBar:new({
    width = screen_w,
    title = self.mode.title,
    subtitle = self:getHeaderStatsText(),
    subtitle_face = Font:getFace("smallinfofont"),
    fullscreen = true,
    left_icon = "chevron.left",
    left_icon_tap_callback = function()
      self:confirmExit(function()
        self:_showModeMenu()
      end)
    end,
    close_callback = function()
      self:confirmExit()
    end,
  })
  self.title_bar_container = FrameContainer:new({
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    padding = 0,
    margin = 0,
    self.title_bar,
  })

  self.time_widget = TextWidget:new({
    text = self:getTimeText(),
    face = Font:getFace("smallinfofont"),
    alignment = "center",
  })
  self.time_container = FrameContainer:new({
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    padding = 0,
    margin = 0,
    self.time_widget,
  })

  local count = #self.problems
  local is_single_column = (count <= 5)

  local col_gap = Screen:scaleBySize(28)
  local expr_width = is_single_column and Screen:scaleBySize(175)
    or Screen:scaleBySize(150)
  local input_width = Screen:scaleBySize(80)
  local mark_width = Screen:scaleBySize(25)
  local row_padding = is_single_column and Screen:scaleBySize(16)
    or Screen:scaleBySize(22)

  local left_col = VerticalGroup:new({ align = "left" })
  local right_col = VerticalGroup:new({ align = "left" })

  local font_face = Font:getFace("cfont")

  local function buildRow(i)
    local prob = self.problems[i]
    local is_focused = (i == self.focused_idx)
    local val = prob.user_answer or ""

    local input_btn = Button:new({
      text = val ~= "" and val or (is_focused and "_" or " "),
      width = input_width,
      bordersize = is_focused and Size.border.bold or Size.border.thin,
      background = is_focused and Blitbuffer.COLOR_LIGHT_GRAY
        or Blitbuffer.COLOR_WHITE,
      padding_v = Screen:scaleBySize(4),
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
      self:_updateInputButton(i)
    end

    self.input_buttons[i] = input_btn

    local mark_text = ""
    if prob.checked then
      mark_text = prob.is_correct and " ✓" or " ✗"
    end

    local mark_widget = TextWidget:new({
      text = mark_text,
      face = font_face,
      width = mark_width,
      alignment = "left",
    })
    local mark_container = FrameContainer:new({
      background = Blitbuffer.COLOR_WHITE,
      bordersize = 0,
      padding = 0,
      margin = 0,
      mark_widget,
    })
    self.mark_widgets[i] = mark_widget
    self.mark_containers[i] = mark_container

    return HorizontalGroup:new({
      TextWidget:new({
        text = prob.text,
        face = font_face,
        width = expr_width,
        alignment = "right",
      }),
      HorizontalSpan:new({ width = Screen:scaleBySize(6) }),
      input_btn,
      HorizontalSpan:new({ width = Screen:scaleBySize(4) }),
      mark_container,
    })
  end

  local columns_group
  if is_single_column then
    for i = 1, count do
      table.insert(left_col, buildRow(i))
      if i < count then
        table.insert(left_col, VerticalSpan:new({ height = row_padding }))
      end
    end
    columns_group = HorizontalGroup:new({
      align = "center",
      left_col,
    })
  else
    local half = math.ceil(count / 2)
    for i = 1, half do
      table.insert(left_col, buildRow(i))
      if i < half then
        table.insert(left_col, VerticalSpan:new({ height = row_padding }))
      end
    end

    for i = half + 1, count do
      table.insert(right_col, buildRow(i))
      if i < count then
        table.insert(right_col, VerticalSpan:new({ height = row_padding }))
      end
    end

    columns_group = HorizontalGroup:new({
      align = "top",
      left_col,
      HorizontalSpan:new({ width = col_gap }),
      right_col,
    })
  end

  local keypad_width =
    math.min(screen_w - Screen:scaleBySize(30), Screen:scaleBySize(480))
  local btn_gap_h = Screen:scaleBySize(10)
  local btn_gap_v = Screen:scaleBySize(8)
  local action_btn_w = math.floor((keypad_width - btn_gap_h) / 2)
  local num_btn_w = math.floor((keypad_width - 2 * btn_gap_h) / 3)
  local btn_h = Screen:scaleBySize(50)

  local function createButton(text, callback, w, h)
    return Button:new({
      text = text,
      bordersize = Size.border.thin,
      background = Blitbuffer.COLOR_WHITE,
      width = w,
      height = h or btn_h,
      text_font_face = "smalltfont",
      text_font_size = 20,
      text_font_bold = true,
      margin = 0,
      padding = 0,
      callback = callback,
    })
  end

  self[1] = FrameContainer:new({
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    padding = 0,
    margin = 0,
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    VerticalGroup:new({
      align = "center",
      self.title_bar_container,
      VerticalSpan:new({ height = Screen:scaleBySize(4) }),
      self.time_container,
      VerticalSpan:new({ height = Screen:scaleBySize(16) }),
      columns_group,
      VerticalSpan:new({ height = Screen:scaleBySize(24) }),
      VerticalGroup:new({
        align = "center",
        HorizontalGroup:new({
          align = "center",
          createButton(_("Check"), function()
            self:checkAnswers()
          end, action_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton(_("New"), function()
            self:generateNewProblems()
          end, action_btn_w, btn_h),
        }),
        VerticalSpan:new({ height = btn_gap_v + Screen:scaleBySize(4) }),
        HorizontalGroup:new({
          align = "center",
          createButton("1", function()
            self:inputDigit("1")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("2", function()
            self:inputDigit("2")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("3", function()
            self:inputDigit("3")
          end, num_btn_w, btn_h),
        }),
        VerticalSpan:new({ height = btn_gap_v }),
        HorizontalGroup:new({
          align = "center",
          createButton("4", function()
            self:inputDigit("4")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("5", function()
            self:inputDigit("5")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("6", function()
            self:inputDigit("6")
          end, num_btn_w, btn_h),
        }),
        VerticalSpan:new({ height = btn_gap_v }),
        HorizontalGroup:new({
          align = "center",
          createButton("7", function()
            self:inputDigit("7")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("8", function()
            self:inputDigit("8")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("9", function()
            self:inputDigit("9")
          end, num_btn_w, btn_h),
        }),
        VerticalSpan:new({ height = btn_gap_v }),
        HorizontalGroup:new({
          align = "center",
          HorizontalSpan:new({ width = num_btn_w }),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("0", function()
            self:inputDigit("0")
          end, num_btn_w, btn_h),
          HorizontalSpan:new({ width = btn_gap_h }),
          createButton("⌫", function()
            self:backspace()
          end, num_btn_w, btn_h),
        }),
      }),
      VerticalSpan:new({ height = Screen:scaleBySize(16) }),
    }),
  })
end

function MathPuzzleScreen:checkAnswers()
  self.is_checked = true
  local result = Generator.checkAnswers(self.problems)

  for i, prob in ipairs(self.problems) do
    self.mark_widgets[i]:setText(prob.is_correct and " ✓" or " ✗")
    self.mark_containers[i]:scheduleRepaint()
  end

  self.plugin.session_correct = (self.plugin.session_correct or 0)
    - (self.round_correct or 0)
    + result.correct_count
  self.plugin.session_wrong = (self.plugin.session_wrong or 0)
    - (self.round_wrong or 0)
    + (result.total - result.correct_count)

  self.round_correct = result.correct_count
  self.round_wrong = result.total - result.correct_count
  self.title_bar:setSubTitle(self:getHeaderStatsText(), true)
  self.title_bar_container:scheduleRepaint()
end

function MathPuzzleScreen:generateNewProblems()
  self.is_checked = false
  self.round_correct = 0
  self.round_wrong = 0
  self.question_count = (self.mode and self.mode.question_count) or 10
  self.problems = Generator.generateProblems(self.mode, self.question_count)
  self.focused_idx = 1
  self:_buildUI()
  self:scheduleRepaint()
end

function MathPuzzleScreen:setMode(mode)
  self.is_checked = false
  self.mode = mode
  self.question_count = mode.question_count or 10
  self.round_correct = 0
  self.round_wrong = 0
  self.problems = Generator.generateProblems(self.mode, self.question_count)
  self.focused_idx = 1
  self:_buildUI()
  self:scheduleRepaint()
end

function MathPuzzleScreen:_showModeMenu()
  if self.plugin.showModeSelection then
    self.plugin:showModeSelection(self)
  end
end

function MathPuzzleScreen:confirmExit(callback)
  if self.is_checked then
    if callback then
      callback()
    else
      UIManager:close(self)
    end
    return
  end

  UIManager:show(ConfirmBox:new({
    text = _(
      "Your progress will be lost if you exit. Are you sure you want to exit?"
    ),
    ok_text = _("Exit"),
    ok_callback = function()
      if callback then
        callback()
      else
        UIManager:close(self)
      end
    end,
  }))
end

function MathPuzzleScreen:onBack()
  self:confirmExit()
  return true
end

function MathPuzzleScreen:onClose()
  self.plugin.screen = nil
  self.plugin.session_start_time = nil
end

return MathPuzzleScreen
