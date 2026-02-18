local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local FFIUtil = require("ffi/util")
local UIManager = require("ui/uimanager")
local dbg = require("dbg")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")

local developer_options = {
  text = gettext("Developer options"),
  sub_item_table = {
    {
      text = gettext("Clear caches"),
      callback = function()
        UIManager:show(ConfirmBox:new({
          text = gettext("Clear the cache folder?"),
          ok_callback = function()
            local DataStorage = require("datastorage")
            local cachedir = DataStorage:getDataDir() .. "/cache"
            if lfs.attributes(cachedir, "mode") == "directory" then
              FFIUtil.purgeDir(cachedir)
            end
            lfs.mkdir(cachedir)
            -- Also remove from the Cache object references to the cache files we've just deleted
            local Cache = require("cache")
            Cache.cached = {}
            UIManager:askForRestart(
              gettext("Caches cleared. Please restart KOReader.")
            )
          end,
        }))
      end,
    },
    {
      text = gettext("Enable debug logging"),
      checked_func = function()
        return G_reader_settings:isTrue("debug")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("debug")
        if G_reader_settings:isTrue("debug") then
          dbg:turnOn()
        else
          dbg:setVerbose(false)
          dbg:turnOff()
          G_reader_settings:makeFalse("debug_verbose")
        end
      end,
    },
    {
      text = gettext("Enable verbose debug logging"),
      enabled_func = function()
        return G_reader_settings:isTrue("debug")
      end,
      checked_func = function()
        return G_reader_settings:isTrue("debug_verbose")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("debug_verbose")
        if G_reader_settings:isTrue("debug_verbose") then
          dbg:setVerbose(true)
        else
          dbg:setVerbose(false)
        end
      end,
    },
  },
}
if Device:isKobo() and not Device:isSunxi() and not Device:hasColorScreen() then
  table.insert(developer_options.sub_item_table, {
    text = gettext("Disable forced 8-bit pixel depth"),
    checked_func = function()
      return G_reader_settings:isTrue("dev_startup_no_fbdepth")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("dev_startup_no_fbdepth")
      UIManager:askForRestart()
    end,
  })
end
--- @note Currently, only Kobo, rM & PB have a fancy crash display (#5328)
if Device:isKobo() or Device:isRemarkable() or Device:isPocketBook() then
  table.insert(developer_options.sub_item_table, {
    text = gettext("Always abort on crash"),
    checked_func = function()
      return G_reader_settings:isTrue("dev_abort_on_crash")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("dev_abort_on_crash")
      UIManager:askForRestart()
    end,
  })
end
local Blitbuffer = require("ffi/blitbuffer")
table.insert(developer_options.sub_item_table, {
  text = gettext("Disable C blitter"),
  enabled_func = function()
    return Blitbuffer.has_cblitbuffer
  end,
  checked_func = function()
    return G_reader_settings:isTrue("dev_no_c_blitter")
  end,
  callback = function()
    G_reader_settings:flipNilOrFalse("dev_no_c_blitter")
    Blitbuffer:enableCBB(G_reader_settings:nilOrFalse("dev_no_c_blitter"))
  end,
})
if Device:hasEinkScreen() and Device:canHWDither() then
  table.insert(developer_options.sub_item_table, {
    text = gettext("Disable HW dithering"),
    checked_func = function()
      return not Device.screen.hw_dithering
    end,
    callback = function()
      Device.screen:toggleHWDithering()
      G_reader_settings:save(
        "dev_no_hw_dither",
        not Device.screen.hw_dithering,
        false
      )
      -- Make sure SW dithering gets disabled when we enable HW dithering
      if Device.screen.hw_dithering and Device.screen.sw_dithering then
        G_reader_settings:makeTrue("dev_no_sw_dither")
        Device.screen:toggleSWDithering(false)
      end
      UIManager:setDirty("all", "full")
    end,
  })
end
if Device:hasEinkScreen() then
  table.insert(developer_options.sub_item_table, {
    text = gettext("Disable SW dithering"),
    enabled_func = function()
      return Device.screen.fb_bpp == 8
    end,
    checked_func = function()
      return not Device.screen.sw_dithering
    end,
    callback = function()
      Device.screen:toggleSWDithering()
      G_reader_settings:save(
        "dev_no_sw_dither",
        not Device.screen.sw_dithering,
        false
      )
      -- Make sure HW dithering gets disabled when we enable SW dithering
      if Device.screen.hw_dithering and Device.screen.sw_dithering then
        G_reader_settings:makeTrue("dev_no_hw_dither")
        Device.screen:toggleHWDithering(false)
      end
      UIManager:setDirty("all", "full")
    end,
  })
end
if Device:isKobo() and Device:hasColorScreen() then
  table.insert(developer_options.sub_item_table, {
    -- We default to a flag (G2) that slightly boosts saturation,
    -- but it *is* a destructive process, so we want to allow disabling it.
    -- @translators CFA is a technical term for the technology behind eInk's color panels. It stands for Color Film/Filter Array, leave the abbreviation alone ;).
    text = gettext("Disable CFA post-processing"),
    checked_func = function()
      return G_reader_settings:isTrue("no_cfa_post_processing")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("no_cfa_post_processing")
      UIManager:askForRestart()
    end,
  })
end
table.insert(developer_options.sub_item_table, {
  text = gettext("Anti-alias rounded corners"),
  checked_func = function()
    return G_reader_settings:nilOrTrue("anti_alias_ui")
  end,
  callback = function()
    G_reader_settings:flipNilOrTrue("anti_alias_ui")
  end,
})
--- @note: Currently, only Kobo implements this quirk
if Device:hasEinkScreen() and Device:isKobo() then
  table.insert(developer_options.sub_item_table, {
    -- @translators Highly technical (ioctl is a Linux API call, the uppercase stuff is a constant). What's translatable is essentially only the action ("bypass") and the article.
    text = gettext("Bypass the WAIT_FOR ioctls"),
    checked_func = function()
      return G_reader_settings:isTrueOr(
        "mxcfb_bypass_wait_for",
        not Device:hasReliableMxcWaitFor()
      )
    end,
    callback = function()
      local mxcfb_bypass_wait_for = G_reader_settings:isTrueOr(
        "mxcfb_bypass_wait_for",
        not Device:hasReliableMxcWaitFor()
      )
      G_reader_settings:save(
        "mxcfb_bypass_wait_for",
        not mxcfb_bypass_wait_for,
        not Devide:hasReliableMxcWaitFor()
      )
      UIManager:askForRestart()
    end,
  })
end
--- @note: Intended to debug/investigate B288 quirks on PocketBook devices
if Device:hasEinkScreen() and Device:isPocketBook() then
  table.insert(developer_options.sub_item_table, {
    -- @translators B288 is the codename of the CPU/chipset (SoC stands for 'System on Chip').
    text = gettext("Ignore feature bans on B288 SoCs"),
    enabled_func = function()
      return Device:isB288SoC()
    end,
    checked_func = function()
      return G_reader_settings:isTrue("pb_ignore_b288_quirks")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("pb_ignore_b288_quirks")
      UIManager:askForRestart()
    end,
  })
end
if Device:isAndroid() then
  table.insert(developer_options.sub_item_table, {
    text = gettext("Start compatibility test"),
    callback = function()
      Device:test()
    end,
  })
end

table.insert(developer_options.sub_item_table, {
  text = gettext("Disable enhanced UI text shaping (xtext)"),
  checked_func = function()
    return G_reader_settings:isFalse("use_xtext")
  end,
  callback = function()
    G_reader_settings:flipNilOrTrue("use_xtext")
    UIManager:askForRestart()
  end,
})
table.insert(developer_options.sub_item_table, {
  text = gettext("UI layout mirroring and text direction"),
  sub_item_table = {
    {
      text = gettext("Reverse UI layout mirroring"),
      checked_func = function()
        return G_reader_settings:isTrue("dev_reverse_ui_layout_mirroring")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("dev_reverse_ui_layout_mirroring")
        UIManager:askForRestart()
      end,
    },
    {
      text = gettext("Reverse UI text direction"),
      checked_func = function()
        return G_reader_settings:isTrue("dev_reverse_ui_text_direction")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("dev_reverse_ui_text_direction")
        UIManager:askForRestart()
      end,
    },
  },
})
table.insert(developer_options.sub_item_table, {
  text_func = function()
    if
      G_reader_settings:nilOrTrue("use_cre_call_cache")
      and G_reader_settings:isTrue("use_cre_call_cache_log_stats")
    then
      return gettext("Enable CRE call cache (with stats)")
    end
    return gettext("Enable CRE call cache")
  end,
  checked_func = function()
    return G_reader_settings:nilOrTrue("use_cre_call_cache")
  end,
  callback = function()
    G_reader_settings:flipNilOrTrue("use_cre_call_cache")
    -- No need to show "This will take effect on next CRE book opening."
    -- as this menu is only accessible from file browser
  end,
  hold_callback = function(touchmenu_instance)
    G_reader_settings:flipNilOrFalse("use_cre_call_cache_log_stats")
    touchmenu_instance:updateItems()
  end,
})
table.insert(developer_options.sub_item_table, {
  text = gettext("Dump the fontlist cache"),
  callback = function()
    local FontList = require("fontlist")
    FontList:dumpFontList()
  end,
})
if Device:isKobo() and Device:canToggleChargingLED() then
  table.insert(developer_options.sub_item_table, {
    -- @translators This is a debug option to help determine cases when standby failed to initiate properly. PM = power management.
    text = gettext("Turn on the LED on PM entry failure"),
    checked_func = function()
      return G_reader_settings:isTrue("pm_debug_entry_failure")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("pm_debug_entry_failure")
    end,
  })
end

return developer_options
