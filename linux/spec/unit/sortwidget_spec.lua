describe("SortWidget widget", function()
  local SortWidget
  local UIManager
  local BD
  local Geom

  local function showWidget(w)
    w._window = { x = 0, y = 0, widget = w }
    w.window = function(self)
      return self._window
    end
    UIManager:show(w)
    return w
  end

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")
    BD = require("ui/bidi")
    Geom = require("ui/geometry")
    SortWidget = require("ui/widget/sortwidget")
  end)

  after_each(function()
    UIManager._window_stack = {}
  end)

  local function createMockItems(count)
    local items = {}
    for i = 1, count do
      table.insert(items, {
        text = string.format("Item %02d", i),
        index = i,
      })
    end
    return items
  end

  it("should debug tap error", function()
    local items = createMockItems(5)
    local widget = showWidget(SortWidget:new({
      title = "Test Sort",
      item_table = items,
      width = 400,
      height = 600,
    }))

    local item_widget = widget.main_content[2]

    local status, err = xpcall(function()
      item_widget:onTap({}, { pos = Geom:new({ x = 100, y = 100 }) })
    end, debug.traceback)

    if not status then
      print("TAP ERROR STACKTRACE:\n" .. tostring(err))
    end
    assert.is_true(status)
  end)
end)
