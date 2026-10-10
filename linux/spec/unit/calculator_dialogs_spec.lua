-- luacheck: ignore 122
local CalculatorSettingsDialog
local CalculatorUnitsDialog
local InputDialog
local PathChooser
local UIManager

describe("Calculator dialogs", function()
  setup(function()
    require("commonrequire")
    InputDialog = require("ui/widget/inputdialog")
    PathChooser = require("ui/widget/pathchooser")
    UIManager = require("ui/uimanager")

    local ok1, mod1 = pcall(require, "calculatorunitsdialog")
    if not ok1 then
      mod1 = require("plugins/calculator.koplugin/calculatorunitsdialog")
    end
    CalculatorUnitsDialog = mod1

    local ok2, mod2 = pcall(require, "calculatorsettingsdialog")
    if not ok2 then
      mod2 = require("plugins/calculator.koplugin/calculatorsettingsdialog")
    end
    CalculatorSettingsDialog = mod2
  end)

  it(
    "configures unit conversion scale for inches to meters correctly",
    function()
      assert.is_table(CalculatorUnitsDialog.units)
      assert.are.equal("cm", CalculatorUnitsDialog.units[1][1])
      assert.are.equal(0.01, CalculatorUnitsDialog.units[1][2])

      assert.are.equal("inch", CalculatorUnitsDialog.units[2][1])
      -- 1 inch = 0.0254 meters.
      -- In production line 37: units = { { "cm", 0.01 }, { "inch", 254 } }.
      -- 254 is off by a factor of 10,000x compared to 0.0254.
      assert.are.equal(0.0254, CalculatorUnitsDialog.units[2][2])
    end
  )

  it(
    "normalizes trailing slash when creating input dialog for directory path",
    function()
      local orig_inputdialog_new = InputDialog.new
      local orig_pathchooser_new = PathChooser.new
      local orig_uimanager_show = UIManager.show
      local captured_input

      UIManager.show = function() end

      InputDialog.new = function(self, args)
        captured_input = args.input
        return {
          getInputText = function()
            return args.input
          end,
        }
      end

      PathChooser.new = function(self, args)
        -- Simulate choosing an existing directory that ends with "/"
        args.onConfirm("/tmp/")
        return {}
      end

      local dlg = {
        calculator_input_path = "/tmp/",
        parent = { settings = {} },
      }

      -- choosePathFile(menu, key, folder_only, new_file, migrate)
      -- When dir_path already ends with "/", line 376 executes `input = dir_path .. "/"`,
      -- producing redundant double slash "/tmp//".
      CalculatorSettingsDialog.choosePathFile(
        dlg,
        nil,
        "calculator_input_path",
        false,
        true,
        nil
      )

      InputDialog.new = orig_inputdialog_new
      PathChooser.new = orig_pathchooser_new
      UIManager.show = orig_uimanager_show

      assert.is_not_nil(captured_input)
      assert.is_nil(
        captured_input:match("//"),
        "Redundant double slash found in input: " .. tostring(captured_input)
      )
    end
  )
end)
