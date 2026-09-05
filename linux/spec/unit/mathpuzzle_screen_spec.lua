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

  local function createScreen(plugin, mode_id, question_count)
    plugin = plugin or createMockPlugin()
    local mode = Generator.getModeById(mode_id or "add_sub_100")
    return MathPuzzleScreen:new({
      plugin = plugin,
      mode = mode,
      question_count = question_count or 10,
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
    local screen = createScreen(nil, "add_sub_100", 10)
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

  it("should verify correct answers and update question marks", function()
    local screen = createScreen(nil, "add_sub_100", 10)
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
    local screen = createScreen(nil, "add_sub_100", 10)
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
    local screen = createScreen(nil, "add_sub_100", 10)
    UIManager:show(screen)

    local Device = require("device")
    local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
    screen:paintTo(test_bb, 0, 0)

    UIManager:close(screen)
  end)

  it("should display correct and wrong marks on answer check", function()
    local screen = createScreen(nil, "add_sub_10", 10)
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
      local screen = createScreen(nil, "add_sub_10", 10)
      UIManager:show(screen)

      screen:onFieldEnter(1)
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
    local screen = createScreen(nil, "add_sub_10", 10)
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

  it(
    "should handle keyboard navigation, slashes, and repeat backspace",
    function()
      local screen = createScreen(nil, "add_sub_10", 10)
      UIManager:show(screen)

      screen:selectField(3)
      screen.input_buttons[3]:setText("4")
      screen:onKeyPress({ key = "9" })
      assert.are.equal("49", screen.problems[3].user_answer)
      screen:onKeyPress("Tab")
      assert.are.equal(4, screen.focused_idx)
      screen.input_buttons[4]:setText("")
      screen:onTextInput("7")
      screen:onKeyPress("/")
      screen:inputDigit("8")
      assert.are.equal("7/8", screen.problems[4].user_answer)
      screen:onKeyRepeat("BackSpace")
      assert.are.equal("7/", screen.problems[4].user_answer)

      UIManager:close(screen)
    end
  )

  it("should wrap around field navigation at boundaries", function()
    local screen = createScreen(nil, "add_sub_10", 10)
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
      assert.are.equal("add_sub_100", plugin.active_mode)
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

      plugin:showPuzzle()
      assert.is_table(plugin.screen)
      assert.is_number(plugin.session_start_time)
      assert.are.equal("Time: 0 minutes", plugin.screen:getTimeText())
      UIManager:close(plugin.screen)
    end
  )

  it(
    "should support 5-question single column layout for 3-term mental math",
    function()
      local screen = createScreen(nil, "three_term_100", 5)
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

      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
    local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
      local screen = createScreen(nil, "add_sub_100", 10)
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
    local screen = createScreen(nil, "add_sub_100", 10)
    UIManager:show(screen)

    screen:selectField(1)
    for _ = 1, 10 do
      screen:inputDigit("8")
    end
    assert.are.equal("888888", screen.problems[1].user_answer)
    assert.are.equal(6, #screen.problems[1].user_answer)

    UIManager:close(screen)
  end)

  it("should wrap around field navigation with nextField and prevField", function()
    local screen = createScreen(nil, "add_sub_100", 10)
    UIManager:show(screen)

    assert.are.equal(1, screen.focused_idx)

    screen:prevField()
    assert.are.equal(10, screen.focused_idx)

    screen:nextField()
    assert.are.equal(1, screen.focused_idx)

    screen:selectField(5)
    screen:onFieldEnter(nil)
    assert.are.equal(6, screen.focused_idx)

    UIManager:close(screen)
  end)

  it("should filter non-digit characters in onTextInput", function()
    local screen = createScreen(nil, "add_sub_100", 10)
    UIManager:show(screen)

    screen:selectField(1)
    assert.is_false(screen:onTextInput("abc"))
    assert.is_false(screen:onTextInput("+"))
    assert.is_false(screen:onTextInput(" "))
    assert.are.equal("", screen.problems[1].user_answer)

    assert.is_true(screen:onTextInput("7"))
    assert.are.equal("7", screen.problems[1].user_answer)

    UIManager:close(screen)
  end)

  it("should handle navigation and deletion keys via onKeyPress and onKeyRepeat", function()
    local screen = createScreen(nil, "add_sub_100", 10)
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
  end)

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

  it("should trigger mode switch callback when selected from showModeSelection", function()
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

    assert.are.equal("three_term_100", plugin.active_mode)
    assert.are.equal("three_term_100", plugin.screen.mode.id)
    assert.are.equal(5, #plugin.screen.problems)

    UIManager:close(menu)
    UIManager:close(plugin.screen)
  end)
end)
