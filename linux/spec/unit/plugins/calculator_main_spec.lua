describe("Calculator main plugin module", function()
  local Calculator, Parser, UIManager, VirtualKeyboard, Font

  local function create_mock_calc(settings)
    settings = settings or {}
    local highlight_items = {}
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
      highlight = {
        addToHighlightDialog = function(self_h, id, func)
          highlight_items[id] = func
        end,
      },
    }
    local calc = Calculator:new({
      ui = mock_ui,
      use_init_file = settings.use_init_file or "no",
      init_file = "plugins/calculator.koplugin/init.calc",
    })
    calc._highlight_items = highlight_items
    return calc
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    package.preload["ui/data/keyboardlayouts/calc_keyboard"] = function()
      return require(
        "plugins/calculator.koplugin/ui/data/keyboardlayouts/calc_keyboard"
      )
    end

    Calculator = require("plugins/calculator.koplugin/main")
    Parser = require("plugins/calculator.koplugin/formulaparser/formulaparser")
    UIManager = require("ui/uimanager")
    VirtualKeyboard = require("ui/widget/virtualkeyboard")
    Font = require("ui/font")
  end)

  teardown(function()
    package.preload["ui/data/keyboardlayouts/calc_keyboard"] = nil
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it(
    "should initialize Calculator plugin and register actions / highlight callbacks",
    function()
      local calc = create_mock_calc({ use_init_file = "no" })
      calc:init()

      assert.is_table(calc)
      assert.is_string(calc.angle_mode)
      assert.is_string(calc.number_format)
      assert.is_function(calc.onDispatcherRegisterActions)
      calc:onDispatcherRegisterActions()

      -- Test highlight dialog button callback
      assert.is_function(calc._highlight_items["13_convert"])
      local mock_highlight = {
        selected_text = { text = "125.5 mm" },
        onExit = function() end,
      }
      local btn_def = calc._highlight_items["13_convert"](mock_highlight)
      assert.is_table(btn_def)
      assert.is_true(btn_def.show_in_highlight_dialog_func())

      mock_highlight.selected_text.text = "no number here"
      assert.is_false(btn_def.show_in_highlight_dialog_func())
    end
  )

  it("should manage virtual keyboard layouts", function()
    local calc = create_mock_calc()
    calc:addKeyboard()
    assert.are.equal(
      "calc_keyboard",
      VirtualKeyboard.lang_to_keyboard_layout["Calculator"]
    )
    calc:restoreKeyboard()
    assert.is_nil(VirtualKeyboard.lang_to_keyboard_layout["Calculator"])
  end)

  it("should format string tables and status line", function()
    local calc = create_mock_calc()
    assert.are.equal("Degree", calc:getString("degree", calc.angle_modes))
    assert.are.equal(
      "default",
      calc:getString("unknown_mode", calc.angle_modes)
    )

    local status = calc:getStatusLine()
    assert.is_string(status)
    assert.is_true(status:find("Format:") ~= nil)

    local tab_expanded = calc:expandTabs("A\tB\tC", 4)
    assert.are.equal("A    B    C", tab_expanded)
  end)

  it(
    "should insert braces for math functions and balance parentheses",
    function()
      local calc = create_mock_calc()

      assert.are.equal("sin( 45)", calc:insertBraces("sin 45"))
      assert.are.equal("cos( 30)", calc:insertBraces("cos 30"))
      assert.are.equal("sqrt( 16)", calc:insertBraces("sqrt 16"))
      assert.are.equal("√(4)", calc:insertBraces("√4"))
      assert.are.equal("(2 + 3)", calc:insertBraces("(2 + 3"))
      assert.are.equal("1E5", calc:insertBraces("1EE5"))
    end
  )

  it(
    "should format mantissa, exponent, and results across all formats",
    function()
      local calc = create_mock_calc()

      -- formatMantissaExponent
      assert.are.equal("0", calc:formatMantissaExponent(0, false))
      assert.is_string(calc:formatMantissaExponent(123456, false))
      assert.is_string(calc:formatMantissaExponent(123456, true)) -- engineering mode

      -- formatResult
      assert.is_nil(calc:formatResult(nil, "auto"))
      assert.are.equal("42", calc:formatResult(42, "native"))
      assert.are.equal("true", calc:formatResult(true, "native"))
      assert.are.equal("false", calc:formatResult(false, "native"))
      assert.are.equal("inf", calc:formatResult(1 / 0, "auto"))

      -- Scientific format
      local sci = calc:formatResult(1234567, "scientific")
      assert.is_true(sci:find("E") ~= nil)

      -- Engineer format
      local eng = calc:formatResult(1234567, "engineer")
      assert.is_true(eng:find("E") ~= nil)

      -- Auto format for small and large values
      local auto_norm = calc:formatResult(12.345, "auto")
      assert.is_string(auto_norm)
      local auto_large = calc:formatResult(10000000, "auto")
      assert.is_true(auto_large:find("E") ~= nil)

      -- Programmer format
      local prog = calc:formatResult(255, "programmer")
      assert.is_true(prog:find("0x") ~= nil)
    end
  )

  it(
    "should evaluate calculations, update history, and handle errors",
    function()
      local calc = create_mock_calc()
      calc.history = ""
      calc.input = {}

      -- 1. No input difference
      calc:calculate("")
      assert.are.equal("", calc.history)

      -- 2. Space command
      calc:calculate(" ")
      assert.are.equal("", calc.history)

      -- 3. Simple addition
      calc:calculate("2 + 3")
      assert.is_true(calc.history:find("5") ~= nil)

      -- 4. Follow up calculation using ans
      calc:calculate(calc.history .. "\nans * 2")
      assert.is_true(calc.history:find("10") ~= nil)

      -- 5. Command returning string / help
      calc:calculate(calc.history .. "\nhelp()")
      assert.is_true(#calc.history > 0)

      -- 6. Syntax error handling
      calc:calculate(calc.history .. "\n2 ++ * 3")
    end
  )

  it(
    "should open input dialog and exercise dialog buttons and callbacks",
    function()
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      local shown_widgets = {}
      UIManager.show = function(self_uim, w)
        table.insert(shown_widgets, w)
      end
      UIManager.close = function() end

      local calc = create_mock_calc()
      calc:onCalculatorStart()

      assert.is_table(calc.input_dialog)
      local dlg = calc.input_dialog
      assert.is_table(dlg.buttons)

      -- Test gotoEnd
      calc:gotoEnd()

      -- Test Convert button ("♺")
      dlg.buttons[1][1].callback()
      assert.is_table(calc.convert_dialog)

      -- Test Clear button ("⎚")
      dlg.buttons[1][2].callback()
      assert.are.equal("", calc.history)
      assert.are.equal(0, #calc.input)

      -- Test Load button ("⇧")
      dlg.buttons[1][3].callback()
      local confirm_load = shown_widgets[#shown_widgets]
      assert.is_table(confirm_load)
      if confirm_load.choice2_callback then
        confirm_load.choice2_callback()
      end

      -- Test Store button ("⇩")
      dlg.buttons[1][4].callback()
      local confirm_store = shown_widgets[#shown_widgets]
      assert.is_table(confirm_store)
      if confirm_store.choice2_callback then
        confirm_store.choice2_callback()
      end

      -- Test Settings button ("☰")
      dlg.buttons[1][5].callback()
      assert.is_table(calc.settings_dialog)

      -- Test Cancel button ("✕")
      dlg.buttons[1][6].callback()

      -- Test enter_callback
      dlg:setInputText("10 + 20")
      dlg.enter_callback()
      assert.is_true(calc.history:find("30") ~= nil)

      -- Test view_pos_callback
      dlg.view_pos_callback(2, 5)
      local line, col = dlg.view_pos_callback()
      assert.are.equal(2, line)
      assert.are.equal(5, col)

      UIManager.show = orig_show
      UIManager.close = orig_close
    end
  )

  it("should handle convertUnit with numeric strings", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function() end
    UIManager.close = function() end

    local calc = create_mock_calc()
    calc:convertUnit("100 km\nignored line")
    assert.is_table(calc.convert_dialog)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should dump and load session and handle invalid files", function()
    local calc = create_mock_calc()
    calc.input = { "5 + 5" }

    local tmp = os.tmpname()
    calc:dump(nil, tmp)

    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.is_true(content:find("5 %+ 5") ~= nil)

    calc:load(nil, tmp)
    os.remove(tmp)

    -- Non-existent files
    calc:load(nil, "/non/existent/path/input.calc")
    calc:dump(nil, "/non/existent/path/output.calc")
  end)

  it("should add main menu item structure", function()
    local calc = create_mock_calc()
    local menu_items = {}

    calc:addToMainMenu(menu_items)
    assert.is_table(menu_items.calculator)
    assert.is_function(menu_items.calculator.callback)
  end)

  it(
    "should persist valid file paths in settings on init [exposes production bug in Calculator:init()]",
    function()
      local saved_settings = {}
      local old_save = G_reader_settings.save
      G_reader_settings.save = function(self_s, key, val)
        saved_settings[key] = val
      end

      local calc = create_mock_calc()
      calc:init()

      -- Production bug: init() uses self.output_path and self.input_path
      -- which are nil and {}, rather than self.calculator_output_path
      -- and self.calculator_input_path
      assert.is_string(saved_settings["calculator_output_path"])
      assert.are.equal(
        calc.calculator_output_path,
        saved_settings["calculator_output_path"]
      )
      assert.is_string(saved_settings["calculator_input_path"])
      assert.are.equal(
        calc.calculator_input_path,
        saved_settings["calculator_input_path"]
      )

      G_reader_settings.save = old_save
    end
  )

  it(
    "should invoke load instead of dump on input dialog Load button [exposes production bug in Calculator:generateInputDialog()]",
    function()
      local dump_called = false
      local load_called = false
      local old_show = UIManager.show
      local shown_confirm
      UIManager.show = function(self_u, w)
        shown_confirm = w
      end

      local calc = create_mock_calc()
      calc.dump = function()
        dump_called = true
      end
      calc.load = function()
        load_called = true
      end

      local dlg = calc:generateInputDialog("status")
      local load_btn = dlg.buttons[1][3]
      assert.are.equal("⇧", load_btn.text)
      load_btn.callback()

      assert.is_not_nil(shown_confirm)
      assert.is_function(shown_confirm.choice2_callback)
      shown_confirm.choice2_callback()

      -- Production bug: choice2_callback invokes self:dump instead of self:load
      assert.is_true(load_called)
      assert.is_false(dump_called)

      UIManager.show = old_show
    end
  )

  it(
    "should format negative numbers with symmetric decimal precision in auto format [exposes production bug in Calculator:formatResult()]",
    function()
      local calc = create_mock_calc()
      -- Positive 123.45678 gets 5 decimal places because val > 1 is true
      assert.are.equal("123.45678", calc:formatResult(123.45678, "auto"))

      -- Production bug: formatResult checks `val > 1` instead of `math.abs(val) > 1`.
      -- For negative numbers like -123.45678, `val > 1` is false, causing msp = 2
      -- and rounding to only 4 decimal places ("-123.4568") instead of 5 ("-123.45678")
      assert.are.equal("-123.45678", calc:formatResult(-123.45678, "auto"))
    end
  )
end)
