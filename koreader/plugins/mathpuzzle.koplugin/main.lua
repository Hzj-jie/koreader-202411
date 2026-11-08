local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")

local Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")
local MathPuzzleScreen =
  require("plugins/mathpuzzle.koplugin/mathpuzzle_screen")

local MathPuzzle = WidgetContainer:extend({
  name = "mathpuzzle",
  is_doc_only = false,
})

function MathPuzzle:init()
  self.session_correct = 0
  self.session_wrong = 0
  self.session_start_time = nil
  self.ui.menu:registerToMainMenu(self)
end

function MathPuzzle:addToMainMenu(menu_items)
  menu_items.mathpuzzle = {
    text = gettext("Math puzzle"),
    sorting_hint = "games",
    callback = function()
      self:showModeSelection()
    end,
  }
end

function MathPuzzle:showModeSelection(existing_screen)
  local items = {}

  for _, mode in ipairs(Generator.getModes()) do
    table.insert(items, {
      text = mode.title,
      subtext = mode.description,
      callback = function()
        if existing_screen then
          existing_screen:setMode(mode)
        else
          self:showPuzzle(mode)
        end
      end,
    })
  end

  local menu
  menu = Menu:new({
    title = gettext("Math Puzzle - Select Mode"),
    item_table = items,
    is_borderless = true,
    is_popout = false,
    fullscreen = true,
    disable_footer_padding = true,
    close_callback = function()
      UIManager:close(menu)
    end,
  })
  UIManager:show(menu)
  return menu
end

function MathPuzzle:showPuzzle(mode)
  assert(mode, "MathPuzzle:showPuzzle requires a mode")
  if self.screen then
    UIManager:close(self.screen)
  end

  self.session_start_time = os.time()
  self.screen = MathPuzzleScreen:new({
    plugin = self,
    mode = mode,
  })
  UIManager:show(self.screen)
end

return MathPuzzle
