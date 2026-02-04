local UIManager = require("ui/uimanager")
local gettext = require("gettext")

return {
  text = gettext("Cloud storage"),
  callback = function()
    local cloud_storage = require("apps/cloudstorage/cloudstorage"):new()
    UIManager:show(cloud_storage)
    function cloud_storage:onExit()
      -- Only refresh the path in file manager.
      local filemanager = require("apps/filemanager/filemanager").instance
      if filemanager ~= nil then
        filemanager:onRefresh()
      end
      UIManager:close(cloud_storage)
    end
  end,
}
