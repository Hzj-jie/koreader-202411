-- luacheck: ignore 122
describe("SSH plugin main module", function()
  local SSH, util, Device, UIManager, InfoMessage, InputDialog

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    util = require("util")
    Device = require("device")
    UIManager = require("ui/uimanager")
    InfoMessage = require("ui/widget/infomessage")
    InputDialog = require("ui/widget/inputdialog")

    local old_pathExists = util.pathExists
    util.pathExists = function(path)
      if path and path:find("dropbear") then
        return true
      end
      return old_pathExists(path)
    end

    SSH = require("plugins/SSH.koplugin/main")
    util.pathExists = old_pathExists
  end)

  local orig_execute, orig_remove, orig_pathExists
  local orig_show, orig_close, orig_nextTick
  local orig_isKindle, orig_isKobo
  local executed_cmds, removed_files, shown_widgets, closed_widgets, next_ticks
  local is_pid_existing, execute_exit_code

  before_each(function()
    executed_cmds = {}
    removed_files = {}
    shown_widgets = {}
    closed_widgets = {}
    next_ticks = {}
    is_pid_existing = false
    execute_exit_code = 0

    orig_execute = os.execute
    orig_remove = os.remove
    orig_pathExists = util.pathExists
    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_nextTick = UIManager.nextTick
    orig_isKindle = Device.isKindle
    orig_isKobo = Device.isKobo

    os.execute = function(cmd)
      table.insert(executed_cmds, cmd)
      return execute_exit_code
    end

    os.remove = function(file)
      table.insert(removed_files, file)
      is_pid_existing = false
      return true
    end

    util.pathExists = function(filepath)
      if filepath == "/tmp/dropbear_koreader.pid" then
        return is_pid_existing
      end
      if filepath and filepath:find("dropbear") then
        return true
      end
      if filepath and filepath:find("settings/SSH") then
        return true
      end
      return orig_pathExists(filepath)
    end

    UIManager.show = function(_, widget)
      table.insert(shown_widgets, widget)
    end
    UIManager.close = function(_, widget)
      table.insert(closed_widgets, widget)
    end
    UIManager.nextTick = function(_, fn)
      table.insert(next_ticks, fn)
      fn()
    end

    Device.isKindle = function()
      return false
    end
    Device.isKobo = function()
      return false
    end
  end)

  after_each(function()
    os.execute = orig_execute
    os.remove = orig_remove
    util.pathExists = orig_pathExists
    UIManager.show = orig_show
    UIManager.close = orig_close
    UIManager.nextTick = orig_nextTick
    Device.isKindle = orig_isKindle
    Device.isKobo = orig_isKobo
  end)

  local function createInstance()
    local mock_menu = {
      registerToMainMenu = function() end,
      updateItems = function() end,
    }
    return SSH:new({ ui = { menu = mock_menu } })
  end

  describe("Initialization & basic queries", function()
    it("should initialize SSH plugin instance and register actions", function()
      local instance = createInstance()
      assert.is_table(instance)
      assert.are.equal("SSH", instance.name)
      assert.are.equal("2222", instance.SSH_port)
      assert.is_false(instance:isRunning())
    end)
  end)

  describe("Start and Stop SSH server", function()
    it("should start dropbear server and display InfoMessage when not quiet", function()
      local instance = createInstance()
      instance.allow_no_password = false
      instance.SSH_port = "2222"

      instance:start(false)

      assert.are.equal(1, #shown_widgets)
      local msg = shown_widgets[1]
      assert.is_table(msg)
      assert.is_true(msg.text:find("SSH server started") ~= nil)

      local dropbear_cmd = nil
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("dropbear") then
          dropbear_cmd = cmd
          break
        end
      end
      assert.is_not_nil(dropbear_cmd)
      assert.is_true(dropbear_cmd:find("-p2222") ~= nil)
      assert.is_nil(dropbear_cmd:find("-n"))
    end)

    it("should append -n when allow_no_password is true and suppress message when quiet", function()
      local instance = createInstance()
      instance.allow_no_password = true
      instance.SSH_port = "2224"

      instance:start(true)
      assert.are.equal(0, #shown_widgets) -- quiet suppresses message

      local dropbear_cmd = nil
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("dropbear") then
          dropbear_cmd = cmd
          break
        end
      end
      assert.is_not_nil(dropbear_cmd)
      assert.is_true(dropbear_cmd:find("-p2224") ~= nil)
      assert.is_true(dropbear_cmd:find("-n") ~= nil)
    end)

    it("should show warning when dropbear execution fails", function()
      local instance = createInstance()
      execute_exit_code = 1

      instance:start(false)
      assert.are.equal(1, #shown_widgets)
      local msg = shown_widgets[1]
      assert.are.equal("notice-warning", msg.icon)
      assert.is_true(msg.text:find("Failed to start SSH server") ~= nil)
    end)

    it("should configure iptables for Kindle and devpts for Kobo", function()
      local instance = createInstance()

      -- Kindle mode
      Device.isKindle = function()
        return true
      end
      instance:start(true)

      local has_iptables_input, has_iptables_output = false, false
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("iptables -A INPUT", 1, true) then
          has_iptables_input = true
        end
        if cmd:find("iptables -A OUTPUT", 1, true) then
          has_iptables_output = true
        end
      end
      assert.is_true(has_iptables_input)
      assert.is_true(has_iptables_output)

      -- Kobo mode
      Device.isKindle = function()
        return false
      end
      Device.isKobo = function()
        return true
      end
      executed_cmds = {}
      instance:start(true)

      local has_devpts = false
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("devpts", 1, true) then
          has_devpts = true
          break
        end
      end
      assert.is_true(has_devpts)
    end)

    it("should stop dropbear server and clean up pidfile", function()
      local instance = createInstance()
      is_pid_existing = true

      Device.isKindle = function()
        return true
      end

      instance:stop()

      -- Kills pid and shows stopped message
      local has_kill = false
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("xargs kill", 1, true) then
          has_kill = true
          break
        end
      end
      assert.is_true(has_kill)

      -- Removed pid file
      assert.are.equal(1, #removed_files)
      assert.are.equal("/tmp/dropbear_koreader.pid", removed_files[1])

      -- Message displayed
      assert.are.equal(1, #shown_widgets)
      assert.is_true(shown_widgets[1].text:find("SSH server stopped", 1, true) ~= nil)

      -- Kindle iptables teardown
      local has_iptables_del = false
      for _, cmd in ipairs(executed_cmds) do
        if cmd:find("iptables -D INPUT", 1, true) then
          has_iptables_del = true
          break
        end
      end
      assert.is_true(has_iptables_del)
    end)
  end)

  describe("Toggle, port dialog, and menu items", function()
    it("should toggle server between running and stopped states", function()
      local instance = createInstance()

      -- When not running, toggle starts server
      is_pid_existing = false
      instance:onToggleSSHServer()
      assert.are.equal(1, #shown_widgets)
      assert.is_true(shown_widgets[1].text:find("SSH server started") ~= nil)

      -- When running, toggle stops server
      is_pid_existing = true
      instance:onToggleSSHServer()
      assert.are.equal(2, #shown_widgets)
      assert.is_true(shown_widgets[2].text:find("SSH server stopped") ~= nil)
    end)

    it("should show port dialog and save updated port upon confirmation", function()
      local instance = createInstance()
      local menu_updated = false
      local mock_menu = {
        updateItems = function()
          menu_updated = true
        end,
      }

      instance:show_port_dialog(mock_menu)
      assert.are.equal(1, #shown_widgets)
      local dialog = shown_widgets[1]
      assert.is_table(dialog)

      -- Cancel callback closes dialog
      dialog.buttons[1][1].callback()
      assert.are.equal(1, #closed_widgets)

      -- Save callback updates SSH_port
      dialog.getInputText = function()
        return "2225"
      end
      dialog.buttons[1][2].callback()
      assert.are.equal(2225, instance.SSH_port)
      assert.is_true(menu_updated)
      assert.are.equal(2, #closed_widgets)
    end)

    it("should register menu items and trigger callbacks", function()
      local instance = createInstance()
      local menu_items = {}
      instance:addToMainMenu(menu_items)

      assert.is_table(menu_items.ssh)
      assert.is_table(menu_items.ssh.sub_item_table)
      local sub_items = menu_items.ssh.sub_item_table
      assert.are.equal(5, #sub_items)

      -- Item 1: Toggle server
      local updated = false
      local mock_menu = {
        updateItems = function()
          updated = true
        end,
      }
      sub_items[1].callback(mock_menu)
      assert.is_true(updated)

      -- Item 2: Port configuration enabled when not running
      is_pid_existing = false
      assert.is_true(sub_items[2].enabled_func())
      is_pid_existing = true
      assert.is_false(sub_items[2].enabled_func())

      -- Item 3: Public key info message
      is_pid_existing = false
      sub_items[3].callback()
      local found_key_msg = false
      for _, w in ipairs(shown_widgets) do
        if w.text and w.text:find("authorized_keys") then
          found_key_msg = true
          break
        end
      end
      assert.is_true(found_key_msg)

      -- Item 4: Login without password toggle
      local prev_allow = instance.allow_no_password
      sub_items[4].callback()
      assert.are.equal(not prev_allow, instance.allow_no_password)

      -- Item 5: Auto start toggle
      sub_items[5].callback()
    end)

    it("should handle autoStart when autostart setting is enabled", function()
      local instance = createInstance()
      local orig_isTrue = G_reader_settings.isTrue

      -- When autostart is enabled and server not running -> starts quietly
      G_reader_settings.isTrue = function(_, key)
        if key == "SSH_autostart" then
          return true
        end
        return orig_isTrue(G_reader_settings, key)
      end

      is_pid_existing = false
      instance:autoStart()
      assert.are.equal(1, #next_ticks)

      -- When autostart is disabled -> does not start
      executed_cmds = {}
      G_reader_settings.isTrue = function()
        return false
      end
      instance:autoStart()
      assert.are.equal(1, #next_ticks) -- no new nextTick scheduled

      G_reader_settings.isTrue = orig_isTrue
    end)
  end)
end)
