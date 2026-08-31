describe("LinkBox", function()
  local LinkBox
  local Geom
  local Blitbuffer
  local Device
  local UIManager

  setup(function()
    require("commonrequire")
    LinkBox = require("ui/widget/linkbox")
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
    Device = require("device")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize LinkBox and set gesture events on touch device", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return true end

    local box = Geom:new({ x = 10, y = 20, w = 100, h = 50 })
    local lb = LinkBox:new({ box = box })

    assert.are.equal(box, lb:getSize())
    assert.truthy(lb.ges_events.TapClose)

    Device.isTouchDevice = orig_is_touch
  end)

  it("should initialize LinkBox without gesture events on non-touch device", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return false end

    local box = Geom:new({ x = 0, y = 0, w = 50, h = 30 })
    local lb = LinkBox:new({ box = box })

    assert.are.equal(box, lb:getSize())
    assert.is_nil(lb.ges_events.TapClose)

    Device.isTouchDevice = orig_is_touch
  end)

  it("should paint border with correct coordinates and style", function()
    local box = Geom:new({ x = 15, y = 25, w = 80, h = 40 })
    local lb = LinkBox:new({
      box = box,
      color = Blitbuffer.COLOR_BLACK,
      radius = 4,
      bordersize = 2,
    })

    local painted = {}
    local mock_bb = {
      paintBorder = function(self, x, y, w, h, bs, c, r)
        table.insert(painted, { x = x, y = y, w = w, h = h, bordersize = bs, color = c, radius = r })
      end,
    }

    lb:paintTo(mock_bb)
    assert.are.equal(1, #painted)
    assert.are.same({
      x = 15,
      y = 25,
      w = 80,
      h = 40,
      bordersize = 2,
      color = Blitbuffer.COLOR_BLACK,
      radius = 4,
    }, painted[1])
  end)

  it("should mark dirty on close", function()
    local box = Geom:new({ x = 10, y = 20, w = 100, h = 50 })
    local lb = LinkBox:new({ box = box })

    local dirty_widget = nil
    local dirty_func = nil
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, func)
      dirty_widget = widget
      dirty_func = func
    end

    lb:onClose()
    assert.is_nil(dirty_widget)
    assert.truthy(dirty_func)
    local mode, region = dirty_func()
    assert.are.equal("partial", mode)
    assert.are.equal(box, region)

    UIManager.setDirty = orig_setDirty
  end)

  it("should mark dirty and schedule timeout on show", function()
    local box = Geom:new({ x = 10, y = 20, w = 100, h = 50 })
    local callback_called = false
    local lb = LinkBox:new({
      box = box,
      timeout = 2.0,
      callback = function()
        callback_called = true
      end,
    })

    local dirty_widget = nil
    local dirty_func = nil
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, func)
      dirty_widget = widget
      dirty_func = func
    end

    local scheduled_time = nil
    local scheduled_func = nil
    local orig_scheduleIn = UIManager.scheduleIn
    UIManager.scheduleIn = function(self, time, func)
      scheduled_time = time
      scheduled_func = func
    end

    local closed_widget = nil
    local orig_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local res = lb:onShow()
    assert.is_true(res)
    assert.are.equal(lb, dirty_widget)
    assert.truthy(dirty_func)
    local mode, region = dirty_func()
    assert.are.equal("ui", mode)
    assert.are.equal(box, region)

    assert.are.equal(2.0, scheduled_time)
    assert.truthy(scheduled_func)
    scheduled_func()
    assert.are.equal(lb, closed_widget)
    assert.is_true(callback_called)

    UIManager.setDirty = orig_setDirty
    UIManager.scheduleIn = orig_scheduleIn
    UIManager.close = orig_close
  end)

  it("should close and cancel callback on tap close", function()
    local box = Geom:new({ x = 10, y = 20, w = 100, h = 50 })
    local callback_called = false
    local lb = LinkBox:new({
      box = box,
      callback = function()
        callback_called = true
      end,
    })

    local closed_widget = nil
    local orig_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local res = lb:onTapClose()
    assert.is_true(res)
    assert.are.equal(lb, closed_widget)
    assert.is_nil(lb.callback)
    assert.is_false(callback_called)

    UIManager.close = orig_close
  end)
end)
