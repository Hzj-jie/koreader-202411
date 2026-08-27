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

  it("should assert when plugin is nil", function()
    assert.has_error(function()
      MathPuzzleScreen:new({
        mode = Generator.getModeById("add_sub_100"),
      })
    end)
  end)

  it("should initialize MathPuzzleScreen and build 10 question rows", function()
    local dummy_ui = { menu = { registerToMainMenu = function() end } }
    local plugin = MathPuzzle:new({ ui = dummy_ui })
    plugin:init()
    local mode = Generator.getModeById("add_sub_100")
    local screen = MathPuzzleScreen:new({
      plugin = plugin,
      mode = mode,
      question_count = 10,
    })
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)
    assert.are.equal(10, #screen.mark_widgets)
    assert.are.equal(10, #screen.mark_containers)
    assert.is_table(screen.title_bar_container)
    assert.is_table(screen.time_container)

    -- Verify answer checking
    for i, field in ipairs(screen.input_buttons) do
      field:setText(tostring(screen.problems[i].answer))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    -- Verify new problem generation
    screen:generateNewProblems()
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_buttons)

    -- Verify mode switching
    local mode_1000 = Generator.getModeById("add_sub_1000")
    screen:setMode(mode_1000)
    assert.are.equal("add_sub_1000", screen.mode.id)
    assert.are.equal(10, #screen.problems)

    -- Verify paintTo clears background and renders without errors
    local Device = require("device")
    local Blitbuffer = require("ffi/blitbuffer")
    local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
    screen:paintTo(test_bb, 0, 0)

    UIManager:close(screen)
  end)

  it("should display wrong marks and allow focus advancement", function()
    local dummy_ui = { menu = { registerToMainMenu = function() end } }
    local plugin = MathPuzzle:new({ ui = dummy_ui })
    plugin:init()
    local mode = Generator.getModeById("add_sub_10")
    local screen = MathPuzzleScreen:new({
      plugin = plugin,
      mode = mode,
      question_count = 10,
    })
    UIManager:show(screen)

    -- Answer first question correctly and rest wrongly
    screen.input_buttons[1]:setText(tostring(screen.problems[1].answer))
    for i = 2, 10 do
      screen.input_buttons[i]:setText(tostring(screen.problems[i].answer + 1))
    end
    screen:checkAnswers()

    assert.is_true(screen.problems[1].is_correct)
    assert.are.equal(" ✓", screen.mark_widgets[1].text)
    assert.is_false(screen.problems[2].is_correct)
    assert.is_truthy(screen.mark_widgets[2].text:find("✗"))

    -- Test field enter advancement
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

    -- Test keypad input and backspace
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

    -- Test keyboard navigation and input
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

    -- Test wrap-around navigation
    screen:selectField(10)
    screen:nextField()
    assert.are.equal(1, screen.focused_idx)
    screen:prevField()
    assert.are.equal(10, screen.focused_idx)

    UIManager:close(screen)
  end)

  it(
    "should initialize MathPuzzle plugin, register menu, and show mode selection",
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

      -- Trigger callback to open mode selection
      menu_items.mathpuzzle.callback()
      assert.is_true(#UIManager._window_stack > 0)
      local menu = UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_table(menu.item_table)
      assert.are.equal(#Generator.getModes(), #menu.item_table)
      assert.is_true(menu.is_borderless)

      -- Select a mode from the menu
      menu.item_table[2].callback()
      assert.is_table(plugin.screen)
      assert.are.equal("add_sub_100", plugin.active_mode)

      -- Verify TitleBar back button and session stats
      assert.are.equal("chevron.left", plugin.screen.title_bar.left_icon)
      assert.is_function(plugin.screen.title_bar.left_icon_tap_callback)

      -- Answer 7 correctly, 3 wrongly
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

      -- Test 1-minute time update event
      assert.is_table(plugin.screen.time_container)
      assert.is_table(plugin.screen.time_widget)
      plugin.session_start_time = os.time() - 60
      plugin.screen:onTimesChange_1M()
      assert.are.equal("Time: 1 minute", plugin.screen.time_widget.text)

      plugin.session_start_time = os.time() - 120
      plugin.screen:onTimesChange_1M()
      assert.are.equal("Time: 2 minutes", plugin.screen.time_widget.text)

      -- Close screen and verify timer state is reset
      UIManager:close(plugin.screen)
      assert.is_nil(plugin.screen)
      assert.is_nil(plugin.session_start_time)

      -- Reopen puzzle and verify new session timer starts fresh
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
      local dummy_ui = { menu = { registerToMainMenu = function() end } }
      local plugin = MathPuzzle:new({ ui = dummy_ui })
      plugin:init()
      local three_mode = Generator.getModeById("three_term_100")
      local screen = MathPuzzleScreen:new({
        plugin = plugin,
        mode = three_mode,
      })
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

      local dummy_ui = { menu = { registerToMainMenu = function() end } }
      local plugin = MathPuzzle:new({ ui = dummy_ui })
      plugin:init()
      local screen = MathPuzzleScreen:new({
        plugin = plugin,
        mode = Generator.getModeById("add_sub_100"),
      })
      UIManager:show(screen)

      local test_bb = Device.screen.bb or Blitbuffer.new(600, 800)
      screen:paintTo(test_bb, 0, 0)

      -- Top of screen tap gesture on empty title area (e.g. x = 300, y = 10)
      local top_tap = Event:new("Gesture", {
        ges = "tap",
        pos = Geom:new({ x = 300, y = 10 }),
      })
      UIManager:userInput(top_tap)
      assert.is_false(underlying_tapped)

      -- Bottom of screen tap gesture on empty margin (e.g. y = Device.screen:getHeight() - 5)
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

      -- Close screen
      UIManager:close(screen)
      UIManager:close(underlying)
    end
  )
end)
