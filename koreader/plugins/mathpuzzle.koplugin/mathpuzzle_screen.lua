local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputText = require("ui/widget/inputtext")
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
  self.font_face = Font:getFace("smallinfofont")
  self.title_font_face = Font:getFace("smalltfont")
  self.input_fields = {}
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
  return string.format(
    _("%s  ·  Correct: %d  ·  Wrong: %d  ·  Time: %s"),
    self.mode.title,
    session_correct,
    session_wrong,
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

function MathPuzzleScreen:buildUI()
  local Screen = Device.screen
  local content_width = math.min(Screen:getWidth(), Screen:getHeight())
  if content_width > Screen:scaleBySize(600) then
    content_width = Screen:scaleBySize(600)
  else
    content_width = math.floor(content_width * 0.95)
  end

  -- Clean up existing input widgets if rebuilding
  if self.input_fields then
    for _, widget in ipairs(self.input_fields) do
      if widget.onClose then
        widget:onClose()
      end
    end
  end
  self.input_fields = {}
  self.mark_widgets = {}
  self.expr_widgets = {}

  self.title_bar = TitleBar:new({
    width = content_width,
    title = _("Math Puzzle"),
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

  local rows_group = VerticalGroup:new({
    align = "center",
  })

  local expr_width = Screen:scaleBySize(160)
  local input_width = Screen:scaleBySize(110)
  local mark_width = Screen:scaleBySize(120)
  local idx_width = Screen:scaleBySize(35)
  local row_padding = Screen:scaleBySize(3)

  for i, prob in ipairs(self.problems) do
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

    local input_field = InputText:new({
      text = prob.user_answer or "",
      hint = "?",
      input_type = "number",
      face = self.font_face,
      width = input_width,
      idx = i,
      focused = (i == self.focused_idx),
      scroll = false,
      parent = self,
      padding = Screen:scaleBySize(4),
      margin = 0,
      alignment = "center",
      enter_callback = function()
        self:onFieldEnter(i)
      end,
      edit_callback = function(is_edited)
        if is_edited and self.input_fields[i] then
          self.problems[i].user_answer = self.input_fields[i]:getText()
        end
      end,
    })
    table.insert(self.input_fields, input_field)

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
    table.insert(self.mark_widgets, mark_widget)

    local row = HorizontalGroup:new({
      idx_widget,
      HorizontalSpan:new({ width = Screen:scaleBySize(8) }),
      expr_widget,
      HorizontalSpan:new({ width = Screen:scaleBySize(12) }),
      input_field,
      HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
      mark_widget,
    })

    table.insert(rows_group, row)
    if i < #self.problems then
      table.insert(rows_group, VerticalSpan:new({ height = row_padding }))
    end
  end

  self.score_text = TextWidget:new({
    text = "",
    face = self.font_face,
    width = content_width,
    alignment = "center",
  })
  self:updateScoreDisplay()

  self.button_table = ButtonTable:new({
    width = content_width,
    buttons = {
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
    VerticalSpan:new({ height = Screen:scaleBySize(10) }),
    rows_group,
    VerticalSpan:new({ height = Screen:scaleBySize(10) }),
    self.score_text,
    VerticalSpan:new({ height = Screen:scaleBySize(10) }),
    self.button_table,
    VerticalSpan:new({ height = Screen:scaleBySize(10) }),
  })

  self.dialog_frame = FrameContainer:new({
    radius = Size.radius.window,
    bordersize = Size.border.window,
    padding = Screen:scaleBySize(10),
    margin = 0,
    background = Blitbuffer.COLOR_WHITE,
    main_layout,
  })

  self[1] = CenterContainer:new({
    dimen = Geom:new({
      w = Screen:getWidth(),
      h = Screen:getHeight(),
    }),
    self.dialog_frame,
  })

  self._input_widget = self.input_fields[self.focused_idx]
end

function MathPuzzleScreen:updateScoreDisplay()
  local checked_count = 0
  for _, prob in ipairs(self.problems) do
    if prob.checked then
      checked_count = checked_count + 1
    end
  end

  if checked_count == 0 then
    self.score_text:setText(_("Enter your answers and tap Check"))
  else
    local result = Generator.checkAnswers(self.problems)
    if result.all_correct then
      self.score_text:setText(
        string.format(
          _("🎉 Perfect Score! %d / %d Correct! (100%%)"),
          result.correct_count,
          result.total
        )
      )
    else
      local pct = math.floor((result.correct_count / result.total) * 100)
      self.score_text:setText(
        string.format(
          _("Score: %d / %d Correct (%d%%) · %d Wrong"),
          result.correct_count,
          result.total,
          pct,
          result.total - result.correct_count
        )
      )
    end
  end
end

function MathPuzzleScreen:onSwitchFocus(inputbox)
  if self._input_widget and self._input_widget ~= inputbox then
    self._input_widget:unfocus()
    self._input_widget:closeKeyboard()
  end

  self._input_widget = inputbox
  self.focused_idx = inputbox.idx
  self._input_widget:focus()
  self._input_widget:showKeyboard()

  UIManager:setDirty(self, function()
    return "ui", self.dimen
  end)
end

function MathPuzzleScreen:onFieldEnter(idx)
  if idx < #self.input_fields then
    local next_field = self.input_fields[idx + 1]
    self:onSwitchFocus(next_field)
  else
    self:checkAnswers()
  end
end

function MathPuzzleScreen:checkAnswers()
  -- Read latest text from all inputs
  for i, field in ipairs(self.input_fields) do
    self.problems[i].user_answer = field:getText()
  end

  local result = Generator.checkAnswers(self.problems)

  for i, prob in ipairs(self.problems) do
    if prob.is_correct then
      self.mark_widgets[i]:setText(" ✓")
    else
      self.mark_widgets[i]:setText(string.format(" ✗ (%d)", prob.answer))
    end
  end

  -- Update session totals
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

  self:updateScoreDisplay()
  if self.title_bar then
    self.title_bar:setSubTitle(self:getHeaderStatsText())
  end

  -- Close keyboard on check so score & answers are fully visible
  if self._input_widget then
    self._input_widget:closeKeyboard()
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
  if self._input_widget then
    self._input_widget:closeKeyboard()
  end
  for _, widget in ipairs(self.input_fields) do
    if widget.onClose then
      widget:onClose()
    end
  end
end

return MathPuzzleScreen
