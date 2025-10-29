local function mergeWith(b)
  local a = {
    device = {
      "keyboard_layout",
      "external_keyboard",
      "font_ui_fallbacks",
      "----------------------------",
      "time",
      "synchronize_time",
      "units",
      "device_status_alarm",
      "charging_led", -- if Device:canToggleChargingLED()
      "autostandby",
      "autosuspend",
      "autoshutdown",
      "battery_statistics",
      "ignore_sleepcover",
      "ignore_open_sleepcover",
      "cover_events",
      "ignore_battery_optimizations",
      "mass_storage_settings", -- if Device:canToggleMassStorage()
      "file_ext_assoc",
      "screenshot",
    },
    navigation = {
      "back_to_exit",
      "back_in_filemanager",
      "back_in_reader",
      "backspace_as_back",
      "----------------------------",
      "physical_buttons_setup",
      "----------------------------",
      "android_volume_keys",
      "android_haptic_feedback",
      "android_back_button",
      "----------------------------",
      "opening_page_location_stack",
      "skim_dialog_position",
    },
    network = {
      "network_wifi",
      "network_proxy",
      "network_powersave",
      "network_restore",
      "network_info",
      "network_before_wifi_action",
      "network_dismiss_scan",
      "----------------------------",
      "ssh",
      "httpremote",
    },
    help = {
      "quickstart_guide",
      "----------------------------",
      "search_menu",
      "----------------------------",
      "report_bug",
      "----------------------------",
      "system_statistics", -- if enabled (Plugin)
      "about",
    },
    exit_menu = {
      "restart_koreader", -- if Device:canRestart()
      "----------------------------",
      "sleep", -- if Device:canSuspend()
      "poweroff", -- if Device:canPowerOff()
      "reboot", -- if Device:canReboot()
      "----------------------------",
      "start_bq", -- if Device:isCervantes()
      "exit",
    },
  }

  for k, v in pairs(b) do
    a[k] = v
  end

  return a
end

return mergeWith
