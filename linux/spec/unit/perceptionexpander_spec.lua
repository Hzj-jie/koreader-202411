-- luacheck: ignore 122
describe("PerceptionExpander widget tests", function()
  local Device, PerceptionExpander, Screen
  local orig_getScreenMode
  local mock_ui

  local function createMockSettings(initial_data)
    local data = initial_data or {}
    return {
      data = data,
      read = function(self, key)
        return self.data[key]
      end,
      save = function(self, key, val)
        self.data[key] = val
      end,
      isTrue = function(self, key)
        return self.data[key] == true
      end,
      flush = function() end,
    }
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Device = require("device")
    Screen = Device.screen
    PerceptionExpander = require("plugins/perceptionexpander.koplugin/main")
    orig_getScreenMode = Screen.getScreenMode
  end)

  teardown(function()
    Screen.getScreenMode = orig_getScreenMode
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Screen.getScreenMode = function()
      return "portrait"
    end
    mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
  end)

  it("should not create UI when disabled on init", function()
    local settings = createMockSettings({ is_enabled = false })
    local plugin = PerceptionExpander:new({ ui = mock_ui, settings = settings })
    plugin:init()

    assert.is_nil(plugin.left_line)
    assert.is_nil(plugin.right_line)
  end)

  it("should add perception expander items to main menu", function()
    local settings = createMockSettings({ is_enabled = true })
    local plugin = PerceptionExpander:new({ ui = mock_ui, settings = settings })
    local menu_items = {}
    plugin:addToMainMenu(menu_items)

    local item = menu_items.speed_reading_module_perception_expander
    assert.is_not_nil(item)
    assert.is_table(item.sub_item_table)
    assert.are.equal(3, #item.sub_item_table)
    assert.are.equal("Enable", item.sub_item_table[1].text)
    assert.are.equal("Settings", item.sub_item_table[2].text)
    assert.are.equal("About", item.sub_item_table[3].text)
  end)

  it("should advance page counter on onPageUpdate", function()
    local settings = createMockSettings({
      is_enabled = true,
      line_thick = 2,
      margin = 0.1,
      line_color_intensity = 0.3,
      shift_each_pages = 5,
      page_counter = 0,
    })
    local plugin = PerceptionExpander:new({ ui = mock_ui, settings = settings })
    plugin:init()

    plugin:onPageUpdate(1)
    assert.are.equal(1, plugin.page_counter)
    plugin:onPageUpdate(2)
    assert.are.equal(2, plugin.page_counter)
  end)

  it(
    "should not repeatedly shrink margin on successive createUI calls in landscape mode",
    function()
      local settings = createMockSettings({
        is_enabled = true,
        line_thick = 2,
        margin = 0.1,
        line_color_intensity = 0.3,
        shift_each_pages = 100,
        page_counter = 0,
      })
      local plugin =
        PerceptionExpander:new({ ui = mock_ui, settings = settings })
      plugin:init()

      Screen.getScreenMode = function()
        return "landscape"
      end

      plugin:createUI()
      assert.are.equal(0.1, plugin.margin)
      assert.are.equal(plugin.screen_width * 0.07, plugin.left_line.dimen.x)

      -- Successive calls to createUI() should not shrink plugin.margin
      plugin:createUI()
      plugin:createUI()

      assert.are.equal(0.1, plugin.margin)
      assert.are.equal(plugin.screen_width * 0.07, plugin.left_line.dimen.x)
    end
  )

  it(
    "should not rebuild UI on onPageUpdate when screen mode does not change",
    function()
      local settings = createMockSettings({
        is_enabled = true,
        line_thick = 2,
        margin = 0.1,
        line_color_intensity = 0.3,
        shift_each_pages = 100,
        page_counter = 0,
      })
      local plugin =
        PerceptionExpander:new({ ui = mock_ui, settings = settings })
      plugin:init()

      local createUI_called = 0
      local orig_createUI = plugin.createUI
      plugin.createUI = function(self_p, ...)
        createUI_called = createUI_called + 1
        return orig_createUI(self_p, ...)
      end

      plugin:onPageUpdate(1)
      assert.are.equal(0, createUI_called)
      plugin:onPageUpdate(2)
      assert.are.equal(0, createUI_called)
    end
  )

  it(
    "in landscape mode, line positions after a shift match what createUI draws for the new margin",
    function()
      local settings = createMockSettings({
        is_enabled = true,
        line_thick = 2,
        margin = 0.1,
        line_color_intensity = 0.3,
        shift_each_pages = 2,
        page_counter = 2,
      })
      local plugin =
        PerceptionExpander:new({ ui = mock_ui, settings = settings })
      plugin:init()

      Screen.getScreenMode = function()
        return "landscape"
      end

      plugin:createUI()
      assert.are.equal(0.1, plugin.margin)
      -- Landscape display margin is 0.1 - 0.03 = 0.07
      assert.are.equal(plugin.screen_width * 0.07, plugin.left_line.dimen.x)

      -- Trigger periodic shift via onPageUpdate
      plugin:onPageUpdate(3)
      assert.are.equal(0, plugin.page_counter)
      assert.are.equal(0.13, plugin.margin)
      -- New margin shifted: 0.13 - 0.03 = 0.10
      local expected_x = plugin.screen_width * 0.10
      assert.are.equal(expected_x, plugin.left_line.dimen.x)
      assert.are.equal(
        plugin.screen_width - expected_x,
        plugin.right_line.dimen.x
      )

      -- Verify createUI with the same new margin produces identical line positions
      plugin:createUI()
      assert.are.equal(expected_x, plugin.left_line.dimen.x)
      assert.are.equal(
        plugin.screen_width - expected_x,
        plugin.right_line.dimen.x
      )
    end
  )
end)
