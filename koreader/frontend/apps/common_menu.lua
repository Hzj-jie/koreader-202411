local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local UIManager = require("ui/uimanager")

local CommonMenu = {}

--- This is a helper function for apps to exit or restart koreader.
function CommonMenu:exitOrRestart(before_exit, ui, after_exit, force)
  assert(before_exit)
  assert(ui)
  -- Only restart sets a callback, which suits us just fine for this check ;)
  if after_exit and not force and not Device:isStartupScriptUpToDate() then
    UIManager:show(ConfirmBox:new({
      text = _(
        "KOReader's startup script has been updated. You'll need to completely exit KOReader to finalize the update."
      ),
      ok_text = _("Restart anyway"),
      ok_callback = function()
        self:exitOrRestart(before_exit, ui, after_exit, true)
      end,
    }))
    return
  end

  before_exit()
  UIManager:nextTick(function()
    UIManager:flushSettings()
    ui:onExit()
    if after_exit then
      after_exit()
    end
  end)
end

return CommonMenu
