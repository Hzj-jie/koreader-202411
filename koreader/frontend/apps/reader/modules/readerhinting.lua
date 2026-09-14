local EventListener = require("ui/widget/eventlistener")

local DHINTCOUNT = G_defaults:read("DHINTCOUNT")

local ReaderHinting = EventListener:extend({
  hinting_states = nil, -- array
})

function ReaderHinting:init()
  self.hinting_states = {}
end

function ReaderHinting:onHintPage()
  if not self.ui.view.hinting then
    return true
  end
  for i = 1, DHINTCOUNT do
    if self.ui.view.state.page + i <= self.document.info.number_of_pages then
      self.document:hintPage(
        self.ui.view.state.page + i,
        self.zoom:getZoom(self.ui.view.state.page + i),
        self.ui.view.state.rotation,
        self.ui.view.state.gamma
      )
    end
  end
  return true
end

function ReaderHinting:onSetHinting(hinting)
  self.ui.view.hinting = hinting
end

function ReaderHinting:onDisableHinting()
  table.insert(self.hinting_states, self.ui.view.hinting)
  self.ui.view.hinting = false
  return true
end

function ReaderHinting:onRestoreHinting()
  self.ui.view.hinting = table.remove(self.hinting_states)
  return true
end

return ReaderHinting
