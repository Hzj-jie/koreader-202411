local DataStorage = require("datastorage")
local Device = require("device")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local gettext = require("gettext")
local _ = gettext

local Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")
local MathPuzzleScreen =
  require("plugins/mathpuzzle.koplugin/mathpuzzle_screen")

local MathPuzzle = WidgetContainer:extend({
  name = "mathpuzzle",
  is_doc_only = false,
})

function MathPuzzle:init()
  self.settings_file = DataStorage:getSettingsDir() .. "/mathpuzzle.lua"
  self.settings = LuaSettings:open(self.settings_file)
  self.active_mode = self.settings:read("last_mode") or "add_sub_100"
  self.session_correct = 0
  self.session_wrong = 0
  self.session_start_time = os.time()
  self.ui.menu:registerToMainMenu(self)
end

function MathPuzzle:addToMainMenu(menu_items)
  menu_items.mathpuzzle = {
    text = _("Math puzzle"),
    sorting_hint = "games",
    callback = function()
      self:showModeSelection()
    end,
  }
end

function MathPuzzle:showModeSelection(existing_screen)
  local Screen = Device.screen
  local modes = Generator.getModes()
  local items = {}

  for _, mode in ipairs(modes) do
    table.insert(items, {
      text = mode.title,
      subtext = mode.description,
      callback = function()
        self.active_mode = mode.id
        self.settings:save("last_mode", mode.id)
        self.settings:flush()
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
    title = _("Math Puzzle - Select Mode"),
    item_table = items,
    width = Screen:getWidth(),
    height = Screen:getHeight(),
    is_borderless = true,
    is_popout = false,
    covers_fullscreen = true,
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
  if self.screen then
    UIManager:close(self.screen)
  end

  mode = mode or Generator.getModeById(self.active_mode)
  self.screen = MathPuzzleScreen:new({
    plugin = self,
    mode = mode,
  })
  UIManager:show(self.screen)
end

return MathPuzzle
