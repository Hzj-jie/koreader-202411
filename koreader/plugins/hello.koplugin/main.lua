--[[--
This is a debug plugin to test Plugin functionality.

@module koplugin.HelloWorld
--]]
--

-- This is a debug plugin, remove the following if block to enable it
if true then
  return { disabled = true }
end

-- luacheck: ignore 511

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")

local Hello = WidgetContainer:extend({
  name = "hello",
  is_doc_only = false,
})

function Hello:onDispatcherRegisterActions()
  Dispatcher:registerAction("helloworld_action", {
    category = "none",
    event = "HelloWorld",
    title = gettext("Hello World"),
    general = true,
  })
end

function Hello:init()
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)
end

function Hello:addToMainMenu(menu_items)
  menu_items.hello_world = {
    text = gettext("Hello World"),
    -- in which menu this should be appended
    sorting_hint = "tools",
    -- a callback when tapping
    callback = function()
      UIManager:show(InfoMessage:new({
        text = gettext("Hello, plugin world"),
      }))
    end,
  }
end

function Hello:onHelloWorld()
  local popup = InfoMessage:new({
    text = gettext("Hello World"),
  })
  UIManager:show(popup)
end

return Hello
