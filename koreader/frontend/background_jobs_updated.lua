--[[--
Raises an event to avoid depending on BackgroundRunner plugin directly.
--]]

function backgroundJobsUpdated()
  local Event = require("ui/event")
  local UIManager = require("ui/uimanager")
  UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
end

return backgroundJobsUpdated
