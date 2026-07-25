local ReaderFont

describe("ReaderFont module", function()
  setup(function()
    require("commonrequire")
    ReaderFont = require("apps/reader/modules/readerfont")
  end)

  it(
    "should initialize ReaderFont instance and register to main menu",
    function()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })
      assert.is_table(font_mod)

      local menu_items = {}
      font_mod:addToMainMenu(menu_items)
      assert.is_table(menu_items.change_font)
    end
  )
end)
