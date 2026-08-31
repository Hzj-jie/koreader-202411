describe("WidgetContainer widget", function()
  local WidgetContainer, Geom, Widget, Event

  setup(function()
    require("commonrequire")
    WidgetContainer = require("ui/widget/container/widgetcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
    Event = require("ui/event")
  end)

  local function createMockBB()
    local painted = {}
    return setmetatable({
      painted = painted,
    }, {
      __index = function()
        return function() end
      end,
    })
  end

  describe("size calculation and dimensions", function()
    it("should return fixed dimen if present", function()
      local container = WidgetContainer:new({
        dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      })
      local size = container:getSize()
      assert.are.equal(100, size.w)
      assert.are.equal(50, size.h)
    end)

    it("should return child widget size if dimen not set", function()
      local inner_widget = Widget:new({ dimen = Geom:new({ w = 40, h = 30 }) })
      local container = WidgetContainer:new({
        inner_widget,
      })
      local size = container:getSize()
      assert.are.equal(40, size.w)
      assert.are.equal(30, size.h)
    end)

    it("should handle empty container without children", function()
      local container = WidgetContainer:new({})
      local size = container:getSize()
      assert.truthy(size)
    end)
  end)

  describe("clear and free", function()
    it("should free and clear all children", function()
      local free_called = false
      local child = Widget:new({
        free = function(self)
          free_called = true
        end,
      })

      local container = WidgetContainer:new({ child })
      assert.are.equal(1, #container)

      container:clear(false)
      assert.is_true(free_called)
      assert.are.equal(0, #container)
    end)

    it("should support clear with skip_free", function()
      local free_called = false
      local child = Widget:new({
        free = function(self)
          free_called = true
        end,
      })

      local container = WidgetContainer:new({ child })
      container:clear(true)
      assert.is_false(free_called)
      assert.are.equal(0, #container)
    end)

    it("should call free(full) on all children", function()
      local full_freed = nil
      local child = Widget:new({
        free = function(self, full)
          full_freed = full
        end,
      })

      local container = WidgetContainer:new({ child })
      container:free(true)
      assert.is_true(full_freed)
    end)
  end)

  describe("dirtyRegion", function()
    it("should return own dirty_dimen if set", function()
      local container = WidgetContainer:new({
        dirty_dimen = Geom:new({ x = 5, y = 5, w = 20, h = 20 }),
      })
      assert.are.equal(20, container:dirtyRegion().w)
    end)

    it("should delegate dirtyRegion to first child", function()
      local child = Widget:new({
        dirty_dimen = Geom:new({ x = 10, y = 10, w = 30, h = 30 }),
      })
      local container = WidgetContainer:new({ child })
      assert.are.equal(30, container:dirtyRegion().w)
    end)
  end)

  describe("paintTo alignments", function()
    it("should skip paint if no children or skip_paint set", function()
      local container = WidgetContainer:new({})
      local bb = createMockBB()
      container:paintTo(bb, 0, 0)

      local container_skip = WidgetContainer:new({
        skip_paint = true,
        Widget:new({ dimen = Geom:new({ w = 10, h = 10 }) }),
      })
      container_skip:paintTo(bb, 0, 0)
    end)

    it("should paint children with top, bottom, center, and vertical_align alignments", function()
      local last_painted_x, last_painted_y
      local child = Widget:new({
        dimen = Geom:new({ w = 20, h = 20 }),
        paintTo = function(self, bb, x, y)
          last_painted_x = x
          last_painted_y = y
        end,
      })

      -- align = "top"
      local container_top = WidgetContainer:new({
        dimen = Geom:new({ w = 100, h = 100 }),
        align = "top",
        child,
      })
      container_top:paintTo(createMockBB(), 0, 0)
      assert.are.equal(40, last_painted_x)
      assert.are.equal(0, last_painted_y)

      -- align = "bottom"
      local container_bottom = WidgetContainer:new({
        dimen = Geom:new({ w = 100, h = 100 }),
        align = "bottom",
        child,
      })
      container_bottom:paintTo(createMockBB(), 0, 0)
      assert.are.equal(40, last_painted_x)
      assert.are.equal(80, last_painted_y)

      -- align = "center"
      local container_center = WidgetContainer:new({
        dimen = Geom:new({ w = 100, h = 100 }),
        align = "center",
        child,
      })
      container_center:paintTo(createMockBB(), 0, 0)
      assert.are.equal(40, last_painted_x)
      assert.are.equal(40, last_painted_y)

      -- vertical_align = "center"
      local container_valign = WidgetContainer:new({
        dimen = Geom:new({ w = 100, h = 100 }),
        vertical_align = "center",
        child,
      })
      container_valign:paintTo(createMockBB(), 10, 10)
      assert.are.equal(10, last_painted_x)
      assert.are.equal(50, last_painted_y)

      -- default align
      local container_default = WidgetContainer:new({
        child,
      })
      container_default:paintTo(createMockBB(), 5, 5)
      assert.are.equal(5, last_painted_x)
      assert.are.equal(5, last_painted_y)
    end)
  end)

  describe("event handling and broadcasting", function()
    it("should propagate events to children until one consumes it", function()
      local child1_handled = false
      local child2_handled = false

      local child1 = Widget:new({
        handleEvent = function(self, ev)
          child1_handled = true
          return true
        end,
      })
      local child2 = Widget:new({
        handleEvent = function(self, ev)
          child2_handled = true
          return false
        end,
      })

      local container = WidgetContainer:new({ child1, child2 })
      local ev = Event:new("TestEvent")
      local handled = container:handleEvent(ev)

      assert.is_true(handled)
      assert.is_true(child1_handled)
      assert.is_false(child2_handled)
    end)

    it("should broadcast events to all children", function()
      local count = 0
      local child1 = Widget:new({
        broadcastEvent = function(self, ev)
          count = count + 1
        end,
      })
      local child2 = Widget:new({
        broadcastEvent = function(self, ev)
          count = count + 1
        end,
      })

      local container = WidgetContainer:new({ child1, child2 })
      container:broadcastEvent(Event:new("BroadcastTest"))

      assert.are.equal(2, count)
    end)
  end)
end)

