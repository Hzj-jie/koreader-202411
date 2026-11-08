describe("MathPuzzle Screen and Plugin", function()
  local Blitbuffer
  local MathPuzzle
  local MathPuzzleScreen
  local Generator
  local UIManager

  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
    UIManager = require("ui/uimanager")
    Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")
    MathPuzzleScreen = require("plugins/mathpuzzle.koplugin/mathpuzzle_screen")
    MathPuzzle = require("plugins/mathpuzzle.koplugin/main")
  end)

  after_each(function()
    -- Clean up window stack after each test
    while #UIManager._window_stack > 0 do
      local top = UIManager._window_stack[#UIManager._window_stack]
      UIManager:close(top.widget)
    end
    UIManager._dirty = {}
  end)

  local function createMockPlugin()
    local dummy_ui = { menu = { registerToMainMenu = function() end } }
    local plugin = MathPuzzle:new({ ui = dummy_ui })
    plugin:init()
    return plugin
  end

  local function createScreen(plugin, mode_id)
    plugin = plugin or createMockPlugin()
    local mode = Generator.getModeById(mode_id or "add_sub_100")
    return MathPuzzleScreen:new({
      plugin = plugin,
      mode = mode,
    })
  end

  it("should assert when plugin is nil", function()
    assert.has_error(function()
      MathPuzzleScreen:new({
        mode = Generator.getModeById("add_sub_100"),
      })
    end)
  end)

  it("should initialize MathPuzzleScreen and build 10 question rows", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)
    assert.are.equal(10, #screen.mark_widgets)
    assert.are.equal(10, #screen.mark_containers)
    assert.is_table(screen.title_bar_container)
    assert.is_table(screen.time_container)

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for arithmetic_progression_100 in single column with inline answer blocks", function()
    local screen = createScreen(nil, "arithmetic_progression_100")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(5, #screen.problems)
    assert.is_true(screen.mode.single_column)
    assert.is_true(#screen.input_buttons >= 20 and #screen.input_buttons <= 25)

    for _, prob in ipairs(screen.problems) do
      assert.are.equal(8, #prob.terms)
      assert.is_true(prob.inline_blanks)
      assert.is_true(#prob.blank_indices >= 4 and #prob.blank_indices <= 5)
    end

    -- Fill all inline answer buttons with correct answers
    for _, btn in ipairs(screen.input_buttons) do
      local prob = screen.problems[btn.prob_id]
      btn:setText(tostring(prob.answers[btn.blank_idx]))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    -- Modifying an answer clears mark
    local first_btn = screen.input_buttons[1]
    first_btn:setText("999")
    assert.is_nil(screen.problems[first_btn.prob_id].is_correct)

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for arithmetic_progression_30_entry with strictly alternating blanks", function()
    local screen = createScreen(nil, "arithmetic_progression_30_entry")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(5, #screen.problems)
    assert.is_true(screen.mode.single_column)
    assert.are.equal(30, screen.mode.max)
    assert.are.equal(3, screen.mode.max_step)
    assert.is_true(screen.mode.alternating_blanks)
    assert.are.equal(20, #screen.input_buttons)

    for _, prob in ipairs(screen.problems) do
      assert.are.equal(8, #prob.terms)
      assert.is_true(prob.inline_blanks)
      assert.is_true(prob.step >= 1 and prob.step <= 3)
      assert.are.equal(4, #prob.blank_indices)
      local str = table.concat(prob.blank_indices, ",")
      assert.is_true(str == "1,3,5,7" or str == "2,4,6,8")
      for _, term in ipairs(prob.terms) do
        assert.is_true(term >= 0 and term <= 30)
      end
    end

    for _, btn in ipairs(screen.input_buttons) do
      local prob = screen.problems[btn.prob_id]
      btn:setText(tostring(prob.answers[btn.blank_idx]))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for arithmetic_progression_50_easy with strictly alternating blanks", function()
    local screen = createScreen(nil, "arithmetic_progression_50_easy")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(5, #screen.problems)
    assert.is_true(screen.mode.single_column)
    assert.are.equal(50, screen.mode.max)
    assert.are.equal(4, screen.mode.max_step)
    assert.is_true(screen.mode.alternating_blanks)
    assert.are.equal(20, #screen.input_buttons)

    for _, prob in ipairs(screen.problems) do
      assert.are.equal(8, #prob.terms)
      assert.is_true(prob.inline_blanks)
      assert.is_true(prob.step >= 1 and prob.step <= 4)
      assert.are.equal(4, #prob.blank_indices)
      local str = table.concat(prob.blank_indices, ",")
      assert.is_true(str == "1,3,5,7" or str == "2,4,6,8")
      for _, term in ipairs(prob.terms) do
        assert.is_true(term >= 0 and term <= 50)
      end
    end

    for _, btn in ipairs(screen.input_buttons) do
      local prob = screen.problems[btn.prob_id]
      btn:setText(tostring(prob.answers[btn.blank_idx]))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for arithmetic_progression_50 in single column with inline answer blocks", function()
    local screen = createScreen(nil, "arithmetic_progression_50")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(5, #screen.problems)
    assert.is_true(screen.mode.single_column)
    assert.are.equal(50, screen.mode.max)
    assert.are.equal(4, screen.mode.max_step)
    assert.is_true(#screen.input_buttons >= 20 and #screen.input_buttons <= 25)

    for _, prob in ipairs(screen.problems) do
      assert.are.equal(8, #prob.terms)
      assert.is_true(prob.inline_blanks)
      assert.is_true(prob.step >= 1 and prob.step <= 4)
      for _, term in ipairs(prob.terms) do
        assert.is_true(term >= 0 and term <= 50)
      end
    end

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for missing_100 with inline blank button", function()
    local screen = createScreen(nil, "missing_100")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)

    for i, prob in ipairs(screen.problems) do
      assert.is_true(prob.text:find("___") ~= nil)
      local btn = screen.input_buttons[i]
      assert.are.equal(i, btn.prob_id)
      assert.is_true(btn.width > 0)
      assert.is_true(btn.height > 0)
    end

    -- Fill all answer buttons with correct answers
    for i, btn in ipairs(screen.input_buttons) do
      local prob = screen.problems[i]
      btn:setText(tostring(prob.answer))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    -- Modifying an answer clears mark
    local first_btn = screen.input_buttons[1]
    first_btn:setText("999")
    assert.is_nil(screen.problems[first_btn.prob_id].is_correct)

    UIManager:close(screen)
  end)

  it("should initialize MathPuzzleScreen for missing_100_add_sub with inline blank button", function()
    local screen = createScreen(nil, "missing_100_add_sub")
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)

    for i, prob in ipairs(screen.problems) do
      assert.is_true(prob.text:find("___") ~= nil)
      assert.is_true(prob.op == "+" or prob.op == "-")
      assert.is_nil(prob.text:find("×"))
      assert.is_nil(prob.text:find("÷"))
      local btn = screen.input_buttons[i]
      assert.are.equal(i, btn.prob_id)
      assert.is_true(btn.width > 0)
      assert.is_true(btn.height > 0)
    end

    -- Fill all answer buttons with correct answers
    for i, btn in ipairs(screen.input_buttons) do
      local prob = screen.problems[i]
      btn:setText(tostring(prob.answer))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    UIManager:close(screen)
  end)

  it("should verify correct answers and update question marks", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    for i, field in ipairs(screen.input_buttons) do
      field:setText(tostring(screen.problems[i].answer))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    UIManager:close(screen)
  end)

  it("should generate new problems and switch modes", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    screen:generateNewProblems()
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)

    local mode_1000 = Generator.getModeById("add_sub_1000")
    screen:setMode(mode_1000)
    assert.are.equal("add_sub_1000", screen.mode.id)
    assert.are.equal(10, #screen.problems)

    UIManager:close(screen)
  end)

  it("should paint screen to blitbuffer without errors", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    local Device = require("device")
    local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
    screen:paintTo(test_bb, 0, 0)

    UIManager:close(screen)
  end)

  it("should display correct and wrong marks on answer check", function()
    local screen = createScreen(nil, "add_sub_10")
    UIManager:show(screen)

    screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
    for i = 2, 10 do
      screen.input_buttons[i]:setText(tostring(screen.problems[i].answer + 1))
    end
    screen:checkAnswers()

    assert.is_true(screen.problems[1].is_correct)
    assert.are.equal(" ✓", screen.mark_widgets[1].text)
    assert.is_false(screen.problems[2].is_correct)
    assert.is_truthy(screen.mark_widgets[2].text:find("✗"))

    UIManager:close(screen)
  end)

  it(
    "should advance focused field on enter and update button styles",
    function()
      local screen = createScreen(nil, "add_sub_10")
      UIManager:show(screen)

      assert.is_true(screen:onKeyPress("Return"))
      assert.are.equal(2, screen.focused_idx)
      assert.are.equal(
        Blitbuffer.COLOR_WHITE,
        screen.input_buttons[1].frame.background
      )
      assert.are.equal(
        Blitbuffer.COLOR_LIGHT_GRAY,
        screen.input_buttons[2].frame.background
      )

      UIManager:close(screen)
    end
  )

  it("should handle keypad digit input and backspace", function()
    local screen = createScreen(nil, "add_sub_10")
    UIManager:show(screen)

    screen:selectField(3)
    assert.are.equal(3, screen.focused_idx)
    assert.are.equal(
      Blitbuffer.COLOR_WHITE,
      screen.input_buttons[2].frame.background
    )
    assert.are.equal(
      Blitbuffer.COLOR_LIGHT_GRAY,
      screen.input_buttons[3].frame.background
    )
    screen.input_buttons[3]:setText("")
    screen:inputDigit("4")
    screen:inputDigit("2")
    assert.are.equal("42", screen.problems[3].user_answer)
    screen:backspace()
    assert.are.equal("4", screen.problems[3].user_answer)

    UIManager:close(screen)
  end)

  it("should handle keyboard navigation and repeat backspace", function()
    local screen = createScreen(nil, "add_sub_10")
    UIManager:show(screen)

    screen:selectField(3)
    screen.input_buttons[3]:setText("4")
    screen:onKeyPress({ key = "9" })
    assert.are.equal("49", screen.problems[3].user_answer)
    screen:onKeyPress("Tab")
    assert.are.equal(4, screen.focused_idx)
    screen.input_buttons[4]:setText("")
    screen:onTextInput("7")
    local Key = require("device/key")
    assert.is_nil((screen:onKeyPress(Key:new("/", {}))))
    screen:inputDigit("8")
    assert.are.equal("78", screen.problems[4].user_answer)
    screen:onKeyRepeat("BackSpace")
    assert.are.equal("7", screen.problems[4].user_answer)

    UIManager:close(screen)
  end)

  it("should wrap around field navigation at boundaries", function()
    local screen = createScreen(nil, "add_sub_10")
    UIManager:show(screen)

    screen:selectField(10)
    screen:nextField()
    assert.are.equal(1, screen.focused_idx)
    screen:prevField()
    assert.are.equal(10, screen.focused_idx)

    UIManager:close(screen)
  end)

  it(
    "should register MathPuzzle to main menu and open mode selection menu",
    function()
      local ui = {
        menu = {
          registerToMainMenu = spy.new(function() end),
        },
      }
      local plugin = MathPuzzle:new({ ui = ui })
      plugin:init()
      assert.spy(ui.menu.registerToMainMenu).was_called_with(ui.menu, plugin)

      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.mathpuzzle)
      assert.is_function(menu_items.mathpuzzle.callback)

      menu_items.mathpuzzle.callback()
      assert.is_true(#UIManager._window_stack > 0)
      local menu = UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_table(menu.item_table)
      assert.are.equal(#Generator.getModes(), #menu.item_table)
      assert.is_true(menu.is_borderless)

      menu.item_table[2].callback()
      assert.is_table(plugin.screen)
      assert.are.equal("add_sub_100", plugin.screen.mode.id)
      assert.are.equal("chevron.left", plugin.screen.title_bar.left_icon)
      assert.is_function(plugin.screen.title_bar.left_icon_tap_callback)

      UIManager:close(plugin.screen)
    end
  )

  it("should track session correct/wrong statistics across rounds", function()
    local plugin = createMockPlugin()
    plugin:showPuzzle(Generator.getModeById("add_sub_100"))

    for i = 1, 7 do
      plugin.screen.input_buttons[i]:setText(
        tostring(plugin.screen.problems[i].answer)
      )
    end
    for i = 8, 10 do
      plugin.screen.input_buttons[i]:setText(
        tostring(plugin.screen.problems[i].answer + 1)
      )
    end
    plugin.screen:checkAnswers()

    assert.are.equal(7, plugin.session_correct)
    assert.are.equal(3, plugin.session_wrong)
    assert.is_string(plugin.screen:getTimeText())
    assert.is_table(plugin.screen.time_widget)
    assert.is_truthy(plugin.screen.time_widget.text:find("Time:"))
    assert.is_truthy(plugin.screen:getHeaderStatsText():find("Correct: 7"))
    assert.is_truthy(plugin.screen:getHeaderStatsText():find("Wrong: 3"))
    assert.is_truthy(plugin.screen:getHeaderStatsText():find("Score: 70%%"))

    -- Start a new round and answer 10 correctly
    plugin.screen:generateNewProblems()
    for i = 1, 10 do
      plugin.screen.input_buttons[i]:setText(
        tostring(plugin.screen.problems[i].answer)
      )
    end
    plugin.screen:checkAnswers()

    assert.are.equal(17, plugin.session_correct)
    assert.are.equal(3, plugin.session_wrong)
    assert.is_truthy(plugin.screen:getHeaderStatsText():find("Score: 85%%"))

    UIManager:close(plugin.screen)
  end)

  it(
    "should update session timer on 1-minute ticks and reset on close",
    function()
      local plugin = createMockPlugin()
      plugin:showPuzzle(Generator.getModeById("add_sub_100"))

      assert.is_table(plugin.screen.time_container)
      assert.is_table(plugin.screen.time_widget)
      plugin.session_start_time = os.time() - 60
      plugin.screen:onTimesChange_1M()
      assert.are.equal("Time: 1 minute", plugin.screen.time_widget.text)

      plugin.session_start_time = os.time() - 120
      plugin.screen:onTimesChange_1M()
      assert.are.equal("Time: 2 minutes", plugin.screen.time_widget.text)

      UIManager:close(plugin.screen)
      assert.is_nil(plugin.screen)
      assert.is_nil(plugin.session_start_time)

      assert.has_error(function()
        plugin:showPuzzle()
      end)
      plugin:showPuzzle(Generator.getModeById("add_sub_100"))
      assert.is_table(plugin.screen)
      assert.is_number(plugin.session_start_time)
      assert.are.equal("Time: 0 minutes", plugin.screen:getTimeText())
      UIManager:close(plugin.screen)
    end
  )

  it(
    "should support 5-question single column layout for 3-term mental math",
    function()
      local screen = createScreen(nil, "three_term_100")
      UIManager:show(screen)

      assert.are.equal(5, #screen.problems)
      assert.are.equal(5, #screen.input_buttons)
      assert.are.equal(5, #screen.mark_widgets)

      for i, field in ipairs(screen.input_buttons) do
        field:setText(tostring(screen.problems[i].answer))
      end
      screen:checkAnswers()

      for _, prob in ipairs(screen.problems) do
        assert.is_true(prob.is_correct)
      end

      UIManager:close(screen)
    end
  )

  it(
    "should consume touch and gesture events at top and bottom of screen without leaking to underlying windows",
    function()
      local Event = require("ui/event")
      local Geom = require("ui/geometry")
      local Device = require("device")
      local InputContainer = require("ui/widget/container/inputcontainer")

      local underlying_tapped = false
      local DummyUnderlyingWindow = InputContainer:extend({
        name = "dummy_underlying",
      })
      function DummyUnderlyingWindow:init()
        self.dimen = Geom:new({
          x = 0,
          y = 0,
          w = Device.screen:getWidth(),
          h = Device.screen:getHeight(),
        })
        self.covers_fullscreen = true
      end
      function DummyUnderlyingWindow:onGesture(ev)
        underlying_tapped = true
        return true
      end

      local underlying = DummyUnderlyingWindow:new()
      UIManager:show(underlying)

      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
      screen:paintTo(test_bb, 0, 0)

      -- Top of screen tap gesture on empty title area
      local top_tap = Event:new("Gesture", {
        ges = "tap",
        pos = Geom:new({ x = 300, y = 10 }),
      })
      UIManager:userInput(top_tap)
      assert.is_false(underlying_tapped)

      -- Bottom of screen tap gesture on empty margin
      local bottom_tap = Event:new("Gesture", {
        ges = "tap",
        pos = Geom:new({ x = 50, y = Device.screen:getHeight() - 5 }),
      })
      UIManager:userInput(bottom_tap)
      assert.is_false(underlying_tapped)

      -- Middle / empty side margin tap gesture
      local middle_tap = Event:new("Gesture", {
        ges = "tap",
        pos = Geom:new({ x = 5, y = 300 }),
      })
      UIManager:userInput(middle_tap)
      assert.is_false(underlying_tapped)

      -- Tap on second input field focuses it
      local second_field = screen.input_buttons[2]
      local second_field_pos = second_field.dimen
      if second_field_pos then
        local field_tap = Event:new("Gesture", {
          ges = "tap",
          pos = Geom:new({
            x = second_field_pos.x + 5,
            y = second_field_pos.y + 5,
          }),
        })
        assert.are.equal(1, screen.focused_idx)
        UIManager:userInput(field_tap)
        assert.are.equal(2, screen.focused_idx)
        assert.is_false(underlying_tapped)
      end

      UIManager:close(screen)
      UIManager:close(underlying)
    end
  )

  it(
    "should exit immediately without confirmation when no input has been entered",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      assert.is_false(screen:hasUncheckedProgress())

      local mode_menu_shown = false
      screen._showModeMenu = function()
        mode_menu_shown = true
      end
      local initial_stack_size = #UIManager._window_stack
      screen.title_bar.left_icon_tap_callback()
      assert.is_true(mode_menu_shown)
      assert.are.equal(initial_stack_size, #UIManager._window_stack)

      UIManager:close(screen)
    end
  )

  it(
    "should show exit confirmation on close, back, and mode switch when input is entered",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen:inputDigit("5")
      assert.is_true(screen:hasUncheckedProgress())

      local initial_stack_size = #UIManager._window_stack
      screen.title_bar.close_callback()
      assert.are.equal(initial_stack_size + 1, #UIManager._window_stack)
      local confirm_box =
        UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_truthy(confirm_box.text:find("progress will be lost"))
      UIManager:close(confirm_box)
      assert.are.equal(initial_stack_size, #UIManager._window_stack)

      screen:onBack()
      assert.are.equal(initial_stack_size + 1, #UIManager._window_stack)
      confirm_box = UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_truthy(confirm_box.text:find("progress will be lost"))
      UIManager:close(confirm_box)

      local mode_menu_shown = false
      screen._showModeMenu = function()
        mode_menu_shown = true
      end
      screen.title_bar.left_icon_tap_callback()
      assert.are.equal(initial_stack_size + 1, #UIManager._window_stack)
      confirm_box = UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_truthy(confirm_box.text:find("progress will be lost"))
      confirm_box.ok_callback()
      assert.is_true(mode_menu_shown)
      UIManager:close(confirm_box)

      UIManager:close(screen)
    end
  )

  it("should exit without confirmation once answers are checked", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    screen:inputDigit("5")
    screen:checkAnswers()
    assert.is_false(screen:hasUncheckedProgress())

    local mode_menu_shown = false
    screen._showModeMenu = function()
      mode_menu_shown = true
    end
    local initial_stack_size = #UIManager._window_stack
    screen.title_bar.left_icon_tap_callback()
    assert.is_true(mode_menu_shown)
    assert.are.equal(initial_stack_size, #UIManager._window_stack)

    screen.title_bar.close_callback()
    assert.are.equal(initial_stack_size - 1, #UIManager._window_stack)
  end)

  it(
    "should remove mark and reset checked state when user changes answer via inputDigit",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
      screen:checkAnswers()
      assert.are.equal(" ✓", screen.mark_widgets[1].text)
      assert.is_true(screen.problems[1].checked)

      screen:selectField(1)
      screen:inputDigit("9")
      assert.are.equal("", screen.mark_widgets[1].text)
      assert.is_false(screen.problems[1].checked)
      assert.is_nil(screen.problems[1].is_correct)

      UIManager:close(screen)
    end
  )

  it(
    "should remove mark and reset checked state when user changes answer via backspace",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
      screen:checkAnswers()
      assert.are.equal(" ✓", screen.mark_widgets[1].text)
      assert.is_true(screen.problems[1].checked)

      screen:selectField(1)
      screen:backspace()
      assert.are.equal("", screen.mark_widgets[1].text)
      assert.is_false(screen.problems[1].checked)
      assert.is_nil(screen.problems[1].is_correct)

      UIManager:close(screen)
    end
  )

  it(
    "should remove mark and reset checked state when user changes answer via setText",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
      screen:checkAnswers()
      assert.are.equal(" ✓", screen.mark_widgets[1].text)
      assert.is_true(screen.problems[1].checked)

      screen.input_buttons[1]:setText("123")
      assert.are.equal("", screen.mark_widgets[1].text)
      assert.is_false(screen.problems[1].checked)
      assert.is_nil(screen.problems[1].is_correct)

      UIManager:close(screen)
    end
  )

  it(
    "should report unchecked progress when modifying an answer after checking",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      for i, field in ipairs(screen.input_buttons) do
        field:setText(tostring(screen.problems[i].answer))
      end
      screen:checkAnswers()
      assert.is_false(screen:hasUncheckedProgress())

      screen:selectField(2)
      screen:inputDigit("1")
      assert.is_true(screen:hasUncheckedProgress())

      screen:checkAnswers()
      assert.is_false(screen:hasUncheckedProgress())

      UIManager:close(screen)
    end
  )

  it(
    "should clear mark widget text and retain non-zero container width to clear mark from screen",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
      screen:checkAnswers()
      assert.are.equal(" ✓", screen.mark_widgets[1].text)
      assert.is_true(screen.mark_containers[1]:getSize().w > 0)

      screen:selectField(1)
      screen:inputDigit("9")
      assert.are.equal("", screen.mark_widgets[1].text)
      assert.is_true(screen.mark_containers[1]:getSize().w > 0)

      local Device = require("device")
      local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
      screen.mark_containers[1]:paintTo(test_bb, 0, 0)

      UIManager:close(screen)
    end
  )

  it(
    "should accumulate session correct and wrong counts on each check button click",
    function()
      local plugin = createMockPlugin()
      plugin:showPuzzle(Generator.getModeById("add_sub_100"))

      for i = 1, 8 do
        plugin.screen.input_buttons[i]:setText(
          tostring(plugin.screen.problems[i].answer)
        )
      end
      for i = 9, 10 do
        plugin.screen.input_buttons[i]:setText(
          tostring(plugin.screen.problems[i].answer + 1)
        )
      end
      plugin.screen:checkAnswers()

      assert.are.equal(8, plugin.session_correct)
      assert.are.equal(2, plugin.session_wrong)

      -- Change one wrong answer to correct and check again: results should accumulate
      plugin.screen.input_buttons[9]:setText(
        tostring(plugin.screen.problems[9].answer)
      )
      plugin.screen:checkAnswers()

      -- Previous (8, 2) + new check (9, 1) = (17, 3)
      assert.are.equal(17, plugin.session_correct)
      assert.are.equal(3, plugin.session_wrong)

      UIManager:close(plugin.screen)
    end
  )

  it("should limit input digit length to 6 characters", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    screen:selectField(1)
    for _ = 1, 10 do
      screen:inputDigit("8")
    end
    assert.are.equal("888888", screen.problems[1].user_answer)
    assert.are.equal(6, #screen.problems[1].user_answer)

    UIManager:close(screen)
  end)

  it(
    "should wrap around field navigation with nextField and prevField",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      assert.are.equal(1, screen.focused_idx)

      screen:prevField()
      assert.are.equal(10, screen.focused_idx)

      screen:nextField()
      assert.are.equal(1, screen.focused_idx)

      screen:selectField(5)
      assert.is_true(screen:onKeyPress("Enter"))
      assert.are.equal(6, screen.focused_idx)

      UIManager:close(screen)
    end
  )

  it("should filter non-digit characters in onTextInput", function()
    local screen = createScreen(nil, "add_sub_100")
    UIManager:show(screen)

    screen:selectField(1)
    assert.is_false(screen:onTextInput("abc"))
    assert.is_false(screen:onTextInput("+"))
    assert.is_false(screen:onTextInput("/"))
    assert.is_false(screen:onTextInput(" "))
    assert.are.equal("", screen.problems[1].user_answer)

    assert.is_true(screen:onTextInput("7"))
    assert.are.equal("7", screen.problems[1].user_answer)

    UIManager:close(screen)
  end)

  it(
    "should handle navigation and deletion keys via onKeyPress and onKeyRepeat",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      screen:selectField(1)
      screen:inputDigit("1")
      screen:inputDigit("2")

      assert.is_true(screen:onKeyPress("Delete"))
      assert.are.equal("1", screen.problems[1].user_answer)

      assert.is_true(screen:onKeyRepeat("BackSpace"))
      assert.are.equal("", screen.problems[1].user_answer)

      assert.is_true(screen:onKeyPress("Tab"))
      assert.are.equal(2, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "Right" }))
      assert.are.equal(3, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "Left" }))
      assert.are.equal(2, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "Up" }))
      assert.are.equal(1, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "Down" }))
      assert.are.equal(2, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "Return" }))
      assert.are.equal(3, screen.focused_idx)

      assert.is_true(screen:onKeyPress({ key = "KP_Enter" }))
      assert.are.equal(4, screen.focused_idx)

      UIManager:close(screen)
    end
  )

  it("should reset plugin screen and session start time on onClose", function()
    local plugin = createMockPlugin()
    plugin:showPuzzle(Generator.getModeById("add_sub_100"))

    assert.is_not_nil(plugin.screen)
    assert.is_not_nil(plugin.session_start_time)

    local screen = plugin.screen
    screen:onClose()
    assert.is_nil(plugin.screen)
    assert.is_nil(plugin.session_start_time)

    UIManager:close(screen)
  end)

  it(
    "should trigger mode switch callback when selected from showModeSelection",
    function()
      local plugin = createMockPlugin()
      plugin:showPuzzle(Generator.getModeById("add_sub_100"))

      local menu = plugin:showModeSelection(plugin.screen)
      assert.is_table(menu)
      assert.is_table(menu.item_table)

      -- Select 3-Term Mental Math (item 12)
      local target_item
      for _, item in ipairs(menu.item_table) do
        if item.text == Generator.getModeById("three_term_100").title then
          target_item = item
          break
        end
      end
      assert.is_not_nil(target_item)
      target_item.callback()

      assert.are.equal("three_term_100", plugin.screen.mode.id)
      assert.are.equal(5, #plugin.screen.problems)

      UIManager:close(menu)
      UIManager:close(plugin.screen)
    end
  )

  it("verifies localized titles and descriptions for new modes", function()
    local gettext = require("gettext")
    gettext.changeLang("zh_CN")
    assert.are.equal(
      "100以内填空题（仅加减法）",
      gettext("Fill-in-the-Blank (+, -) within 100")
    )
    assert.are.equal(
      "30以内等差数列（入门）",
      gettext("Arithmetic Progression within 30 (Entry Level)")
    )
    assert.are.equal(
      "100以内算式接龙（加减法）",
      gettext("Math Snake (+, -) within 100")
    )
    assert.are.equal(
      "100以内的连续加减法接龙计算",
      gettext("Chain addition and subtraction steps within 100")
    )

    gettext.changeLang("zh_TW")
    assert.are.equal(
      "100以內填空題（僅加減法）",
      gettext("Fill-in-the-Blank (+, -) within 100")
    )
    assert.are.equal(
      "30以內等差數列（入門）",
      gettext("Arithmetic Progression within 30 (Entry Level)")
    )
    assert.are.equal(
      "100以內算式接龍（加減法）",
      gettext("Math Snake (+, -) within 100")
    )
    assert.are.equal(
      "100以內的連續加減法接龍計算",
      gettext("Chain addition and subtraction steps within 100")
    )

    gettext.changeLang("C")
  end)

  it(
    "should render math_snake_100 in a 4x3 serpentine layout within screen bounds",
    function()
      local Device = require("device")
      local Font = require("ui/font")
      local gettext = require("gettext")
      local Screen = Device.screen
      local TextWidget = require("ui/widget/textwidget")
      local screen = createScreen(nil, "math_snake_100")
      UIManager:show(screen)

      local test_bb = Screen.bb
        or Blitbuffer.new(Screen:getWidth(), Screen:getHeight())
      screen:paintTo(test_bb, 0, 0)

      assert.are.equal(11, #screen.problems)
      assert.are.equal(11, #screen.input_buttons)
      assert.are.equal(11, #screen.mark_widgets)
      assert.are.equal(11, #screen.mark_containers)

      local btns = screen.input_buttons
      -- Row 1 (head, 1, 2, 3): strictly left to right
      assert.are.equal(btns[1].dimen.y, btns[2].dimen.y)
      assert.are.equal(btns[2].dimen.y, btns[3].dimen.y)
      assert.is_true(btns[1].dimen.x < btns[2].dimen.x)
      assert.is_true(btns[2].dimen.x < btns[3].dimen.x)

      -- Row 2 (7 <- 6 <- 5 <- 4): strictly below row 1, right to left
      assert.are.equal(btns[4].dimen.y, btns[5].dimen.y)
      assert.are.equal(btns[5].dimen.y, btns[6].dimen.y)
      assert.are.equal(btns[6].dimen.y, btns[7].dimen.y)
      assert.is_true(btns[4].dimen.y > btns[3].dimen.y)
      assert.are.equal(btns[3].dimen.x, btns[4].dimen.x)
      assert.is_true(btns[4].dimen.x > btns[5].dimen.x)
      assert.is_true(btns[5].dimen.x > btns[6].dimen.x)
      assert.is_true(btns[6].dimen.x > btns[7].dimen.x)

      -- Row 3 (8 -> 9 -> 10 -> 11): strictly below row 2, left to right
      assert.are.equal(btns[8].dimen.y, btns[9].dimen.y)
      assert.are.equal(btns[9].dimen.y, btns[10].dimen.y)
      assert.are.equal(btns[10].dimen.y, btns[11].dimen.y)
      assert.is_true(btns[8].dimen.y > btns[7].dimen.y)
      assert.are.equal(btns[7].dimen.x, btns[8].dimen.x)
      assert.is_true(btns[8].dimen.x < btns[9].dimen.x)
      assert.is_true(btns[9].dimen.x < btns[10].dimen.x)
      assert.is_true(btns[10].dimen.x < btns[11].dimen.x)

      -- 4-column vertical alignment
      assert.is_true(btns[7].dimen.x < btns[1].dimen.x)
      assert.are.equal(btns[1].dimen.x, btns[6].dimen.x)
      assert.are.equal(btns[6].dimen.x, btns[9].dimen.x)
      assert.are.equal(btns[2].dimen.x, btns[5].dimen.x)
      assert.are.equal(btns[5].dimen.x, btns[10].dimen.x)
      assert.are.equal(btns[4].dimen.x, btns[11].dimen.x)

      -- Walk painted widget tree for head box, Check button, connectors, and TextWidgets
      local check_btn
      local head_btn
      local text_counts = {}
      local h_conns = {}
      local turn_conns = {}
      local head_text = tostring(screen.problems[1].a)
      local function collectWidgets(widget, visited)
        if type(widget) ~= "table" or visited[widget] then
          return
        end
        visited[widget] = true
        if widget.frame and widget.dimen then
          if widget.text == gettext("Check") then
            check_btn = widget
          elseif widget.text == head_text and not widget.callback then
            head_btn = widget
          end
        elseif not widget.frame and type(widget.text) == "string" then
          text_counts[widget.text] = (text_counts[widget.text] or 0) + 1
        elseif
          widget[1]
          and type(widget[1].text) == "string"
          and widget.dimen
        then
          local label = widget[1].text
          if label:match("↓$") then
            table.insert(turn_conns, widget)
          elseif label:match("→$") or label:match("^← ") then
            table.insert(h_conns, widget)
          end
        end
        for _, child in ipairs(widget) do
          collectWidgets(child, visited)
        end
      end
      collectWidgets(screen[1], {})

      assert.is_not_nil(check_btn)
      assert.is_not_nil(head_btn)
      assert.are.equal(btns[1].dimen.w, head_btn.dimen.w)
      assert.are.equal(btns[1].dimen.h, head_btn.dimen.h)
      assert.are.equal(btns[1].dimen.y, head_btn.dimen.y)
      assert.is_true(head_btn.dimen.x < btns[1].dimen.x)

      assert.are.equal(1, text_counts[head_text])
      local ltr_conn_count = 0
      local rtl_conn_count = 0
      local turn_conn_count = 0
      for text, c in pairs(text_counts) do
        if text:match("→$") then
          ltr_conn_count = ltr_conn_count + c
        elseif text:match("^← ") then
          rtl_conn_count = rtl_conn_count + c
        elseif text:match("↓$") then
          turn_conn_count = turn_conn_count + c
        end
      end
      assert.are.equal(6, ltr_conn_count)
      assert.are.equal(3, rtl_conn_count)
      assert.are.equal(2, turn_conn_count)
      assert.is_nil(text_counts["Start"])

      local expected_labels = {}
      for i, prob in ipairs(screen.problems) do
        local label
        if i == 4 or i == 8 then
          label = string.format("%s %d ↓", prob.op, prob.b)
        elseif i >= 5 and i <= 7 then
          label = string.format("← %s %d", prob.op, prob.b)
        else
          label = string.format("%s %d →", prob.op, prob.b)
        end
        expected_labels[label] = (expected_labels[label] or 0) + 1
      end
      for label, count in pairs(expected_labels) do
        assert.is_true((text_counts[label] or 0) >= count)
      end

      assert.are.equal(2, #turn_conns)
      table.sort(turn_conns, function(a, b)
        return a.dimen.y < b.dimen.y
      end)
      assert.are.equal(
        string.format("%s %d ↓", screen.problems[4].op, screen.problems[4].b),
        turn_conns[1][1].text
      )
      assert.are.equal(btns[3].dimen.x, turn_conns[1].dimen.x)
      assert.is_true(turn_conns[1][1]:getSize().w <= turn_conns[1].dimen.w)
      assert.are.equal(
        string.format("%s %d ↓", screen.problems[8].op, screen.problems[8].b),
        turn_conns[2][1].text
      )
      assert.are.equal(btns[7].dimen.x, turn_conns[2].dimen.x)
      assert.is_true(turn_conns[2][1]:getSize().w <= turn_conns[2].dimen.w)
      for _, hc in ipairs(h_conns) do
        assert.is_true(hc[1]:getSize().w <= hc.dimen.w)
      end

      -- Bounds, mark pinning, and mark slot sizing checks
      local min_mark_h = TextWidget:new({
        text = " ✓",
        face = Font:getFace("x_smallinfofont"),
      })
        :getSize().h
      local title_bottom = screen.title_bar.dimen.y + screen.title_bar.dimen.h
      for i = 1, 11 do
        local btn = btns[i]
        local mc = screen.mark_containers[i]
        assert.is_true(btn.dimen.x >= 0)
        assert.is_true(btn.dimen.x + btn.dimen.w <= Screen:getWidth())
        assert.is_true(mc.dimen.x >= 0)
        assert.is_true(mc.dimen.x + mc.dimen.w <= Screen:getWidth())
        assert.is_true(mc.dimen.y >= title_bottom)
        assert.is_true(btn.dimen.y + btn.dimen.h < check_btn.dimen.y)
        assert.is_true(btn.dimen.y + btn.dimen.h <= Screen:getHeight())
        assert.are.equal(btn.dimen.x, mc.dimen.x)
        assert.are.equal(btn.dimen.y, mc.dimen.y + mc.dimen.h)
        assert.is_true(mc:getSize().w > 0)
        assert.is_true(mc:getSize().h >= min_mark_h)
      end

      UIManager:close(screen)
    end
  )

  it(
    "should fit built content and keypad within screen height for every registered mode",
    function()
      local Device = require("device")
      local Screen = Device.screen
      local test_bb = Screen.bb
        or Blitbuffer.new(Screen:getWidth(), Screen:getHeight())

      for _, mode in ipairs(Generator.getModes()) do
        local screen = createScreen(nil, mode.id)
        UIManager:show(screen)
        screen:paintTo(test_bb, 0, 0)

        assert.is_true(
          screen[1][1]:getSize().h <= Screen:getHeight(),
          mode.id .. " content overflows screen height"
        )

        local zero_btn
        local backspace_btn
        local function findKeypadButtons(widget, visited)
          if type(widget) ~= "table" or visited[widget] then
            return
          end
          visited[widget] = true
          if widget.frame and widget.dimen then
            if widget.text == "0" then
              zero_btn = widget
            elseif widget.text == "⌫" then
              backspace_btn = widget
            end
          end
          for _, child in ipairs(widget) do
            findKeypadButtons(child, visited)
          end
        end
        findKeypadButtons(screen[1], {})

        assert.is_not_nil(zero_btn)
        assert.is_not_nil(backspace_btn)
        assert.is_true(
          zero_btn.dimen.y + zero_btn.dimen.h <= Screen:getHeight()
        )
        assert.is_true(
          backspace_btn.dimen.y + backspace_btn.dimen.h <= Screen:getHeight()
        )

        UIManager:close(screen)
      end
    end
  )

  it("should preserve serpentine direction under RTL UI layout", function()
    local BD = require("ui/bidi")
    local orig_mirrored = BD.mirroredUILayout
    finally(function()
      BD.mirroredUILayout = orig_mirrored
    end)
    BD.mirroredUILayout = function()
      return true
    end

    local Device = require("device")
    local Screen = Device.screen
    local screen = createScreen(nil, "math_snake_100")
    UIManager:show(screen)
    local test_bb = Screen.bb
      or Blitbuffer.new(Screen:getWidth(), Screen:getHeight())
    screen:paintTo(test_bb, 0, 0)

    local btns = screen.input_buttons
    assert.is_true(btns[1].dimen.x < btns[2].dimen.x)
    assert.is_true(btns[2].dimen.x < btns[3].dimen.x)
    assert.are.equal(btns[3].dimen.x, btns[4].dimen.x)
    assert.is_true(btns[4].dimen.x > btns[5].dimen.x)
    assert.is_true(btns[5].dimen.x > btns[6].dimen.x)
    assert.is_true(btns[6].dimen.x > btns[7].dimen.x)
    assert.are.equal(btns[7].dimen.x, btns[8].dimen.x)
    assert.is_true(btns[8].dimen.x < btns[9].dimen.x)

    local turn_conns = {}
    local function collectTurnConns(widget, visited)
      if type(widget) ~= "table" or visited[widget] then
        return
      end
      visited[widget] = true
      if
        widget[1]
        and type(widget[1].text) == "string"
        and widget[1].text:match("↓$")
        and widget.dimen
      then
        table.insert(turn_conns, widget)
      end
      for _, child in ipairs(widget) do
        collectTurnConns(child, visited)
      end
    end
    collectTurnConns(screen[1], {})

    assert.are.equal(2, #turn_conns)
    table.sort(turn_conns, function(a, b)
      return a.dimen.y < b.dimen.y
    end)
    assert.are.equal(btns[3].dimen.x, turn_conns[1].dimen.x)
    assert.are.equal(btns[7].dimen.x, turn_conns[2].dimen.x)

    UIManager:close(screen)
  end)

  it(
    "should navigate snake steps in order, grade per step, clear single marks, and switch from mode menu",
    function()
      local plugin = createMockPlugin()
      plugin:showPuzzle(Generator.getModeById("add_sub_100"))
      local menu = plugin:showModeSelection(plugin.screen)
      local target_item
      for _, item in ipairs(menu.item_table) do
        if item.text == Generator.getModeById("math_snake_100").title then
          target_item = item
          break
        end
      end
      assert.is_not_nil(target_item)
      target_item.callback()

      local screen = plugin.screen
      assert.are.equal("math_snake_100", screen.mode.id)
      assert.are.equal(11, #screen.problems)
      assert.are.equal(11, #screen.input_buttons)

      -- Sequential navigation along snake path 1..11 -> wrap to 1
      assert.are.equal(1, screen.focused_idx)
      for idx = 1, 11 do
        assert.are.equal(idx, screen.focused_idx)
        assert.are.equal(idx, screen.input_buttons[idx].prob_id)
        screen:nextField()
      end
      assert.are.equal(1, screen.focused_idx)

      -- Enter 10 correct answers and 1 wrong answer at step 4
      for idx = 1, 11 do
        local val = idx == 4 and (screen.problems[idx].answer + 1)
          or screen.problems[idx].answer
        screen.input_buttons[idx]:setText(tostring(val))
      end
      screen:checkAnswers()

      assert.are.equal(10, plugin.session_correct)
      assert.are.equal(1, plugin.session_wrong)
      assert.are.equal(" ✓", screen.mark_widgets[3].text)
      assert.is_truthy(screen.mark_widgets[4].text:find("✗"))
      assert.are.equal(" ✓", screen.mark_widgets[5].text)

      -- Editing step 4 clears only step 4's mark
      screen:selectField(4)
      screen:inputDigit("9")
      assert.are.equal("", screen.mark_widgets[4].text)
      assert.is_false(screen.problems[4].checked)
      assert.is_nil(screen.problems[4].is_correct)
      assert.are.equal(" ✓", screen.mark_widgets[3].text)
      assert.are.equal(" ✓", screen.mark_widgets[5].text)

      UIManager:close(menu)
      UIManager:close(screen)
    end
  )

  it(
    "should invoke digit and backspace callbacks from built keypad buttons",
    function()
      local screen = createScreen(nil, "add_sub_100")
      UIManager:show(screen)

      local is_input_btn = {}
      for _, btn in ipairs(screen.input_buttons) do
        is_input_btn[btn] = true
      end
      local keypad_buttons = {}
      local function collectKeypad(widget)
        if type(widget) ~= "table" then
          return
        end
        if widget.callback and widget.text and not is_input_btn[widget] then
          keypad_buttons[widget.text] = widget
        end
        for _, child in ipairs(widget) do
          collectKeypad(child)
        end
      end
      collectKeypad(screen[1])

      keypad_buttons["1"].callback()
      keypad_buttons["2"].callback()
      keypad_buttons["0"].callback()
      keypad_buttons["⌫"].callback()
      assert.are.equal("12", screen.problems[1].user_answer)
      assert.are.equal("12", screen.input_buttons[1].text)

      screen:selectField(2)
      keypad_buttons["3"].callback()
      keypad_buttons["4"].callback()
      keypad_buttons["5"].callback()
      assert.are.equal("345", screen.problems[2].user_answer)

      screen:selectField(3)
      keypad_buttons["6"].callback()
      keypad_buttons["7"].callback()
      keypad_buttons["8"].callback()
      keypad_buttons["9"].callback()
      assert.are.equal("6789", screen.problems[3].user_answer)

      UIManager:close(screen)
    end
  )
end)
