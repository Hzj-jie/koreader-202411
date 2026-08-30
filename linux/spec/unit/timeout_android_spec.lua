describe("TimeoutAndroid element", function()
  local TimeoutAndroid, ffi

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ffi = require("ffi")
    pcall(function()
      ffi.cdef([[
        enum {
          AKEEP_SCREEN_ON_DISABLED = 0,
          AKEEP_SCREEN_ON_ENABLED = -1
        };
      ]])
    end)

    package.loaded.android = {
      needsWakelocks = function()
        return false
      end,
      timeout = {
        get = function()
          return 0
        end,
        set = function() end,
      },
      settings = {
        hasPermission = function()
          return true
        end,
        requestPermission = function() end,
      },
    }

    TimeoutAndroid = require("ui/elements/timeout_android")
  end)

  teardown(function()
    package.loaded.android = nil
  end)

  it("should generate Android screen timeout menu structure", function()
    assert.is_table(TimeoutAndroid)
    assert.is_function(TimeoutAndroid.getTimeoutMenuTable)

    local menu = TimeoutAndroid:getTimeoutMenuTable()
    assert.is_table(menu)
    assert.is_string(menu.text)
    assert.is_table(menu.sub_item_table)
    assert.is_true(#menu.sub_item_table >= 8)

    -- Test item callbacks and enabled/checked functions
    for _, item in ipairs(menu.sub_item_table) do
      if type(item) == "table" then
        if item.enabled_func then
          item.enabled_func()
        end
        if item.checked_func then
          item.checked_func()
        end
        if item.callback then
          item.callback()
        end
      end
    end
  end)

  it(
    "should include permission override option when permission missing",
    function()
      package.loaded.android.settings.hasPermission = function()
        return false
      end

      local menu = TimeoutAndroid:getTimeoutMenuTable()
      assert.is_table(menu)
      assert.is_table(menu.sub_item_table)
      assert.are.equal(
        "Allow system settings override",
        menu.sub_item_table[1].text
      )

      menu.sub_item_table[1].callback()
    end
  )
end)
