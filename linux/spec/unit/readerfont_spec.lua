describe("ReaderFont module", function()
  local ReaderFont, UIManager, Font

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")
    Font = require("ui/font")
    ReaderFont = require("apps/reader/modules/readerfont")
  end)

  local function create_mock_ui()
    return {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      document = {
        fallback_fonts = { "Noto Sans" },
        info = {
          has_crengine = true,
        },
      },
    }
  end

  describe("Initialization & Main Menu", function()
    it(
      "should initialize ReaderFont instance and register to main menu",
      function()
        local mock_ui = create_mock_ui()
        local font_mod = ReaderFont:new({
          font_face = "Noto Serif",
          ui = mock_ui,
        })
        assert.is_table(font_mod)
        assert.spy(mock_ui.menu.registerToMainMenu).was_called()

        local menu_items = {}
        font_mod:addToMainMenu(menu_items)
        assert.is_table(menu_items.change_font)
      end
    )
  end)

  describe("Font Face & Size Operations", function()
    it("should handle font face setting", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "FreeSerif",
        ui = mock_ui,
      })

      assert.are.equal(font_mod.font_face, "FreeSerif")
    end)

    it("should provide font settings submenus", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        font_family_fonts = {},
      })

      if type(font_mod.getFontSettingsTable) == "function" then
        local settings_table = font_mod:getFontSettingsTable()
        assert.is_table(settings_table)
        assert.truthy(#settings_table > 0)
      end
    end)
  end)
end)
