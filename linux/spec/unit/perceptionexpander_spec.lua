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
    "should preserve page_counter progress across createUI(true) since settings never saves it",
    function()
      local settings = createMockSettings({
        is_enabled = true,
        line_thick = 2,
        margin = 0.1,
        line_color_intensity = 0.3,
        shift_each_pages = 100,
      })
      local plugin =
        PerceptionExpander:new({ ui = mock_ui, settings = settings })
      plugin:init()

      plugin.page_counter = 42
      -- createUI(true) reads page_counter from settings without fallback,
      -- wiping in-memory page_counter back to nil (prototype 0).
      plugin:createUI(true)
      assert.are.equal(42, plugin.page_counter)
    end
  )

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
end)
