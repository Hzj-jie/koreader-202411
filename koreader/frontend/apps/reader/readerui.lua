--[[
ReaderUI is an abstraction for a reader interface.

It works using data gathered from a document interface.
]]
--

local BD = require("ui/bidi")
local Device = require("device")
local DeviceListener = require("device/devicelistener")
local DocCache = require("document/doccache")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerFileSearcher =
  require("apps/filemanager/filemanagerfilesearcher")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LanguageSupport = require("languagesupport")
local NetworkListener = require("ui/network/networklistener")
local Notification = require("ui/widget/notification")
local PluginLoader = require("pluginloader")
local ReaderActivityIndicator =
  require("apps/reader/modules/readeractivityindicator")
local ReaderAnnotation = require("apps/reader/modules/readerannotation")
local ReaderBack = require("apps/reader/modules/readerback")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local ReaderConfig = require("apps/reader/modules/readerconfig")
local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
local ReaderCropping = require("apps/reader/modules/readercropping")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderFont = require("apps/reader/modules/readerfont")
local ReaderGoto = require("apps/reader/modules/readergoto")
local ReaderHandMade = require("apps/reader/modules/readerhandmade")
local ReaderHinting = require("apps/reader/modules/readerhinting")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local ReaderScrolling = require("apps/reader/modules/readerscrolling")
local ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
local ReaderLink = require("apps/reader/modules/readerlink")
local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderPageMap = require("apps/reader/modules/readerpagemap")
local ReaderPanning = require("apps/reader/modules/readerpanning")
local ReaderPaging = require("apps/reader/modules/readerpaging")
local ReaderRolling = require("apps/reader/modules/readerrolling")
local ReaderSearch = require("apps/reader/modules/readersearch")
local ReaderStatus = require("apps/reader/modules/readerstatus")
local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
local ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
local ReaderToc = require("apps/reader/modules/readertoc")
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local ReaderTypography = require("apps/reader/modules/readertypography")
local ReaderUserHyph = require("apps/reader/modules/readeruserhyph")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderZooming = require("apps/reader/modules/readerzooming")
local Screenshoter = require("ui/widget/screenshoter")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen
local T = ffiUtil.template

local ReaderUI = InputContainer:extend({
  name = "ReaderUI",

  -- if we have a parent container, it must be referenced for now
  dialog = nil,

  -- the document interface
  document = nil,

  -- password for document unlock
  password = nil,
})

function ReaderUI:registerModule(name, ui_module)
  if name then
    self[name] = ui_module
    ui_module.name = "reader" .. name
  end
  table.insert(self, ui_module)
end

function ReaderUI:init()
  UIManager:show(self, self.seamless and "ui" or "full")

  -- cap screen refresh on pan to 2 refreshes per second
  local pan_rate = Screen.low_pan_rate and 2.0 or 30.0

  Input:inhibitInput(true) -- Inhibit any past and upcoming input events.
  Device:setIgnoreInput(true) -- Avoid ANRs on Android with unprocessed events.

  -- if we are not the top level dialog ourselves, it must be given in the table
  if not self.dialog then
    self.dialog = self
  end

  self.doc_settings = DocSettings:open(self.document.file)

  self:registerKeyEvents()

  -- a view container (so it must be child #1!)
  -- all paintable widgets need to be a child of reader view
  self:registerModule(
    "view",
    ReaderView:new({
      dialog = self.dialog,
      dimen = self.dimen,
      ui = self,
      document = self.document,
    })
  )

  -- screenshot controller, it has the highest priority to receive the user
  -- input, e.g. swipe or two-finger-tap
  self:registerModule(
    "screenshot",
    Screenshoter:new({
      prefix = "Reader",
      dialog = self.dialog,
      view = self.view,
      ui = self,
    })
  )

  -- goto link controller
  self:registerModule(
    "link",
    ReaderLink:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- text highlight
  self:registerModule(
    "highlight",
    ReaderHighlight:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- menu widget should be registered after link widget and highlight widget
  -- so that taps on link and highlight areas won't popup reader menu
  -- reader menu controller
  self:registerModule(
    "menu",
    ReaderMenu:new({
      view = self.view,
      ui = self,
    })
  )
  -- Handmade/custom ToC and hidden flows
  self:registerModule(
    "handmade",
    ReaderHandMade:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- Table of content controller
  self:registerModule(
    "toc",
    ReaderToc:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
    })
  )
  -- bookmark controller
  self:registerModule(
    "bookmark",
    ReaderBookmark:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
    })
  )
  self:registerModule(
    "annotation",
    ReaderAnnotation:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- reader goto controller
  -- "goto" being a dirty keyword in Lua?
  self:registerModule(
    "gotopage",
    ReaderGoto:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  self:registerModule(
    "languagesupport",
    LanguageSupport:new({
      ui = self,
      document = self.document,
    })
  )
  -- dictionary
  self:registerModule(
    "dictionary",
    ReaderDictionary:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- wikipedia
  self:registerModule(
    "wikipedia",
    ReaderWikipedia:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
  )
  -- device status controller
  self:registerModule(
    "devicestatus",
    ReaderDeviceStatus:new({
      ui = self,
    })
  )
  -- configurable controller
  if self.document.info.configurable then
    -- config panel controller
    self:registerModule(
      "config",
      ReaderConfig:new({
        configurable = self.document.configurable,
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
      })
    )
    if self.document.info.has_pages then
      -- kopt option controller
      self:registerModule(
        "koptlistener",
        ReaderKoptListener:new({
          dialog = self.dialog,
          view = self.view,
          ui = self,
          document = self.document,
        })
      )
    else
      -- cre option controller
      self:registerModule(
        "crelistener",
        ReaderCoptListener:new({
          dialog = self.dialog,
          view = self.view,
          ui = self,
          document = self.document,
        })
      )
    end
    -- activity indicator for when some settings take time to take effect (Kindle under KPV)
    if not ReaderActivityIndicator:isStub() then
      self:registerModule(
        "activityindicator",
        ReaderActivityIndicator:new({
          dialog = self.dialog,
          view = self.view,
          ui = self,
          document = self.document,
        })
      )
    end
  end
  -- for page specific controller
  if self.document.info.has_pages then
    -- cropping controller
    self:registerModule(
      "cropping",
      ReaderCropping:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
        document = self.document,
      })
    )
    -- paging controller
    self:registerModule(
      "paging",
      ReaderPaging:new({
        pan_rate = pan_rate,
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- zooming controller
    self:registerModule(
      "zooming",
      ReaderZooming:new({
        dialog = self.dialog,
        document = self.document,
        view = self.view,
        ui = self,
      })
    )
    -- panning controller
    self:registerModule(
      "panning",
      ReaderPanning:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- hinting controller
    self:registerModule(
      "hinting",
      ReaderHinting:new({
        dialog = self.dialog,
        zoom = self.zooming,
        view = self.view,
        ui = self,
        document = self.document,
      })
    )
  else
    -- load crengine default settings (from cr3.ini, some of these
    -- will be overridden by our settings by some reader modules below)
    if self.document.setupDefaultView then
      self.document:setupDefaultView()
    end
    -- make sure we render document first before calling any callback, so using
    -- onReadSettings which happens before onReaderInited.
    self.onReadSettings = function()
      local start_time = time.now()
      if not self.document:loadDocument() then
        self:dealWithLoadDocumentFailure()
      end
      logger.dbg(
        string.format(
          "  loading took %.3f seconds",
          time.to_s(time.since(start_time))
        )
      )

      -- used to read additional settings after the document has been
      -- loaded (but not rendered yet)
      UIManager:broadcastEvent(
        Event:new("PreRenderDocument", self.doc_settings)
      )

      start_time = time.now()
      self.document:render()
      logger.dbg(
        string.format(
          "  rendering took %.3f seconds",
          time.to_s(time.since(start_time))
        )
      )

      -- Uncomment to output the built DOM (for debugging)
      -- logger.dbg(self.document:getHTMLFromXPointer(".0", 0x6830))
    end
    -- styletweak controller (must be before typeset controller)
    self:registerModule(
      "styletweak",
      ReaderStyleTweak:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- typeset controller
    self:registerModule(
      "typeset",
      ReaderTypeset:new({
        configurable = self.document.configurable,
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- font menu
    self:registerModule(
      "font",
      ReaderFont:new({
        configurable = self.document.configurable,
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- user hyphenation (must be registered before typography)
    self:registerModule(
      "userhyph",
      ReaderUserHyph:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- typography menu (replaces previous hyphenation menu / ReaderHyphenation)
    self:registerModule(
      "typography",
      ReaderTypography:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- rolling controller
    self:registerModule(
      "rolling",
      ReaderRolling:new({
        configurable = self.document.configurable,
        pan_rate = pan_rate,
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
    -- pagemap controller
    self:registerModule(
      "pagemap",
      ReaderPageMap:new({
        dialog = self.dialog,
        view = self.view,
        ui = self,
      })
    )
  end
  self.disable_double_tap = G_reader_settings:nilOrTrue("disable_double_tap")
  -- scrolling (scroll settings + inertial scrolling)
  self:registerModule(
    "scrolling",
    ReaderScrolling:new({
      pan_rate = pan_rate,
      dialog = self.dialog,
      ui = self,
      view = self.view,
    })
  )
  -- back location stack
  self:registerModule(
    "back",
    ReaderBack:new({
      ui = self,
      view = self.view,
    })
  )
  -- fulltext search
  self:registerModule(
    "search",
    ReaderSearch:new({
      dialog = self.dialog,
      view = self.view,
      ui = self,
    })
  )
  -- book status
  self:registerModule(
    "status",
    ReaderStatus:new({
      ui = self,
      document = self.document,
    })
  )
  -- thumbnails service (book map, page browser)
  self:registerModule(
    "thumbnail",
    ReaderThumbnail:new({
      ui = self,
      document = self.document,
    })
  )
  -- file searcher
  self:registerModule(
    "filesearcher",
    FileManagerFileSearcher:new({
      dialog = self.dialog,
      ui = self,
    })
  )
  -- folder shortcuts
  self:registerModule(
    "folder_shortcuts",
    FileManagerShortcuts:new({
      dialog = self.dialog,
      ui = self,
    })
  )
  -- history view
  self:registerModule(
    "history",
    FileManagerHistory:new({
      dialog = self.dialog,
      ui = self,
    })
  )
  -- collections/favorites view
  self:registerModule(
    "collections",
    FileManagerCollection:new({
      dialog = self.dialog,
      ui = self,
    })
  )
  -- book info
  self:registerModule(
    "bookinfo",
    FileManagerBookInfo:new({
      dialog = self.dialog,
      document = self.document,
      ui = self,
    })
  )
  -- event listener to change device settings
  self:registerModule(
    "devicelistener",
    DeviceListener:new({
      document = self.document,
      view = self.view,
      ui = self,
    })
  )
  self:registerModule(
    "networklistener",
    NetworkListener:new({
      document = self.document,
      view = self.view,
      ui = self,
    })
  )

  -- koreader plugins
  for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
    local ok, plugin_or_err = PluginLoader:createPluginInstance(plugin_module, {
      dialog = self.dialog,
      view = self.view,
      ui = self,
      document = self.document,
    })
    if ok then
      self:registerModule(plugin_module.name, plugin_or_err)
      logger.dbg(
        "RD loaded plugin",
        plugin_module.name,
        "at",
        plugin_module.path
      )
    end
  end

  -- Allow others to change settings based on external factors
  -- Must be called after plugins are loaded & before setting are read.
  UIManager:broadcastEvent(
    Event:new("DocSettingsLoad", self.doc_settings, self.document)
  )
  -- we only read settings after all the widgets are initialized
  UIManager:broadcastEvent(Event:new("ReadSettings", self.doc_settings))
  UIManager:broadcastEvent(Event:new("ReaderInited"))

  -- Now that document is loaded, store book metadata in settings.
  local props = self.document:getProps()
  self.doc_settings:saveSetting("doc_props", props)
  -- And have an extended and customized copy in memory for quick access.
  self.doc_props = FileManagerBookInfo.extendProps(props, self.document.file)

  local md5 = self.doc_settings:readSetting("partial_md5_checksum")
  if md5 == nil then
    md5 = util.partialMD5(self.document.file)
    self.doc_settings:saveSetting("partial_md5_checksum", md5)
  end

  local summary = self.doc_settings:readTableSetting("summary")
  if summary.status == nil then
    summary.status = "reading"
    summary.modified = os.date("%Y-%m-%d", os.time())
  end

  if
    summary.status ~= "complete"
    or not G_reader_settings:nilOrTrue("history_freeze_finished_books")
  then
    require("readhistory"):addItem(self.document.file) -- (will update "lastfile")
  end

  -- After initialisation notify that document is loaded and rendered
  -- CREngine only reports correct page count after rendering is done
  -- Need the same event for PDF document
  UIManager:broadcastEvent(Event:new("ReaderReady", self.doc_settings))
  UIManager:broadcastEvent(Event:new("PostReaderReady"))

  Device:setIgnoreInput(false) -- Allow processing of events (on Android).
  Input:inhibitInputUntil(0.2)

  -- print("Ordered registered gestures:")
  -- for _, tzone in ipairs(self._ordered_touch_zones) do
  --   print("  "..tzone.def.id)
  -- end

  assert(ReaderUI.instance == nil)
  ReaderUI.instance = self
end

function ReaderUI:registerKeyEvents()
  if Device:hasKeys() then
    self.key_events.Home = { { "Home" } }
    self.key_events.Reload = { { "F5" } }
    if Device:hasDPad() and Device:useDPadAsActionKeys() then
      self.key_events.KeyContentSelection =
        { { { "Up", "Down" } }, event = "StartHighlightIndicator" }
    end
    if Device:hasScreenKB() or Device:hasSymKey() then
      if Device:hasKeyboard() then
        self.key_events.KeyToggleWifi =
          { { "Shift", "Home" }, event = "ToggleWifi" }
        self.key_events.OpenLastDoc = { { "Shift", "Back" } }
      else -- Currently exclusively targets Kindle 4.
        self.key_events.KeyToggleWifi =
          { { "ScreenKB", "Home" }, event = "ToggleWifi" }
        self.key_events.OpenLastDoc = { { "ScreenKB", "Back" } }
      end
    end
  end
end

ReaderUI.onPhysicalKeyboardConnected = ReaderUI.registerKeyEvents

function ReaderUI:setLastDirForFileBrowser(dir)
  if dir and #dir > 1 and dir:sub(-1) == "/" then
    dir = dir:sub(1, -2)
  end
  self.last_dir_for_file_browser = dir
end

function ReaderUI:getLastDirFile(to_file_browser)
  if to_file_browser and self.last_dir_for_file_browser then
    local dir = self.last_dir_for_file_browser
    self.last_dir_for_file_browser = nil
    return dir
  end
  local QuickStart = require("ui/quickstart")
  local last_dir
  local last_file = G_reader_settings:readSetting("lastfile")
  -- ignore quickstart guide as last_file so we can go back to home dir
  if last_file and last_file ~= QuickStart.quickstart_filename then
    last_dir = last_file:match("(.*)/")
  end
  return last_dir, last_file
end

function ReaderUI:showFileManager(file, selected_files)
  local FileManager = require("apps/filemanager/filemanager")

  local last_dir, last_file
  if file then
    last_dir = util.splitFilePathName(file)
    last_file = file
  else
    last_dir, last_file = self:getLastDirFile(true)
  end
  if FileManager.instance then
    FileManager.instance:reinit(last_dir, last_file)
  else
    FileManager:showFiles(last_dir, last_file, selected_files)
  end
end

function ReaderUI:onShowingReader()
  -- Allows us to optimize out a few useless refreshes in various CloseWidgets handlers...
  self.tearing_down = true
  self.dithered = nil

  -- Don't enforce a "full" refresh, leave that decision to the next widget we'll *show*.
  self:onExit(false)
end

-- Same as above, except we don't close it yet. Useful for plugins that need to close custom Menus before calling showReader.
function ReaderUI:onSetupShowReader()
  self.tearing_down = true
  self.dithered = nil
end

--- @note: Will sanely close existing FileManager/ReaderUI instance for you!
---    This is the *only* safe way to instantiate a new ReaderUI instance!
---    (i.e., don't look at the testsuite, which resorts to all kinds of nasty hacks).
function ReaderUI:showReader(file, provider, seamless)
  logger.dbg("show reader ui")

  origin_file = file
  file = ffiUtil.realpath(file)
  if file == nil or lfs.attributes(file, "mode") ~= "file" then
    UIManager:show(InfoMessage:new({
      text = T(
        _("File '%1' does not exist."),
        BD.filepath(filemanagerutil.abbreviate(origin_file))
      ),
    }))
    return
  end

  if not DocumentRegistry:hasProvider(file) and provider == nil then
    UIManager:show(InfoMessage:new({
      text = T(
        _("File '%1' is not supported."),
        BD.filepath(filemanagerutil.abbreviate(file))
      ),
    }))
    self:showFileManager(file)
    return
  end

  -- We can now signal the existing ReaderUI/FileManager instances that it's time to go bye-bye...
  UIManager:broadcastEvent(Event:new("ShowingReader"))
  provider = provider or DocumentRegistry:getProvider(file)
  if provider.provider then
    self:showReaderCoroutine(file, provider, seamless)
  else
    UIManager:show(InfoMessage:new({
      text = _("No reader engine for this file or invalid file."),
    }))
    self:showFileManager(file)
  end
end

function ReaderUI:showReaderCoroutine(file, provider, seamless)
  -- doShowReader might block for a long time, so force repaint here
  UIManager:runWith(
    function()
      logger.dbg("creating coroutine for showing reader")
      local co = coroutine.create(function()
        self:doShowReader(file, provider, seamless)
      end)
      local ok, err = coroutine.resume(co)
      if err ~= nil or ok == false then
        io.stderr:write("[!] doShowReader coroutine crashed:\n")
        io.stderr:write(debug.traceback(co, err, 1))
        -- Restore input if we crashed before ReaderUI has restored it
        Device:setIgnoreInput(false)
        Input:inhibitInputUntil(0.2)
        -- Need localization.
        UIManager:show(InfoMessage:new({
          text = _("Unfortunately KOReader crashed.")
            .. "\n"
            .. _(
              "Report a bug to https://github.com/Hzj-jie/koreader-202411 can help developers to improve it."
            ),
        }))
        self:showFileManager(file)
      end
    end,
    InfoMessage:new({
      text = T(
        _("Opening file '%1'."),
        BD.filepath(filemanagerutil.abbreviate(file))
      ),
      invisible = seamless,
    })
  )
end

function ReaderUI:doShowReader(file, provider, seamless)
  if seamless then
    UIManager:avoidFlashOnNextRepaint()
  end
  logger.info("opening file", file)
  -- Only keep a single instance running
  assert(ReaderUI.instance == nil)
  local document = DocumentRegistry:openDocument(file, provider)
  if not document then
    UIManager:show(InfoMessage:new({
      text = _("No reader engine for this file or invalid file."),
    }))
    self:showFileManager(file)
    return
  end
  if document.is_locked then
    logger.info("document is locked")
    self._coroutine = coroutine.running() or self._coroutine
    self:unlockDocumentWithPassword(document)
    if coroutine.running() then
      local unlock_success = coroutine.yield()
      if not unlock_success then
        self:showFileManager(file)
        return
      end
    end
  end
  local reader = ReaderUI:new({
    dimen = Screen:getSize(),
    covers_fullscreen = true, -- hint for UIManager:_repaint()
    document = document,
    seamless = seamless,
  })

  Screen:setWindowTitle(reader.doc_props.display_title)
  Device:notifyBookState(reader.doc_props.display_title, document)

  -- This is mostly for the few callers that bypass the coroutine shenanigans and call doShowReader directly,
  -- instead of showReader...
  -- Otherwise, showReader will have taken care of that *before* instantiating a new RD,
  -- in order to ensure a sane ordering of plugins teardown -> instantiation.
  local FileManager = require("apps/filemanager/filemanager")
  if FileManager.instance then
    FileManager.instance:onExit()
  end
end

function ReaderUI:unlockDocumentWithPassword(document, try_again)
  logger.dbg("show input password dialog")
  self.password_dialog = InputDialog:new({
    title = try_again and _("Password is incorrect, try again?")
      or _("Input document password"),
    buttons = {
      {
        {
          text = _("Cancel"),
          id = "close",
          callback = function()
            self:closeDialog()
            coroutine.resume(self._coroutine)
          end,
        },
        {
          text = _("OK"),
          callback = function()
            local success = self:onVerifyPassword(document)
            self:closeDialog()
            if success then
              coroutine.resume(self._coroutine, success)
            else
              self:unlockDocumentWithPassword(document, true)
            end
          end,
        },
      },
    },
    text_type = "password",
  })
  UIManager:show(self.password_dialog)
  self.password_dialog:showKeyboard()
end

function ReaderUI:onVerifyPassword(document)
  local password = self.password_dialog:getInputText()
  return document:unlock(password)
end

function ReaderUI:closeDialog()
  self.password_dialog:onExit()
  UIManager:close(self.password_dialog)
end

function ReaderUI:onScreenResize(dimen)
  self.dimen = dimen
  self:updateTouchZonesOnScreenResize(dimen)
end

function ReaderUI:saveSettings()
  -- Note, this behavior should only impact ReaderUI and its modules but not
  -- other components, since it's called by UIManager:close /
  -- widget:broadcastEvent("FlushSettings"). I.e. only the widget and its sub
  -- widgets need to flush settings.
  -- Note, even calling UIManager:broadcastEvent, it shouldn't make noticeable
  -- difference, as the UIManager should only know ReaderUI in the case.
  self:broadcastEvent(Event:new("SaveSettings"))
  self.doc_settings:flush()
  G_reader_settings:flush()
end

function ReaderUI:onFlushSettings(show_notification)
  self:saveSettings()
  if show_notification then
    -- Invoked from dispatcher to explicitly flush settings
    Notification:notify(_("Book metadata saved."))
  end
end

function ReaderUI:onExit(full_refresh)
  if self.document == nil then
    -- This shouldn't happen, but who knows who would call ReaderUI:onExit?
    return
  end
  logger.dbg("closing reader")
  UIManager:runWith(
    function()
      PluginLoader:finalize()
      Device:notifyBookState(nil, nil)
      -- if self.dialog is us, we'll have our onFlushSettings() called
      -- by UIManager:close() below, so avoid double save
      if self.dialog ~= self then
        self:saveSettings()
      end
      if self.document ~= nil then
        require("readhistory"):updateLastBookTime(self.tearing_down)
        -- Serialize the most recently displayed page for later launch
        DocCache:serialize(self.document.file)
        logger.dbg("closing document")
        UIManager:broadcastEvent(Event:new("CloseDocument"))
        if
          self.document:isEdited()
          and not self.highlight.highlight_write_into_pdf
        then
          self.document:discardChange()
        end
        self.document:close()
        self.document = nil
      end
      if self.dialog == self then
        UIManager:close(self, full_refresh ~= false and "full")
      else
        UIManager:close(self)
        UIManager:close(self.dialog, full_refresh ~= false and "full")
      end
    end,
    InfoMessage:new({
      -- Need localization.
      text = T(_("Saving progress of file %1"), self.document.file),
    })
  )
end

function ReaderUI:onClose()
  -- In case someone broadcasts Exit or Close multiple times.
  assert(ReaderUI.instance == self or ReaderUI.instance == nil)
  ReaderUI.instance = nil
  self._coroutine = nil
end

function ReaderUI:dealWithLoadDocumentFailure()
  -- Sadly, we had to delay loadDocument() to about now, so we only
  -- know now this document is not valid or recognized.
  -- We can't do much more than crash properly here (still better than
  -- going on and segfaulting when calling other methods on unitiliazed
  -- _document)
  -- As we are in a coroutine, we can pause and show an InfoMessage before exiting
  local _coroutine = coroutine.running()
  if coroutine then
    logger.warn(
      "crengine failed recognizing or parsing this file: unsupported or invalid document"
    )
    UIManager:show(InfoMessage:new({
      text = _(
        "Failed recognizing or parsing this file: unsupported or invalid document.\nKOReader will exit now."
      ),
      dismiss_callback = function()
        coroutine.resume(_coroutine, false)
      end,
    }))
    -- Restore input, so can catch the InfoMessage dismiss and exit
    Device:setIgnoreInput(false)
    Input:inhibitInputUntil(0.2)
    coroutine.yield() -- pause till InfoMessage is dismissed
  end
  -- We have to error and exit the coroutine anyway to avoid any segfault
  error(
    "crengine failed recognizing or parsing this file: unsupported or invalid document"
  )
end

function ReaderUI:onHome()
  local file = self.document.file
  self:onExit(false)
  self:showFileManager(file)
  return true
end

function ReaderUI:onReload()
  self:reloadDocument()
end

function ReaderUI:_loadDocument(file, seamless)
  -- Mimic onShowingReader's refresh optimizations
  self.tearing_down = true
  self.dithered = nil

  UIManager:broadcastEvent(Event:new("CloseReaderMenu"))
  UIManager:broadcastEvent(Event:new("CloseConfigMenu"))
  self.highlight:onExit() -- close highlight dialog if any
  self:onExit(false)

  self:showReader(file, nil, seamless)
end

function ReaderUI:reloadDocument(seamless)
  UIManager:broadcastEvent(Event:new("PreserveCurrentSession")) -- don't reset statistics' start_current_period
  self:_loadDocument(self.document.file, seamless)
end

function ReaderUI:switchDocument(new_file, seamless)
  if not new_file or new_file == self.document.file then
    return
  end
  self:_loadDocument(new_file, seamless)
end

function ReaderUI:onOpenLastDoc()
  self:switchDocument(self.menu:getPreviousFile())
end

function ReaderUI:getCurrentPage()
  return self.paging and self.paging.current_page
    or self.document:getCurrentPage()
end

function ReaderUI:ready()
  return ReaderUI.instance ~= nil
end

return ReaderUI
