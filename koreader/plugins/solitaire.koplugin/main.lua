local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")

local SolitaireUI = require("plugins/solitaire.koplugin/solitaireui")

local Solitaire = WidgetContainer:extend({
  name = "solitaire",
  is_doc_only = false,
})

function Solitaire:init()
  self.ui.menu:registerToMainMenu(self)
end

function Solitaire:addToMainMenu(menu_items)
  menu_items.solitaire = {
    text = gettext("Solitaire"),
    sorting_hint = "games", -- Changed from "more_tools" to "tools"
    callback = function()
      self:startGame()
    end,
  }
end

function Solitaire:startGame()
  local game_ui = SolitaireUI:new({
    name = "solitaire_game",
  })
  UIManager:show(game_ui)
end

return Solitaire
