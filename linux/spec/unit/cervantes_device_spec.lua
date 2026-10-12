-- luacheck: ignore 122
local orig_open = io.open
local orig_popen = io.popen
local orig_execute = os.execute

-- Intercept pcb check during device module probe
io.popen = function(cmd, mode)
  if cmd:find("ntxinfo", 1, true) then
    return {
      read = function(self, fmt)
        return 68 -- Cervantes 4
      end,
      close = function(self) end,
    }
  end
  return orig_popen(cmd, mode)
end

require("commonrequire")
package.loaded["device/cervantes/device"] = nil
local Cervantes4 = require("device/cervantes/device")

-- Restore io.popen after initial require
io.popen = orig_popen

describe("Cervantes device", function()
  describe("hardware properties and models", function()
    it(
      "reports correct model and platform capabilities for Cervantes 4",
      function()
        assert.are.equal("Cervantes4", Cervantes4.model)
        assert.is_true(Cervantes4:isCervantes())
        assert.is_true(Cervantes4:isAlwaysPortrait())
        assert.is_true(Cervantes4:hasFrontlight())
        assert.is_true(Cervantes4:hasNaturalLight())
        assert.is_true(Cervantes4:canSuspend())
        assert.is_true(Cervantes4:canReboot())
        assert.is_true(Cervantes4:canPowerOff())
        assert.are.equal("/mnt/public", Cervantes4.home_dir)
        assert.are.equal(300, Cervantes4.display_dpi)
      end
    )

    it("checks mass storage support via safemode file", function()
      io.open = function(path, mode)
        if path == "/usr/share/safemode/version" then
          return {
            close = function(self) end,
          }
        end
        return orig_open(path, mode)
      end
      assert.is_true(Cervantes4.canToggleMassStorage())

      io.open = function(path, mode)
        if path == "/usr/share/safemode/version" then
          return nil
        end
        return orig_open(path, mode)
      end
      assert.is_false(Cervantes4.canToggleMassStorage())
      io.open = orig_open
    end)
  end)

  describe("setDateTime", function()
    local executed_cmds = {}

    before_each(function()
      executed_cmds = {}
      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end
    end)

    after_each(function()
      os.execute = orig_execute
    end)

    it("executes date and hwclock for complete date and time", function()
      local res = Cervantes4:setDateTime(2026, 10, 10, 15, 45, 30)
      assert.is_true(res)
      assert.are.equal("date -s '2026-10-10 15:45:30'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("executes date time-only when date parts omitted", function()
      local res = Cervantes4:setDateTime(nil, nil, nil, 12, 0, 0)
      assert.is_true(res)
      assert.are.equal("date -s '12:0'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("returns true without executing when hour or min is nil", function()
      local res = Cervantes4:setDateTime(2026, 10, 10, nil, 30, 0)
      assert.is_true(res)
      assert.are.equal(0, #executed_cmds)
    end)
  end)

  describe("power actions", function()
    local executed_cmds = {}

    before_each(function()
      executed_cmds = {}
      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end
    end)

    after_each(function()
      os.execute = orig_execute
    end)

    it("executes suspend and resume scripts", function()
      Cervantes4:suspend()
      assert.are.equal("./suspend.sh", executed_cmds[1])

      Cervantes4:resume()
      assert.are.equal("./resume.sh", executed_cmds[2])
    end)

    it("executes reboot and powerOff commands", function()
      Cervantes4:reboot()
      assert.are.equal("sleep 1 && reboot &", executed_cmds[1])

      Cervantes4:powerOff()
      assert.are.equal("sleep 1 && halt &", executed_cmds[2])
    end)
  end)

  describe("NetworkManager integration", function()
    local mock_network_mgr
    local executed_cmds = {}
    local release_ip_called = false
    local check_wifi_called = false

    before_each(function()
      executed_cmds = {}
      release_ip_called = false
      check_wifi_called = false

      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end

      mock_network_mgr = {
        releaseIP = function(self)
          release_ip_called = true
        end,
        reconnect = function(self, cb, interactive)
          return true
        end,
        setWirelessBackend = function(self, backend, config)
          self.backend = backend
          self.config = config
        end,
        _asyncCheckWifiState = function(self)
          check_wifi_called = true
        end,
        killRestoreWifiAsync = function(self) end,
      }

      Cervantes4:initNetworkManager(mock_network_mgr)
    end)

    after_each(function()
      os.execute = orig_execute
    end)

    it("configures eth0 interface and wpa_supplicant backend", function()
      assert.are.equal("eth0", mock_network_mgr:getNetworkInterfaceName())
      assert.are.equal("wpa_supplicant", mock_network_mgr.backend)
      assert.are.equal(
        "/var/run/wpa_supplicant/eth0",
        mock_network_mgr.config.ctrl_interface
      )
    end)

    it("turns off wifi by releasing IP and calling disable-wifi.sh", function()
      mock_network_mgr:_turnOffWifi()
      assert.are.equal("./release-ip.sh", executed_cmds[1])
      assert.are.equal("./disable-wifi.sh", executed_cmds[2])
    end)

    it("turns on wifi by calling enable-wifi.sh and reconnecting", function()
      local ok = mock_network_mgr:_turnOnWifi()
      assert.is_true(ok)
      assert.are.equal("./enable-wifi.sh", executed_cmds[1])
    end)

    it("restoreWifiAsync executes restore-wifi-async.sh", function()
      mock_network_mgr:restoreWifiAsync()
      assert.are.equal("./restore-wifi-async.sh", executed_cmds[1])
    end)
  end)
end)
