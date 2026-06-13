local spy = require("luassert.spy")
local mock = require("luassert.mock")

describe("systemstat", function()
  local SystemStatWidget
  local orig_uimanager_show
  local spy_uimanager_show
  local mock_bookinfomanager
  local orig_getPowerDevice

  setup(function()
    require("commonrequire")

    -- Monkey-patch real Device if needed
    local Device = require("device")
    orig_getPowerDevice = Device.getPowerDevice
    Device.getPowerDevice = function()
      return {
        isCharging = function() return true end,
        isCharged = function() return true end,
        isAuxBatteryConnected = function() return false end,
        isAuxCharging = function() return false end,
        isAuxCharged = function() return false end,
      }
    end

    -- Monkey-patch UIManager.show
    local UIManager = require("ui/uimanager")
    orig_uimanager_show = UIManager.show
    spy_uimanager_show = spy.new(function() end)
    UIManager.show = spy_uimanager_show

    -- Mock BookInfoManager
    mock_bookinfomanager = {
      getBookCount = spy.new(function() return 123 end)
    }
    package.loaded["bookinfomanager"] = mock_bookinfomanager

    -- Load SystemStatWidget using dofile to avoid path resolution issues in tests
    SystemStatWidget = dofile("plugins/systemstat.koplugin/main.lua")
  end)

  teardown(function()
    local Device = require("device")
    Device.getPowerDevice = orig_getPowerDevice
    local UIManager = require("ui/uimanager")
    UIManager.show = orig_uimanager_show
    package.loaded["bookinfomanager"] = nil
  end)

  it("shows indexed files count in statistics", function()
    local menu = {
      registerToMainMenu = spy.new(function() end)
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu
      }
    })

    -- Trigger statistics display
    widget:onShowSysStatistics()

    -- Verify UIManager:show was called with KeyValuePage
    assert.spy(spy_uimanager_show).was.called(1)
    local key_value_page = spy_uimanager_show.calls[1].refs[2]
    assert.is_not_nil(key_value_page)

    -- Verify KeyValuePage title
    assert.equal("System statistics", key_value_page.title)

    -- Verify "Indexed files" is in kv_pairs with value 123
    local found = false
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  Indexed files" then -- Note the leading spaces in gettext
        assert.equal(123, pair[2])
        found = true
        break
      end
    end
    assert.is_true(found, "Indexed files entry not found in system statistics")
  end)
end)
