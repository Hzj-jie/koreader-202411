-- luacheck: ignore 122
describe("Exporter Main plugin module", function()
  local Exporter, Dispatcher, G_reader_settings_orig

  setup(function()
    require("commonrequire")
    Exporter = require("plugins/exporter.koplugin/main")
    Dispatcher = require("dispatcher")
  end)

  before_each(function()
    G_reader_settings:save("exporter", {})
  end)

  local function create_mock_exporter()
    local exp = Exporter:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
        document = {
          file = "/tmp/test_book.epub",
        },
        view = {},
        annotation = {
          updatePageNumbers = function() end,
        },
      },
    })
    exp.targets = {}
    return exp
  end

  describe("Lifecycle and dispatcher actions", function()
    it("registers dispatcher actions for current and all notes", function()
      local exp = create_mock_exporter()
      exp:onDispatcherRegisterActions()

      assert.is_not_nil(Dispatcher:getNameFromItem("export_current_notes"))
      assert.is_not_nil(Dispatcher:getNameFromItem("export_all_notes"))
    end)

    it("evaluates readiness checks based on targets and doc state", function()
      local exp = create_mock_exporter()
      assert.is_false(exp:isReady())
      assert.is_true(exp:isDocReady())
      assert.is_false(exp:isReadyToExport())

      local mock_target = {
        isEnabled = function()
          return true
        end,
        is_remote = false,
      }
      exp.targets["text"] = mock_target
      assert.is_true(exp:isReady())
      assert.is_true(exp:isReadyToExport())
      assert.is_falsy((exp:requiresNetwork()))

      mock_target.is_remote = true
      assert.is_true(exp:requiresNetwork())
    end)
  end)

  describe("Menu construction and style toggles", function()
    it("builds main menu submenus for formats and highlight styles", function()
      local exp = create_mock_exporter()
      local mock_target = {
        name = "html",
        getMenuTable = function()
          return { text = "HTML" }
        end,
        isEnabled = function()
          return true
        end,
      }
      exp.targets["html"] = mock_target

      local menu_items = {}
      exp:addToMainMenu(menu_items)

      assert.is_table(menu_items.exporter)
      assert.is_table(menu_items.exporter.sub_item_table)
    end)
  end)
end)
