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

    it("should exercise user styletweaks directory processing", function()
      local DataStorage = require("datastorage")
      local lfs = require("libs/libkoreader-lfs")
      local user_dir = DataStorage:getDataDir() .. "/styletweaks"
      local test_subdir = user_dir .. "/test_group"
      lfs.mkdir(user_dir)
      lfs.mkdir(test_subdir)
      local f1 = io.open(user_dir .. "/custom1.css", "w")
      if f1 then
        f1:write("p { margin: 0; }")
        f1:close()
      end
      local f2 = io.open(test_subdir .. "/custom2.css", "w")
      if f2 then
        f2:write("div { padding: 0; }")
        f2:close()
      end

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

      assert.is_table(tweak.tweaks_by_id["custom1.css"])
      assert.is_table(tweak.tweaks_by_id["custom2.css"])

      -- Toggle user tweaks and get CSS
      tweak:onToggleStyleTweak("custom1.css", tweak.tweaks_by_id["custom1.css"], true)
      tweak:updateCssText(false)
      assert.is_string(tweak:getCssText())

      -- Cleanup
      os.remove(user_dir .. "/custom1.css")
      os.remove(test_subdir .. "/custom2.css")
      lfs.rmdir(test_subdir)
    end)

    it("should exercise editBookTweak and all its interactive callbacks", function()
      local UIManager = require("ui/uimanager")
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

      local mock_menu = {
        closeMenu = function() end,
        updateItems = function() end,
      }

      -- Test editBookTweak when empty
      tweak.book_style_tweak = nil
      tweak.book_style_tweak_enabled = false
      tweak:editBookTweak(mock_menu)

      local editor
      for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w and w.button_table then
          editor = w
          break
        end
      end
      assert.is_not_nil(editor)

      -- Exercise view_pos_callback
      if editor.view_pos_callback then
        editor.view_pos_callback(5, 10)
        local l, c = editor.view_pos_callback()
        assert.are.equal(5, l)
        assert.are.equal(10, c)
      end

      -- Exercise reset_callback
      if editor.reset_callback then
        local reset_text, reset_msg = editor.reset_callback("")
        assert.is_string(reset_msg)
      end

      -- Exercise button table callbacks (Use sample / Prettify / Condense)
      if editor.button_table then
        local tweak_btn = editor.button_table:getButtonById("editBookTweakButton")
        if tweak_btn and tweak_btn.callback then
          tweak_btn.callback()
          tweak_btn.callback()
          tweak_btn.callback()
        end
      end

      -- Exercise edited_callback
      if editor.edited_callback then
        editor:setInputText("")
        editor.edited_callback()
        editor:setInputText("p { color: red; }")
        editor.edited_callback()
      end

      -- Exercise CSS suggestions button
      if editor.button_table then
        local css_btn = editor.button_table:getButtonById("css_suggestions_button_id")
        if css_btn and css_btn.callback then
          css_btn.callback()
          local popup
          for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if w and w.buttons and w ~= editor then
              popup = w
              break
            end
          end
          if popup and popup.buttons then
            for _, row in ipairs(popup.buttons) do
              for _, btn in ipairs(row) do
                if btn.hold_callback then
                  pcall(btn.hold_callback)
                  local sub_info = UIManager._window_stack[#UIManager._window_stack].widget
                  if sub_info and sub_info ~= popup and sub_info ~= editor then
                    UIManager:close(sub_info)
                  end
                end
                if btn.callback then
                  pcall(btn.callback)
                  local sub_pop = UIManager._window_stack[#UIManager._window_stack].widget
                  if sub_pop and sub_pop ~= popup and sub_pop ~= editor then
                    if sub_pop.buttons then
                      for _, s_row in ipairs(sub_pop.buttons) do
                        for _, s_btn in ipairs(s_row) do
                          if s_btn.hold_callback then
                            pcall(s_btn.hold_callback)
                            local s_info = UIManager._window_stack[#UIManager._window_stack].widget
                            if s_info and s_info ~= sub_pop and s_info ~= popup and s_info ~= editor then
                              UIManager:close(s_info)
                            end
                          end
                        end
                      end
                    end
                    UIManager:close(sub_pop)
                  end
                end
              end
            end
            UIManager:close(popup)
          end
        end
      end


      -- Exercise save_callback with creation
      if editor.save_callback then
        local ok, msg = editor.save_callback("body { font-size: 16px; }", false)
        assert.is_true(ok)
        assert.is_true(tweak.book_style_tweak_enabled)

        -- Update existing
        ok, msg = editor.save_callback("body { font-size: 18px; }", false)
        assert.is_true(ok)

        -- Save unmodified
        ok, msg = editor.save_callback("body { font-size: 18px; }", false)
        assert.is_true(ok)

        -- Empty and remove
        ok, msg = editor.save_callback("", false)
        assert.is_true(ok)
        assert.is_false(tweak.book_style_tweak_enabled)
      end

      -- Exercise close_callback
      if editor.close_callback then
        editor.save_callback_called = false
        editor.close_callback(true)
        editor.close_callback(false)
      end

      while #UIManager._window_stack > 0 do
        local top = UIManager._window_stack[#UIManager._window_stack].widget
        if top then
          UIManager:close(top)
        else
          break
        end
      end
    end)

    it("should exercise all menu items and sub-item callbacks", function()
      local UIManager = require("ui/uimanager")
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

      local mock_menu = {
        closeMenu = function() end,
        updateItems = function() end,
      }

      local function walkMenu(items)
        for _, item in ipairs(items) do
          if item.text_func then pcall(item.text_func) end
          if item.checked_func then pcall(item.checked_func) end
          if item.enabled_func then pcall(item.enabled_func) end
          if item.callback then
            pcall(item.callback, mock_menu)
            while #UIManager._window_stack > 0 do
              local top = UIManager._window_stack[#UIManager._window_stack].widget
              if top then
                UIManager:close(top)
              else
                break
              end
            end
          end
          if item.hold_callback then
            pcall(item.hold_callback, mock_menu)
            local info_w = UIManager._window_stack[#UIManager._window_stack]
            if info_w and info_w.widget then
              local w = info_w.widget
              if w.toggle_global_default_callback then
                pcall(w.toggle_global_default_callback)
              end
              if w.toggle_tweak_in_dispatcher_callback then
                pcall(w.toggle_tweak_in_dispatcher_callback)
              end
              UIManager:close(w)
            end
          end
          if item.sub_item_table then
            walkMenu(item.sub_item_table)
          end
        end
      end

      walkMenu(tweak.tweaks_table)
    end)
  end)
end)

