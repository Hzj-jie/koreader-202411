local spy = require("luassert.spy")

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
        isCharging = function()
          return true
        end,
        isCharged = function()
          return true
        end,
        isAuxBatteryConnected = function()
          return false
        end,
        isAuxCharging = function()
          return false
        end,
        isAuxCharged = function()
          return false
        end,
      }
    end

    -- Monkey-patch UIManager.show
    local UIManager = require("ui/uimanager")
    orig_uimanager_show = UIManager.show
    spy_uimanager_show = spy.new(function() end)
    UIManager.show = spy_uimanager_show

    -- Mock BookInfoManager
    mock_bookinfomanager = {
      getBookCount = spy.new(function()
        return 123
      end),
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
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
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

  it("shows 0 for background processes when none are running", function()
    local ffiUtil = require("ffi/util")
    local gettext = require("gettext")
    ffiUtil.subprocesses = {}

    local menu = {
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
    })
    widget:onShowSysStatistics()

    local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    local bg_entry = nil
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  " .. gettext("Background processes") then
        bg_entry = pair
        break
      end
    end
    assert.is_not_nil(bg_entry)
    assert.are.equal(0, bg_entry[2])
    assert.is_nil(bg_entry.callback)
  end)

  it("shows count and tap to view for background processes when running", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local ffiUtil = require("ffi/util")
    local gettext = require("gettext")
    local T = ffiUtil.template

    local start = os.time() - 5
    ffiUtil.subprocesses = {
      [101] = {
        pid = 101,
        cmd = "test_script.lua:10",
        start_time = start,
        output = "hello world",
      },
      [102] = {
        pid = 102,
        cmd = "empty_script.lua:20",
        start_time = start,
        output = "",
      },
    }

    local menu = {
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
    })
    widget:onShowSysStatistics()

    local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    local bg_entry = nil
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  " .. gettext("Background processes") then
        bg_entry = pair
        break
      end
    end
    assert.is_not_nil(bg_entry)
    assert.are.equal(T(gettext("%1 (tap to view)"), 2), bg_entry[2])
    assert.is_function(bg_entry.callback)

    -- Tap the background processes entry
    bg_entry.callback()
    local proc_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.is_not_nil(proc_page)
    assert.are.equal(gettext("Background processes"), proc_page.title)
    assert.are.equal(2, #proc_page.kv_pairs)

    -- First entry: pid 101 (sorted by pid)
    local p1 = proc_page.kv_pairs[1]
    assert.are.equal("[101] test_script.lua:10", p1[1])
    assert.is_truthy(p1[2]:match("^%d+:%d%d:%d%d$"))
    assert.is_function(p1.callback)

    -- Tap p1 (has output)
    p1.callback()
    local viewer1 = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.are.equal("[101] test_script.lua:10", viewer1.title)
    assert.are.equal("hello world", viewer1.text)
    assert.are.equal(Blitbuffer.COLOR_BLACK, viewer1.fgcolor)
    assert.are.equal("code", viewer1.text_type)

    -- Second entry: pid 102 (empty output)
    local p2 = proc_page.kv_pairs[2]
    assert.are.equal("[102] empty_script.lua:20", p2[1])
    assert.is_function(p2.callback)

    -- Tap p2 (empty output -> shows gettext("No output.") in COLOR_DARK_GRAY)
    p2.callback()
    local viewer2 = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.are.equal("[102] empty_script.lua:20", viewer2.title)
    assert.are.equal(gettext("No output."), viewer2.text)
    assert.are.equal(Blitbuffer.COLOR_DARK_GRAY, viewer2.fgcolor)
    assert.are.equal("code", viewer2.text_type)

    ffiUtil.subprocesses = {}
  end)
end)
