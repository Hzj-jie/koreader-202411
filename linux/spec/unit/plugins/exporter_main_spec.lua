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

  describe("Defect verifications", function()
    it(
      "fails: exposes Share as ... callback crashing when getDocumentClippings returns empty table",
      function()
        local exp = create_mock_exporter()
        local shared_called = false
        local mock_target = {
          name = "markdown",
          shareable = true,
          getMenuTable = function()
            return { text = "Markdown" }
          end,
          isEnabled = function()
            return true
          end,
          share = function()
            shared_called = true
          end,
        }
        exp.targets["markdown"] = mock_target

        -- Stub getDocumentClippings to return empty table {}
        exp.getDocumentClippings = function()
          return {}
        end

        local menu_items = {}
        exp:addToMainMenu(menu_items)

        -- Find the "Share as Markdown" submenu entry
        local sub_item_table = menu_items.exporter.sub_item_table
        local share_entry = nil
        for _, item in ipairs(sub_item_table) do
          if item.sub_item_table then
            for _, sub in ipairs(item.sub_item_table) do
              if sub.text and sub.text:match("Share as markdown") then
                share_entry = sub
                break
              end
            end
          end
        end

        assert.is_not_nil(share_entry)
        assert.is_function(share_entry.callback)

        -- Calling the callback when getDocumentClippings() returns {}
        -- crashes at line 292:
        --   for _, notes in pairs(clippings) do document = notes or {} end
        --   if #document > 0 then ... end
        -- Because clippings is {}, the loop does not run and document is nil.
        -- #document throws: attempt to get length of local 'document' (a nil value).
        -- The test asserts that calling the callback succeeds without throwing a nil-length error.
        local ok, err = pcall(share_entry.callback)
        assert.is_true(
          ok,
          "Share as callback should not crash when clippings is empty: "
            .. tostring(err)
        )
        assert.is_false(shared_called)
      end
    )
  end)
end)
