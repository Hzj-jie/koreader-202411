local BD = require("ui/bidi")
local Device = require("device")
local EventListener = require("ui/widget/eventlistener")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local _pending_connected = {}
local _pending_online = {}
local _last_tx_packets = 0

local NetworkListener = EventListener:extend({})

if not Device:hasWifiToggle() then
  return NetworkListener
end

function NetworkListener:_wifiActivityCheck()
  if not G_reader_settings:isTrue("auto_disable_wifi") then
    return
  end
  if not NetworkMgr:isWifiOn() then
    return
  end

  -- This should be more than enough to catch actual activity vs. noise spread
  -- over 5 minutes.
  local NETWORK_ACTIVITY_NOISE_MARGIN = 12 -- unscaled_size_check: ignore
  local current_tx_packets = self:_getTxPackets()
  if current_tx_packets - _last_tx_packets > NETWORK_ACTIVITY_NOISE_MARGIN then
    _last_tx_packets = current_tx_packets
    return
  end
  _last_tx_packets = 0
  NetworkMgr:toggleWifiOff()
end

function NetworkListener:onTimesChange_5M()
  self:_wifiActivityCheck()
end

function NetworkListener:onToggleWifi()
  -- This is not a bug, but to allow users connecting to the wifi network if the
  -- wifi is on but not connected.
  if not NetworkMgr:isConnected() then
    NetworkMgr:toggleWifiOn()
  else
    NetworkMgr:toggleWifiOff(true) -- flag it as interactive
  end
end

function NetworkListener:onInfoWifiOff()
  NetworkMgr:toggleWifiOff(true) -- flag it as interactive
end

function NetworkListener:onInfoWifiOn()
  -- This is not a bug, but to allow users connecting to the wifi network if the
  -- wifi is on but not connected.
  if not NetworkMgr:isConnected() then
    NetworkMgr:toggleWifiOn()
  else
    local info_text
    local current_network = NetworkMgr:getCurrentNetwork()
    -- this method is only available for some implementations
    if current_network and current_network.ssid then
      info_text =
        T(_("Already connected to network %1."), BD.wrap(current_network.ssid))
    else
      info_text = _("Already connected.")
    end
    UIManager:show(InfoMessage:new({
      text = info_text,
      timeout = 1,
    }))
  end
end

-- Read the statistics/tx_packets sysfs entry for the current network interface.
-- It *should* be the least noisy entry on an idle network...
-- The fact that auto_disable_wifi is only available on devices that expose a
-- net sysfs entry allows us to get away with a Linux-only solution.
function NetworkListener:_getTxPackets()
  -- read tx_packets stats from sysfs (for the right network if)
  local file = io.open(
    "/sys/class/net/"
      .. NetworkMgr:getNetworkInterfaceName()
      .. "/statistics/tx_packets",
    "rb"
  )

  -- file exists only when Wi-Fi module is loaded.
  if not file then
    return 0
  end

  local tx_packets = file:read("*number")
  file:close()

  -- Will be 0 if NaN, just like we want it
  if tx_packets ~= tx_packets then
    return 0
  end
  return tx_packets
end

function NetworkListener:onNetworkConnected()
  logger.dbg("NetworkListener: onNetworkConnected")

  for _, v in pairs(_pending_connected) do
    UIManager:nextTick(v)
  end
  _pending_connected = {}
end

function NetworkListener:onNetworkOnline()
  logger.dbg("NetworkListener: onNetworkOnline")

  for _, v in pairs(_pending_online) do
    UIManager:nextTick(v)
  end
  _pending_online = {}
end

function NetworkListener:_pendingKeyOf(callback)
  return require("ffi/sha2").md5(string.dump(callback, true))
end

function NetworkListener:onPendingConnected(callback, key)
  assert(callback ~= nil)
  _pending_connected[key or self:_pendingKeyOf(callback)] = callback
end

function NetworkListener:onPendingOnline(callback, key)
  assert(callback ~= nil)
  _pending_online[key or self:_pendingKeyOf(callback)] = callback
end

-- Returns a human readable string to indicate the # of pending jobs.
function NetworkListener:countsOfPendingJobs()
  return string.format(
    "%d / %d",
    util.tableSize(_pending_connected),
    util.tableSize(_pending_online)
  )
end

-- Also unschedule on suspend (and we happen to also kill Wi-Fi to do so, so resetting the stats is also relevant here)
function NetworkListener:onSuspend()
  logger.dbg("NetworkListener: onSuspend")

  -- If we haven't already (e.g., via Generic's handlePowerEvent), kill Wi-Fi.
  -- Do so only on devices where we have explicit management of Wi-Fi: assume the host system does things properly elsewhere.
  if Device:hasWifiManager() and NetworkMgr:isWifiOn() then
    NetworkMgr:toggleWifiOff()
  end
end

-- If the platform implements NetworkMgr:restoreWifiAsync, run it as needed
if Device:hasWifiRestore() then
  function NetworkListener:onResume()
    NetworkMgr:restoreWifiAndCheckAsync(
      "NetworkListener: onResume will restore Wi-Fi in the background"
    )
  end
end

function NetworkListener:onShowNetworkInfo()
  if not NetworkMgr:isWifiOn() then
    -- This shouldn't happen, but in case something is very weird happening
    -- right between showing the network menu and the ShowNetworkInfo event.
    UIManager:show(InfoMessage:new({
      text = _("Wi-Fi off."),
      timeout = 3,
    }))
    return
  end
  if not NetworkMgr:isConnected() then
    -- User action, interactive == true.
    NetworkMgr:reconnectOrShowNetworkMenu(nil, true)
    return
  end
  if Device.retrieveNetworkInfo then
    UIManager:runWith(
      function()
        -- Since it's running with some display hints, we can spend some time to
        -- query the online state again in case the network dropped between two
        -- online state checks.
        NetworkMgr:_queryOnlineState()
        -- Need localization.
        UIManager:show(InfoMessage:new({
          -- Need localization.
          text = table.concat(Device:retrieveNetworkInfo(), "\n") .. "\n" .. _(
            "Internet"
          ) .. " " .. (NetworkMgr:isOnline() and _("online") or _(
            "offline"
          )),
          -- IPv6 addresses are *loooooong*!
          face = Font:getFace("x_smallinfofont"),
        }))
      end,
      -- Need localization.
      _("Retrieving network information…")
    )
  else
    UIManager:show(InfoMessage:new({
      text = _("Could not retrieve network info."),
      timeout = 3,
    }))
  end
end

return NetworkListener
