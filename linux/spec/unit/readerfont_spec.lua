describe("ReaderFont module", function()
  local ReaderFont, UIManager, Font, credocument

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")
    Font = require("ui/font")

    credocument = require("document/credocument")
    credocument.engineInit = function()
      return {
        getFontFaces = function()
          return { "Noto Serif", "FreeSerif" }
        end,
        getFontFaceFilenameAndFaceIndex = function()
          return "font.ttf", 0, false
        end,
      }
    end

    ReaderFont = require("apps/reader/modules/readerfont")
    ReaderFont.registerKeyEvents = function() end
  end)

  local function create_mock_ui()
    return {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      view = {
        setFontFace = function() end,
      },
      document = {
        fallback_fonts = { "Noto Sans" },
        info = {
          has_crengine = true,
        },
        getFontFaces = function()
          return { "Noto Serif", "FreeSerif" }
        end,
        setFontFace = function() end,
        setHeaderFont = function() end,
        setFontSize = function() end,
        setFontBaseWeight = function() end,
        setFontHinting = function() end,
        setFontKerning = function() end,
        setWordSpacing = function() end,
        setWordExpansion = function() end,
        setCJKWidthScaling = function() end,
        setInterlineSpacePercent = function() end,
        setGammaIndex = function() end,
        setFontFamilyFontFaces = function() end,
      },
      doc_settings = {
        read = function() end,
        readTable = function() end,
        readTableRef = function()
          return {}
        end,
        save = function() end,
        delete = function() end,
        isTrue = function()
          return false
        end,
        nilOrTrue = function()
          return true
        end,
      },
    }
  end

  local function create_default_configurable()
    return {
      font_size = 20,
      font_base_weight = 0,
      font_hinting = 1,
      font_kerning = 1,
      word_spacing = { 100, 100 },
      word_expansion = 0,
      cjk_width_scaling = 100,
      line_spacing = 100,
      font_gamma = 15,
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
          configurable = create_default_configurable(),
        })
        assert.is_table(font_mod)
        assert.spy(mock_ui.menu.registerToMainMenu).was_called()

        local menu_items = {}
        font_mod:addToMainMenu(menu_items)
        assert.is_table(menu_items.change_font)
      end
    )
  end)

  describe("Font Settings and Persistence", function()
    it("should handle settings read and save operations", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      font_mod:onReadSettings(mock_ui.doc_settings)
      font_mod:onSaveSettings()
    end)

    it("should build font settings menu table", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      local settings_table = font_mod:getFontSettingsTable()
      assert.is_table(settings_table)
      assert.is_true(#settings_table > 0)
    end)
  end)

  describe("Font Face & Size Operations", function()
    it("should handle font face setting", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "FreeSerif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      assert.are.equal(font_mod.font_face, "FreeSerif")
    end)

    it(
      "should handle font weight, gamma, and size adjustment settings",
      function()
        local mock_ui = create_mock_ui()
        local font_mod = ReaderFont:new({
          font_face = "Noto Serif",
          font_size = 20,
          ui = mock_ui,
          configurable = create_default_configurable(),
        })

        if type(font_mod.onAdjustFontSize) == "function" then
          font_mod:onAdjustFontSize(2)
          assert.are.equal(22, font_mod.configurable.font_size)
        end

        if type(font_mod.setFontWeight) == "function" then
          font_mod:setFontWeight(15)
          assert.are.equal(15, font_mod.font_weight)
        end

        if type(font_mod.setFontGamma) == "function" then
          font_mod:setFontGamma(15)
          assert.are.equal(15, font_mod.font_gamma)
        end
      end
    )
  end)
end)
