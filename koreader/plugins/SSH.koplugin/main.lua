local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage") -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")
local logger = require("logger")
local util = require("util")
local T = require("ffi/util").template

if not Device:isKobo() and not Device:isEmulator() then
  return { disabled = true }
end

-- This plugin uses a patched dropbear that adds two things:
-- the -n option to bypass password checks
-- reads the authorized_keys file from the relative path: settings/SSH/authorized_keys

local path = DataStorage:getFullDataDir()
if not util.pathExists("dropbear") then
  return { disabled = true }
end

local auto_started = false

local SSH = WidgetContainer:extend({
  name = "SSH",
  is_doc_only = false,
})

function SSH:init()
  self.SSH_port = G_reader_settings:read("SSH_port") or "2222"
  self.allow_no_password = G_reader_settings:isTrue("SSH_allow_no_password")
  self.ui.menu:registerToMainMenu(self)
  self:onDispatcherRegisterActions()
  if not auto_started then
    auto_started = true
    self:autoStart()
  end
end

function SSH:autoStart()
  if G_reader_settings:isTrue("SSH_autostart") then
    -- Delay this until after all plugins are loaded
    UIManager:nextTick(function()
      if not self:isRunning() then
        self:start(true)
      end
    end)
  end
end

function SSH:start(quiet)
  -- Make a hole in the Kindle's firewall
  if Device:isKindle() then
    os.execute(
      string.format(
        "%s %s %s",
        "iptables -A INPUT -p tcp --dport",
        self.SSH_port,
        "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"
      )
    )
    os.execute(
      string.format(
        "%s %s %s",
        "iptables -A OUTPUT -p tcp --sport",
        self.SSH_port,
        "-m conntrack --ctstate ESTABLISHED -j ACCEPT"
      )
    )
  elseif Device:isKobo() then
    -- An SSH/telnet server of course needs to be able to manipulate
    -- pseudoterminals...
    -- Kobo's init scripts fail to set this up...
    os.execute([[if [ ! -d "/dev/pts" ] ; then
            mkdir -p /dev/pts
            mount -t devpts devpts /dev/pts
            fi]])
  end

  if not util.pathExists(path .. "/settings/SSH/") then
    os.execute("mkdir " .. path .. "/settings/SSH")
  end

  local cmd = string.format(
    "./dropbear -E -R -p%s -P /tmp/dropbear_koreader.pid",
    self.SSH_port
  )
  if self.allow_no_password then
    cmd = cmd .. " -n"
  end

  logger.dbg("[Network] Launching SSH server : ", cmd)
  if os.execute(cmd) == 0 then
    if not quiet then
      UIManager:show(InfoMessage:new({
        timeout = 10,
        -- @translators: %1 is the SSH port, %2 is the network info.
        text = T(
          gettext("SSH server started.\n\nSSH port: %1\n%2"),
          self.SSH_port,
          Device.retrieveNetworkInfo
              and table.concat(Device:retrieveNetworkInfo(), "\n")
            or gettext("Could not retrieve network info.")
        ),
      }))
    end
  else
    UIManager:show(InfoMessage:new({
      icon = "notice-warning",
      text = gettext("Failed to start SSH server."),
    }))
  end
end

function SSH:isRunning()
  return util.pathExists("/tmp/dropbear_koreader.pid")
end

function SSH:stop()
  os.execute("cat /tmp/dropbear_koreader.pid | xargs kill")
  UIManager:show(InfoMessage:new({
    text = T(gettext("SSH server stopped.")),
    timeout = 2,
  }))

  if self:isRunning() then
    os.remove("/tmp/dropbear_koreader.pid")
  end

  -- Plug the hole in the Kindle's firewall
  if Device:isKindle() then
    os.execute(
      string.format(
        "%s %s %s",
        "iptables -D INPUT -p tcp --dport",
        self.SSH_port,
        "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"
      )
    )
    os.execute(
      string.format(
        "%s %s %s",
        "iptables -D OUTPUT -p tcp --sport",
        self.SSH_port,
        "-m conntrack --ctstate ESTABLISHED -j ACCEPT"
      )
    )
  end
end

function SSH:onToggleSSHServer()
  if self:isRunning() then
    self:stop()
  else
    self:start()
  end
end

function SSH:show_port_dialog(touchmenu_instance)
  self.port_dialog = InputDialog:new({
    title = gettext("Choose SSH port"),
    input = self.SSH_port,
    input_type = "number",
    input_hint = self.SSH_port,
    buttons = {
      {
        {
          text = gettext("Cancel"),
          id = "close",
          callback = function()
            UIManager:close(self.port_dialog)
          end,
        },
        {
          text = gettext("Save"),
          is_enter_default = true,
          callback = function()
            local value = tonumber(self.port_dialog:getInputText())
            if value and value >= 0 then
              self.SSH_port = value
              G_reader_settings:save("SSH_port", self.SSH_port)
              UIManager:close(self.port_dialog)
              touchmenu_instance:updateItems()
            end
          end,
        },
      },
    },
  })
  UIManager:show(self.port_dialog)
end

function SSH:addToMainMenu(menu_items)
  menu_items.ssh = {
    text = gettext("SSH server"),
    sub_item_table = {
      {
        text_func = function()
          -- Need localization
          return self:isRunning() and gettext("Stop SSH server")
            or gettext("Stop SSH server")
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
          self:onToggleSSHServer()
          touchmenu_instance:updateItems()
        end,
      },
      {
        text_func = function()
          return T(gettext("SSH port (%1)"), self.SSH_port)
        end,
        keep_menu_open = true,
        enabled_func = function()
          return not self:isRunning()
        end,
        -- Need localization
        help_text = gettext("Stop SSH server to configure"),
        callback = function(touchmenu_instance)
          self:show_port_dialog(touchmenu_instance)
        end,
      },
      {
        text = gettext("SSH public key"),
        keep_menu_open = true,
        enabled_func = function()
          return not self:isRunning()
        end,
        -- Need localization
        help_text = gettext("Stop SSH server to configure"),
        callback = function()
          local info = InfoMessage:new({
            timeout = 60,
            text = T(
              gettext("Put your public SSH keys in\n%1"),
              BD.filepath(path .. "/settings/SSH/authorized_keys")
            ),
          })
          UIManager:show(info)
        end,
      },
      {
        text = gettext("Login without password (DANGEROUS)"),
        checked_func = function()
          return self.allow_no_password
        end,
        enabled_func = function()
          return not self:isRunning()
        end,
        -- Need localization
        help_text = gettext("Stop SSH server to configure"),
        callback = function()
          self.allow_no_password = not self.allow_no_password
          G_reader_settings:flipNilOrFalse("SSH_allow_no_password")
        end,
      },
      {
        -- Need localization
        text = gettext("Auto start SSH server"),
        checked_func = function()
          return G_reader_settings:isTrue("SSH_autostart")
        end,
        callback = function()
          G_reader_settings:flipNilOrFalse("SSH_autostart")
          self:autoStart()
        end,
      },
    },
  }
end

function SSH:onDispatcherRegisterActions()
  Dispatcher:registerAction("toggle_ssh_server", {
    category = "none",
    event = "ToggleSSHServer",
    title = gettext("Toggle SSH server"),
    general = true,
  })
end

return SSH
