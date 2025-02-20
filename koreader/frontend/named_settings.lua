--- Provides functions to read settings from G_reader_settings with default
--- values. This file helps share the configurations across multiple components
--- without needing to rely on the order of saveSetting and readSetting calls,
--- as well as the preexistent of the value in the G_require("named_settings").
--- Unless there is a clear reason, functions won't return nil or empty values.

local named_settings = {}

function named_settings.home_dir()
  -- Use of readSetting("home_dir") should still be possible but very limited, e.g. protected by
  -- G_named_settings:has("home_dir") or with another way to provide the backup_dir().
  return G_reader_settings:readSetting("home_dir") or require("util").backup_dir()
end

function named_settings.lastdir()
  return G_reader_settings:readSetting("lastdir") or require("util").backup_dir()
end

function named_settings.activate_menu()
  return G_reader_settings:readSetting("activate_menu") or "swipe_tap"
end

return named_settings
