describe("CommonInfoMenuTable element", function()
  local CommonInfoMenuTable
  local DataStorage, Device, Event, FfiUtil, Notification, UIManager, Version, dbg, lfs
  local orig_hasKeyboard, orig_isAndroid
  local orig_getCurrentRevision, orig_getUncachedCurrentRevision, orig_getShortVersion

  local function loadModule()
    package.loaded["ui/elements/common_info_menu_table"] = nil
    return require("ui/elements/common_info_menu_table")
  end

  setup(function()
    require("commonrequire")

    DataStorage = require("datastorage")
    Device = require("device")
    Event = require("ui/event")
    FfiUtil = require("ffi/util")
    Notification = require("ui/widget/notification")
    UIManager = require("ui/uimanager")
    Version = require("version")
    dbg = require("dbg")
    lfs = require("libs/libkoreader-lfs")

    orig_hasKeyboard = Device.hasKeyboard
    orig_isAndroid = Device.isAndroid
    orig_getCurrentRevision = Version.getCurrentRevision
    orig_getUncachedCurrentRevision = Version.getUncachedCurrentRevision
    orig_getShortVersion = Version.getShortVersion
  end)

  teardown(function()
    Device.hasKeyboard = orig_hasKeyboard
    Device.isAndroid = orig_isAndroid
    Version.getCurrentRevision = orig_getCurrentRevision
    Version.getUncachedCurrentRevision = orig_getUncachedCurrentRevision
    Version.getShortVersion = orig_getShortVersion
  end)

  before_each(function()
    G_reader_settings:delete("debug_verbose")
    G_reader_settings:delete("debug")
    Device.hasKeyboard = function()
      return false
    end
    Device.isAndroid = function()
      return false
    end
    CommonInfoMenuTable = loadModule()
  end)

  it("should return a valid common info menu table", function()
    assert.is_table(CommonInfoMenuTable)
    assert.is_table(CommonInfoMenuTable.help)
    assert.are.equal("Help", CommonInfoMenuTable.help.text)
    assert.is_table(CommonInfoMenuTable.quickstart_guide)
    assert.are.equal(
      "Quickstart guide",
      CommonInfoMenuTable.quickstart_guide.text
    )
    assert.is_table(CommonInfoMenuTable.search_menu)
    assert.are.equal("Menu search", CommonInfoMenuTable.search_menu.text)
    assert.is_true(CommonInfoMenuTable.search_menu.keep_menu_open)
    assert.is_table(CommonInfoMenuTable.report_bug)
    assert.is_true(CommonInfoMenuTable.report_bug.keep_menu_open)
    assert.is_table(CommonInfoMenuTable.about)
    assert.is_true(CommonInfoMenuTable.about.keep_menu_open)
  end)

  describe("keyboard shortcuts option", function()
    it("is omitted when Device does not have keyboard", function()
      Device.hasKeyboard = function()
        return false
      end
      local table_no_kb = loadModule()
      assert.is_nil(table_no_kb.keyboard_shortcuts)
    end)

    it(
      "is included when Device has keyboard and displays shortcuts page",
      function()
        Device.hasKeyboard = function()
          return true
        end
        local table_kb = loadModule()
        assert.is_table(table_kb.keyboard_shortcuts)
        assert.are.equal("Keyboard shortcuts", table_kb.keyboard_shortcuts.text)

        local mock_key_events = {
          { "Home", { "Go home" } },
          { "Back", { "Go back" } },
        }
        local spy_keyEvents = stub(UIManager, "keyEvents", function()
          local i = 0
          return function()
            i = i + 1
            if mock_key_events[i] then
              return mock_key_events[i][1], mock_key_events[i][2]
            end
          end
        end)
        local spy_show = stub(UIManager, "show")

        table_kb.keyboard_shortcuts.callback()

        assert.stub(spy_keyEvents).was_called(1)
        assert.stub(spy_show).was_called(1)
        local shown_page = spy_show.calls[1].vals[2]
        assert.are.equal("Keyboard shortcuts", shown_page.title)

        UIManager.keyEvents:revert()
        UIManager.show:revert()
      end
    )
  end)

  describe("developer mode items", function()
    it("omits dev options when DEV_MODE is false", function()
      G_defaults:save("DEV_MODE", false)
      local menu = loadModule()
      assert.is_nil(menu.common_log_files)
      assert.is_nil(menu.advanced_settings)
      assert.is_nil(menu.developer_options)
    end)

    it("includes dev options when DEV_MODE is true", function()
      G_defaults:save("DEV_MODE", true)
      local menu = loadModule()
      assert.is_table(menu.common_log_files)
      assert.are.equal("Common log files", menu.common_log_files.text)
      assert.is_table(menu.common_log_files.sub_item_table)
      assert.are.equal(3, #menu.common_log_files.sub_item_table)

      assert.is_not_nil(menu.advanced_settings)
      assert.is_not_nil(menu.developer_options)

      local item1 = menu.common_log_files.sub_item_table[1]
      assert.are.equal("batterystat.log", item1.text)

      local mock_readerui = { showReader = stub() }
      package.loaded["apps/reader/readerui"] = mock_readerui

      item1.callback()

      local expected_path =
        FfiUtil.realpath(DataStorage:getFullDataDir() .. "/batterystat.log")
      assert
        .stub(mock_readerui.showReader)
        .was_called_with(mock_readerui, expected_path)

      -- Check enabled_func
      local is_enabled = item1.enabled_func()
      local expected_enabled = expected_path ~= nil
        and lfs.attributes(expected_path, "mode") == "file"
      assert.are.equal(expected_enabled, is_enabled)

      package.loaded["apps/reader/readerui"] = nil
      G_defaults:save("DEV_MODE", false)
    end)
  end)

  describe("quickstart guide option", function()
    it("opens quickstart guide", function()
      local mock_readerui = { showReader = stub() }
      local mock_quickstart = {
        getQuickStart = function()
          return "/path/to/quickstart.epub"
        end,
      }

      package.loaded["apps/reader/readerui"] = mock_readerui
      package.loaded["ui/quickstart"] = mock_quickstart

      CommonInfoMenuTable.quickstart_guide.callback()

      assert
        .stub(mock_readerui.showReader)
        .was_called_with(mock_readerui, "/path/to/quickstart.epub")

      package.loaded["apps/reader/readerui"] = nil
      package.loaded["ui/quickstart"] = nil
    end)
  end)

  describe("search menu option", function()
    it("broadcasts ShowMenuSearch event", function()
      local spy_broadcast = stub(UIManager, "broadcastEvent")

      CommonInfoMenuTable.search_menu.callback()

      assert.stub(spy_broadcast).was_called(1)
      local event = spy_broadcast.calls[1].vals[2]
      assert.are.equal("onShowMenuSearch", event.handler)

      UIManager.broadcastEvent:revert()
    end)
  end)

  describe("report bug option", function()
    it("returns correct text based on debug_verbose setting", function()
      G_reader_settings:delete("debug_verbose")
      assert.are.equal(
        "Report a bug",
        CommonInfoMenuTable.report_bug.text_func()
      )

      G_reader_settings:save("debug_verbose", true)
      assert.are.equal(
        "Report a bug (verbose logging is enabled)",
        CommonInfoMenuTable.report_bug.text_func()
      )
    end)

    it("triggers log dump on android and shows confirm box", function()
      Device.isAndroid = function()
        return true
      end

      local mock_android = { dumpLogs = stub() }
      package.loaded["android"] = mock_android

      local spy_show = stub(UIManager, "show")
      local mock_menu = { updateItems = stub() }

      CommonInfoMenuTable.report_bug.callback(mock_menu)

      assert.stub(mock_android.dumpLogs).was_called(1)
      assert.stub(spy_show).was_called(1)

      local confirm_box = spy_show.calls[1].vals[2]
      assert.is_not_nil(confirm_box.text)
      assert.is_table(confirm_box.other_buttons)

      -- Test toggle button in confirm box (enabling verbose logging)
      local toggle_btn_cb = confirm_box.other_buttons[1][1].callback
      local spy_turnOn = stub(dbg, "turnOn")
      local spy_setVerbose = stub(dbg, "setVerbose")
      local spy_notify = stub(Notification, "notify")
      local spy_askForRestart = stub(UIManager, "askForRestart")

      G_reader_settings:delete("debug_verbose")
      toggle_btn_cb()

      assert.stub(spy_turnOn).was_called(1)
      assert.stub(spy_setVerbose).was_called_with(dbg, true)
      assert.is_true(G_reader_settings:isTrue("debug_verbose"))
      assert.is_true(G_reader_settings:isTrue("debug"))
      assert
        .stub(spy_notify)
        .was_called_with(Notification, "Verbose logging enabled")
      assert.stub(mock_menu.updateItems).was_called(1)
      assert.stub(spy_askForRestart).was_called(1)

      -- Test toggle button in confirm box (disabling verbose logging)
      local spy_turnOff = stub(dbg, "turnOff")

      toggle_btn_cb()

      assert.stub(spy_setVerbose).was_called_with(dbg, false)
      assert.stub(spy_turnOff).was_called(1)
      assert.is_false(G_reader_settings:isTrue("debug_verbose"))
      assert.is_false(G_reader_settings:isTrue("debug"))
      assert
        .stub(spy_notify)
        .was_called_with(Notification, "Verbose logging disabled")

      dbg.turnOn:revert()
      dbg.turnOff:revert()
      dbg.setVerbose:revert()
      Notification.notify:revert()
      UIManager.askForRestart:revert()
      UIManager.show:revert()
      package.loaded["android"] = nil
    end)
  end)

  describe("about option", function()
    it("has short version in text", function()
      Version.getShortVersion = function()
        return "v2024.11"
      end
      local menu = loadModule()
      assert.is_not_nil(string.find(menu.about.text, "v2024.11"))
    end)

    it("shows info message when revision matches source revision", function()
      Version.getCurrentRevision = function()
        return "git-12345"
      end
      Version.getUncachedCurrentRevision = function()
        return "git-12345"
      end

      local spy_show = stub(UIManager, "show")
      CommonInfoMenuTable.about.callback()

      assert.stub(spy_show).was_called(1)
      local info_msg = spy_show.calls[1].vals[2]
      assert.are.equal("koreader", info_msg.icon)
      assert.is_nil(
        string.find(info_msg.text, "may not match source code version")
      )

      UIManager.show:revert()
    end)

    it(
      "shows restart warning when running revision does not match source revision",
      function()
        Version.getCurrentRevision = function()
          return "git-12345"
        end
        Version.getUncachedCurrentRevision = function()
          return "git-67890"
        end

        local spy_show = stub(UIManager, "show")
        CommonInfoMenuTable.about.callback()

        assert.stub(spy_show).was_called(1)
        local info_msg = spy_show.calls[1].vals[2]
        assert.is_not_nil(
          string.find(
            info_msg.text,
            "Running version may not match source code version"
          )
        )

        UIManager.show:revert()
      end
    )
  end)
end)
