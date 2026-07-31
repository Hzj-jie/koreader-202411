describe("ReaderStyleTweak module", function()
  local ReaderStyleTweak, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize ReaderStyleTweak class", function()
    assert.is_table(ReaderStyleTweak)
  end)

  describe("Settings & Tweak Operations", function()
    it("should handle reading and saving style tweak settings", function()
      local mock_ui = {
        document = {
          info = { has_crengine = true },
          setStyleTweaks = function() end,
        },
        menu = { registerToMainMenu = function() end },
        doc_settings = {
          readTableRef = function() return {} end,
          readTable = function() return {} end,
          read = function() end,
          nilOrTrue = function() return true end,
          save = function() end,
          delete = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({ ui = mock_ui })
      tweak:onReadSettings(mock_ui.doc_settings)
      tweak:onSaveSettings()
    end)

    it("should check tweak active status and rebuild CSS", function()
      local mock_ui = {
        document = {
          info = { has_crengine = true },
          setStyleTweaks = function() end,
        },
        menu = { registerToMainMenu = function() end },
        doc_settings = {
          readTableRef = function() return {} end,
          readTable = function() return {} end,
          read = function() end,
          nilOrTrue = function() return true end,
          save = function() end,
          delete = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({ ui = mock_ui })
      tweak:onReadSettings(mock_ui.doc_settings)

      if type(tweak.makeTweakCss) == "function" then
        tweak:makeTweakCss(false)
      end
    end)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({
        ui = mock_ui,
      })
      local menu_items = {}
      tweak:addToMainMenu(menu_items)
      assert.is_table(menu_items.style_tweaks)
    end)

    it("should register dispatcher actions", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({
        ui = mock_ui,
      })
      if type(tweak.onDispatcherRegisterActions) == "function" then
        tweak:onDispatcherRegisterActions()
      end
    end)
  end)
end)
