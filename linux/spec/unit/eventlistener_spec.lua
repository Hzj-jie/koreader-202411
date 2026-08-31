describe("EventListener class", function()
  local EventListener, Event

  setup(function()
    require("commonrequire")
    EventListener = require("ui/widget/eventlistener")
    Event = require("ui/event")
  end)

  it("should route event to string handler function and unpack args", function()
    local received_arg1, received_arg2 = nil, nil
    local el = EventListener:new({
      onMyCustomEvent = function(self, arg1, arg2)
        received_arg1 = arg1
        received_arg2 = arg2
        return true
      end,
    })

    local ev = Event:new("MyCustomEvent", "hello", "world")
    local res = el:handleEvent(ev)

    assert.is_true(res)
    assert.is.same("hello", received_arg1)
    assert.is.same("world", received_arg2)
  end)

  it("should route event to table of handler functions", function()
    local call_count = 0
    local el = EventListener:new({
      onMyCustomEvent = {
        function(self, _event)
          call_count = call_count + 1
          return false
        end,
        function(self, _event)
          call_count = call_count + 1
          return true
        end,
      },
    })

    local ev = Event:new("MyCustomEvent")
    local res = el:handleEvent(ev)

    assert.is_true(res)
    assert.is.same(2, call_count)
  end)

  it("should return false if no handler is registered", function()
    local el = EventListener:new({})
    local ev = Event:new("MyCustomEvent")
    local res = el:handleEvent(ev)

    assert.is_false(res)
  end)

  it(
    "should return true for programmatic event even if handler returns false",
    function()
      local el = EventListener:new({
        onMyCustomEvent = function(self, _event)
          return false
        end,
      })

      local ev = Event:new("MyCustomEvent") -- programmatic event by default
      assert.is_false(ev:isUserInput())

      local res = el:handleEvent(ev)
      assert.is_true(res) -- Overridden to true by EventListener on master!
    end
  )

  it("should respect handler return status for user input event", function()
    local el = EventListener:new({
      onMyCustomEvent = function(self, _event)
        return false
      end,
    })

    local ev = Event:new("MyCustomEvent"):asUserInput()
    assert.is_true(ev:isUserInput())

    local res = el:handleEvent(ev)
    assert.is_false(res) -- Preserves false for user input!
  end)

  it("should call init during instantiation if present", function()
    local initialized = false
    local el = EventListener:new({
      init = function(self)
        initialized = true
      end,
    })
    assert.truthy(el)
    assert.is_true(initialized)
  end)

  it("should check isAlwaysOnTop and isShownModal", function()
    local UIManager = require("ui/uimanager")
    local el_nonmodal = EventListener:new({ modal = false })
    assert.is_false(el_nonmodal:isAlwaysOnTop())
    assert.is_false(el_nonmodal:isShownModal())

    local el_modal = EventListener:new({ modal = true })
    assert.is_true(el_modal:isAlwaysOnTop())

    -- Test when not in window stack vs in window stack
    assert.is_false(el_modal:isShownModal())

    local orig_isWindowWidget = UIManager.isWindowWidget
    UIManager.isWindowWidget = function(_, w)
      return w == el_modal
    end

    assert.is_true(el_modal:isShownModal())

    -- Modal absorbing unhandled user input
    local ev = Event:new("UnhandledEvent"):asUserInput()
    assert.is_true(el_modal:handleEvent(ev))
    assert.is_false(el_nonmodal:handleEvent(ev))

    UIManager.isWindowWidget = orig_isWindowWidget
  end)

  it("should handle broadcastEvent and table handlers with all returning false", function()
    local handled_count = 0
    local el = EventListener:new({
      onTableEvent = {
        function()
          handled_count = handled_count + 1
          return false
        end,
        function()
          handled_count = handled_count + 1
          return false
        end,
      },
    })

    local ev_user = Event:new("TableEvent"):asUserInput()
    assert.is_false(el:handleEvent(ev_user))
    assert.are.equal(2, handled_count)

    -- broadcastEvent delegates to handleEvent
    el:broadcastEvent(Event:new("TableEvent"))
    assert.are.equal(4, handled_count)
  end)
end)
