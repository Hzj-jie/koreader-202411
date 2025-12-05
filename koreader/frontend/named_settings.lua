--- Provides functions to read settings from G_reader_settings with default
--- values. This file helps share the configurations across multiple components
--- without needing to rely on the order of saveSetting and readSetting calls,
--- as well as the preexistent of the value in the G_named_settings.
--- Unless there is a clear reason, functions won't return nil or empty values.

local named_settings = {
  set = {},
}

function named_settings.home_dir()
  -- Use of readSetting("home_dir") should still be possible but very limited, e.g. protected by
  -- G_named_settings:has("home_dir") or with another way to provide the backup_dir().
  return G_reader_settings:readSetting("home_dir")
    or require("util").backup_dir()
end

function named_settings.lastdir()
  return G_reader_settings:readSetting("lastdir")
    or require("util").backup_dir()
end

function named_settings.activate_menu()
  return G_reader_settings:readSetting("activate_menu") or "swipe_tap"
end

function named_settings.auto_standby_timeout_seconds()
  return G_reader_settings:readSetting("auto_standby_timeout_seconds") or -1
end

function named_settings.back_in_filemanager()
  return G_reader_settings:readSetting("back_in_filemanager") or "default"
end

function named_settings.back_in_reader()
  return G_reader_settings:readSetting("back_in_reader") or "previous_location"
end

function named_settings.back_to_exit()
  return G_reader_settings:readSetting("back_to_exit") or "prompt"
end

function named_settings.dict_font_size()
  return G_reader_settings:readSetting("dict_font_size") or 20
end

function named_settings.dimension_units()
  return G_reader_settings:readSetting("dimension_units") or "mm"
end

function named_settings.document_metadata_folder()
  return G_reader_settings:readSetting("document_metadata_folder") or "doc"
end

function named_settings.duration_format()
  return G_reader_settings:readSetting("duration_format") or "classic"
end

function named_settings.show_file_in_bold()
  return G_reader_settings:readSetting("show_file_in_bold") or "new"
end

function named_settings.set.show_file_in_bold(value)
  return G_reader_settings:saveSetting("show_file_in_bold", value, "new")
end

return named_settings
