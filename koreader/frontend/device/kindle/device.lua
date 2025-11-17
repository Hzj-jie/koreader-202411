local Generic = require("device/generic/device")
local LibLipcs = require("liblipcs")
local UIManager
local T = require("ffi/util").template
local ffi = require("ffi")
local time = require("ui/time")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

-- We're going to need a few <linux/fb.h> & <linux/input.h> constants...
local ffi = require("ffi")
local C = ffi.C
require("ffi/linux_fb_h")
require("ffi/linux_input_h")
require("ffi/posix_h")
require("ffi/fbink_input_h")

-- Try to detect WARIO+ Kindle boards (i.MX6 & i.MX7)
local function isWarioOrMore()
  -- Parse cpuinfo line by line, until we find the Hardware description
  for line in io.lines("/proc/cpuinfo") do
    if line:find("^Hardware") then
      local cpu_hw = line:match("^Hardware%s*:%s([%g%s]*)$")
      -- NOTE: I couldn't dig up a cpuinfo dump from an Oasis 2 to check the CPU part value,
      --     but for Wario (Cortex A9), matching that to 0xc09 would work, too.
      --     On the other hand, I'm already using the Hardware match in MRPI, so, that sealed the
      --     deal ;).

      -- If we've got a Hardware string, check if it mentions an i.MX 6 or 7 or a MTK...
      if cpu_hw:find("i%.MX%s?[6-7]") or cpu_hw:find("MT8110") then
        return true
      end
    end
  end
  return false
end

-- Try to detect Kindle running hardfp firmware
local function isHardFP()
  return require("util").pathExists("/lib/ld-linux-armhf.so.3")
end

local function kindleGetSavedNetworks()
  return LibLipcs:hash_accessor()
    :read_hash_property("com.lab126.wifid", "profileData")
end

local function kindleGetCurrentProfile()
  local result = LibLipcs:hash_accessor()
    :read_hash_property("com.lab126.wifid", "currentEssid")
  if result == nil then
    return nil
  end
  -- there is only a single element
  return result[1]
end

local function kindleAuthenticateNetwork(essid)
  LibLipcs:accessor()
    :set_string_property("com.lab126.cmd", "ensureConnection", "wifi:" .. essid)
end

local function kindleSaveNetwork(data)
  local lipc = LibLipcs:hash_accessor()
  if LibLipcs:isFake(lipc) then
    return
  end
  local profile = lipc:new_hasharray()
  if profile == nil then
    return
  end
  profile:add_hash()
  profile:put_string(0, "essid", data.ssid)
  if string.find(data.flags, "WPA") then
    profile:put_string(0, "secured", "yes")
    profile:put_string(0, "psk", data.password)
    profile:put_int(0, "store_nw_user_pref", 0) -- tells amazon we don't want them to have our password
  else
    profile:put_string(0, "secured", "no")
  end
  local ha_result =
    lipc:access_hash_property("com.lab126.wifid", "createProfile", profile)
  profile:destroy()
  if ha_result ~= nil then
    ha_result:destroy() -- destroy the returned empty ha
  end
end

local function kindleDeleteNetwork(data)
  LibLipcs:accessor()
    :set_string_property("com.lab126.wifid", "deleteProfile", data.ssid)
end

local function kindleGetScanList()
  --[[ This logic is strange :/
  if kindleIsWifiConnected() then
    -- return a fake scan list containing only the currently connected profile :)
    local profile = kindleGetCurrentProfile()
    return { profile }, nil
  end
  --]]
  -- Wait at most 1s.
  for _ = 0, 4 do
    local result = LibLipcs:hash_accessor()
      :read_hash_property("com.lab126.wifid", "scanList")
    if result ~= nil then
      -- This is a very edge case where the scanList call fails sometimes.
      return result, nil
    end
    C.usleep(250 * 1000)
  end
  -- Need localization
  return nil,
    require("gettext")("Cannot find any Wi-Fi, please try again later.")
end

local function kindleScanThenGetResults()
  local _ = require("gettext")
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    return nil, _("Unable to communicate with the Wi-Fi backend")
  end

  lipc:set_string_property("com.lab126.wifid", "scan", "") -- trigger a scan

  -- Mimic WpaClient:scanThenGetResults: block while waiting for the scan to finish.
  -- Ideally, we'd do this via a poll/event workflow, but, eh', this is going to be good enough for now ;p.
  -- For future reference, see `lipc-wait-event -m -s 0 -t com.lab126.wifid '*'`
  --[[
    -- For a connection:
    [00:00:04.675699] cmStateChange "PENDING"
    [00:00:04.677402] scanning
    [00:00:05.488043] scanComplete
    [00:00:05.973188] cmConnected
    [00:00:05.977862] cmStateChange "CONNECTED"
    [00:00:05.980698] signalStrength "1/5"
    [00:00:06.417549] cmConnected

    -- And a disconnection:
    [00:01:34.094652] cmDisconnected
    [00:01:34.096088] cmStateChange "NA"
    [00:01:34.219802] signalStrength "0/5"
    [00:01:34.221802] cmStateChange "READY"
    [00:01:35.656375] cmIntfNotAvailable
    [00:01:35.658710] cmStateChange "NA"
  --]]
  local done_scanning = false
  for i = 0, 80 do -- 20s in chunks on 250ms
    if lipc:get_string_property("com.lab126.wifid", "scanState") == "idle" then
      done_scanning = true
      logger.dbg(
        "kindleScanThenGetResults: Wi-Fi scan took",
        i * 0.25,
        "seconds"
      )
      break
    end

    -- Whether it's still "scanning" or in whatever other state we don't know about,
    -- try again until it says it's done.
    C.usleep(250 * 1000)
  end

  if done_scanning then
    return kindleGetScanList()
  end
  logger.warn("kindleScanThenGetResults: Timed-out scanning for Wi-Fi networks")
  return nil, _("Scanning for Wi-Fi networks timed out")
end

local function kindleEnableWifi(toggle)
  if toggle == nil then
    toggle = 0
  end
  assert(type(toggle) == "number")
  assert(toggle == 0 or toggle == 1)
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    -- No liblipclua on FW < 5.x ;)
    -- Always kill 3G first...
    os.execute("lipc-set-prop -i com.lab126.wan enable 0")
    os.execute("lipc-set-prop -i com.lab126.cmd wirelessEnable " .. toggle)
    os.execute("lipc-set-prop -i com.lab126.wifid enable " .. toggle)
  else
    -- Be extremely thorough... c.f., #6019
    -- NOTE: I *assume* this'll also ensure we prefer Wi-Fi over 3G/4G, which is a plus in my book...
    lipc:set_int_property("com.lab126.cmd", "wirelessEnable", toggle)
    lipc:set_int_property("com.lab126.wifid", "enable", toggle)
  end
end

--[[
Test if a kindle device is flagged as a Special Offers device (i.e., ad supported) (FW >= 5.x)
--]]
local function isSpecialOffers()
  -- Look at the current blanket modules to see if the SO screensavers are enabled...
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    return true
  end
  local loaded_blanket_modules =
    lipc:get_string_property("com.lab126.blanket", "load")
  if not loaded_blanket_modules then
    logger.warn("could not get lipc property")
    return true
  end
  return string.find(loaded_blanket_modules, "ad_screensaver") ~= nil
end

--[[
Test if a kindle device has *received* Special Offers (FW < 5.x)
--]]
local function hasSpecialOffers()
  if lfs.attributes("/mnt/us/system/.assets", "mode") == "directory" then
    return true
  else
    return false
  end
end

local function frameworkStopped()
  if os.getenv("STOP_FRAMEWORK") ~= "yes" then
    return nil
  end
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    return nil
  end
  local frameworkStarted = lipc:register_int_property("frameworkStarted", "r")
  frameworkStarted.value = 1
  lipc:set_string_property("com.lab126.blanket", "unload", "splash")
  lipc:set_string_property("com.lab126.blanket", "unload", "screensaver")
  return lipc
end

local function initRotation(screen)
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    return
  end
  local orientation_code =
    lipc:get_string_property("com.lab126.winmgr", "accelerometer")
  logger.dbg("orientation_code =", orientation_code)
  local rotation_mode = 0
  if orientation_code then
    if orientation_code == "U" then
      rotation_mode = screen.DEVICE_ROTATED_UPRIGHT
    elseif orientation_code == "R" then
      rotation_mode = screen.DEVICE_ROTATED_CLOCKWISE
    elseif orientation_code == "D" then
      rotation_mode = screen.DEVICE_ROTATED_UPSIDE_DOWN
    elseif orientation_code == "L" then
      rotation_mode = screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
    end
  end
  if rotation_mode > 0 then
    screen.native_rotation_mode = rotation_mode
  end
  screen:setRotationMode(rotation_mode)
end

local Kindle = Generic:extend({
  model = "Kindle",
  isKindle = util.yes,
  -- NOTE: We can cheat by adding a platform-specific entry here, because the only code that will check for this is here.
  isSpecialOffers = isSpecialOffers(),
  hasWifiRestore = util.yes,
  -- NOTE: HW inversion is generally safe on mxcfb Kindles
  canHWInvert = util.yes,
  -- NOTE: And the fb driver is generally sane on those, too
  canModifyFBInfo = util.yes,
  -- NOTE: Newer devices will turn the frontlight off at 0
  canTurnFrontlightOff = util.yes,
  -- NOTE: Via powerd.toggleSuspend
  canSuspend = util.yes,
  canReboot = util.yes,
  canPowerOff = util.yes,
  home_dir = "/mnt/us",
  -- New devices are REAGL-aware, default to REAGL
  isREAGL = util.yes,
  -- Rex & Zelda devices sport an updated driver.
  isZelda = util.no,
  isRex = util.no,
  -- So do devices running on a MediaTek SoC
  isMTK = util.no,
  -- But of course, some devices don't actually support all the features the kernel exposes...
  isNightModeChallenged = util.no,
  -- NOTE: While this ought to behave on Zelda/Rex, turns out, nope, it really doesn't work on *any* of 'em :/ (c.f., ko#5884).
  canHWDither = util.no,
  -- Device has an Ambient Light Sensor
  hasLightSensor = util.no,
  -- The time the device went into suspend
  suspend_time = 0,
  framework_lipc_handle = frameworkStopped(),
  -- Kindle cannot disconnect a wifi, it will reconnect wifi automatically.
  canDisconnectWifi = util.no,
})

function Kindle:retrieveNetworkInfo()
  -- The default ioctl SSID retrieving logic does not work on some kindle
  -- models, use kindle way to include the SSID when missing.
  local results = Generic.retrieveNetworkInfo(self)
  local profile = kindleGetCurrentProfile()
  local ssid
  if profile == nil then
    ssid = _("SSID: off/any")
  else
    ssid = T(_('SSID: "%1"'), ffi.string(profile.essid))
  end
  for _, value in ipairs(results) do
    if value == ssid then
      return results
    end
  end
  table.insert(results, 3, ssid)
  return results
end

function Kindle:initNetworkManager(NetworkMgr)
  if LibLipcs:supported() then
    function NetworkMgr:_turnOnWifi(complete_callback, interactive)
      kindleEnableWifi(1)
      if self:reconnectOrShowNetworkMenu(complete_callback, interactive) then
        return true
      end
      -- It's impossible to force a sync wifi connection operation, but can only
      -- rely on the NetworkMgr:connectivityCheck to verify the state.
      return EBUSY
    end
  else
    -- If we can't use the lipc Lua bindings, we can't support any kind of interactive Wi-Fi UI...
    function NetworkMgr:_turnOnWifi(complete_callback, interactive)
      kindleEnableWifi(1)
      if complete_callback then
        complete_callback()
      end
    end
  end

  function NetworkMgr:_turnOffWifi()
    kindleEnableWifi(0)
  end

  function NetworkMgr:getNetworkInterfaceName()
    return "wlan0" -- so far, all Kindles appear to use wlan0
  end

  function NetworkMgr:restoreWifiAsync()
    kindleEnableWifi(1)
  end

  function NetworkMgr:authenticateNetwork(network)
    kindleAuthenticateNetwork(network.ssid)
    return true, nil
  end

  -- NOTE: We don't have a disconnectNetwork & releaseIP implementation,
  --     which means the "disconnect" button in NetworkSetting kind of does nothing ;p.
  -- Kindle connects to the perferred network automatically, and
  -- wifid/cmDisconnect does not disconnect the wifi.
  function NetworkMgr:saveNetwork(setting)
    kindleSaveNetwork(setting)
  end

  function NetworkMgr:deleteNetwork(setting)
    kindleDeleteNetwork(setting)
  end

  function NetworkMgr:getNetworkList()
    kindleEnableWifi(1)
    local scan_list, err = kindleScanThenGetResults()
    if not scan_list then
      return nil, err
    end

    -- trick ui/widget/networksetting into displaying the correct signal strength icon
    local qualities = {
      [1] = 0,
      [2] = 6,
      [3] = 31,
      [4] = 56,
      [5] = 81,
    }

    local network_list = {}
    local saved_profiles = kindleGetSavedNetworks()
    local current_profile = kindleGetCurrentProfile()
    for _, network in ipairs(scan_list) do
      local password = nil
      if network.known == "yes" then
        for _, p in ipairs(saved_profiles) do
          -- Earlier FW do not have a netid field at all, fall back to essid as that's the best we'll get (we don't get bssid either)...
          if
            (p.netid and p.netid == network.netid)
            or (p.netid == nil and p.essid == network.essid)
          then
            password = p.psk
            break
          end
        end
      end
      local connected = false
      if current_profile ~= nil then
        -- See comment above about netid being unfortunately optional...
        if current_profile.netid then
          connected = current_profile.netid ~= -1
            and current_profile.netid == network.netid
        else
          connected = current_profile.essid ~= ""
            and current_profile.essid == network.essid
        end
      end
      table.insert(network_list, {
        -- signal_level is purely for fun, the widget doesn't do anything with it. The WpaClient backend stores the raw dBa attenuation in it.
        signal_level = string.format(
          "%d/%d",
          network.signal,
          network.signal_max
        ),
        signal_quality = qualities[network.signal],
        connected = connected,
        flags = network.key_mgmt,
        ssid = network.essid ~= "" and network.essid,
        password = password,
      })
    end
    return network_list, nil
  end

  function NetworkMgr:getCurrentNetwork()
    local profile = kindleGetCurrentProfile()
    if profile == nil then
      return nil
    end
    return { ssid = profile.essid }
  end

  NetworkMgr.isWifiOn = function()
    return self:isWifiUp()
  end
  NetworkMgr.isConnected = function()
    return self:isWifiConnected()
  end
end

-- sysfsInterfaceOperational may not indicate the internal state of
-- com.lab126.wifid.
function Kindle:isWifiUp()
  local function shouldDelayLipc()
    if self.last_resume_at == nil then
      -- Very likely the initial start of KOReader.
      return false
    end
    -- Delay the initial com.lab126.cmd wirelessEnable call after resume. See
    -- https://github.com/Hzj-jie/koreader-202411/issues/260 and
    -- https://github.com/Hzj-jie/koreader-202411/issues/266
    return time.to_s(time.realtime() - self.last_resume_at) < 10
  end
  if shouldDelayLipc() then
    return false
  end
  local lipc = LibLipcs:accessor()
  if not LibLipcs:isFake(lipc) then
    return (lipc:get_int_property("com.lab126.wifid", "enable") or 0) == 1
      and (lipc:get_int_property("com.lab126.cmd", "wirelessEnable") or 0)
        == 1
  end
  local std_out = io.popen("lipc-get-prop -i com.lab126.wifid enable", "r")
  if not std_out then
    return false
  end
  local result = std_out:read("*number")
  std_out:close()

  if not result or result ~= 1 then
    return false
  end

  std_out = io.popen("lipc-get-prop -i com.lab126.cmd wirelessEnable", "r")
  if not std_out then
    return false
  end
  result = std_out:read("*number")
  std_out:close()

  if not result or result ~= 1 then
    return false
  end

  return true
end

function Kindle:isWifiConnected()
  local function kindleWifiState()
    local lipc = LibLipcs:accessor()
    if not LibLipcs:isFake(lipc) then
      return lipc:get_string_property("com.lab126.wifid", "cmState")
    end

    local std_out = io.popen("lipc-get-prop com.lab126.wifid cmState", "r")
    if not std_out then
      return nil
    end
    local result = std_out:read("*l")
    std_out:close()
    return result
  end

  if not self:isWifiUp() then
    -- Checking wifi up may be delayed and causes the consistency issue.
    return false
  end
  return kindleWifiState() == "CONNECTED"
end

function Kindle:supportsScreensaver()
  return not self.isSpecialOffers
end

function Kindle:openInputDevices()
  -- Auto-detect input devices (via FBInk's fbink_input_scan)
  local ok, FBInkInput = pcall(ffi.loadlib, "fbink_input", 1)
  if not ok then
    print("fbink_input not loaded:", FBInkInput)
    -- NOP fallback for the testsuite...
    FBInkInput = { fbink_input_scan = function() end }
  end
  local dev_count = ffi.new("size_t[1]")
  -- We care about: the touchscreen, a properly scaled stylus, pagination buttons, a home button and a fiveway.
  local match_mask = bit.bor(
    C.INPUT_TOUCHSCREEN,
    C.INPUT_SCALED_TABLET,
    C.INPUT_PAGINATION_BUTTONS,
    C.INPUT_HOME_BUTTON,
    C.INPUT_DPAD
  )
  local devices = FBInkInput.fbink_input_scan(match_mask, 0, 0, dev_count)
  if devices ~= nil then
    for i = 0, tonumber(dev_count[0]) - 1 do
      local dev = devices[i]
      if dev.matched then
        self.input:fdopen(
          tonumber(dev.fd),
          ffi.string(dev.path),
          ffi.string(dev.name)
        )
      end
    end
    C.free(devices)
  else
    -- Auto-detection failed, warn and fall back to defaults
    logger.warn(
      "We failed to auto-detect the proper input devices, input handling may be inconsistent!"
    )
    if self.touch_dev then
      -- We've got a preferred path specified for the touch panel
      self.input:open(self.touch_dev)
    else
      -- That generally works out well enough on legacy devices...
      self.input:open("/dev/input/event0")
      self.input:open("/dev/input/event1")
    end
  end

  -- Getting the device where rotation events end up without catching a bunch of false-positives is... trickier,
  -- thanks to the inane event code being used...
  if self:hasGSensor() then
    -- i.e., we want something that reports EV_ABS:ABS_PRESSURE that isn't *also* a pen (because those are pretty much guaranteed to report pressure...).
    --     And let's add that isn't also a touchscreen to the mix, because while not true at time of writing, that's an event touchscreens sure can support...
    devices = FBInkInput.fbink_input_scan(
      C.INPUT_ROTATION_EVENT,
      bit.bor(C.INPUT_TABLET, C.INPUT_TOUCHSCREEN),
      C.NO_RECAP,
      dev_count
    )
    if devices ~= nil then
      for i = 0, tonumber(dev_count[0]) - 1 do
        local dev = devices[i]
        if dev.matched then
          self.input:fdopen(
            tonumber(dev.fd),
            ffi.string(dev.path),
            ffi.string(dev.name)
          )
        end
      end
      C.free(devices)
    end
  end

  self.input:open("fake_events")
end

function Kindle:otaModel()
  local model
  if self:isTouchDevice() or self.model == "Kindle4" then
    if isHardFP() then
      model = "kindlehf"
    elseif isWarioOrMore() then
      model = "kindlepw2"
    else
      model = "kindle"
    end
  else
    model = "kindle-legacy"
  end
  return model, "ota"
end

function Kindle:init()
  -- Check if the device supports deep sleep/quick boot
  if
    lfs.attributes("/sys/devices/platform/falconblk/uevent", "mode") == "file"
  then
    -- Now, poke the appreg db to see if it's actually *enabled*...
    -- NOTE: The setting is only available on registered devices, as such, it *can* be missing,
    --     which is why we check for it existing and being *disabled*, as that ensures user interaction.
    local SQ3 = require("lua-ljsqlite3/init")
    local appreg = SQ3.open("/var/local/appreg.db", "ro")
    local hibernation_disabled = tonumber(
      appreg:rowexec(
        "SELECT EXISTS(SELECT value FROM properties WHERE handlerId = 'dcc' AND name = 'hibernate.enabled' AND value = 0);"
      )
    )
    -- Check the actual delay while we're there...
    local hibernation_delay = appreg:rowexec(
      "SELECT value FROM properties WHERE handlerId = 'dcc' AND name = 'hibernate.s2h.rtc.secs'"
    ) or appreg:rowexec(
      "SELECT value FROM properties WHERE handlerId = 'dcd' AND name = 'hibernate.s2h.rtc.secs'"
    ) or 3600
    appreg:close()
    if hibernation_disabled == 1 then
      self.canDeepSleep = false
    else
      self.canDeepSleep = true
      self.hibernationDelay = tonumber(hibernation_delay)
      logger.dbg(
        "Kindle: Device supports hibernation, enters hibernation after",
        self.hibernationDelay,
        "seconds in suspend"
      )
    end
  else
    self.canDeepSleep = false
  end

  -- If the device-specific init hasn't done so already (devices without keys don't), instantiate Input.
  if not self.input then
    self.input = require("device/input"):new({ device = self })
  end

  -- Auto-detect & open input devices
  self:openInputDevices()

  -- Follow user preference for the hall effect sensor's state
  if self.powerd:hasHallSensor() then
    if G_reader_settings:has("kindle_hall_effect_sensor_enabled") then
      self.powerd:onToggleHallSensor(
        G_reader_settings:readSetting("kindle_hall_effect_sensor_enabled")
      )
    end
  end

  Generic.init(self)
end

function Kindle:usbPlugIn()
  -- NOTE: We cannot support running in USBMS mode (we cannot, we live on the partition being exported!).
  --     But since that's the default state of the Kindle system, we have to try to make nice...
  --     To that end, we're currently SIGSTOPping volumd to inhibit the system's USBMS mode handling.
  --     It's not perfect (e.g., if the system is setup for USBMS and not USBNet,
  --     the frontlight will be turned off when plugged in), but it at least prevents users from completely
  --     shooting themselves in the foot (c.f., https://github.com/koreader/koreader/issues/3220)!
  --     On the upside, we don't have to bother waking up the WM to show us the USBMS screen :D.
  -- NOTE: If the device is put in USBNet mode before we even start, everything's peachy, though :).
end

-- Hopefully, the event sources are fairly portable...
-- c.f., https://github.com/koreader/koreader/pull/11174#issuecomment-1830064445
-- NOTE: There's no distinction between real button presses and powerd_test -p or lipc-set-prop -i com.lab126.powerd powerButton 1
local POWERD_EVENT_SOURCES = {
  [1] = "BUTTON_WAKEUP", -- outOfScreenSaver 1
  [2] = "BUTTON_SUSPEND", -- goingToScreenSaver 2
  [4] = "HALL_SUSPEND", -- goingToScreenSaver 4
  [6] = "HALL_WAKEUP", -- outOfScreenSaver 6
}

function Kindle:_intoScreenSaver(source)
  logger.dbg(
    "Kindle:_intoScreenSaver via",
    POWERD_EVENT_SOURCES[source]
      or string.format("UNKNOWN_SUSPEND (%d)", source or -1)
  )
  if self.screen_saver_mode then
    return
  end

  if self:supportsScreensaver() then
    -- NOTE: Meaning this is not a SO device ;)
    local Screensaver = require("ui/screensaver")
    Screensaver:setup()
    Screensaver:show()
    return
  end
  -- Let the native system handle screensavers on SO devices...
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -CONT awesome")
  elseif os.getenv("CVM_STOPPED") == "yes" then
    os.execute("killall -CONT cvm")
  end

  -- Don't forget to flag ourselves in ScreenSaver mode like Screensaver:show would,
  -- so that we do the right thing on resume ;).
  self.screen_saver_mode = true
end

function Kindle:_outofScreenSaver(source)
  logger.dbg(
    "Kindle:_outofScreenSaver via",
    POWERD_EVENT_SOURCES[source]
      or string.format("UNKNOWN_WAKEUP (%d)", source or -1)
  )
  if not self.screen_saver_mode then
    return
  end
  if not self:supportsScreensaver() then
    -- Stop awesome again if need be...
    if os.getenv("AWESOME_STOPPED") == "yes" then
      os.execute("killall -STOP awesome")
    elseif os.getenv("CVM_STOPPED") == "yes" then
      os.execute("killall -STOP cvm")
    end
    -- NOTE: We redraw after a slightly longer delay to take care of the potentially dynamic ad screen...
    --     This is obviously brittle as all hell. Tested on a slow-ass PW1.
    UIManager:scheduleIn(3, function()
      UIManager:setDirty("all", "full")
    end)
    -- Flip the switch again
    self.screen_saver_mode = false
    return
  end
  local Screensaver = require("ui/screensaver")
  if Screensaver:close() then
    -- And redraw everything in case the framework managed to screw us over...
    UIManager:nextTick(function()
      UIManager:setDirty("all", "full")
    end)
  end
end

-- On stock, there's a distinction between OutOfSS (which *requests* closing the SS) and ExitingSS, which fires once they're *actually* closed...
-- Unused yet.
-- function Kindle:exitingScreenSaver() end

function Kindle:usbPlugOut()
  -- NOTE: See usbPlugIn(), we don't have anything fancy to do here either.
end

function Kindle:wakeupFromSuspend(ts)
  logger.dbg("Kindle:wakeupFromSuspend", ts)
  self.powerd:wakeupFromSuspend(ts)
end

function Kindle:readyToSuspend(delay)
  logger.dbg("Kindle:readyToSuspend", delay)
  self.powerd:readyToSuspend(delay)
end

-- We add --no-same-permissions --no-same-owner to make the userstore fuse proxy happy...
function Kindle:untar(archive, extract_to)
  return os.execute(
    ("./tar --no-same-permissions --no-same-owner -xf %q -C %q"):format(
      archive,
      extract_to
    )
  )
end

function Kindle:UIManagerReady(uimgr)
  UIManager = uimgr
end

function Kindle:setEventHandlers(uimgr)
  -- These custom fake events *will* pass an argument...
  self.input.fake_event_args.IntoSS = {}
  self.input.fake_event_args.OutOfSS = {}
  self.input.fake_event_args.WakeupFromSuspend = {}
  self.input.fake_event_args.ReadyToSuspend = {}

  UIManager.event_handlers.Suspend = function()
    self.powerd:toggleSuspend()
  end
  UIManager.event_handlers.IntoSS = function(input_event)
    self.powerd:beforeSuspend()
    -- Retrieve the argument set by Input:handleKeyBoardEv
    local arg = table.remove(self.input.fake_event_args[input_event])
    self:_intoScreenSaver(arg)
  end
  UIManager.event_handlers.OutOfSS = function(input_event)
    local arg = table.remove(self.input.fake_event_args[input_event])
    self:_outofScreenSaver(arg)
    self.powerd:afterResume()

    -- If the device supports deep sleep, and we woke up from hibernation (which kicks in at the 1H mark),
    -- chuck an extra tiny refresh to get rid of the "waking up" banner if the above refresh was too early...
    if not self.canDeepSleep then
      return
    end
    if (self.last_resume_at - self.last_suspend_at) <= time.s(self.hibernationDelay) then
      return
    end
    if
      lfs.attributes("/var/local/system/powerd/hibernate_session_tracker", "mode")
      ~= "file"
    then
      return
    end
    local mtime = lfs.attributes(
      "/var/local/system/powerd/hibernate_session_tracker",
      "modification"
    )
    local now = os.time()
    if math.abs(now - mtime) > 60 then
      return
    end
    -- That was less than a minute ago, assume we're golden.
    logger.dbg("Kindle: Woke up from hibernation")
    -- The banner on a 1236x1648 PW5 is 1235x125; we refresh the bottom 10% of the screen to be safe.
    local Geom = require("ui/geometry")
    local screen_height = self.screen:getHeight()
    local refresh_height = math.ceil(screen_height * (1 / 10))
    local refresh_region = Geom:new({
      x = 0,
      y = screen_height - 1 - refresh_height,
      w = self.screen:getWidth(),
      h = refresh_height,
    })
    UIManager:scheduleIn(1.5, function()
      UIManager:setDirty("all", "ui", refresh_region)
    end)
  end
  -- Unused yet.
  -- self.powerd:afterResume() here may not always work, some units do not
  -- trigger the ExitingSS behavior.
  -- UIManager.event_handlers.ExitingSS = function()
  --   self:exitingScreenSaver()
  -- end
  UIManager.event_handlers.Charging = function()
    self:_beforeCharging()
    self:usbPlugIn()
  end
  UIManager.event_handlers.NotCharging = function()
    self:usbPlugOut()
    self:_afterNotCharging()
  end
  UIManager.event_handlers.WakeupFromSuspend = function(input_event)
    local arg = table.remove(self.input.fake_event_args[input_event])
    self:wakeupFromSuspend(arg)
  end
  UIManager.event_handlers.ReadyToSuspend = function(input_event)
    local arg = table.remove(self.input.fake_event_args[input_event])
    self:readyToSuspend(arg)
  end
end

function Kindle:ambientBrightnessLevel()
  local lipc = LibLipcs:accessor()
  if LibLipcs:isFake(lipc) then
    return 0
  end
  local value = lipc:get_int_property("com.lab126.powerd", "alsLux")
  if type(value) ~= "number" then
    return 0
  end
  value = value
    * (G_defaults:readSetting("KINDLE_AMBIENT_BRIGHTNESS_MULTIPLIER") or 1)
  if value < 10 then
    return 0
  end
  if value < 96 then
    return 1
  end
  if value < 192 then
    return 2
  end
  if value < 32768 then
    return 3
  end
  return 4
end

function Kindle:reboot()
  os.execute("shutdown -r now")
end

function Kindle:powerOff()
  os.execute("shutdown -h now")
end

local Kindle2 = Kindle:extend({
  model = "Kindle2",
  isREAGL = util.no,
  hasKeyboard = util.yes,
  hasKeys = util.yes,
  hasSymKey = util.yes,
  hasDPad = util.yes,
  useDPadAsActionKeys = util.yes,
  canHWInvert = util.no,
  canModifyFBInfo = util.no,
  canUseCBB = util.no, -- 4bpp
  canUseWAL = util.no, -- Kernel too old to support mmap'ed I/O on /mnt/us
  supportsScreensaver = util.yes, -- The first ad-supported device was the K3
})

local KindleDXG = Kindle:extend({
  model = "KindleDXG",
  isREAGL = util.no,
  hasKeyboard = util.yes,
  hasKeys = util.yes,
  hasSymKey = util.yes,
  hasDPad = util.yes,
  useDPadAsActionKeys = util.yes,
  canHWInvert = util.no,
  canModifyFBInfo = util.no,
  canUseCBB = util.no, -- 4bpp
  canUseWAL = util.no, -- Kernel too old to support mmap'ed I/O on /mnt/us
  supportsScreensaver = util.yes, -- The first ad-supported device was the K3
})

local Kindle3 = Kindle:extend({
  model = "Kindle3",
  isREAGL = util.no,
  hasKeyboard = util.yes,
  hasKeys = util.yes,
  hasSymKey = util.yes,
  hasDPad = util.yes,
  useDPadAsActionKeys = util.yes,
  canHWInvert = util.no,
  canModifyFBInfo = util.no,
  canUseCBB = util.no, -- 4bpp
  isSpecialOffers = hasSpecialOffers(),
})

local Kindle4 = Kindle:extend({
  model = "Kindle4",
  isREAGL = util.no,
  hasKeys = util.yes,
  hasScreenKB = util.yes,
  hasDPad = util.yes,
  useDPadAsActionKeys = util.yes,
  canHWInvert = util.no,
  canModifyFBInfo = util.no,
  -- NOTE: It could *technically* use the C BB, as it's running @ 8bpp, but it's expecting an inverted palette...
  canUseCBB = util.no,
  isSpecialOffers = hasSpecialOffers(),
})

local KindleTouch = Kindle:extend({
  model = "KindleTouch",
  isREAGL = util.no,
  isTouchDevice = util.yes,
  hasKeys = util.yes,
  touch_dev = "/dev/input/event3",
})

local KindlePaperWhite = Kindle:extend({
  model = "KindlePaperWhite",
  isREAGL = util.no,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  canTurnFrontlightOff = util.no,
  display_dpi = 212,
  touch_dev = "/dev/input/event0",
})

local KindlePaperWhite2 = Kindle:extend({
  model = "KindlePaperWhite2",
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  canTurnFrontlightOff = util.no,
  display_dpi = 212,
  touch_dev = "/dev/input/event1",
})

local KindleBasic = Kindle:extend({
  model = "KindleBasic",
  isTouchDevice = util.yes,
  touch_dev = "/dev/input/event1",
})

local KindleVoyage = Kindle:extend({
  model = "KindleVoyage",
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasLightSensor = util.yes,
  hasKeys = util.yes,
  display_dpi = 300,
  touch_dev = "/dev/input/event1",
})

local KindlePaperWhite3 = Kindle:extend({
  model = "KindlePaperWhite3",
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  canTurnFrontlightOff = util.no,
  display_dpi = 300,
  touch_dev = "/dev/input/event1",
})

local KindleOasis = Kindle:extend({
  model = "KindleOasis",
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasKeys = util.yes,
  hasGSensor = util.yes,
  display_dpi = 300,
  --[[
  -- NOTE: Points to event3 on Wi-Fi devices, event4 on 3G devices...
  --     3G devices apparently have an extra SX9500 Proximity/Capacitive controller for mysterious purposes...
  --     This evidently screws with the ordering, so, use the udev by-path path instead to avoid hackier workarounds.
  --     cf. #2181
  --]]
  touch_dev = "/dev/input/by-path/platform-imx-i2c.1-event",
})

local KindleOasis2 = Kindle:extend({
  model = "KindleOasis2",
  isZelda = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasLightSensor = util.yes,
  hasKeys = util.yes,
  hasGSensor = util.yes,
  display_dpi = 300,
  touch_dev = "/dev/input/by-path/platform-30a30000.i2c-event",
})

local KindleOasis3 = Kindle:extend({
  model = "KindleOasis3",
  isZelda = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasNaturalLight = util.yes,
  hasNaturalLightMixer = util.yes,
  hasLightSensor = util.yes,
  hasKeys = util.yes,
  hasGSensor = util.yes,
  display_dpi = 300,
  touch_dev = "/dev/input/by-path/platform-30a30000.i2c-event",
})

local KindleBasic2 = Kindle:extend({
  model = "KindleBasic2",
  isTouchDevice = util.yes,
  touch_dev = "/dev/input/event0",
})

local KindlePaperWhite4 = Kindle:extend({
  model = "KindlePaperWhite4",
  isRex = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  display_dpi = 300,
  -- NOTE: LTE devices once again have a mysterious extra SX9310 proximity sensor...
  --     Except this time, we can't rely on by-path, because there's no entry for the TS :/.
  --     Should be event2 on Wi-Fi, event3 on LTE, we'll fix it in init.
  touch_dev = "/dev/input/event2",
})

local KindleBasic3 = Kindle:extend({
  model = "KindleBasic3",
  isRex = util.yes,
  -- NOTE: Apparently, the KT4 doesn't actually support the fancy nightmode waveforms, c.f., ko/#5076
  --     It also doesn't handle HW dithering, c.f., base/#1039
  isNightModeChallenged = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  touch_dev = "/dev/input/event2",
})

local KindlePaperWhite5 = Kindle:extend({
  model = "KindlePaperWhite5",
  isMTK = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasNaturalLight = util.yes,
  -- NOTE: We *can* technically control both LEDs independently,
  --     but the mix is device-specific, we don't have access to the LUT for the mix powerd is using,
  --     and the widget is designed for the Kobo Aura One anyway, so, hahaha, nope.
  hasNaturalLightMixer = util.yes,
  display_dpi = 300,
  -- NOTE: While hardware dithering (via MDP) should be a thing, it doesn't appear to do anything right now :/.
  canHWDither = util.no,
  canDoSwipeAnimation = util.yes,
  -- NOTE: Input device path is variable, see findInputDevices
})

local KindleBasic4 = Kindle:extend({
  model = "KindleBasic4",
  isMTK = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  display_dpi = 300,
  canHWDither = util.no,
  canDoSwipeAnimation = util.yes,
  -- NOTE: Like the PW5, input device path is variable, see findInputDevices
})

local KindleScribe = Kindle:extend({
  model = "KindleScribe",
  isMTK = util.yes,
  isTouchDevice = util.yes,
  hasFrontlight = util.yes,
  hasNaturalLight = util.yes,
  -- NOTE: We *can* technically control both LEDs independently,
  --     but the mix is device-specific, we don't have access to the LUT for the mix powerd is using,
  --     and the widget is designed for the Kobo Aura One anyway, so, hahaha, nope.
  hasNaturalLightMixer = util.yes,
  hasLightSensor = util.yes,
  hasGSensor = util.yes,
  display_dpi = 300,
  touch_dev = "/dev/input/touch",
  canHWDither = util.yes,
  canDoSwipeAnimation = util.yes,
})

function Kindle2:init()
  self.screen =
    require("ffi/framebuffer_einkfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    is_charging_file = "/sys/devices/platform/charger/charging",
  })
  self.input = require("device/input"):new({
    device = self,
    event_map = require("device/kindle/event_map_keyboard"),
  })
  Kindle.init(self)
end

function KindleDXG:init()
  self.screen =
    require("ffi/framebuffer_einkfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    is_charging_file = "/sys/devices/platform/charger/charging",
  })
  self.input = require("device/input"):new({
    device = self,
    event_map = require("device/kindle/event_map_keyboard"),
  })
  self.keyboard_layout = require("device/kindle/keyboard_layout")
  Kindle.init(self)
end

function Kindle3:init()
  self.screen =
    require("ffi/framebuffer_einkfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    batt_capacity_file = "/sys/devices/system/luigi_battery/luigi_battery0/battery_capacity",
    is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
  })
  self.input = require("device/input"):new({
    device = self,
    event_map = require("device/kindle/event_map_kindle4"),
  })
  self.keyboard_layout = require("device/kindle/keyboard_layout")
  self.k3_alt_plus_key_kernel_translated =
    require("device/kindle/k3_alt_and_top_row")
  Kindle.init(self)
end

function Kindle4:init()
  self.screen =
    require("ffi/framebuffer_einkfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
    is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
  })
  self.input = require("device/input"):new({
    device = self,
    event_map = require("device/kindle/event_map_kindle4"),
  })
  Kindle.init(self)
end

function KindleTouch:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
    is_charging_file = "/sys/devices/platform/fsl-usb2-udc/charging",
  })
  self.input = require("device/input"):new({
    device = self,
    -- Kindle Touch has a single button
    event_map = { [102] = "Home" },
  })

  -- Kindle Touch needs event modification for proper coordinates
  self.input:registerEventAdjustHook(
    self.input.adjustTouchScale,
    { x = 600 / 4095, y = 800 / 4095 }
  )

  Kindle.init(self)
end

function KindlePaperWhite:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/devices/system/fl_tps6116x/fl_tps6116x0/fl_intensity",
    batt_capacity_file = "/sys/devices/system/yoshi_battery/yoshi_battery0/battery_capacity",
    is_charging_file = "/sys/devices/platform/aplite_charger.0/charging",
  })

  Kindle.init(self)
end

function KindlePaperWhite2:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
    batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
    is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    batt_status_file = "/sys/class/power_supply/max77696-battery/status",
    hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
  })

  Kindle.init(self)
end

function KindleBasic:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
    is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
  })

  Kindle.init(self)
end

function KindleVoyage:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
    batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
    is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
  })
  self.input = require("device/input"):new({
    device = self,
    event_map = {
      [104] = "LPgBack",
      [109] = "LPgFwd",
    },
  })
  -- touch gestures fall into these cold spots defined by (x, y, r)
  -- will be rewritten to 'none' ges thus being ignored
  -- x, y is the absolute position disregard of screen mode, r is spot radius
  self.cold_spots = {
    {
      x = 1080 + 50,
      y = 485,
      r = 80,
    },
    {
      x = 1080 + 70,
      y = 910,
      r = 120,
    },
    {
      x = -50,
      y = 485,
      r = 80,
    },
    {
      x = -70,
      y = 910,
      r = 120,
    },
  }

  self.input:registerGestureAdjustHook(function(_, ges)
    if ges then
      local pos = ges.pos
      for _, spot in ipairs(self.cold_spots) do
        if
          (spot.x - pos.x) * (spot.x - pos.x)
            + (spot.y - pos.y) * (spot.y - pos.y)
          < spot.r * spot.r
        then
          ges.ges = "none"
        end
      end
    end
  end)

  Kindle.init(self)

  -- Re-enable WhisperTouch keys when started without framework
  if self.framework_lipc_handle then
    self.framework_lipc_handle:set_int_property(
      "com.lab126.deviced",
      "fsrkeypadEnable",
      1
    )
    self.framework_lipc_handle:set_int_property(
      "com.lab126.deviced",
      "fsrkeypadPrevEnable",
      1
    )
    self.framework_lipc_handle:set_int_property(
      "com.lab126.deviced",
      "fsrkeypadNextEnable",
      1
    )
  end
end

function KindlePaperWhite3:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
    batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
    is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
  })

  Kindle.init(self)
end

-- HAL for gyro orientation switches (EV_ABS:ABS_PRESSURE (?!) w/ custom values to EV_MSC:MSC_GYRO w/ our own custom values)
local function OasisGyroTranslation(this, ev)
  local DEVICE_ORIENTATION_PORTRAIT_LEFT = 15
  local DEVICE_ORIENTATION_PORTRAIT_RIGHT = 17
  local DEVICE_ORIENTATION_PORTRAIT = 19
  local DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT = 16
  local DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT = 18
  local DEVICE_ORIENTATION_PORTRAIT_ROTATED = 20
  local DEVICE_ORIENTATION_LANDSCAPE = 21
  local DEVICE_ORIENTATION_LANDSCAPE_ROTATED = 22

  if ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
    if
      ev.value == DEVICE_ORIENTATION_PORTRAIT
      or ev.value == DEVICE_ORIENTATION_PORTRAIT_LEFT
      or ev.value == DEVICE_ORIENTATION_PORTRAIT_RIGHT
    then
      -- i.e., UR
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_UPRIGHT
    elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE then
      -- i.e., CW
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_CLOCKWISE
    elseif
      ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED
      or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_LEFT
      or ev.value == DEVICE_ORIENTATION_PORTRAIT_ROTATED_RIGHT
    then
      -- i.e., UD
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_UPSIDE_DOWN
    elseif ev.value == DEVICE_ORIENTATION_LANDSCAPE_ROTATED then
      -- i.e., CCW
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_COUNTER_CLOCKWISE
    end
  end
end

function KindleOasis:init()
  -- temporarily wake up awesome
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -CONT awesome")
  end

  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/max77696-bl/brightness",
    -- NOTE: Points to the embedded battery. The one in the cover is codenamed "soda".
    batt_capacity_file = "/sys/devices/system/wario_battery/wario_battery0/battery_capacity",
    is_charging_file = "/sys/devices/system/wario_charger/wario_charger0/charging",
    hall_file = "/sys/devices/system/wario_hall/wario_hall0/hall_enable",
  })

  self.input = require("device/input"):new({
    device = self,

    event_map = {
      [104] = "RPgFwd",
      [109] = "RPgBack",
    },
  })

  Kindle.init(self)

  --- @note See comments in KindleOasis2:init() for details.
  initRotation(self.screen)
  -- put awesome back to sleep
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -STOP awesome")
  end

  self.input:registerEventAdjustHook(OasisGyroTranslation)
  self.input.handleMiscEv = function(this, ev)
    if ev.code == C.MSC_GYRO then
      return this:handleGyroEv(ev)
    end
  end
end

-- HAL for gyro orientation switches (EV_ABS:ABS_PRESSURE (?!) w/ custom values to EV_MSC:MSC_GYRO w/ our own custom values)
local function KindleGyroTransform(this, ev)
  -- See source code:
  -- c.f., drivers/input/misc/accel/bma2x2.c for KOA2/KOA3
  -- c.f., drivers/input/misc/kx132/kx132.h for KS
  local UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED = 15
  local UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED = 16
  local UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED = 17
  local UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED = 18

  if ev.type == C.EV_ABS and ev.code == C.ABS_PRESSURE then
    if ev.value == UPWARD_PORTRAIT_UP_INTERRUPT_HAPPENED then
      -- i.e., UR
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_UPRIGHT
    elseif ev.value == UPWARD_LANDSCAPE_LEFT_INTERRUPT_HAPPENED then
      -- i.e., CW
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_CLOCKWISE
    elseif ev.value == UPWARD_PORTRAIT_DOWN_INTERRUPT_HAPPENED then
      -- i.e., UD
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_UPSIDE_DOWN
    elseif ev.value == UPWARD_LANDSCAPE_RIGHT_INTERRUPT_HAPPENED then
      -- i.e., CCW
      ev.type = C.EV_MSC
      ev.code = C.MSC_GYRO
      ev.value = C.DEVICE_ROTATED_COUNTER_CLOCKWISE
    end
  end
end

function KindleOasis2:init()
  -- temporarily wake up awesome
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -CONT awesome")
  end

  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/max77796-bl/brightness",
    batt_capacity_file = "/sys/class/power_supply/max77796-battery/capacity",
    is_charging_file = "/sys/class/power_supply/max77796-charger/charging",
    batt_status_file = "/sys/class/power_supply/max77796-charger/status",
  })

  self.input = require("device/input"):new({
    device = self,

    -- Top, Bottom (yes, it's the reverse than on non-Oasis devices)
    event_map = {
      [104] = "RPgFwd",
      [109] = "RPgBack",
    },
  })

  Kindle.init(self)

  --- @note When starting KOReader with the device upside down ("D"), touch input is registered wrong
  --    (i.e., probably upside down).
  --    If it's started upright ("U"), everything's okay, and turning it upside down after that works just fine.
  --    See #2206 & #2209 for the original KOA implementation, which obviously doesn't quite cut it here...
  --    See also <https://www.mobileread.com/forums/showthread.php?t=298302&page=5>
  --    See also #11159 for details about the solution (Kindle Scribe as an example)
  --    In regular mode, awesome is woken up for a brief moment for lipc calls.
  --    In no-framework mode, this works as is.
  -- NOTE: It'd take some effort to actually start KOReader while in a LANDSCAPE orientation,
  --     since they're only exposed inside the stock reader, and not the Home/KUAL Booklets.
  initRotation(self.screen)
  -- put awesome back to sleep
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -STOP awesome")
  end

  self.input:registerEventAdjustHook(KindleGyroTransform)
  self.input.handleMiscEv = function(this, ev)
    if ev.code == C.MSC_GYRO then
      return this:handleGyroEv(ev)
    end
  end
end

function KindleOasis3:init()
  -- temporarily wake up awesome
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -CONT awesome")
  end

  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/lm3697-bl1/brightness",
    warmth_intensity_file = "/sys/class/backlight/lm3697-bl0/brightness",
    batt_capacity_file = "/sys/class/power_supply/max77796-battery/capacity",
    is_charging_file = "/sys/class/power_supply/max77796-charger/charging",
    batt_status_file = "/sys/class/power_supply/max77796-charger/status",
  })

  self.input = require("device/input"):new({
    device = self,

    -- Top, Bottom (yes, it's the reverse than on non-Oasis devices)
    event_map = {
      [104] = "RPgFwd",
      [109] = "RPgBack",
    },
  })

  Kindle.init(self)

  --- @note The same quirks as on the Oasis 2 apply ;).
  initRotation(self.screen)
  -- put awesome back to sleep
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -STOP awesome")
  end

  self.input:registerEventAdjustHook(KindleGyroTransform)
  self.input.handleMiscEv = function(this, ev)
    if ev.code == C.MSC_GYRO then
      return this:handleGyroEv(ev)
    end
  end
end

function KindleBasic2:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    batt_capacity_file = "/sys/class/power_supply/bd7181x_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd7181x_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd7181x_bat/status",
    hall_file = "/sys/devices/system/heisenberg_hall/heisenberg_hall0/hall_enable",
  })

  Kindle.init(self)
end

function KindlePaperWhite4:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/bl/brightness",
    batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
    hall_file = "/sys/bus/platform/drivers/hall_sensor/rex_hall/hall_enable",
  })

  Kindle.init(self)
end

function KindleBasic3:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/bl/brightness",
    batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
    hall_file = "/sys/bus/platform/drivers/hall_sensor/rex_hall/hall_enable",
  })

  Kindle.init(self)

  -- This device doesn't emit ABS_MT_TRACKING_ID:-1 events on contact lift,
  -- so we have to rely on contact lift detection via BTN_TOUCH:0,
  -- c.f., https://github.com/koreader/koreader/issues/5070
  self.input.snow_protocol = true
  self.input.handleTouchEv = self.input.handleTouchEvSnow
end

function KindlePaperWhite5:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/fp9966-bl1/brightness",
    warmth_intensity_file = "/sys/class/backlight/fp9966-bl0/brightness",
    batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
    hall_file = "/sys/devices/platform/eink_hall/hall_enable",
  })

  -- Enable the so-called "fast" mode, so as to prevent the driver from silently promoting refreshes to REAGL.
  self.screen:_MTK_ToggleFastMode(true)

  Kindle.init(self)
end

function KindleBasic4:init()
  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/fp9966-bl1/brightness",
    warmth_intensity_file = "/sys/class/backlight/fp9966-bl0/brightness",
    batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
  })

  -- Enable the so-called "fast" mode, so as to prevent the driver from silently promoting refreshes to REAGL.
  self.screen:_MTK_ToggleFastMode(true)

  Kindle.init(self)
end

function KindleScribe:init()
  -- temporarily wake up awesome
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -CONT awesome")
  end

  self.screen =
    require("ffi/framebuffer_mxcfb"):new({ device = self, debug = logger.dbg })
  self.powerd = require("device/kindle/powerd"):new({
    device = self,
    fl_intensity_file = "/sys/class/backlight/fp9966-bl1/brightness",
    warmth_intensity_file = "/sys/class/backlight/fp9966-bl0/brightness",
    batt_capacity_file = "/sys/class/power_supply/bd71827_bat/capacity",
    is_charging_file = "/sys/class/power_supply/bd71827_bat/charging",
    batt_status_file = "/sys/class/power_supply/bd71827_bat/status",
    hall_file = "/sys/devices/platform/eink_hall/hall_enable",
  })

  -- Enable the so-called "fast" mode, so as to prevent the driver from silently promoting refreshes to REAGL.
  self.screen:_MTK_ToggleFastMode(true)

  Kindle.init(self)

  --- @note The same quirks as on the Oasis 2 and 3 apply ;).
  -- Logic is slightly different, cannot use the initRotation.
  local lipc = LibLipcs:accessor()
  if not LibLipcs:isFake(lipc) then
    local orientation_code =
      lipc:get_string_property("com.lab126.winmgr", "accelerometer")
    logger.dbg("orientation_code =", orientation_code)
    local rotation_mode = 0
    if orientation_code then
      if orientation_code == "U" or orientation_code == "L" then
        rotation_mode = self.screen.DEVICE_ROTATED_UPRIGHT
      elseif orientation_code == "D" or orientation_code == "R" then
        rotation_mode = self.screen.DEVICE_ROTATED_UPSIDE_DOWN
      end
    end
    if rotation_mode > 0 then
      self.screen.native_rotation_mode = rotation_mode
    end
    self.screen:setRotationMode(rotation_mode)
  end
  -- put awesome back to sleep
  if os.getenv("AWESOME_STOPPED") == "yes" then
    os.execute("killall -STOP awesome")
  end

  -- Setup accelerometer rotation input
  self.input:registerEventAdjustHook(KindleGyroTransform)
  self.input.handleMiscEv = function(this, ev)
    if ev.code == C.MSC_GYRO then
      return this:handleGyroEv(ev)
    end
  end

  -- Setup pen input
  self.input.wacom_protocol = true
end

function KindleTouch:exit()
  if self:isMTK() then
    -- Disable the so-called "fast" mode
    self.screen:_MTK_ToggleFastMode(false)
  end

  if self.framework_lipc_handle then
    -- Fixes missing *stock Amazon UI* screensavers on exiting out of "no framework" started KOReader
    -- module was unloaded in frameworkStopped() function but wasn't (re)loaded on KOReader exit
    self.framework_lipc_handle:set_string_property(
      "com.lab126.blanket",
      "load",
      "screensaver"
    )
  end

  Generic.exit(self)

  if self.isSpecialOffers then
    -- Wakey wakey...
    if os.getenv("AWESOME_STOPPED") == "yes" then
      os.execute("killall -CONT awesome")
    end
    -- fake a touch event
    if self.touch_dev then
      local width, height =
        self.screen:getScreenWidth(), self.screen:getScreenHeight()
      require("ffi/input").fakeTapInput(
        self.touch_dev,
        math.min(width, height) / 2,
        math.max(width, height) - 30
      )
    end
  end
end
KindlePaperWhite.exit = KindleTouch.exit
KindlePaperWhite2.exit = KindleTouch.exit
KindleBasic.exit = KindleTouch.exit
KindleVoyage.exit = KindleTouch.exit
KindlePaperWhite3.exit = KindleTouch.exit
KindleOasis.exit = KindleTouch.exit
KindleOasis2.exit = KindleTouch.exit
KindleBasic2.exit = KindleTouch.exit
KindlePaperWhite4.exit = KindleTouch.exit
KindleBasic3.exit = KindleTouch.exit
KindleOasis3.exit = KindleTouch.exit
KindlePaperWhite5.exit = KindleTouch.exit
KindleBasic4.exit = KindleTouch.exit
KindleScribe.exit = KindleTouch.exit

function Kindle3:exit()
  -- send double menu key press events to trigger screen refresh
  os.execute("echo 'send 139' > /proc/keypad;echo 'send 139' > /proc/keypad")

  Generic.exit(self)
end

KindleDXG.exit = Kindle3.exit

----------------- device recognition: -------------------

local function Set(list)
  local set = {}
  for _, l in ipairs(list) do
    set[l] = true
  end
  return set
end

local kindle_sn_fd = io.open("/proc/usid", "r")
if not kindle_sn_fd then
  return
end
local kindle_sn = kindle_sn_fd:read("*line")
kindle_sn_fd:close()
-- NOTE: Attempt to sanely differentiate v1 from v2,
--     c.f., https://github.com/NiLuJe/FBInk/commit/8a1161734b3f5b4461247af461d26987f6f1632e
local kindle_sn_lead = string.sub(kindle_sn, 1, 1)

-- NOTE: Update me when new devices come out :)
--     c.f., https://wiki.mobileread.com/wiki/Kindle_Serial_Numbers for identified variants
--     c.f., https://github.com/NiLuJe/KindleTool/blob/master/KindleTool/kindle_tool.h#L174 for all variants
local k2_set = Set({ "02", "03" })
local dx_set = Set({ "04", "05" })
local dxg_set = Set({ "09" })
local k3_set = Set({ "08", "06", "0A" })
local k4_set = Set({ "0E", "23" })
local touch_set = Set({ "0F", "11", "10", "12" })
local pw_set = Set({ "24", "1B", "1D", "1F", "1C", "20" })
local pw2_set = Set({
  "D4",
  "5A",
  "D5",
  "D6",
  "D7",
  "D8",
  "F2",
  "17",
  "60",
  "F4",
  "F9",
  "62",
  "61",
  "5F",
})
local kt2_set = Set({ "C6", "DD" })
local kv_set = Set({ "13", "54", "2A", "4F", "52", "53" })
local pw3_set = Set({
  "0G1",
  "0G2",
  "0G4",
  "0G5",
  "0G6",
  "0G7",
  "0KB",
  "0KC",
  "0KD",
  "0KE",
  "0KF",
  "0KG",
  "0LK",
  "0LL",
})
local koa_set = Set({ "0GC", "0GD", "0GR", "0GS", "0GT", "0GU" })
local koa2_set = Set({
  "0LM",
  "0LN",
  "0LP",
  "0LQ",
  "0P1",
  "0P2",
  "0P6",
  "0P7",
  "0P8",
  "0S1",
  "0S2",
  "0S3",
  "0S4",
  "0S7",
  "0SA",
})
local kt3_set = Set({ "0DU", "0K9", "0KA" })
local pw4_set = Set({
  "0PP",
  "0T1",
  "0T2",
  "0T3",
  "0T4",
  "0T5",
  "0T6",
  "0T7",
  "0TJ",
  "0TK",
  "0TL",
  "0TM",
  "0TN",
  "102",
  "103",
  "16Q",
  "16R",
  "16S",
  "16T",
  "16U",
  "16V",
})
local kt4_set = Set({ "10L", "0WF", "0WG", "0WH", "0WJ", "0VB" })
local koa3_set = Set({ "11L", "0WQ", "0WP", "0WN", "0WM", "0WL" })
local pw5_set =
  Set({ "1LG", "1Q0", "1PX", "1VD", "219", "21A", "2BH", "2BJ", "2DK" })
local kt5_set = Set({ "22D", "25T", "23A", "2AQ", "2AP", "1XH", "22C" })
local ks_set = Set({ "27J", "2BL", "263", "227", "2BM", "23L", "23M", "270" })

if kindle_sn_lead == "B" or kindle_sn_lead == "9" then
  local kindle_devcode = string.sub(kindle_sn, 3, 4)

  if k2_set[kindle_devcode] then
    return Kindle2
  elseif dx_set[kindle_devcode] then
    return Kindle2
  elseif dxg_set[kindle_devcode] then
    return KindleDXG
  elseif k3_set[kindle_devcode] then
    return Kindle3
  elseif k4_set[kindle_devcode] then
    return Kindle4
  elseif touch_set[kindle_devcode] then
    return KindleTouch
  elseif pw_set[kindle_devcode] then
    return KindlePaperWhite
  elseif pw2_set[kindle_devcode] then
    return KindlePaperWhite2
  elseif kt2_set[kindle_devcode] then
    return KindleBasic
  elseif kv_set[kindle_devcode] then
    return KindleVoyage
  end
else
  local kindle_devcode_v2 = string.sub(kindle_sn, 4, 6)

  if pw3_set[kindle_devcode_v2] then
    return KindlePaperWhite3
  elseif koa_set[kindle_devcode_v2] then
    return KindleOasis
  elseif koa2_set[kindle_devcode_v2] then
    return KindleOasis2
  elseif kt3_set[kindle_devcode_v2] then
    return KindleBasic2
  elseif pw4_set[kindle_devcode_v2] then
    return KindlePaperWhite4
  elseif kt4_set[kindle_devcode_v2] then
    return KindleBasic3
  elseif koa3_set[kindle_devcode_v2] then
    return KindleOasis3
  elseif pw5_set[kindle_devcode_v2] then
    return KindlePaperWhite5
  elseif kt5_set[kindle_devcode_v2] then
    return KindleBasic4
  elseif ks_set[kindle_devcode_v2] then
    return KindleScribe
  end
end

local kindle_sn_prefix = string.sub(kindle_sn, 1, 6)
error("unknown Kindle model: " .. kindle_sn_prefix)
