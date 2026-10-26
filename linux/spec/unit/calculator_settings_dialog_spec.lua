-- luacheck: ignore 122
local CalculatorSettingsDialog
local InputDialog
local PathChooser
local UIManager

describe("CalculatorSettingsDialog", function()
  setup(function()
    require("commonrequire")
    InputDialog = require("ui/widget/inputdialog")
    PathChooser = require("ui/widget/pathchooser")
    UIManager = require("ui/uimanager")

    local ok, mod = pcall(require, "calculatorsettingsdialog")
    if not ok then
      mod = require("plugins/calculator.koplugin/calculatorsettingsdialog")
    end
    CalculatorSettingsDialog = mod
  end)

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
