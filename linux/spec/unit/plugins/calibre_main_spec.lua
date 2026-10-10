-- luacheck: ignore 122
describe("Calibre plugin main module", function()
  local Calibre, CalibreWireless, CalibreExtensions, CalibreSearch
  local Dispatcher, UIManager, MultiInputDialog

  setup(function()
    require("commonrequire")
    Calibre = require("plugins/calibre.koplugin/main")
    CalibreWireless = require("plugins/calibre.koplugin/wireless")
    CalibreExtensions = require("plugins/calibre.koplugin/extensions")
    CalibreSearch = require("plugins/calibre.koplugin/search")
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")
    MultiInputDialog = require("ui/widget/multiinputdialog")
  end)

  describe("Lifecycle and event handlers", function()
    it(
      "initializes plugin, registers dispatcher actions and main menu",
      function()
        local registered_plugin
        local mock_ui = {
          menu = {
            registerToMainMenu = function(_, plugin)
              registered_plugin = plugin
            end,
          },
        }
        local plugin = Calibre:new({ ui = mock_ui })

        local orig_init = CalibreWireless.init
        local wireless_inited = false
        CalibreWireless.init = function()
          wireless_inited = true
        end
        finally(function()
          CalibreWireless.init = orig_init
        end)

        plugin:init()
        assert.is_true(wireless_inited)
        assert.are.equal(plugin, registered_plugin)

        assert.are.equal(
          "Calibre metadata search",
          Dispatcher:getNameFromItem("calibre_search")
        )
        assert.are.equal(
          "Browse all calibre tags",
          Dispatcher:getNameFromItem("calibre_browse_tags")
        )
        assert.are.equal(
          "Calibre wireless connect",
          Dispatcher:getNameFromItem("calibre_start_connection")
        )
      end
    )

    it(
      "triggers CalibreSearch on onCalibreSearch and onCalibreBrowseBy",
      function()
        local plugin = Calibre:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        local search_shown = false
        local orig_show = CalibreSearch.ShowSearch
        CalibreSearch.ShowSearch = function()
          search_shown = true
        end

        local browse_field = nil
        local orig_find = CalibreSearch.find
        CalibreSearch.find = function(_, field)
          browse_field = field
        end

        finally(function()
          CalibreSearch.ShowSearch = orig_show
          CalibreSearch.find = orig_find
        end)

        assert.is_true(plugin:onCalibreSearch())
        assert.is_true(search_shown)

        assert.is_true(plugin:onCalibreBrowseBy("series"))
        assert.are.equal("series", browse_field)
        assert.are.equal("", CalibreSearch.search_value)
      end
    )

    it(
      "invokes closeWirelessConnection on network disconnect, suspend, and exit",
      function()
        local plugin = Calibre:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        local closed_count = 0
        local orig_close = plugin.closeWirelessConnection
        plugin.closeWirelessConnection = function()
          closed_count = closed_count + 1
        end
        finally(function()
          plugin.closeWirelessConnection = orig_close
        end)

        plugin:onNetworkDisconnected()
        plugin:onSuspend()
        plugin:onExit()
        plugin:onCloseWirelessConnection()
        assert.are.equal(4, closed_count)
      end
    )

    it(
      "connects wireless socket on onStartWirelessConnection when not connected",
      function()
        local plugin = Calibre:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        local connect_called = false
        local orig_connect = CalibreWireless.connect
        CalibreWireless.connect = function()
          connect_called = true
        end
        local orig_socket = CalibreWireless.calibre_socket
        CalibreWireless.calibre_socket = nil

        finally(function()
          CalibreWireless.connect = orig_connect
          CalibreWireless.calibre_socket = orig_socket
        end)

        plugin:onStartWirelessConnection()
        assert.is_true(connect_called)

        connect_called = false
        CalibreWireless.calibre_socket = {}
        plugin:onStartWirelessConnection()
        assert.is_false(connect_called)
      end
    )
  end)

  describe("Menu tables and UI integration", function()
    it("builds main menu table for FileManager and Reader", function()
      local fm_plugin = Calibre:new({
        ui = { menu = { registerToMainMenu = function() end }, view = nil },
      })
      local menu_items = {}
      fm_plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.calibre)
      assert.is_table(menu_items.find_book_in_calibre_catalog)

      local reader_plugin = Calibre:new({
        ui = { menu = { registerToMainMenu = function() end }, view = {} },
      })
      G_reader_settings:save("calibre_search_from_reader", false)
      menu_items = {}
      reader_plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.calibre)
      assert.is_nil(menu_items.find_book_in_calibre_catalog)

      G_reader_settings:save("calibre_search_from_reader", true)
      menu_items = {}
      reader_plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.find_book_in_calibre_catalog)
    end)

    it("constructs search settings menu table", function()
      local plugin =
        Calibre:new({ ui = { menu = { registerToMainMenu = function() end } } })
      local search_menu = plugin:getSearchMenuTable()
      assert.is_table(search_menu)

      local found_libs, found_caching, found_case, found_search_title =
        false, false, false, false
      for _, item in ipairs(search_menu) do
        if item.text and item.text:find("Manage libraries") then
          found_libs = true
        elseif item.text and item.text:find("Store metadata in cache") then
          found_caching = true
        elseif item.text and item.text:find("Case sensitive") then
          found_case = true
        elseif item.text and item.text:find("Search by title") then
          found_search_title = true
        end
      end
      assert.is_true(found_libs)
      assert.is_true(found_caching)
      assert.is_true(found_case)
      assert.is_true(found_search_title)
    end)

    it("constructs wireless settings menu table with File formats", function()
      local plugin =
        Calibre:new({ ui = { menu = { registerToMainMenu = function() end } } })
      local orig_isCustom = CalibreExtensions.isCustom
      CalibreExtensions.isCustom = function()
        return false
      end
      finally(function()
        CalibreExtensions.isCustom = orig_isCustom
      end)

      local wireless_menu = plugin:getWirelessMenuTable()
      assert.is_table(wireless_menu)

      local found_formats = false
      for _, item in ipairs(wireless_menu) do
        if item.text and item.text:find("File formats") then
          found_formats = true
          break
        end
      end
      assert.is_true(found_formats)
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes closeWirelessConnection calling non-existent CalibreWireless:disconnect()",
      function()
        local plugin = Calibre:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        local dummy_socket = { stop = function() end }
        CalibreWireless.calibre_socket = dummy_socket

        finally(function()
          CalibreWireless.calibre_socket = nil
        end)

        -- In main.lua:67:
        -- if CalibreWireless.calibre_socket then CalibreWireless:disconnect() end
        -- In wireless.lua, CalibreWireless defines _disconnect(), not disconnect().
        -- Calling closeWirelessConnection() should disconnect cleanly and clear calibre_socket.
        plugin:closeWirelessConnection()
        assert.is_nil(CalibreWireless.calibre_socket)
      end
    )

    it(
      "fails: exposes custom server address port validation upper bound 65355 instead of 65535",
      function()
        local plugin = Calibre:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        local menu_table = plugin:getWirelessMenuTable()

        -- Find server address config item
        local config_item
        for _, item in ipairs(menu_table) do
          if item.sub_item_table then
            for _, sub in ipairs(item.sub_item_table) do
              if sub.text and sub.text:find("Manual") then
                config_item = sub
                break
              end
            end
          end
          if config_item then
            break
          end
        end
        assert.is_table(config_item)

        local orig_new = MultiInputDialog.new
        local captured_dlg
        MultiInputDialog.new = function(self, args)
          local dlg = orig_new(self, args)
          captured_dlg = dlg
          return dlg
        end

        local orig_show = UIManager.show
        local orig_close = UIManager.close
        UIManager.show = function() end
        UIManager.close = function() end

        finally(function()
          MultiInputDialog.new = orig_new
          UIManager.show = orig_show
          UIManager.close = orig_close
          G_reader_settings:delete("calibre_wireless_url")
        end)

        config_item.callback()
        assert.is_table(captured_dlg)

        captured_dlg.getFields = function()
          return { "192.168.1.10", "65500" }
        end

        local ok_btn = captured_dlg.buttons[1][2]
        assert.are.equal("OK", ok_btn.text)
        ok_btn.callback()

        local saved = G_reader_settings:read("calibre_wireless_url")
        assert.is_table(saved)
        -- Due to `port > 65355 then port = 9090`, 65500 is mistakenly reset to 9090.
        -- Expected correct port is 65500.
        assert.are.equal(65500, saved.port)
      end
    )
  end)
end)
