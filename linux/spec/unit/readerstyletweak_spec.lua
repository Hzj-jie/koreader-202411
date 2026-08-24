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
          readTableRef = function()
            return {}
          end,
          readTable = function()
            return {}
          end,
          read = function() end,
          nilOrTrue = function()
            return true
          end,
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
          readTableRef = function()
            return {}
          end,
          readTable = function()
            return {}
          end,
          read = function() end,
          nilOrTrue = function()
            return true
          end,
          save = function() end,
          delete = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({ ui = mock_ui })
      tweak:onReadSettings(mock_ui.doc_settings)

      assert.is_false(tweak:isTweakEnabled("dummy_tweak"))
      local enabled_count = tweak:nbTweaksEnabled({})
      assert.are.equal(0, enabled_count)

      local css = tweak:getCssText()
      assert.is_string(css)

      tweak:updateCssText(false)
      tweak:onToggleStyleTweak("test_tweak", {}, true)
    end)

    it(
      "should resolve conflicts correctly when enabling and making default",
      function()
        local mock_ui = {
          document = {
            info = { has_crengine = true },
            setStyleTweaks = function() end,
          },
          menu = { registerToMainMenu = function() end },
          doc_settings = {
            readTableRef = function()
              return {}
            end,
            readTable = function()
              return {}
            end,
            read = function() end,
            nilOrTrue = function()
              return true
            end,
            save = function() end,
            delete = function() end,
          },
        }
        local tweak = ReaderStyleTweak:new({ ui = mock_ui })
        tweak:onReadSettings(mock_ui.doc_settings)

        tweak.doc_tweaks = { tweak_a = true, tweak_b = true }
        tweak.global_tweaks = { tweak_c = true }

        -- Conflict as string
        tweak:resolveConflictsBeforeEnabling("tweak_x", "tweak_a")
        assert.is_nil(tweak.doc_tweaks.tweak_a)
        assert.is_true(tweak.doc_tweaks.tweak_b)

        -- Conflict as table
        tweak:resolveConflictsBeforeEnabling(
          "tweak_y",
          { "tweak_b", "tweak_c" }
        )
        assert.is_nil(tweak.doc_tweaks.tweak_b)
        assert.is_false(tweak.doc_tweaks.tweak_c)

        -- Conflict as function
        tweak.doc_tweaks = { tweak_1 = true, tweak_2 = true }
        tweak:resolveConflictsBeforeEnabling("tweak_z", function(id)
          return id == "tweak_1"
        end)
        assert.is_nil(tweak.doc_tweaks.tweak_1)
        assert.is_true(tweak.doc_tweaks.tweak_2)

        -- Making default conflict resolution
        tweak.global_tweaks = { tweak_m = true, tweak_n = true }
        tweak.doc_tweaks = { tweak_m = true, tweak_n = false }
        tweak:resolveConflictsBeforeMakingDefault("tweak_new", { "tweak_m" })
        assert.is_nil(tweak.global_tweaks.tweak_m)
        assert.is_true(tweak.global_tweaks.tweak_n)
        assert.is_nil(tweak.doc_tweaks.tweak_m)
      end
    )

    it(
      "should handle onToggleStyleTweak with local and global settings",
      function()
        local mock_ui = {
          document = {
            info = { has_crengine = true },
            setStyleTweaks = function() end,
          },
          menu = { registerToMainMenu = function() end },
          doc_settings = {
            readTableRef = function()
              return {}
            end,
            readTable = function()
              return {}
            end,
            read = function() end,
            nilOrTrue = function()
              return true
            end,
            save = function() end,
            delete = function() end,
          },
        }
        local tweak = ReaderStyleTweak:new({ ui = mock_ui })
        tweak:onReadSettings(mock_ui.doc_settings)

        -- Toggle doc tweak on
        tweak:onToggleStyleTweak("tweak_1", nil, true)
        assert.is_true(tweak.doc_tweaks.tweak_1)

        -- Toggle doc tweak off
        tweak:onToggleStyleTweak("tweak_1", nil, true)
        assert.is_nil(tweak.doc_tweaks.tweak_1)

        -- Global default enabled, toggle doc tweak off overrides to false
        tweak.global_tweaks.tweak_1 = true
        tweak:onToggleStyleTweak("tweak_1", nil, true)
        assert.is_false(tweak.doc_tweaks.tweak_1)

        -- Toggling again sets it to true
        tweak:onToggleStyleTweak("tweak_1", nil, true)
        assert.is_true(tweak.doc_tweaks.tweak_1)
      end
    )

    it(
      "should handle TweakInfoWidget interactions via menu hold callback",
      function()
        local mock_ui = {
          document = {
            info = { has_crengine = true },
            setStyleTweaks = function() end,
          },
          menu = { registerToMainMenu = function() end },
          doc_settings = {
            readTableRef = function()
              return {}
            end,
            readTable = function()
              return {}
            end,
            read = function() end,
            nilOrTrue = function()
              return true
            end,
            save = function() end,
            delete = function() end,
          },
        }
        local tweak = ReaderStyleTweak:new({ ui = mock_ui })
        tweak:onReadSettings(mock_ui.doc_settings)

        local shown_widget
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        UIManager.show = function(self, w)
          shown_widget = w
        end

        local function findTweakItem(menu_table)
          for _, item in ipairs(menu_table) do
            if item.tweak_id and item.hold_callback then
              return item
            elseif item.sub_item_table then
              local found = findTweakItem(item.sub_item_table)
              if found then
                return found
              end
            end
          end
        end

        local tweak_item = findTweakItem(tweak.tweaks_table)
        assert.is_not_nil(tweak_item)

        tweak_item.hold_callback({})
        assert.is_not_nil(shown_widget)

        local info_widget = shown_widget
        local Blitbuffer = require("ffi/blitbuffer")
        local bb = Blitbuffer.new(800, 600)
        info_widget:paintTo(bb, 0, 0)
        info_widget:registerKeyEvents()
        info_widget:onClose()

        -- Tap inside CSS box
        local Geom = require("ui/geometry")
        local inside_pos = Geom:new({
          x = info_widget.css_frame.dimen.x + 5,
          y = info_widget.css_frame.dimen.y + 5,
        })
        local handled = info_widget:onTap(nil, { pos = inside_pos })
        assert.is_true(handled)

        -- Tap outside
        local outside_pos = Geom:new({
          x = info_widget.movable.dimen.x - 50,
          y = info_widget.movable.dimen.y - 50,
        })
        local handled_out = info_widget:onTap(nil, { pos = outside_pos })
        assert.is_true(handled_out)

        UIManager.show = orig_show
      end
    )
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items and sub items", function()
      local mock_ui = {
        document = {
          info = { has_crengine = true },
          setStyleTweaks = function() end,
        },
        menu = { registerToMainMenu = function() end },
        doc_settings = {
          readTableRef = function()
            return {}
          end,
          readTable = function()
            return {}
          end,
          read = function() end,
          nilOrTrue = function()
            return true
          end,
          save = function() end,
          delete = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({
        ui = mock_ui,
      })
      tweak:onReadSettings(mock_ui.doc_settings)

      local menu_items = {}
      tweak:addToMainMenu(menu_items)
      assert.is_table(menu_items.style_tweaks)
      assert.is_string(menu_items.style_tweaks.text_func())

      local sub_table = menu_items.style_tweaks.sub_item_table
      assert.is_table(sub_table)
    end)

    it("should register dispatcher actions", function()
      local mock_ui = {
        document = {
          info = { has_crengine = true },
          setStyleTweaks = function() end,
        },
        menu = { registerToMainMenu = function() end },
        doc_settings = {
          readTableRef = function()
            return {}
          end,
          readTable = function()
            return {}
          end,
          read = function() end,
          nilOrTrue = function()
            return true
          end,
          save = function() end,
          delete = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({
        ui = mock_ui,
      })
      tweak:onReadSettings(mock_ui.doc_settings)

      if type(tweak.onDispatcherRegisterActions) == "function" then
        tweak:onDispatcherRegisterActions()
      end
    end)
  end)
end)
