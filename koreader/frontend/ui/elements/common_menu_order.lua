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
    setting = {
      -- common settings
      -- those that don't exist will simply be skipped during menu gen
      "frontlight", -- if Device:hasFrontlight()
      "night_mode",
      "----------------------------",
      "network",
      "screen",
      "----------------------------",
      "taps_and_gestures",
      "navigation",
      "document",
      "----------------------------",
      "language",
      "device",
      -- end common settings
      "----------------------------",
    },
    document = {
      "document_metadata_location",
      "document_auto_save",
      "document_end_action",
      "language_support",
      "----------------------------",
    },
    screen = {
      "screensaver",
      "autodim",
      "auto_frontlight",
      "keep_alive",
      "----------------------------",
      "screen_rotation",
      "----------------------------",
      "screen_dpi",
      "screen_eink_opt",
      "autowarmth",
      "color_rendering",
      "----------------------------",
      "screen_timeout",
      "fullscreen",
      "----------------------------",
      "screen_notification",
    },
    taps_and_gestures = {
      "gesture_manager",
      "gesture_intervals",
      "----------------------------",
      "ignore_hold_corners",
      "screen_disable_double_tab",
      "----------------------------",
      "menu_activate",
      "----------------------------",
    },
    tools = {
      "read_timer",
      "calibre",
      "exporter",
      "statistics",
      "move_to_archive",
      "wallabag",
      "news_downloader",
      "text_editor",
      "profiles",
      "qrclipboard",
      "----------------------------",
      "book_shortcuts",
      "doc_setting_tweak",
      "terminal",
      "clock",
      "weather",
      "calculator",
      "----------------------------",
      "plugin_management",
    },
    search = {
      "search_settings",
      "findhistory",
      "----------------------------",
      "dictionary_lookup",
      "dictionary_lookup_history",
      "vocabbuilder",
      "----------------------------",
      "wikipedia_lookup",
      "wikipedia_history",
      "----------------------------",
    },
    search_settings = {
      "dictionary_settings",
      "wikipedia_settings",
    },
    main = {
      "history",
      "open_previous_document",
      "----------------------------",
      "favorites",
      "collections",
      "----------------------------",
      "mass_storage_actions", -- if Device:canToggleMassStorage()
      "----------------------------",
      "common_log_files",
      "ota_update", -- if Device:hasOTAUpdates()
      "help",
      "keyboard_shortcuts", -- explicitly place it here to save key presses
      "----------------------------",
      "exit_menu",
    },
  }

  for k, v in pairs(b) do
    a[k] = v
  end

  return a
end

return mergeWith
