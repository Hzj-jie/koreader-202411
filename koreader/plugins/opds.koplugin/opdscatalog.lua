local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ConfirmBox = require("ui/widget/confirmbox")
local FrameContainer = require("ui/widget/container/framecontainer")
local OPDSBrowser = require("opdsbrowser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")
local logger = require("logger")
local Screen = require("device").screen
local T = require("ffi/util").template

local OPDSCatalog = WidgetContainer:extend({
  title = gettext("OPDS Catalog"),
})

function OPDSCatalog:init()
  local opds_browser = OPDSBrowser:new({
    title = self.title,
    show_parent = self,
    is_popout = false,
    is_borderless = true,
    close_callback = function()
      return self:onExit()
    end,
    file_downloaded_callback = function(downloaded_file)
      UIManager:show(ConfirmBox:new({
        text = T(
          gettext(
            "File saved to:\n%1\nWould you like to read the downloaded book now?"
          ),
          BD.filepath(downloaded_file)
        ),
        ok_text = gettext("Read now"),
        cancel_text = gettext("Read later"),
        ok_callback = function()
          local Event = require("ui/event")
          UIManager:broadcastEvent(Event:new("SetupShowReader"))

          self:onExit()

          local ReaderUI = require("apps/reader/readerui")
          ReaderUI:showReader(downloaded_file)
        end,
      }))
    end,
  })

  self[1] = FrameContainer:new({
    padding = 0,
    bordersize = 0,
    background = Blitbuffer.COLOR_WHITE,
    opds_browser,
  })
end

function OPDSCatalog:onShow()
  UIManager:setDirty(self, function()
    return "ui", self[1].dimen -- i.e., FrameContainer
  end)
end

function OPDSCatalog:onClose()
  UIManager:setDirty(nil, function()
    return "ui", self[1].dimen
  end)
end

function OPDSCatalog:showCatalog()
  logger.dbg("show OPDS catalog")
  UIManager:show(OPDSCatalog:new({
    dimen = Screen:getSize(),
    covers_fullscreen = true, -- hint for UIManager:_repaint()
  }))
end

function OPDSCatalog:onExit()
  logger.dbg("close OPDS catalog")
  UIManager:close(self)
  return true
end

return OPDSCatalog
