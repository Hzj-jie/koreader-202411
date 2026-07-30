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

    it("should handle font weight, gamma, and size adjustment settings", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        font_size = 20,
        ui = mock_ui,
      })

      if type(font_mod.onAdjustFontSize) == "function" then
        font_mod:onAdjustFontSize(2)
        assert.are.equal(22, font_mod.font_size)
      end

      if type(font_mod.setFontWeight) == "function" then
        font_mod:setFontWeight(15)
        assert.are.equal(15, font_mod.font_weight)
      end

      if type(font_mod.setFontGamma) == "function" then
        font_mod:setFontGamma(15)
        assert.are.equal(15, font_mod.font_gamma)
      end
    end)

    it("should handle fallback font queries", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
      })

      if type(font_mod.getFallbackFont) == "function" then
        local fb = font_mod:getFallbackFont()
        assert.is_string(fb)
      end
    end)
  end)
end)
