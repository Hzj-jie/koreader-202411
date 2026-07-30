describe("ReaderStyleTweak module", function()
  local ReaderStyleTweak

  setup(function()
    require("commonrequire")
    ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
  end)

  it("should initialize ReaderStyleTweak class", function()
    assert.is_table(ReaderStyleTweak)
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

    it("should manage active style tweaks", function()
      local mock_ui = {
        document = {
          info = {
            has_crengine = true,
          },
        },
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local tweak = ReaderStyleTweak:new({
        ui = mock_ui,
      })

      if type(tweak.isTweakActive) == "function" then
        assert.is_boolean(tweak:isTweakActive("sample_tweak"))
      end
    end)
  end)
end)
