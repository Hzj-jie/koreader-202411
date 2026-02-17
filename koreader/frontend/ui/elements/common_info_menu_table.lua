local BD = require("ui/bidi")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local FfiUtil = require("ffi/util")
local InfoMessage = require("ui/widget/infomessage")
local KeyValuePage = require("ui/widget/keyvaluepage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Version = require("version")
local dbg = require("dbg")
local dump = require("dump")
local lfs = require("libs/libkoreader-lfs")
local gettext = require("gettext")
local T = FfiUtil.template

local common_info = {}

-- main tab

common_info.help = {
  text = gettext("Help"),
}
if Device:hasKeyboard() then
  common_info.keyboard_shortcuts = {
    text = gettext("Keyboard shortcuts"), -- no localization
    callback = function()
      local kv_pairs = {}
      for k, v in UIManager:keyEvents() do
        table.insert(kv_pairs, {
          k,
          dump(v[1])
            :gsub("%s+", "")
            :gsub('"', "")
            :gsub("%[%d+%]=", "")
            :gsub(",}", "}")
            :gsub(",", ", ")
            :gsub("^{", "")
            :gsub("}$", ""),
        })
      end
      UIManager:show(KeyValuePage:new({
        title = gettext("Keyboard shortcuts"), -- no localization
        kv_pairs = kv_pairs,
      }))
    end,
  }
end
if G_defaults:isTrue("DEV_MODE") then
  common_info.common_log_files = {
    -- Need l11n
    text = gettext("Common log files"),
    sub_item_table = {},
  }
  for _, file in ipairs({
    "batterystat.log",
    "crash.log",
    "crash.prev.log",
  }) do
    local fullpath =
      FfiUtil.realpath(DataStorage:getFullDataDir() .. "/" .. file)
    table.insert(common_info.common_log_files.sub_item_table, {
      text = file,
      enabled_func = function()
        return fullpath ~= nil and lfs.attributes(fullpath, "mode") == "file"
      end,
      callback = function()
        require("apps/reader/readerui"):showReader(fullpath)
      end,
    })
  end

  common_info.advanced_settings =
    require("ui/elements/advanced_settings_menu_table")
  common_info.developer_options = require("ui/elements/dev_opt_menu_table")
end

common_info.quickstart_guide = {
  text = gettext("Quickstart guide"),
  callback = function()
    require("apps/reader/readerui"):showReader(
      require("ui/quickstart"):getQuickStart()
    )
  end,
}
common_info.search_menu = {
  text = gettext("Menu search"),
  callback = function()
    UIManager:broadcastEvent(Event:new("ShowMenuSearch"))
  end,
  keep_menu_open = true,
}
common_info.report_bug = {
  text_func = function()
    local label = gettext("Report a bug")
    if G_reader_settings:isTrue("debug_verbose") then
      label = label .. " " .. gettext("(verbose logging is enabled)")
    end
    return label
  end,
  keep_menu_open = true,
  callback = function(touchmenu_instance)
    local log_path =
      string.format("%s/%s", DataStorage:getDataDir(), "crash.log")
    local common_msg = T(
      gettext(
        "Please report bugs to \nhttps://github.com/koreader/koreader/issues\n\nVersion:\n%1\n\nDetected device:\n%2"
      ),
      Version:getCurrentRevision(),
      Device:info()
    ):gsub("koreader/koreader", "Hzj-jie/koreader-202411")
    local log_msg = T(
      gettext(
        "Verbose logs will make our investigations easier. If possible, try to reproduce the issue while it's enabled, and attach %1 to your bug report."
      ),
      log_path
    )

    if Device:isAndroid() then
      local android = require("android")
      android.dumpLogs()
    end

    local msg
    if lfs.attributes(log_path, "mode") == "file" then
      msg = string.format("%s\n\n%s", common_msg, log_msg)
    else
      msg = common_msg
    end
    UIManager:show(ConfirmBox:new({
      text = msg,
      icon = "notice-info",
      no_ok_button = true,
      other_buttons_first = true,
      other_buttons = {
        {
          {
            text = G_reader_settings:isTrue("debug_verbose") and gettext(
              "Disable verbose logging"
            ) or gettext("Enable verbose logging"),
            callback = function()
              -- Flip verbose logging on dismissal
              -- Unlike in the dev options, we flip everything at once.
              if G_reader_settings:isTrue("debug_verbose") then
                dbg:setVerbose(false)
                dbg:turnOff()
                G_reader_settings:makeFalse("debug_verbose")
                G_reader_settings:makeFalse("debug")
                Notification:notify(gettext("Verbose logging disabled"))
              else
                dbg:turnOn()
                dbg:setVerbose(true)
                G_reader_settings:makeTrue("debug")
                G_reader_settings:makeTrue("debug_verbose")
                Notification:notify(gettext("Verbose logging enabled"))
              end
              touchmenu_instance:updateItems()
              -- Also unlike the dev options, explicitly ask for a restart,
              -- to make sure framebuffer pulls in a logger.dbg ref that doesn't point to noop on init ;).
              UIManager:askForRestart()
            end,
          },
        },
      },
    }))
  end,
}
common_info.about = {
  -- Concatenation to avoid changing translations.
  text = gettext("About") .. " - " .. T(gettext("Version: %1"), Version:getShortVersion()),
  keep_menu_open = true,
  callback = function()
    UIManager:show(InfoMessage:new({
      text = T(
        gettext(
          "KOReader %1\n\nA document viewer for E Ink devices.\n\n"
            .. "Licensed under Affero GPL v3. All dependencies are free software.\n\n"
            .. "http://koreader.rocks"
        ),
        BD.ltr(Version:getCurrentRevision())
      ):gsub("koreader.rocks", "github.com/Hzj-jie/koreader-202411")
        .. (
          Version:getUncachedCurrentRevision()
              == Version:getCurrentRevision()
            and ""
          or "\n\n"
            .. T(
              gettext(
                "Running version may not match source code version %1.\n"
                  .. "Please consider restarting KOReader at the ealiest convenience."
              ),
              Version:getUncachedCurrentRevision()
            )
        ), -- Need localization
      icon = "koreader",
    }))
  end,
}

return common_info
