describe("Calculator main plugin module", function()
  local Calculator

  local function create_mock_calc()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    return Calculator:new({
      ui = mock_ui,
    })
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Calculator = require("plugins/calculator.koplugin/main")
  end)

  it("should initialize Calculator plugin instance", function()
    local calc = create_mock_calc()
    assert.is_table(calc)
    assert.is_string(calc.angle_mode)
    assert.is_string(calc.number_format)
  end)

  it("should format calculation results in various formats", function()
    local calc = create_mock_calc()

    assert.are.equal("42", calc:formatResult(42, "native"))
    assert.are.equal("true", calc:formatResult(true, "native"))
    assert.is_string(calc:formatResult(1234567, "scientific"))
    assert.is_string(calc:formatResult(1234567, "engineer"))
    assert.is_string(calc:formatResult(255, "programmer"))
  end)

  it("should evaluate and update calculation history", function()
    local calc = create_mock_calc()

    calc.history = ""
    calc:calculate("1 + 1")
    assert.is_true(calc.history:find("2") ~= nil)
  end)

  it("should dump and load calculator session to file", function()
    local calc = create_mock_calc()
    calc.input = { "1+1" }

    local tmp = os.tmpname()
    calc:dump(nil, tmp)

    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.is_true(content:find("1%+1") ~= nil)

    calc:load(nil, tmp)
    os.remove(tmp)
  end)

  it("should add main menu item structure", function()
    local calc = create_mock_calc()
    local menu_items = {}

    calc:addToMainMenu(menu_items)
    assert.is_table(menu_items.calculator)
    assert.is_function(menu_items.calculator.callback)
  end)
end)
