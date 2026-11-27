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

    it(
      "omits remote targets and still writes local exports when Device:hasNetwork() is false",
      function()
        local Device = require("device")
        local UIManager = require("ui/uimanager")
        local ffiUtil = require("ffi/util")
        local gettext = require("gettext")
        local lfs = require("libs/libkoreader-lfs")
        local orig_has_network = Device.hasNetwork
        local orig_main = package.loaded["plugins/exporter.koplugin/main"]
        local orig_net = package.loaded["ui/network/manager"]
        local orig_readwise =
          package.loaded["plugins/exporter.koplugin/target/readwise"]
        local orig_text =
          package.loaded["plugins/exporter.koplugin/target/text"]
        local tmp_dir = os.tmpname()
        os.remove(tmp_dir)
        assert(lfs.mkdir(tmp_dir))
        local shown = {}
        local show_stub = stub(UIManager, "show", function(_self, widget)
          table.insert(shown, widget)
        end)
        finally(function()
          show_stub:revert()
          Device.hasNetwork = orig_has_network
          package.loaded["plugins/exporter.koplugin/main"] = orig_main
          package.loaded["ui/network/manager"] = orig_net
          package.loaded["plugins/exporter.koplugin/target/readwise"] =
            orig_readwise
          package.loaded["plugins/exporter.koplugin/target/text"] = orig_text
          ffiUtil.purgeDir(tmp_dir)
        end)

        G_reader_settings:save("exporter", {
          clipping_dir = tmp_dir,
          readwise = { enabled = true, token = "tok" },
          text = { enabled = true },
        })

        Device.hasNetwork = function()
          return false
        end
        package.loaded["ui/network/manager"] = nil
        package.loaded["plugins/exporter.koplugin/target/readwise"] = nil
        package.loaded["plugins/exporter.koplugin/target/text"] = nil
        package.loaded["plugins/exporter.koplugin/main"] = nil
        local NoNetExporter = require("plugins/exporter.koplugin/main")

        for _, name in ipairs({
          "flomo",
          "joplin",
          "memos",
          "nextcloud",
          "readwise",
          "xmnote",
        }) do
          assert.is_nil(NoNetExporter.targets[name])
        end
        for _, name in ipairs({
          "html",
          "json",
          "markdown",
          "my_clippings",
          "text",
        }) do
          assert.is_table(NoNetExporter.targets[name])
        end

        local exp = NoNetExporter:new({
          ui = {
            menu = { registerToMainMenu = function() end },
            document = { file = tmp_dir .. "/book.epub" },
            view = {},
            annotation = { updatePageNumbers = function() end },
          },
        })
        assert.is_falsy((exp:requiresNetwork()))

        local menu_items = {}
        exp:addToMainMenu(menu_items)
        local formats_item
        for _, item in ipairs(menu_items.exporter.sub_item_table) do
          if item.text == gettext("Choose formats and services") then
            formats_item = item
            break
          end
        end
        assert.is_table(formats_item)
        assert.are.equal(5, #formats_item.sub_item_table)

        exp:exportClippings({
          ["Test Book"] = {
            title = "Test Book",
            output_filename = "Test Book",
            file = tmp_dir .. "/book.epub",
            {
              {
                page = 1,
                time = 1700000000,
                text = "Hello local export",
              },
            },
          },
        })
        assert.are.equal(1, #shown)
        local exported_file
        for entry in lfs.dir(tmp_dir) do
          if entry:match("%.txt$") then
            exported_file = tmp_dir .. "/" .. entry
            break
          end
        end
        assert.is_string(exported_file)
        local f = assert(io.open(exported_file, "r"))
        local content = f:read("*a")
        f:close()
        assert.is_truthy(content:find("Hello local export", 1, true))

        Device.hasNetwork = function()
          return true
        end
        package.loaded["plugins/exporter.koplugin/main"] = nil
        local NetExporter = require("plugins/exporter.koplugin/main")
        assert.is_table(NetExporter.targets.readwise)
      end
    )
  end)
end)
