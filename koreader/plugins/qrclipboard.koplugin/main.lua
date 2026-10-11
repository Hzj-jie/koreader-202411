--[[--
This plugin generates a QR code from clipboard content.

@module koplugin.QRClipboard
--]]
--

local Device = require("device")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")

local QRClipboard = WidgetContainer:extend({
  name = "qrclipboard",
  is_doc_only = false,
})

function QRClipboard:init()
  self.ui.menu:registerToMainMenu(self)
end

function QRClipboard:addToMainMenu(menu_items)
  menu_items.qrclipboard = {
    text = gettext("QR from clipboard"),
    callback = function()
      local text = Device.input:getClipboardText()
      if text and text ~= "" then
        UIManager:show(QRMessage:new({
          text = text,
          width = Device.screen:getWidth(),
          height = Device.screen:getHeight(),
        }))
      end
    end,
  }
end

return QRClipboard
