describe("MathPuzzle Screen and Plugin", function()
  local MathPuzzle
  local MathPuzzleScreen
  local Generator
  local UIManager

  setup(function()
    require("commonrequire")
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
  end)

  it("should initialize MathPuzzleScreen and build 10 question rows", function()
    local mode = Generator.getModeById("add_sub_100")
    local screen = MathPuzzleScreen:new({
      mode = mode,
      question_count = 10,
    })
    UIManager:show(screen)

    assert.is_table(screen.problems)
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_fields)
    assert.are.equal(10, #screen.mark_widgets)

    -- Verify answer checking
    for i, field in ipairs(screen.input_fields) do
      field:setText(tostring(screen.problems[i].answer))
    end
    screen:checkAnswers()

    for _, prob in ipairs(screen.problems) do
      assert.is_true(prob.is_correct)
    end

    -- Verify new problem generation
    screen:generateNewProblems()
    assert.are.equal(10, #screen.problems)
    assert.are.equal(10, #screen.input_fields)

    -- Verify mode switching
    local mode_1000 = Generator.getModeById("add_sub_1000")
    screen:setMode(mode_1000)
    assert.are.equal("add_sub_1000", screen.mode.id)
    assert.are.equal(10, #screen.problems)

    UIManager:close(screen)
  end)

  it("should display wrong marks and allow focus advancement", function()
    local mode = Generator.getModeById("add_sub_10")
    local screen = MathPuzzleScreen:new({
      mode = mode,
      question_count = 10,
    })
    UIManager:show(screen)

    -- Answer first question correctly and rest wrongly
    screen.input_fields[1]:setText(tostring(screen.problems[1].answer))
    for i = 2, 10 do
      screen.input_fields[i]:setText(tostring(screen.problems[i].answer + 1))
    end
    screen:checkAnswers()

    assert.is_true(screen.problems[1].is_correct)
    assert.are.equal(" ✓", screen.mark_widgets[1].text)
    assert.is_false(screen.problems[2].is_correct)
    assert.is_truthy(screen.mark_widgets[2].text:find("✗"))

    -- Test field enter advancement
    screen:onFieldEnter(1)
    assert.are.equal(2, screen.focused_idx)

    -- Test keypad input and backspace
    screen:selectField(3)
    assert.are.equal(3, screen.focused_idx)
    screen.input_fields[3]:setText("")
    screen:inputDigit("4")
    screen:inputDigit("2")
    assert.are.equal("42", screen.problems[3].user_answer)
    screen:backspace()
    assert.are.equal("4", screen.problems[3].user_answer)

    -- Test keyboard navigation
    screen:onKeyDown("9")
    assert.are.equal("49", screen.problems[3].user_answer)
    screen:onKeyDown("Tab")
    assert.are.equal(4, screen.focused_idx)
    screen:onKeyDown("BackSpace")
    screen:prevField()
    assert.are.equal(3, screen.focused_idx)

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
      assert.is_true(menu.covers_fullscreen)
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
        plugin.screen.input_fields[i]:setText(
          tostring(plugin.screen.problems[i].answer)
        )
      end
      for i = 8, 10 do
        plugin.screen.input_fields[i]:setText(
          tostring(plugin.screen.problems[i].answer + 1)
        )
      end
      plugin.screen:checkAnswers()

      assert.are.equal(7, plugin.session_correct)
      assert.are.equal(3, plugin.session_wrong)
      assert.is_string(plugin.screen:getFormattedTime())
      assert.is_truthy(plugin.screen:getHeaderStatsText():find("Correct: 7"))
      assert.is_truthy(plugin.screen:getHeaderStatsText():find("Wrong: 3"))
      assert.is_truthy(plugin.screen:getHeaderStatsText():find("Score: 70%%"))

      -- Start a new round and answer 10 correctly
      plugin.screen:generateNewProblems()
      for i = 1, 10 do
        plugin.screen.input_fields[i]:setText(
          tostring(plugin.screen.problems[i].answer)
        )
      end
      plugin.screen:checkAnswers()

      assert.are.equal(17, plugin.session_correct)
      assert.are.equal(3, plugin.session_wrong)
      assert.is_truthy(plugin.screen:getHeaderStatsText():find("Score: 85%%"))

      UIManager:close(plugin.screen)
    end
  )
end)
