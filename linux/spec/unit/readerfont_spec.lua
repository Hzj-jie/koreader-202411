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
        getGammaLevel = function()
          return 15
        end,
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
      font_mod:onSetFont("Noto Serif")
      assert.are.equal("Noto Serif", font_mod.font_face)
    end)

    it("should handle font size changes and gestures", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      font_mod:onSetFontSize(24)
      assert.are.equal(24, font_mod.configurable.font_size)

      font_mod:onChangeSize(2)
      assert.are.equal(26, font_mod.configurable.font_size)

      font_mod:onChangeSize(-4)
      assert.are.equal(22, font_mod.configurable.font_size)

      font_mod:onIncreaseFontSize({ distance = 10 })
      assert.is_true(font_mod.configurable.font_size >= 22)

      font_mod:onDecreaseFontSize({ distance = 10 })
      assert.is_true(font_mod.configurable.font_size <= 26)
    end)

    it("should handle typographical and rendering settings", function()
      Font.getGammaIndex = function(_, g)
        return g or 15
      end
      Font.getGammaLevel = function(_, g)
        return g or 15
      end
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      font_mod:onSetLineSpace(120)
      assert.are.equal(120, font_mod.configurable.line_spacing)

      font_mod:onSetFontBaseWeight(2)
      assert.are.equal(2, font_mod.configurable.font_base_weight)

      font_mod:onSetFontHinting(2)
      assert.are.equal(2, font_mod.configurable.font_hinting)

      font_mod:onSetFontKerning(2)
      assert.are.equal(2, font_mod.configurable.font_kerning)

      font_mod:onSetWordSpacing({ 110, 110 })
      assert.are.same({ 110, 110 }, font_mod.configurable.word_spacing)

      font_mod:onSetWordExpansion(1)
      assert.are.equal(1, font_mod.configurable.word_expansion)

      font_mod:onSetCJKWidthScaling(95)
      assert.are.equal(95, font_mod.configurable.cjk_width_scaling)

      font_mod:onSetFontGamma(20)
      assert.are.equal(20, font_mod.configurable.font_gamma)
    end)

    it("should handle recent fonts and face sorting", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        fonts_recently_selected = { "Noto Serif" },
        font_family_fonts = {},
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      font_mod:addToRecentlySelectedList("Noto Serif")
      local sorted =
        font_mod:sortFaceList({ "FreeSerif", "Noto Serif", "Helvetica" })
      assert.is_table(sorted)
      assert.is_true(#sorted >= 2)

      font_mod:updateFontFamilyFonts()
      local fam_table = font_mod:getFontFamiliesTable()
      assert.is_table(fam_table)
    end)

    it("should handle makeDefault MultiConfirmBox callbacks", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      local shown_box
      font_mod.showWidget = function(self, w)
        shown_box = w
      end

      local menu_updated = false
      local mock_menu = {
        updateItems = function()
          menu_updated = true
        end,
      }

      -- Regular font
      font_mod:makeDefault("Noto Serif", false, mock_menu)
      assert.is_not_nil(shown_box)
      shown_box.choice1_callback()
      assert.are.equal("Noto Serif", G_reader_settings:read("cre_font"))
      assert.is_true(menu_updated)

      menu_updated = false
      mock_ui.document.setupFallbackFontFaces = function() end
      shown_box.choice2_callback()
      assert.are.equal("Noto Serif", G_reader_settings:read("fallback_font"))
      assert.is_true(menu_updated)

      -- Monospace font
      menu_updated = false
      font_mod:makeDefault("Courier", true, mock_menu)
      assert.is_not_nil(shown_box)
      shown_box.choice2_callback()
      assert.are.equal("Courier", G_reader_settings:read("monospace_font"))
      assert.is_true(menu_updated)
    end)

    it("should handle gesToFontSize with various directions", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      -- Number passthrough
      assert.are.equal(20, font_mod:gesToFontSize(20))

      -- Horizontal gesture
      local h_step = font_mod:gesToFontSize({
        direction = "horizontal",
        distance = 100,
      })
      assert.is_number(h_step)

      -- Vertical gesture
      local v_step = font_mod:gesToFontSize({
        direction = "vertical",
        distance = 100,
      })
      assert.is_number(v_step)

      -- Diagonal gesture
      local d_step = font_mod:gesToFontSize({
        direction = "diagonal",
        distance = 100,
      })
      assert.is_number(d_step)
    end)

    it("should exercise face menu items and font settings table", function()
      local mock_ui = create_mock_ui()
      local font_mod = ReaderFont:new({
        font_face = "Noto Serif",
        ui = mock_ui,
        configurable = create_default_configurable(),
      })

      font_mod:setupFaceMenuTable()
      assert.is_table(font_mod.face_table)

      -- Check face_table refresh_func
      local refreshed = font_mod.face_table.refresh_func()
      assert.is_table(refreshed)
      assert.are.equal(
        "Noto Serif",
        font_mod.face_table.open_on_menu_item_id_func()
      )

      -- Exercise font settings items
      local settings = font_mod:getFontSettingsTable()
      for _, item in ipairs(settings) do
        if item.checked_func then
          pcall(item.checked_func)
        end
        if item.enabled_func then
          pcall(item.enabled_func)
        end
        if item.text_func then
          pcall(item.text_func)
        end
      end

      -- Exercise font family menu items
      local families = font_mod:getFontFamiliesTable()
      for _, item in ipairs(families) do
        if item.checked_func then
          pcall(item.checked_func)
        end
        if item.text_func then
          pcall(item.text_func)
        end
      end
    end)
  end)
end)
