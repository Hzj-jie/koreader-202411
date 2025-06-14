local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local ffiutil = require("ffi/util")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local C = ffi.C
local T = ffiutil.template

-- We'll need a bunch of stuff for getifaddrs in NetworkMgr:ifHasAnAddress
require("ffi/posix_h")

-- We unfortunately don't have that one in ffi/posix_h :/
local EBUSY = 16

local NetworkMgr = {
  pending_connectivity_check = false,
  pending_connection = false,

  was_online = false,
}

local function raiseNetworkEvent(t)
  UIManager:broadcastEvent(Event:new("Network" .. t))
  UIManager:broadcastEvent(Event:new("NetworkStateChanged"))
end

function NetworkMgr:_networkConnected()
  raiseNetworkEvent("Connected")
  UIManager:nextTick(function()
    -- This is a hacky way to ensure the NetworkOnline event can be triggered
    -- after a NetworkConnected event.
    self.was_online = false
    self:_queryOnlineState()
  end)
end

function NetworkMgr:_networkDisconnected()
  -- A less preferred way to allow Emulator raising the events.
  raiseNetworkEvent("Disconnected")
end

function NetworkMgr:_readNWSettings()
  self.nw_settings =
    LuaSettings:open(DataStorage:getSettingsDir() .. "/network.lua")
end

-- Common chunk of stuff we have to do when aborting a connection attempt
function NetworkMgr:_dropPendingWifiConnection(
  mark_wifi_was_off,
  turn_off_wifi,
  turn_off_wifi_callback
)
  -- Cancel any pending connectivity check, because it wouldn't achieve anything
  self:_unscheduleConnectivityCheck()
  -- Make sure we don't have an async script running...
  if Device:hasWifiRestore() then
    self:stopAsyncWifiRestore()
  end
  -- Can't be connecting since we're killing Wi-Fi ;)
  self.pending_connection = false

  if turn_off_wifi then
    self:_turnOffWifi(turn_off_wifi_callback)
  end

  if mark_wifi_was_off then
    G_reader_settings:makeFalse("wifi_was_on")
  end
end

function NetworkMgr:_abortWifiConnection()
  -- We only want to actually kill the WiFi on platforms where we can do that seamlessly.
  return self:_dropPendingWifiConnection(true, Device:hasSeamlessWifiToggle())
end

-- Attempt to deal with platforms that don't guarantee isConnected when turnOnWifi returns,
-- so that we only attempt to connect to WiFi *once* when using the beforeWifiAction framework...
function NetworkMgr:_requestToTurnOnWifi(wifi_cb, interactive) -- bool | EBUSY
  if self.pending_connection then
    -- We've already enabled WiFi, don't try again until the earlier attempt succeeds or fails...
    return EBUSY
  end

  -- Connecting will take a few seconds, broadcast that information so affected modules/plugins can react.
  raiseNetworkEvent("Connecting")
  self.pending_connection = true

  return self:_turnOnWifi(wifi_cb, interactive)
end

-- Used after restoreWifiAsync() and the turn_on beforeWifiAction to make sure we eventually send a NetworkConnected event,
-- as quite a few things rely on it (KOSync, c.f. #5109; the network activity check, c.f., #6424).
function NetworkMgr:_connectivityCheck(iter, callback, interactive)
  -- Give up after a while (restoreWifiAsync can take over 45s, so, try to cover that)...
  if iter >= 180 then
    logger.info("Failed to restore Wi-Fi (after", iter * 0.25, "seconds)!")
    self:_abortWifiConnection()

    -- Handle the UI warning if it's from a beforeWifiAction...
    if interactive then
      UIManager:show(
        InfoMessage:new({ text = _("Error connecting to the network") })
      )
    end
    return
  end

  if self:_isWifiConnected() then
    G_reader_settings:makeTrue("wifi_was_on")
    logger.info("Wi-Fi successfully restored (after", iter * 0.25, "seconds)!")
    self:_networkConnected()

    if callback then
      callback()
    else
      -- If this trickled down from a turn_onbeforeWifiAction and there is no callback,
      -- mention that the action needs to be retried manually.
      if interactive then
        UIManager:show(InfoMessage:new({
          text = _("You can now retry the action that required network access"),
          timeout = 3,
        }))
      end
    end
    self.pending_connectivity_check = false
    -- We're done, so we can stop blocking concurrent connection attempts
    self.pending_connection = false
  else
    UIManager:scheduleIn(
      0.25,
      self._connectivityCheck,
      self,
      iter + 1,
      callback,
      interactive
    )
  end
end

function NetworkMgr:_scheduleConnectivityCheck(callback, interactive)
  self.pending_connectivity_check = true
  UIManager:scheduleIn(
    0.25,
    self._connectivityCheck,
    self,
    1,
    callback,
    interactive
  )
end

function NetworkMgr:_unscheduleConnectivityCheck()
  UIManager:unschedule(self._connectivityCheck)
  self.pending_connectivity_check = false
end

function NetworkMgr:shouldRestoreWifi()
  return Device:hasWifiRestore()
    and G_reader_settings:isTrue("wifi_was_on")
    and G_reader_settings:isTrue("auto_restore_wifi")
end

function NetworkMgr:restoreWifiAndCheckAsync(msg)
  -- Attempt to restore wifi in the background if necessary
  if self:shouldRestoreWifi() then
    if msg then
      logger.dbg(msg)
    end
    self:restoreWifiAsync()
    self:_scheduleConnectivityCheck()
  end
end

function NetworkMgr:_queryOnlineState()
  logger.info("NetworkMgr: _queryOnlineState, was_online",
              tostring(self.was_online),
              ", isWifiConnected ",
              tostring(self:_isWifiConnected()))
  local last_state = self.was_online
  if self:_isWifiConnected() then
    self.was_online = self:_isOnline()
  else
    self.was_online = false
  end
  if last_state ~= self.was_online then
    if self.was_online then
      raiseNetworkEvent("Online")
    else
      raiseNetworkEvent("Offline")
    end
  end
end

function NetworkMgr:init()
  Device:initNetworkManager(self)

  -- Trigger an initial NetworkConnected event if WiFi was already up when we
  -- were launched
  if self:_isWifiConnected() then
    -- NOTE: This needs to be delayed because we run on require, while
    -- NetworkListener gets spun up sliiightly later on FM/ReaderUI init...
    UIManager:nextTick(function()
      self:_networkConnected()
    end)
  else
    self:restoreWifiAndCheckAsync(
      "NetworkMgr: init will restore Wi-Fi in the background"
    )
  end
  if Device:hasWifiToggle() then
    UIManager:nextTick(function()
      -- Initial state.
      self:_queryOnlineState()
      require("background_jobs").insert({
        when = 60,
        repeated = true,
        executable = function()
          self:_queryOnlineState()
        end,
      })
    end)
  end

  return self
end

-- The following methods are Device specific, and need to be initialized in Device:initNetworkManager.
-- Some of them can be set by calling NetworkMgr:setWirelessBackend
-- NOTE: The interactive flag is set by callers when the toggle was a *direct* user prompt (i.e., Menu or Gesture),
--     as opposed to an indirect one (like the beforeWifiAction framework).
--     It allows the backend to skip UI prompts for non-interactive use-cases.
-- NOTE: May optionally return a boolean, e.g., return false if the backend can guarantee the connection failed.
-- NOTE: These *must* run or appropriately forward complete_callback (e.g., to reconnectOrShowNetworkMenu),
--     as said callback is responsible for schedulig the connectivity check,
--     which, in turn, is responsible for the Event signaling!
function NetworkMgr:_turnOnWifi(complete_callback, interactive) end
function NetworkMgr:_turnOffWifi(complete_callback) end

--- There are three states of the network.
--- 1. isWifiOn
---    wifi is on, not connected.
--- 2. isConnected
---    wifi is connected, usually the ip should be assigned via obtainIP, unless
---    the platform has no way to force obtaining IP address. may or may not
---    have the internet access.
--- 3. isOnline
---    have internet access.
--- isConnected implies isWifiOn, isOnline implies isConnected and isWifiOn - if
--- wifi is the only way of network access, i.e. not android.
--- There are 5 events (4 have been implemented)
--- Connecting, start connecting the wifi, raised before turning on wifi or
---             initiate the connection. isWifiOn may be true or false when this
---             event is raised, but isConnected is guranteed to be false.
--- Connected, the connection is generated, isConnected is true when this event
---            is raised.
--- Disconnecting, start disconnecting and turning off the wifi, raised before
---                turning off wifi. isConnected is guranteed to be true when
---                this event is raised.
--- Disconnected, the connection is dropped and the wifi is turned off, raised
---               after turning off wifi. isWifiOn is guranteed to be false when
---               this event is raised.
--- Onlined, the internet access is verified, raised after isOnline becoming
---          true.
--- Note, network access is not a reliable state, so the gurantees above only
--- indicates the states changes rather than the network state when the event
--- handles are executing. e.g. if isConnected is true, the logic of enabling
--- wifi will not be executed at all, thus the onNetworkConnecting event.
---
--- The uses of Connecting and Disconnecting events are questionable, and may
--- be removed sooner or later.

-- This function returns the current status of the WiFi radio
-- NOTE: On !hasWifiToggle platforms, we assume networking is always available,
--     so as not to confuse the whole beforeWifiAction framework
--     (and let it fail with network errors when offline, instead of looping on unimplemented stuff...).
-- It's expected to be a cheap operation; if the implementation is heavy, use a cache.
function NetworkMgr:isWifiOn()
  return not Device:hasWifiToggle()
end
-- This function is expected to be overridden by device.
-- It's expected to be a cheap operation; if the implementation is heavy, use a cache.
function NetworkMgr:isConnected()
  return not Device:hasWifiToggle()
end

-- A shortcut of isWifiOn and isConnected, do not expect to be overridden.
-- The state of isConnected but !isWifiOn is in general not supported.
function NetworkMgr:_isWifiConnected()
  if not Device:hasWifiToggle() then
    return true
  end
  return self:isWifiOn() and self:isConnected()
end

function NetworkMgr:getNetworkInterfaceName() end
function NetworkMgr:getConfiguredNetworks() end -- From the *backend*, e.g., wpa_cli list_networks (as opposed to `getAllSavedNetworks`)
function NetworkMgr:getNetworkList() end
function NetworkMgr:getCurrentNetwork() end
function NetworkMgr:authenticateNetwork(network) end
function NetworkMgr:disconnectNetwork(network) end
-- NOTE: This is currently only called on hasWifiManager platforms!
function NetworkMgr:obtainIP() end
function NetworkMgr:releaseIP() end
-- This function should call both turnOnWifi() and obtainIP() in a non-blocking manner.
function NetworkMgr:restoreWifiAsync() end
-- This function should stop the pending restoreWifiAsync if any.
function NetworkMgr:stopAsyncWifiRestore() end
-- End of device specific methods

-- Helper function if restore-wifi-async.sh is implemented.
function NetworkMgr:killRestoreWifiAsync()
  os.execute("pkill -TERM restore-wifi-async.sh 2>/dev/null")
end

-- Helper functions for devices that use sysfs entries to check connectivity.
function NetworkMgr:sysfsWifiOn()
  -- Network interface directory only exists as long as the Wi-Fi module is loaded
  return util.pathExists("/sys/class/net/" .. self:getNetworkInterfaceName())
end

function NetworkMgr:sysfsCarrierConnected()
  -- Read carrier state from sysfs.
  -- NOTE: We can afford to use CLOEXEC, as devices too old for it don't support Wi-Fi anyway ;)
  local out
  local file = io.open(
    "/sys/class/net/" .. self:getNetworkInterfaceName() .. "/carrier",
    "re"
  )

  -- File only exists while the Wi-Fi module is loaded, but may fail to read until the interface is brought up.
  if file then
    -- 0 means the interface is down, 1 that it's up
    -- (technically, it reflects the state of the physical link (e.g., plugged in or not for Ethernet))
    -- This does *NOT* represent network association state for Wi-Fi (it'll return 1 as soon as ifup)!
    out = file:read("*number")
    file:close()
  end

  return out == 1
end

function NetworkMgr:sysfsInterfaceOperational()
  -- Reads the interface's RFC2863 operational state from sysfs, and wait for it to be up
  -- (For Wi-Fi, that means associated & successfully authenticated)
  local out
  local file = io.open(
    "/sys/class/net/" .. self:getNetworkInterfaceName() .. "/operstate",
    "re"
  )

  -- Possible values: "unknown", "notpresent", "down", "lowerlayerdown", "testing", "dormant", "up"
  -- (c.f., Linux's <Documentation/ABI/testing/sysfs-class-net>)
  -- We're *assuming* all the drivers we care about implement this properly, so we can just rely on checking for "up".
  -- On unsupported drivers, this would be stuck on "unknown" (c.f., Linux's <Documentation/networking/operstates.rst>)
  -- NOTE: This does *NOT* mean the interface has been assigned an IP!
  if file then
    out = file:read("*l")
    file:close()
  end

  return out == "up"
end

-- This relies on the BSD API instead of the Linux ioctls (netdevice(7)), because handling IPv6 is slightly less painful this way...
function NetworkMgr:ifHasAnAddress()
  -- If the interface isn't operationally up, no need to go any further
  if not self:sysfsInterfaceOperational() then
    logger.dbg("NetworkMgr: interface is not operational yet")
    return false
  end

  -- It's up, do the getifaddrs dance to see if it was assigned an IP yet...
  -- c.f., getifaddrs(3)
  local ifaddr = ffi.new("struct ifaddrs *[1]")
  if C.getifaddrs(ifaddr) == -1 then
    local errno = ffi.errno()
    logger.err("NetworkMgr: getifaddrs:", ffi.string(C.strerror(errno)))
    return false
  end

  local ok
  local ifa = ifaddr[0]
  while ifa ~= nil do
    if
      ifa.ifa_addr ~= nil
      and C.strcmp(ifa.ifa_name, self:getNetworkInterfaceName()) == 0
    then
      local family = ifa.ifa_addr.sa_family
      if family == C.AF_INET or family == C.AF_INET6 then
        local host = ffi.new("char[?]", C.NI_MAXHOST)
        local s = C.getnameinfo(
          ifa.ifa_addr,
          family == C.AF_INET and ffi.sizeof("struct sockaddr_in")
            or ffi.sizeof("struct sockaddr_in6"),
          host,
          C.NI_MAXHOST,
          nil,
          0,
          C.NI_NUMERICHOST
        )
        if s ~= 0 then
          logger.err("NetworkMgr: getnameinfo:", ffi.string(C.gai_strerror(s)))
          ok = false
        else
          logger.dbg(
            "NetworkMgr: interface",
            self:getNetworkInterfaceName(),
            "is up @",
            ffi.string(host)
          )
          ok = true
        end
        -- Regardless of failure, we only check a single if, so we're done
        break
      end
    end
    ifa = ifa.ifa_next
  end
  C.freeifaddrs(ifaddr[0])

  return ok
end

--[[
-- This function costs 10ms on kindle with great wifi connection, it's slow naturally.
-- The socket API equivalent of "ip route get 203.0.113.1 || ip route get 2001:db8::1".
--
-- These addresses are from special ranges reserved for documentation
-- (RFC 5737, RFC 3849) and therefore likely to just use the default route.
function NetworkMgr:_hasDefaultRoute()
  local socket = require("socket")

  local s, ret, err
  s, err = socket.udp()
  if s == nil then
    logger.err("NetworkMgr: socket.udp:", err)
    return nil
  end

  ret, err = s:setpeername("203.0.113.1", "53")
  if ret == nil then
    -- Most likely "Network is unreachable", meaning there's no route to that address.
    logger.dbg("NetworkMgr: socket.udp.setpeername:", err)

    -- Try IPv6, may still succeed if this is an IPv6-only network.
    ret, err = s:setpeername("2001:db8::1", "53")
    if ret == nil then
      -- Most likely "Network is unreachable", meaning there's no route to that address.
      logger.dbg("NetworkMgr: socket.udp.setpeername:", err)
    end
  end

  s:close()

  -- If setpeername succeeded, we have a default route.
  return ret ~= nil
end

-- Use microsoft services by default to allow accessing in mainland china.

-- This function costs 100ms on kindle with great wifi connection, it's slow naturally.
function NetworkMgr:_canResolveHostnames()
  -- Microsoft uses `dns.msftncsi.com` for Windows, see
  -- <https://technet.microsoft.com/en-us/library/ee126135#BKMK_How> for
  -- more information. They also check whether <http://www.msftncsi.com/ncsi.txt>
  -- returns `Microsoft NCSI`.
  return require("socket").dns.toip("dns.msftncsi.com") ~= nil
end
--]]

-- This function costs 100ms on kindle with great wifi connection, it's slow naturally.
function NetworkMgr:_canPingMicrosoftCom()
  local ip = require("socket").dns.toip("www.microsoft.com")
  if ip == nil then
    return false
  end
  return Device:ping4(ip)
end

function NetworkMgr:toggleWifiOn(wifi_cb) -- false | nil
  if self:_isWifiConnected() then
    if wifi_cb then
      wifi_cb()
    end
    return
  end

  local info = InfoMessage:new({
    text = _("Turning on Wi-Fi…"),
  })
  UIManager:show(info)
  UIManager:forceRePaint()
  -- NOTE: Let the backend run the wifi_cb via a connectivity check once it's *actually* attempted a connection,
  --     as it knows best when that actually happens (especially reconnectOrShowNetworkMenu), unlike us.
  local connectivity_cb = function()
    -- NOTE: We *could* arguably have multiple connectivity checks running concurrently,
    --     but only having a single one running makes things somewhat easier to follow...
    if self.pending_connectivity_check then
      self:_unscheduleConnectivityCheck()
    end

    -- This will handle sending the proper Event, manage wifi_was_on, as well as tearing down Wi-Fi in case of failures.
    self:_scheduleConnectivityCheck(function()
      if wifi_cb then
        wifi_cb()
      end
    end, true)
  end

  -- Some implementations (usually, hasWifiManager) can report whether they were successful
  local status = self:_requestToTurnOnWifi(connectivity_cb, true)
  -- Note, when showing the network list, the callback would be heavily delayed, and the info will
  -- block the list.
  UIManager:close(info)
  -- If turnOnWifi failed, abort early
  if status == false then
    logger.warn("NetworkMgr:toggleWifiOn: Connection failed!")
    self:_abortWifiConnection()
    return false
  elseif status == EBUSY then
    -- NOTE: This means turnOnWifi was *not* called (this time).
    logger.warn(
      "NetworkMgr:toggleWifiOn: A previous connection attempt is still ongoing!"
    )
    -- We don't really have a great way of dealing with the wifi_cb in this case, we'll just drop
    -- it...
    -- We don't want to run multiple concurrent connectivity checks,
    -- which means we'd need to unschedule the pending one, which would effectively rewind the timer,
    -- which we don't want, especially if we're non-interactive,
    -- as that would risk rescheduling the same thing over and over again...
    if wifi_cb then
      logger.warn(
        "NetworkMgr:toggleWifiOn: We've had to drop wifi_cb:",
        wifi_cb
      )
    end
    UIManager:close(info)
    UIManager:show(InfoMessage:new({
      text = _(
        "A previous connection attempt is still ongoing, this one will be ignored!"
      ),
      timeout = 3,
    }))
  end
end

function NetworkMgr:toggleWifiOff(complete_callback, interactive)
  if not self:isWifiOn() then
    return
  end

  local info
  if interactive then
    info = InfoMessage:new({
      text = _("Turning off Wi-Fi…"),
    })
    UIManager:show(info)
    UIManager:forceRePaint()
  end

  local complete_callback = function()
    self:_networkDisconnected()
    if cb then
      cb()
    end
  end
  raiseNetworkEvent("Disconnecting")

  self:_dropPendingWifiConnection(interactive, true, complete_callback)
  if interactive then
    -- Note, similar to the toggleWifiOn, the info will be dismissed before the connection is fully
    -- dropped.
    UIManager:close(info)
  end
end

-- NOTE: Only used by the beforeWifiAction framework, so, can never be flagged as "interactive" ;).
function NetworkMgr:_promptWifiOn(complete_callback) -- void
  -- If there's already an ongoing connection attempt, don't even display the ConfirmBox,
  -- as that's just confusing, especially on Android, because you might have seen the one you tapped "Turn on" on disappear,
  -- and be surprised by new ones that popped up out of focus while the system settings were opened...
  if self.pending_connection then
    -- Like other beforeWifiAction backends, the callback is forfeit anyway
    logger.warn(
      "NetworkMgr:promptWifiOn: A previous connection attempt is still ongoing!"
    )
    return
  end

  UIManager:show(ConfirmBox:new({
    text = _("Do you want to turn on Wi-Fi?"),
    ok_text = _("Turn on"),
    ok_callback = function()
      self:toggleWifiOn(complete_callback)
    end,
  }))
end

-- This is only used on Android, the intent being we assume the system will eventually turn on WiFi on its own in the background...
function NetworkMgr:_doNothingAndWaitForConnection(callback) -- void
  if self:_isWifiConnected() then
    if callback then
      callback()
    end
    return
  end

  self:_scheduleConnectivityCheck(callback)
end

--- @note: The callback will only run *after* a *successful* network connection.
---    The only guarantee it provides is isConnected (i.e., an IP & a local gateway),
---    *NOT* isOnline (i.e., WAN), se be careful with recursive callbacks!
---    Should only return false on *explicit* failures,
---    in which case the backend will already have called _abortWifiConnection
function NetworkMgr:_beforeWifiAction(callback) -- false | nil
  local wifi_enable_action = G_reader_settings:readSetting("wifi_enable_action")
  if wifi_enable_action == "turn_on" then
    return self:toggleWifiOn(callback)
  elseif wifi_enable_action == "ignore" then
    return self:_doNothingAndWaitForConnection(callback)
  else
    return self:_promptWifiOn(callback)
  end
end

-- This function is slow naturally, especially on weak internet connections.
-- It's not expected to override this function, it provides platform independent ways of checking
-- internet access.
function NetworkMgr:_isOnline()
  assert(Device:hasWifiToggle())
  return self:_canPingMicrosoftCom()
  --[[
  local dr = self:_hasDefaultRoute()
  local rh = self:_canResolveHostnames()
  if dr ~= rh then
    logger.info(
      "_hasDefaultRoute ",
      tostring(dr),
      " returns different value compared with _canResolveHostnames ",
      tostring(rh)
    )
  end
  return dr
  ]]--
end

-- Return a cached online state from the last _isOnline call.
function NetworkMgr:isOnline()
  -- For the same reasons as isWifiOn and isConnected above, bypass this on !hasWifiToggle platforms.
  if not Device:hasWifiToggle() then
    return true
  end

  -- Updating self.was_online may be delayed as long as 1 minute.
  return self:_isWifiConnected() and self.was_online
end

function NetworkMgr:setHTTPProxy(proxy)
  local http = require("socket.http")
  http.PROXY = proxy
  if proxy then
    G_reader_settings:saveSetting("http_proxy", proxy)
    G_reader_settings:makeTrue("http_proxy_enabled")
  else
    G_reader_settings:makeFalse("http_proxy_enabled")
  end
end

-- Helper functions to hide the quirks of using beforeWifiAction properly ;).

-- Run callback *now* if you're currently online (ie., isOnline),
-- or attempt to go online and run it *ASAP* without any more user interaction.
-- NOTE: If you're currently connected but without Internet access (i.e., isConnected and not isOnline),
--     it will just attempt to re-connect, *without* running the callback.
-- c.f., ReaderWikipedia:onShowWikipediaLookup @ frontend/apps/reader/modules/readerwikipedia.lua
function NetworkMgr:runWhenOnline(callback)
  if self:isOnline() then
    callback()
  else
    --- @note: Avoid infinite recursion, beforeWifiAction only guarantees isConnected, not isOnline.
    if self:_isWifiConnected() then
      self:_beforeWifiAction()
    else
      self:_beforeWifiAction(callback)
    end
  end
end

-- This one is for callbacks that only require isConnected, and since that's
-- guaranteed by beforeWifiAction, you also have a guarantee that the callback
-- *will* run.
function NetworkMgr:runWhenConnected(callback)
  if self:_isWifiConnected() then
    callback()
  else
    self:_beforeWifiAction(callback)
  end
end

-- Mild variants that are used for recursive calls at the beginning of a complex function call.
-- Returns true when not yet online, in which case you should *abort* (i.e., return) the initial call,
-- and otherwise, go-on as planned.
-- NOTE: If you're currently connected but without Internet access (i.e., isConnected and not isOnline),
--     it will just attempt to re-connect, *without* running the callback.
-- c.f., ReaderWikipedia:lookupWikipedia @ frontend/apps/reader/modules/readerwikipedia.lua
function NetworkMgr:willRerunWhenOnline(callback)
  if self:isOnline() then
    return false
  end
  --- @note: Avoid infinite recursion, beforeWifiAction only guarantees
  --- isConnected, not isOnline.
  if self:_isWifiConnected() then
    self:_beforeWifiAction()
  else
    self:_beforeWifiAction(callback)
  end
  return true
end

-- This one is for callbacks that only require isConnected, and since that's
-- guaranteed by beforeWifiAction, you also have a guarantee that the callback
-- *will* run.
function NetworkMgr:willRerunWhenConnected(callback)
  if self:_isWifiConnected() then
    return false
  end
  self:_beforeWifiAction(callback)
  return true
end

function NetworkMgr:getWifiMenuTable()
  if Device:isAndroid() then
    return {
      text = _("Wi-Fi settings"),
      callback = function()
        self:_openSettings()
      end,
    }
  else
    return self:getWifiToggleMenuTable()
  end
end

function NetworkMgr:getWifiToggleMenuTable()
  return {
    text = _("Wi-Fi connection"),
    enabled_func = function()
      return Device:hasWifiToggle()
    end,
    checked_func = function()
      return self:isWifiOn()
    end,
    callback = function(menu)
      local complete_callback = function()
        -- Notify TouchMenu to update item check state
        menu:updateItems()
      end -- complete_callback()
      -- interactive
      if self:isWifiOn() then
        self:toggleWifiOff(complete_callback, true)
      else
        self:toggleWifiOn(complete_callback)
      end
    end,
    hold_callback = function(menu)
      if self:isWifiOn() then
        self:reconnectOrShowNetworkMenu(
          function()
            menu:updateItems()
          end,
          -- interactive
          true,
          -- prefer_list
          true
        )
      end
    end,
  }
end

function NetworkMgr:getProxyMenuTable()
  local proxy_enabled = function()
    return G_reader_settings:readSetting("http_proxy_enabled")
  end
  local proxy = function()
    return G_reader_settings:readSetting("http_proxy")
  end
  return {
    text_func = function()
      return T(_("HTTP proxy %1"), (proxy_enabled() and BD.url(proxy()) or ""))
    end,
    checked_func = function()
      return proxy_enabled()
    end,
    callback = function()
      if not proxy_enabled() and proxy() then
        self:setHTTPProxy(proxy())
      elseif proxy_enabled() then
        self:setHTTPProxy(nil)
      end
      if not proxy() then
        UIManager:show(InfoMessage:new({
          text = _(
            "Tip:\nLong press on this menu entry to configure HTTP proxy."
          ),
        }))
      end
    end,
    hold_input = {
      title = _("Enter proxy address"),
      hint = proxy(),
      callback = function(input)
        self:setHTTPProxy(input)
      end,
    },
  }
end

function NetworkMgr:getPowersaveMenuTable()
  return {
    text = _("Disable Wi-Fi connection when inactive"),
    help_text = Device:isKindle()
        and _(
          [[This is unlikely to function properly on a stock Kindle, given how much network activity the framework generates.]]
        )
      or _(
        [[This will automatically turn Wi-Fi off after a generous period of network inactivity, without disrupting workflows that require a network connection, so you can just keep reading without worrying about battery drain.]]
      ),
    checked_func = function()
      return G_reader_settings:isTrue("auto_disable_wifi")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("auto_disable_wifi")
      -- NOTE: Well, not exactly, but the activity check wouldn't be (un)scheduled until the next Network(Dis)Connected event...
      UIManager:askForRestart()
    end,
  }
end

function NetworkMgr:getRestoreMenuTable()
  return {
    text = _("Restore Wi-Fi connection on resume"),
    -- i.e., *everything* flips wifi_was_on true, but only direct user interaction (i.e., Menu & Gestures) will flip it off.
    help_text = _(
      [[This will attempt to automatically and silently re-connect to Wi-Fi on startup or on resume if Wi-Fi used to be enabled the last time you used KOReader, and you did not explicitly disable it.]]
    ),
    checked_func = function()
      return G_reader_settings:isTrue("auto_restore_wifi")
    end,
    enabled_func = function()
      return Device:hasWifiRestore()
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("auto_restore_wifi")
    end,
  }
end

function NetworkMgr:getInfoMenuTable()
  return {
    text = _("Network info"),
    keep_menu_open = true,
    enabled_func = function()
      -- Technically speaking self:isConnected() == true means
      -- self:isWifiOn() == true.
      return Device:isAndroid() or self:isConnected() or self:isWifiOn()
    end,
    callback = function()
      UIManager:broadcastEvent(Event:new("ShowNetworkInfo"))
    end,
  }
end

function NetworkMgr:getBeforeWifiActionMenuTable()
  local wifi_enable_action_setting = G_reader_settings:readSetting(
    "wifi_enable_action"
  ) or "prompt"
  local wifi_enable_actions = {
    turn_on = { _("turn on"), _("Turn on") },
    prompt = { _("prompt"), _("Prompt") },
  }
  if Device:isAndroid() then
    wifi_enable_actions.ignore = { _("ignore"), _("Ignore") }
  end
  local action_table = function(wifi_enable_action)
    return {
      text = wifi_enable_actions[wifi_enable_action][2],
      checked_func = function()
        return wifi_enable_action_setting == wifi_enable_action
      end,
      callback = function()
        wifi_enable_action_setting = wifi_enable_action
        G_reader_settings:saveSetting("wifi_enable_action", wifi_enable_action)
      end,
    }
  end

  local t = {
    text_func = function()
      return T(
        _("Action when Wi-Fi is off: %1"),
        wifi_enable_actions[wifi_enable_action_setting][1]
      )
    end,
    sub_item_table = {
      action_table("turn_on"),
      action_table("prompt"),
    },
  }
  if Device:isAndroid() then
    table.insert(t.sub_item_table, action_table("ignore"))
  end

  return t
end

function NetworkMgr:getDismissScanMenuTable()
  return {
    text = _("Dismiss Wi-Fi scan popup after connection"),
    checked_func = function()
      return G_reader_settings:nilOrTrue("auto_dismiss_wifi_scan")
    end,
    callback = function()
      G_reader_settings:flipNilOrTrue("auto_dismiss_wifi_scan")
    end,
  }
end

function NetworkMgr:getMenuTable(common_settings)
  if Device:hasWifiToggle() then
    common_settings.network_wifi = self:getWifiMenuTable()
  end

  common_settings.network_proxy = self:getProxyMenuTable()
  common_settings.network_info = self:getInfoMenuTable()

  -- Allow auto_disable_wifi on devices where the net sysfs entry is exposed.
  -- TODO: It doesn't work on kindle, see the comment in networklistener.
  if self:getNetworkInterfaceName() and not Device:isKindle() then
    common_settings.network_powersave = self:getPowersaveMenuTable()
  end

  if Device:hasWifiRestore() or Device:isEmulator() then
    common_settings.network_restore = self:getRestoreMenuTable()
  end

  common_settings.network_dismiss_scan = self:getDismissScanMenuTable()

  if Device:hasWifiToggle() then
    common_settings.network_before_wifi_action =
      self:getBeforeWifiActionMenuTable()
  end
end

function NetworkMgr:reconnectOrShowNetworkMenu(
  complete_callback,
  interactive,
  prefer_list
) -- bool
  local function scanNetworkList()
    -- NOTE: Fairly hackish workaround for #4387,
    --     rescan if the first scan appeared to yield an empty list.
    --- @fixme This *might* be an issue better handled in lj-wpaclient...
    local err
    for _ = 0, 3 do
      local network_list
      network_list, err = self:getNetworkList()
      if network_list ~= nil and #network_list > 0 then
        return network_list
      end
      -- The last rescanning won't happen, but I doubt even if it matters.
      logger.warn("Initial Wi-Fi scan yielded no results, rescanning")
    end
    if interactive then
      if err == nil or err == "" then
        -- Kindle won't return errors.
        -- Need localization.
        err = _("No available wifi networks found.")
      end
      UIManager:show(InfoMessage:new({ text = err }))
    end
    return false
  end

  local network_list
  if interactive then
    local info = InfoMessage:new({ text = _("Scanning for networks…") })
    UIManager:show(info)
    UIManager:forceRePaint()
    network_list = scanNetworkList()
    UIManager:close(info)
  else
    network_list = scanNetworkList()
  end
  if network_list == false then
    return false
  end
  assert(type(network_list) == "table")

  table.sort(network_list, function(l, r)
    return l.signal_quality > r.signal_quality
  end)

  -- ssid indicates the state of the connection; it's nil if not connected.
  local ssid
  -- We need to do two passes, as we may have *both* an already connected network (from the global wpa config),
  -- *and* preferred networks, and if the preferred networks have a better signal quality,
  -- they'll be sorted *earlier*, which would cause us to try to associate to a different AP than
  -- what wpa_supplicant is already trying to do...
  -- NOTE: We can't really skip this, even when we force showing the scan list,
  --     as the backend *will* connect in the background regardless of what we do,
  --     and we *need* our complete_callback to run,
  --     which would not be the case if we were to just dismiss the scan list,
  --     especially since it wouldn't show as "connected" in this case...
  for _, network in ipairs(network_list) do
    if network.connected then
      -- On platforms where we use wpa_supplicant (if we're calling this, we probably are),
      -- the invocation will check its global config, and if an AP configured there is reachable,
      -- it'll already have connected to it on its own.
      ssid = network.ssid
      break
    end
  end

  -- Next, look for our own preferred networks...
  local err_msg = _("Connection failed")
  -- Only auto connecting when user did not initiate the operation. I.e. when
  -- user clicks on the "Wi-Fi connection" menu, always prefer showing the
  -- menu.
  if
    ssid == nil
    and (
      not interactive or G_reader_settings:nilOrTrue("auto_dismiss_wifi_scan")
    )
  then
    for _, network in ipairs(network_list) do
      if network.password then
        -- If we hit a preferred network and we're not already connected,
        -- attempt to connect to said preferred network....
        logger.dbg(
          "NetworkMgr: Attempting to authenticate on preferred network",
          util.fixUtf8(network.ssid, "�")
        )
        local success
        success, err_msg = self:authenticateNetwork(network)
        if success then
          ssid = network.ssid
          network.connected = true
          break
        else
          logger.dbg("NetworkMgr: authentication failed:", err_msg)
        end
      end
    end
  end

  -- If we haven't even seen any of our preferred networks, wait a bit to see if wpa_supplicant manages to connect in the background anyway...
  -- This happens when we break too early from re-scans triggered by wpa_supplicant itself,
  -- which shouldn't really ever happen since https://github.com/koreader/lj-wpaclient/pull/11
  -- c.f., WpaClient:scanThenGetResults in lj-wpaclient for more details.
  if Device:hasWifiManager() and ssid == nil then
    -- Don't bother if wpa_supplicant doesn't actually have any configured networks...
    local configured_networks = self:getConfiguredNetworks()
    local has_preferred_networks = configured_networks
      and #configured_networks > 0

    local iter = has_preferred_networks and 0 or 60
    -- We wait 15s at most (like the restore-wifi-async script)
    while ssid == nil and iter < 60 do
      -- Check every 250ms
      iter = iter + 1
      ffiutil.usleep(250 * 1e+3)

      local nw = self:getCurrentNetwork()
      if nw then
        ssid = nw.ssid
        -- Flag it as connected in the list
        for _, network in ipairs(network_list) do
          if ssid == network.ssid then
            network.connected = true
          end
        end
        logger.dbg(
          "NetworkMgr: wpa_supplicant automatically connected to network",
          util.fixUtf8(ssid, "�"),
          "(after",
          iter * 0.25,
          "seconds)"
        )
      end
    end
  end

  -- Connected, get ip address first anyway.
  if ssid ~= nil then
    self:obtainIP()
  end

  if ssid == nil or prefer_list then
    -- NOTE: Also supports a disconnect_callback, should we use it for something?
    --     Tearing down Wi-Fi completely when tapping "disconnect" would feel a bit harsh, though...
    -- We don't want to display the AP list for non-interactive callers (e.g., beforeWifiAction framework)...
    if interactive or prefer_list then
      UIManager:show(require("ui/widget/networksetting"):new({
        network_list = network_list,
        connect_callback = complete_callback,
      }))
    end
    return (ssid ~= nil)
  end

  if interactive then
    -- NOTE: On Kindle, we don't have an explicit obtainIP implementation,
    --     and authenticateNetwork is async,
    --     so we don't *actually* have a full connection yet,
    --     we've just *started* connecting to the requested network...
    UIManager:show(InfoMessage:new({
      tag = "NetworkMgr", -- for crazy KOSync purposes
      text = T(
        Device:isKindle() and _("Connecting to network %1…")
          or _("Connected to network %1"),
        BD.wrap(util.fixUtf8(ssid, "�"))
      ),
      timeout = 3,
      dismiss_callback = complete_callback,
    }))
  elseif complete_callback then
    complete_callback()
  end
  logger.dbg("NetworkMgr: Connected to network", util.fixUtf8(ssid, "�"))

  return true
end

function NetworkMgr:saveNetwork(setting)
  if not self.nw_settings then
    self:_readNWSettings()
  end

  self.nw_settings:saveSetting(setting.ssid, {
    ssid = setting.ssid,
    password = setting.password,
    psk = setting.psk,
    flags = setting.flags,
  })
  self.nw_settings:flush()
end

function NetworkMgr:deleteNetwork(setting)
  if not self.nw_settings then
    self:_readNWSettings()
  end
  self.nw_settings:delSetting(setting.ssid)
  self.nw_settings:flush()
end

function NetworkMgr:getAllSavedNetworks()
  if not self.nw_settings then
    self:_readNWSettings()
  end
  return self.nw_settings
end

function NetworkMgr:setWirelessBackend(name, options)
  require("ui/network/" .. name).init(self, options)
end

if
  G_reader_settings:readSetting("http_proxy_enabled")
  and G_reader_settings:readSetting("http_proxy")
then
  NetworkMgr:setHTTPProxy(G_reader_settings:readSetting("http_proxy"))
elseif G_defaults:readSetting("NETWORK_PROXY") then
  NetworkMgr:setHTTPProxy(G_defaults:readSetting("NETWORK_PROXY"))
end

return NetworkMgr:init()
