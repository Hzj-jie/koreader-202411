describe("KOSync plugin tests", function()
  local KOSyncClass, kosync, mock_ui, mock_client
  local Device, UIManager, NetworkMgr, Dispatcher, G_reader_settings, MultiInputDialog
  local match

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    match = require("luassert.match")
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Device = require("device")
    UIManager = require("ui/uimanager")
    NetworkMgr = require("ui/network/manager")
    Dispatcher = require("dispatcher")
    MultiInputDialog = require("ui/widget/multiinputdialog")
    G_reader_settings = _G.G_reader_settings

    G_reader_settings:delete("kosync")
    G_reader_settings:delete("device_id")
    G_reader_settings:delete("wifi_enable_action")

    KOSyncClass = dofile("plugins/kosync.koplugin/main.lua")

    mock_ui = {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      document = {
        file = "/path/to/test.epub",
        info = {
          has_pages = true,
        },
      },
      paging = {
        getLastPercent = function()
          return 0.5
        end,
        getLastProgress = function()
          return "50"
        end,
      },
      rolling = {
        getLastPercent = function()
          return 0.5
        end,
        getLastProgress = function()
          return "/xpointer(1)"
        end,
      },
      doc_settings = {
        read = function(_, key)
          if key == "partial_md5_checksum" then
            return "dummy_md5_checksum"
          end
        end,
      },
      view = {
        document = {
          file = "/path/to/test.epub",
        },
      },
    }

    mock_client = {
      register = spy.new(function(_, username, userkey)
        return true, 201, { message = "Registered" }
      end),
      authorize = spy.new(function(_, username, userkey)
        return true, 200, { message = "Authorized" }
      end),
      update_progress = spy.new(
        function(
          self_arg,
          username,
          userkey,
          doc_digest,
          progress,
          percentage,
          device_model,
          device_id,
          callback
        )
          if callback then
            callback(true, { message = "Progress updated" })
          end
          return true
        end
      ),
      get_progress = spy.new(
        function(self_arg, username, userkey, doc_digest, callback)
          if callback then
            callback(true, {
              progress = "60",
              percentage = 0.6,
              device = "OtherDevice",
              device_id = "other_id",
              timestamp = 1000,
            })
          end
          return true
        end
      ),
    }

    stub(NetworkMgr, "isOnline")
    NetworkMgr.isOnline.returns(true)

    stub(NetworkMgr, "runWhenOnline", function(...)
      for _, arg in ipairs({ ... }) do
        if type(arg) == "function" then
          arg()
        end
      end
      return true
    end)
    stub(NetworkMgr, "willRerunWhenOnline", function(...)
      for _, arg in ipairs({ ... }) do
        if type(arg) == "function" then
          arg()
        end
      end
      return false
    end)
    stub(NetworkMgr, "shouldRestoreWifi")
    NetworkMgr.shouldRestoreWifi.returns(false)

    stub(UIManager, "show")
    stub(UIManager, "close")
    stub(UIManager, "broadcastEvent")
    stub(UIManager, "scheduleIn", function(self_arg, delay, callback)
      local cb = type(self_arg) == "function" and self_arg or callback
      if cb then
        cb()
      end
    end)
    stub(UIManager, "runWith", function(...)
      for _, arg in ipairs({ ... }) do
        if type(arg) == "function" then
          arg()
        end
      end
    end)

    stub(MultiInputDialog, "new", function(self_arg, spec)
      local s = (type(self_arg) == "table" and self_arg.fields) and self_arg
        or spec
      s.fields_value = { "", "" }
      s.getFields = function(self_field)
        return self_field.fields_value
      end
      return s
    end)

    kosync = KOSyncClass:new({
      ui = mock_ui,
      path = "plugins/kosync.koplugin",
    })
    stub(kosync, "_createClient", function()
      return mock_client
    end)
  end)

  after_each(function()
    NetworkMgr.isOnline:revert()
    NetworkMgr.runWhenOnline:revert()
    NetworkMgr.willRerunWhenOnline:revert()
    NetworkMgr.shouldRestoreWifi:revert()

    UIManager.show:revert()
    UIManager.close:revert()
    UIManager.broadcastEvent:revert()
    UIManager.scheduleIn:revert()
    UIManager.runWith:revert()

    MultiInputDialog.new:revert()

    if kosync._createClient.revert then
      kosync._createClient:revert()
    end

    package.unload("plugins/kosync.koplugin/main")
    G_reader_settings:delete("kosync")
    G_reader_settings:delete("device_id")
    G_reader_settings:delete("wifi_enable_action")
  end)

  describe("Initialization", function()
    it("initializes default settings and registers to main menu", function()
      kosync:init()

      assert.is_not_nil(kosync.settings)
      assert.are.equal(false, kosync.settings.auto_sync)
      assert.are.equal(1, kosync.settings.sync_forward) -- PROMPT
      assert.are.equal(3, kosync.settings.sync_backward) -- DISABLE
      assert.are.equal(0, kosync.settings.checksum_method) -- BINARY
      assert
        .spy(mock_ui.menu.registerToMainMenu)
        .was_called_with(mock_ui.menu, kosync)
      assert.is_not_nil(G_reader_settings:read("device_id"))
    end)

    it(
      "disables auto_sync if seamless wifi toggle enabled but wifi_enable_action is not turn_on",
      function()
        stub(Device, "hasSeamlessWifiToggle")
        Device.hasSeamlessWifiToggle.returns(true)
        G_reader_settings:save("wifi_enable_action", "prompt")
        G_reader_settings:save("kosync", { auto_sync = true })

        kosync:init()

        assert.is_false(kosync.settings.auto_sync)

        Device.hasSeamlessWifiToggle:revert()
      end
    )

    it("initializes document state when partial_md5_checksum exists", function()
      kosync.data_initialized = nil
      kosync.settings = { auto_sync = true }
      stub(kosync, "_getProgress")

      kosync:initDocumentState()

      assert.is_true(kosync.data_initialized)
      assert.stub(kosync._getProgress).was_called()

      kosync._getProgress:revert()
    end)

    it(
      "does not re-initialize document state if already initialized",
      function()
        kosync.data_initialized = true
        stub(kosync, "_getProgress")

        kosync:initDocumentState()

        assert.stub(kosync._getProgress).was_not_called()
        kosync._getProgress:revert()
      end
    )
  end)

  describe("Dispatcher Actions & Reader Ready", function()
    it("registers dispatcher actions and handles onReaderReady", function()
      stub(Dispatcher, "registerAction")
      stub(kosync, "initDocumentState")

      kosync:onDispatcherRegisterActions()
      assert.stub(Dispatcher.registerAction).was_called(2)

      kosync:onReaderReady()
      assert.stub(kosync.initDocumentState).was_called_with(match.is_table())

      Dispatcher.registerAction:revert()
      kosync.initDocumentState:revert()
    end)
  end)

  describe("Settings Mutators", function()
    it("sets custom server correctly when valid", function()
      kosync:init()
      kosync:setCustomServer("https://sync.example.com")
      assert.are.equal(
        "https://sync.example.com",
        kosync.settings.custom_server
      )

      kosync:setCustomServer("")
      assert.is_nil(kosync.settings.custom_server)
    end)

    it("reverts custom server and shows warning when invalid", function()
      kosync:init()
      kosync.settings.custom_server = "https://old.example.com"
      kosync._createClient.invokes(function()
        error("invalid url")
      end)

      kosync:setCustomServer("invalid_url")

      assert.are.equal("https://old.example.com", kosync.settings.custom_server)
      assert.are.equal("invalid_url", kosync.last_custom_server_attempt)
      assert.stub(UIManager.show).was_called()
    end)

    it("sets sync strategies and checksum method", function()
      kosync:init()
      kosync:setSyncForward(2)
      assert.are.equal(2, kosync.settings.sync_forward)

      kosync:setSyncBackward(1)
      assert.are.equal(1, kosync.settings.sync_backward)

      kosync:setChecksumMethod(1)
      assert.are.equal(1, kosync.settings.checksum_method)
    end)
  end)

  describe("Main Menu Construction", function()
    it("adds kosync menu items to main menu", function()
      kosync:init()
      local menu_items = {}
      kosync:addToMainMenu(menu_items)

      assert.is_not_nil(menu_items.progress_sync)
      local sub_items = menu_items.progress_sync.sub_item_table
      assert.is_table(sub_items)
    end)

    it("handles custom server menu item tap_input_func", function()
      kosync:init()
      local menu_items = {}
      kosync:addToMainMenu(menu_items)
      local custom_server_item = menu_items.progress_sync.sub_item_table[1]

      local input_spec = custom_server_item.tap_input_func()
      assert.are.equal("https://", input_spec.input)

      stub(kosync, "setCustomServer")
      input_spec.callback("https://new.example.com")
      assert
        .stub(kosync.setCustomServer)
        .was_called_with(match.is_table(), "https://new.example.com")
      kosync.setCustomServer:revert()
    end)

    it("handles login/logout menu item text and callback", function()
      kosync:init()
      local menu_items = {}
      kosync:addToMainMenu(menu_items)
      local login_item = menu_items.progress_sync.sub_item_table[2]

      -- When logged out
      assert.is_truthy(login_item.text_func():find("Register / Login"))
      local cb = login_item.callback_func()
      stub(kosync, "_login")
      cb("mock_menu")
      assert.stub(kosync._login).was_called_with(match.is_table(), "mock_menu")

      -- When logged in
      kosync.settings.userkey = "dummy_userkey"
      assert.are.equal("Logout", login_item.text_func())
      local cb_logout = login_item.callback_func()
      stub(kosync, "_logout")
      cb_logout("mock_menu")
      assert.stub(kosync._logout).was_called_with(match.is_table(), "mock_menu")
    end)

    it("handles auto_sync menu item callback and wifi check", function()
      kosync:init()
      local menu_items = {}
      kosync:addToMainMenu(menu_items)
      local auto_sync_item = menu_items.progress_sync.sub_item_table[3]

      assert.is_false(auto_sync_item.checked_func())
      assert.is_string(auto_sync_item.help_text)

      -- Toggle auto_sync ON (calls _getProgress)
      stub(kosync, "_getProgress")
      auto_sync_item.callback()
      assert.is_true(kosync.settings.auto_sync)
      assert.stub(kosync._getProgress).was_called_with(match.is_table(), true)

      -- Toggle auto_sync OFF (calls _updateProgress)
      stub(kosync, "_updateProgress")
      auto_sync_item.callback()
      assert.is_false(kosync.settings.auto_sync)
      assert
        .stub(kosync._updateProgress)
        .was_called_with(match.is_table(), true)

      -- Wifi check block when toggle ON
      stub(Device, "hasSeamlessWifiToggle")
      Device.hasSeamlessWifiToggle.returns(true)
      G_reader_settings:save("wifi_enable_action", "prompt")
      auto_sync_item.callback()
      assert.is_false(kosync.settings.auto_sync)
      assert.stub(UIManager.show).was_called()

      Device.hasSeamlessWifiToggle:revert()
    end)

    it("handles sync strategy and checksum menu subitems", function()
      kosync:init()
      local menu_items = {}
      kosync:addToMainMenu(menu_items)

      -- Sync forward menu item (index 4)
      local forward_item = menu_items.progress_sync.sub_item_table[4]
      assert.is_string(forward_item.text_func())
      forward_item.sub_item_table[1].callback() -- Silently
      assert.are.equal(2, kosync.settings.sync_forward)
      assert.is_true(forward_item.sub_item_table[1].checked_func())

      forward_item.sub_item_table[2].callback() -- Prompt
      assert.are.equal(1, kosync.settings.sync_forward)
      assert.is_true(forward_item.sub_item_table[2].checked_func())

      forward_item.sub_item_table[3].callback() -- Never
      assert.are.equal(3, kosync.settings.sync_forward)
      assert.is_true(forward_item.sub_item_table[3].checked_func())

      -- Sync backward menu item (index 5)
      local backward_item = menu_items.progress_sync.sub_item_table[5]
      assert.is_string(backward_item.text_func())
      backward_item.sub_item_table[1].callback() -- Silently
      assert.are.equal(2, kosync.settings.sync_backward)

      backward_item.sub_item_table[2].callback() -- Prompt
      assert.are.equal(1, kosync.settings.sync_backward)

      backward_item.sub_item_table[3].callback() -- Never
      assert.are.equal(3, kosync.settings.sync_backward)

      -- Push / Pull items (index 6 & 7)
      local push_item = menu_items.progress_sync.sub_item_table[6]
      local pull_item = menu_items.progress_sync.sub_item_table[7]
      assert.is_false(push_item.enabled_func())
      assert.is_false(pull_item.enabled_func())
      kosync.settings.userkey = "valid"
      assert.is_true(push_item.enabled_func())
      assert.is_true(pull_item.enabled_func())

      stub(kosync, "_updateProgress")
      push_item.callback()
      assert
        .stub(kosync._updateProgress)
        .was_called_with(match.is_table(), true)

      stub(kosync, "_getProgress")
      pull_item.callback()
      assert.stub(kosync._getProgress).was_called_with(match.is_table(), true)

      -- Checksum method subitems (index 8)
      local checksum_item = menu_items.progress_sync.sub_item_table[8]
      checksum_item.sub_item_table[2].callback() -- Filename
      assert.are.equal(1, kosync.settings.checksum_method)
      assert.is_true(checksum_item.sub_item_table[2].checked_func())

      checksum_item.sub_item_table[1].callback() -- Binary
      assert.are.equal(0, kosync.settings.checksum_method)
      assert.is_true(checksum_item.sub_item_table[1].checked_func())
    end)
  end)

  describe("Login and Registration", function()
    it("shows login dialog and handles invalid user input", function()
      kosync:init()
      kosync:_login()

      assert.stub(UIManager.show).was_called()
      local call_args = UIManager.show.calls[1].refs
      local dialog = call_args[2] or call_args[1]
      assert.is_not_nil(dialog)

      dialog.fields_value = { "", "" }

      -- Click Login with empty fields
      local buttons = dialog.buttons[1]
      local login_btn = buttons[2]
      login_btn.callback()
      assert.stub(UIManager.show).was_called(2) -- Error InfoMessage shown

      -- Click Cancel button
      local cancel_btn = buttons[1]
      cancel_btn.callback()
      assert.stub(UIManager.close).was_called_with(match.is_table(), dialog)
    end)

    it("triggers _doLogin when valid fields submitted", function()
      kosync:init()
      stub(kosync, "_doLogin")
      kosync:_login()

      local call_args = UIManager.show.calls[1].refs
      local dialog = call_args[2] or call_args[1]
      dialog.fields_value = { "testuser", "testpass" }

      local login_btn = dialog.buttons[1][2]
      login_btn.callback()

      assert
        .stub(kosync._doLogin)
        .was_called_with(match.is_table(), "testuser", "testpass", nil)
    end)

    it("triggers _doRegister when register button clicked", function()
      kosync:init()
      stub(kosync, "_doRegister")
      kosync:_login()

      local call_args = UIManager.show.calls[1].refs
      local dialog = call_args[2] or call_args[1]

      -- Invalid input test on register
      dialog.fields_value = { "", "" }
      local reg_btn = dialog.buttons[1][3]
      reg_btn.callback()
      assert.stub(UIManager.show).was_called(2)

      -- Valid input test on register
      dialog.fields_value = { "newuser", "newpass" }
      reg_btn.callback()
      assert
        .stub(kosync._doRegister)
        .was_called_with(match.is_table(), "newuser", "newpass", nil)
    end)

    it("handles _doLogin success and failure cases", function()
      kosync:init()
      local mock_menu = { updateItems = spy.new(function() end) }

      -- Success case
      kosync:_doLogin("user1", "pass1", mock_menu)
      assert.are.equal("user1", kosync.settings.username)
      assert.is_string(kosync.settings.userkey)
      assert.spy(mock_menu.updateItems).was_called()
      assert.stub(UIManager.show).was_called()

      -- Client returns ok = false (status error)
      mock_client.authorize = spy.new(function()
        return false, "Invalid password"
      end)
      kosync:_doLogin("user1", "wrongpass", mock_menu)

      -- Client returns ok = false (no status)
      mock_client.authorize = spy.new(function()
        return false, nil
      end)
      kosync:_doLogin("user1", "wrongpass", mock_menu)

      -- Client returns status = false, body = error
      mock_client.authorize = spy.new(function()
        return true, false, { message = "Account suspended" }
      end)
      kosync:_doLogin("user1", "wrongpass", mock_menu)
    end)

    it("handles _doRegister success and failure cases", function()
      kosync:init()
      local mock_menu = { updateItems = spy.new(function() end) }

      -- Success case
      kosync:_doRegister("user2", "pass2", mock_menu)
      assert.are.equal("user2", kosync.settings.username)
      assert.is_string(kosync.settings.userkey)
      assert.spy(mock_menu.updateItems).was_called()

      -- Client returns ok = false (status error)
      mock_client.register = spy.new(function()
        return false, "User exists"
      end)
      kosync:_doRegister("user2", "pass2", mock_menu)

      -- Client returns ok = false (no status)
      mock_client.register = spy.new(function()
        return false, nil
      end)
      kosync:_doRegister("user2", "pass2", mock_menu)

      -- Client returns status = false, body = error
      mock_client.register = spy.new(function()
        return true, false, { message = "Registration forbidden" }
      end)
      kosync:_doRegister("user2", "pass2", mock_menu)
    end)

    it("handles _logout", function()
      kosync:init()
      kosync.settings.userkey = "some_key"
      kosync.settings.auto_sync = false
      local mock_menu = { updateItems = spy.new(function() end) }

      kosync:_logout(mock_menu)

      assert.is_nil(kosync.settings.userkey)
      assert.is_true(kosync.settings.auto_sync)
      assert.spy(mock_menu.updateItems).was_called()
    end)
  end)

  describe("Progress & Document Digest", function()
    it(
      "calculates document progress for paged and rolling documents",
      function()
        kosync:init()

        -- Paged document
        mock_ui.document.info.has_pages = true
        assert.are.equal(0.5, kosync:_getLastPercent())
        assert.are.equal("50", kosync:_getLastProgress())

        -- Rolling document
        mock_ui.document.info.has_pages = false
        assert.are.equal(0.5, kosync:_getLastPercent())
        assert.are.equal("/xpointer(1)", kosync:_getLastProgress())
      end
    )

    it("calculates document digest based on checksum method", function()
      kosync:init()

      -- BINARY checksum method
      kosync.settings.checksum_method = 0
      assert.are.equal("dummy_md5_checksum", kosync:_getDocumentDigest())

      -- FILENAME checksum method
      kosync.settings.checksum_method = 1
      assert.is_string(kosync:_getDocumentDigest())

      -- FILENAME when document.file is nil
      mock_ui.document.file = nil
      assert.is_nil(kosync:_getDocumentDigest())
    end)

    it("syncs to progress for paged and rolling documents", function()
      kosync:init()

      -- Paged document
      mock_ui.document.info.has_pages = true
      kosync:_syncToProgress("10")
      assert.stub(UIManager.broadcastEvent).was_called()

      -- Rolling document
      UIManager.broadcastEvent:clear()
      mock_ui.document.info.has_pages = false
      kosync:_syncToProgress("/xpointer(2)")
      assert.stub(UIManager.broadcastEvent).was_called()

      -- When document is nil
      mock_ui.document = nil
      kosync:_syncToProgress("10")
    end)
  end)

  describe("Push Progress", function()
    it("prompts login when trying to push without login", function()
      kosync:init()
      kosync.settings.username = nil
      kosync.settings.userkey = nil

      kosync:_updateProgress(true)
      assert.stub(UIManager.show).was_called()
    end)

    it("debounces push progress when non-interactive", function()
      kosync:init()
      kosync.settings.username = "user"
      kosync.settings.userkey = "key"

      kosync.push_timestamp = UIManager:getElapsedTimeSinceBoot()
      mock_client.update_progress:clear()

      kosync:_updateProgress(false)
      assert.spy(mock_client.update_progress).was_not_called()
    end)

    it("pushes progress successfully in interactive mode", function()
      kosync:init()
      kosync.settings.username = "user"
      kosync.settings.userkey = "key"

      kosync:_updateProgress(true)
      assert.spy(mock_client.update_progress).was_called()
      assert.stub(UIManager.show).was_called()
    end)

    it("handles push progress failure in interactive mode", function()
      kosync:init()
      kosync.settings.username = "user"
      kosync.settings.userkey = "key"

      -- Client returns ok = false in callback
      mock_client.update_progress = spy.new(
        function(
          self_arg,
          username,
          userkey,
          doc_digest,
          progress,
          percentage,
          device_model,
          device_id,
          callback
        )
          if callback then
            callback(false, nil)
          end
          return true
        end
      )
      kosync:_updateProgress(true)
      assert.stub(UIManager.show).was_called()

      -- Client throws pcall error
      mock_client.update_progress = spy.new(function()
        error("network error")
      end)
      kosync:_updateProgress(true)
      assert.stub(UIManager.show).was_called()
    end)
  end)

  describe("Pull Progress", function()
    it("prompts login when trying to pull without login", function()
      kosync:init()
      kosync.settings.username = nil
      kosync.settings.userkey = nil

      kosync:_getProgress(true)
      assert.stub(UIManager.show).was_called()
    end)

    it("debounces pull progress when non-interactive", function()
      kosync:init()
      kosync.settings.username = "user"
      kosync.settings.userkey = "key"

      kosync.pull_timestamp = UIManager:getElapsedTimeSinceBoot()
      mock_client.get_progress:clear()

      kosync:_getProgress(false)
      assert.spy(mock_client.get_progress).was_not_called()
    end)

    it(
      "handles missing progress or same device or already synchronized",
      function()
        kosync:init()
        kosync.settings.username = "user"
        kosync.settings.userkey = "key"

        -- Response without body/ok
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(false, nil)
        end)
        kosync:_getProgress(true)
        assert.stub(UIManager.show).was_called()

        -- Response without percentage
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {})
        end)
        kosync:_getProgress(true)
        assert.stub(UIManager.show).was_called()

        -- Response from same device
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {
            percentage = 0.8,
            device = Device.model,
            device_id = kosync.device_id,
          })
        end)
        kosync:_getProgress(true)
        assert.stub(UIManager.show).was_called()

        -- Response with same progress / percentage
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {
            percentage = 0.5,
            progress = "50",
            device = "OtherDevice",
            device_id = "other_id",
          })
        end)
        kosync:_getProgress(true)
        assert.stub(UIManager.show).was_called()
      end
    )

    it("pulls and syncs progress in interactive mode", function()
      kosync:init()
      kosync.settings.username = "user"
      kosync.settings.userkey = "key"

      mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
        cb(true, {
          percentage = 0.8,
          progress = "80",
          device = "OtherDevice",
          device_id = "other_id",
        })
      end)

      stub(kosync, "_syncToProgress")
      kosync:_getProgress(true)
      assert
        .stub(kosync._syncToProgress)
        .was_called_with(match.is_table(), "80")

      kosync._syncToProgress:revert()
    end)

    it(
      "handles non-interactive pull progress strategies (forward / backward)",
      function()
        kosync:init()
        kosync.settings.username = "user"
        kosync.settings.userkey = "key"

        -- Forward sync strategy: SILENT
        kosync.settings.sync_forward = 2 -- SILENT
        kosync.last_page_turn_timestamp = 100
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {
            percentage = 0.8,
            progress = "80",
            timestamp = 200, -- newer
            device = "OtherDevice",
            device_id = "other_id",
          })
        end)
        stub(kosync, "_syncToProgress")
        kosync.pull_timestamp = 0
        kosync:_getProgress(false)
        assert
          .stub(kosync._syncToProgress)
          .was_called_with(match.is_table(), "80")

        -- Forward sync strategy: PROMPT
        kosync.settings.sync_forward = 1 -- PROMPT
        kosync.pull_timestamp = 0
        kosync:_getProgress(false)
        assert.stub(UIManager.show).was_called()
        local call_args = UIManager.show.calls[#UIManager.show.calls].refs
        local confirm_box = call_args[2] or call_args[1]
        confirm_box.ok_callback()
        assert
          .stub(kosync._syncToProgress)
          .was_called_with(match.is_table(), "80")

        -- Backward sync strategy: SILENT
        kosync.settings.sync_backward = 2 -- SILENT
        kosync.last_page_turn_timestamp = 300
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {
            percentage = 0.2,
            progress = "20",
            timestamp = 200, -- older
            device = "OtherDevice",
            device_id = "other_id",
          })
        end)
        kosync.pull_timestamp = 0
        kosync:_getProgress(false)
        assert
          .stub(kosync._syncToProgress)
          .was_called_with(match.is_table(), "20")

        -- Backward sync strategy: PROMPT
        kosync.settings.sync_backward = 1 -- PROMPT
        kosync.pull_timestamp = 0
        kosync:_getProgress(false)
        assert.stub(UIManager.show).was_called()
        local call_args_back = UIManager.show.calls[#UIManager.show.calls].refs
        local confirm_box_back = call_args_back[2] or call_args_back[1]
        confirm_box_back.ok_callback()
        assert
          .stub(kosync._syncToProgress)
          .was_called_with(match.is_table(), "20")

        -- When timestamp is nil (legacy server), uses percentage comparison
        mock_client.get_progress = spy.new(function(self_arg, u, k, d, cb)
          cb(true, {
            percentage = 0.8,
            progress = "80",
            timestamp = nil,
            device = "OtherDevice",
            device_id = "other_id",
          })
        end)
        kosync.settings.sync_forward = 2 -- SILENT
        kosync.pull_timestamp = 0
        kosync:_getProgress(false)
        assert
          .stub(kosync._syncToProgress)
          .was_called_with(match.is_table(), "80")

        -- Error during pcall
        mock_client.get_progress = spy.new(function()
          error("pull error")
        end)
        kosync.pull_timestamp = 0
        kosync:_getProgress(true)
        assert.stub(UIManager.show).was_called()

        kosync._syncToProgress:revert()
      end
    )
  end)

  describe("Event Handlers", function()
    it("handles onPageUpdate", function()
      kosync:init()
      kosync.settings.auto_sync = false
      kosync:onPageUpdate(1)
      assert.are.equal(0, kosync.last_page_turn_timestamp)

      kosync.settings.auto_sync = true
      kosync:onPageUpdate(nil)
      assert.are.equal(0, kosync.last_page_turn_timestamp)

      kosync:onPageUpdate(5)
      assert.is_not_equal(0, kosync.last_page_turn_timestamp)
    end)

    it("handles onSaveSettings, onSuspend, onNetworkDisconnecting", function()
      kosync:init()
      stub(kosync, "_updateProgress")

      kosync.settings.auto_sync = false
      kosync:onSaveSettings()
      kosync:onSuspend()
      kosync:onNetworkDisconnecting()
      assert.stub(kosync._updateProgress).was_not_called()

      kosync.settings.auto_sync = true
      kosync.push_timestamp = 0
      kosync:onSaveSettings()
      kosync.push_timestamp = 0
      kosync:onSuspend()
      kosync.push_timestamp = 0
      kosync:onNetworkDisconnecting()
      assert.stub(kosync._updateProgress).was_called(3)

      kosync._updateProgress:revert()
    end)

    it("handles onResume and onNetworkOnline", function()
      kosync:init()
      stub(kosync, "_getProgress")

      kosync.settings.auto_sync = false
      kosync:onResume()
      kosync:onNetworkOnline()
      assert.stub(kosync._getProgress).was_not_called()

      kosync.settings.auto_sync = true
      kosync.pull_timestamp = 0
      kosync:onResume()
      kosync.pull_timestamp = 0
      kosync:onNetworkOnline()
      assert.stub(kosync._getProgress).was_called(2)

      -- When NetworkMgr:shouldRestoreWifi() is true
      NetworkMgr.shouldRestoreWifi.returns(true)
      kosync._getProgress:clear()
      kosync:onResume()
      assert.stub(kosync._getProgress).was_not_called()

      kosync._getProgress:revert()
    end)

    it("handles onKOSyncPushProgress and onKOSyncPullProgress", function()
      kosync:init()
      stub(kosync, "_updateProgress")
      stub(kosync, "_getProgress")

      kosync:onKOSyncPushProgress()
      assert
        .stub(kosync._updateProgress)
        .was_called_with(match.is_table(), true)

      kosync:onKOSyncPullProgress()
      assert.stub(kosync._getProgress).was_called_with(match.is_table(), true)

      kosync._updateProgress:revert()
      kosync._getProgress:revert()
    end)

    it("registers dispatcher actions safely", function()
      kosync:init()
      if type(kosync.onDispatcherRegisterActions) == "function" then
        kosync:onDispatcherRegisterActions()
      end
    end)
  end)
end)
