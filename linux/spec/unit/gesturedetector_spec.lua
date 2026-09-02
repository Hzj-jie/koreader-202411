describe("gesturedetector module", function()
  local GestureDetector
  local mock_screen = {
    scaleByDPI = function(self, v)
      return v
    end,
    getWidth = function(self)
      return 600
    end,
    getHeight = function(self)
      return 800
    end,
    getTouchRotation = function(self)
      return 0
    end,
    DEVICE_ROTATED_UPRIGHT = 0,
  }
  local mock_input = {
    main_finger_slot = 0,
    clearTimeout = function() end,
    setTimeout = function() end,
  }

  setup(function()
    require("commonrequire")
    GestureDetector = require("device/gesturedetector")
  end)

  describe("adjustGesCoordinate", function()
    local function adjustTest(ges_type, direction, rotation_mode)
      local ges = {
        ges = ges_type,
        direction = direction,
        multiswipe_directions = direction,
      }
      GestureDetector.screen = {
        DEVICE_ROTATED_UPRIGHT = 0,
        DEVICE_ROTATED_CLOCKWISE = 1,
        DEVICE_ROTATED_UPSIDE_DOWN = 2,
        DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
      }
      GestureDetector.screen.getTouchRotation = function()
        return rotation_mode
      end

      return GestureDetector:adjustGesCoordinate(ges).direction
    end

    it("should not translate rotation 0", function()
      assert.are.equal("north", adjustTest("swipe", "north", 0))
      assert.are.equal("north", adjustTest("multiswipe", "north", 0))
      assert.are.equal("north", adjustTest("pan", "north", 0))
      assert.are.equal("north", adjustTest("two_finger_swipe", "north", 0))
      assert.are.equal("north", adjustTest("two_finger_pan", "north", 0))
    end)
    it("should translate rotation 270", function()
      assert.are.equal("west", adjustTest("swipe", "north", 3))
      assert.are.equal("west", adjustTest("multiswipe", "north", 3))
      assert.are.equal("west", adjustTest("pan", "north", 3))
      assert.are.equal("west", adjustTest("two_finger_swipe", "north", 3))
      assert.are.equal("west", adjustTest("two_finger_pan", "north", 3))
    end)
    it("should translate rotation 180", function()
      assert.are.equal("south", adjustTest("swipe", "north", 2))
      assert.are.equal("south", adjustTest("multiswipe", "north", 2))
      assert.are.equal("south", adjustTest("pan", "north", 2))
      assert.are.equal("south", adjustTest("two_finger_swipe", "north", 2))
      assert.are.equal("south", adjustTest("two_finger_pan", "north", 2))
    end)
    it("should translate rotation 90", function()
      assert.are.equal("east", adjustTest("swipe", "north", 1))
      assert.are.equal("east", adjustTest("multiswipe", "north", 1))
      assert.are.equal("east", adjustTest("pan", "north", 1))
      assert.are.equal("east", adjustTest("two_finger_swipe", "north", 1))
      assert.are.equal("east", adjustTest("two_finger_pan", "north", 1))
    end)
  end)

  it(
    "should handle isTwoFingerTap safely when buddy contact has nil initial_tev",
    function()
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = mock_input,
        active_contacts = {},
        contact_count = 0,
      })

      -- Create slot 0 contact and immediately bind its current touch event
      local contactA = gd:newContact(0)
      contactA.down = true
      contactA.current_tev = { timev = 1000, x = 10, y = 20, id = 1 }

      -- Create slot 1 contact (it will automatically link contactA as buddy and copy its initial_tev)
      local contactB = gd:newContact(1)
      contactB.down = true
      contactB.current_tev = { timev = 1001, x = 15, y = 25, id = 2 }
      contactB.initial_tev = nil -- Explicitly nil the buddy's initial_tev to simulate the platform bug

      -- Call isTwoFingerTap on contactA passing the buddy contactB
      local is_tap = contactA:isTwoFingerTap(contactB)

      -- Verify it returns false gracefully instead of raising a nil dereference crash
      assert.is_false(is_tap)
    end
  )

  it(
    "should automatically heal a contact missing initial_tev during feedEvent",
    function()
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = mock_input,
        active_contacts = {},
        contact_count = 0,
      })

      -- Prepare a single mock event frame to feed to this slot
      local mock_event = { slot = 0, timev = 1005, x = 20, y = 30, id = 3 }

      -- Create a contact that bypasses standard initialState down events (so initial_tev is nil)
      local contact = gd:newContact(0)
      contact.down = true
      contact.initial_tev = nil -- Explicitly nil out initial_tev
      contact.current_tev = mock_event -- Pre-bind current_tev to simulate real runtime environment

      contact.state = function(self)
        -- Simple dummy state function that just checks initial_tev (will crash if nil!)
        assert.is_table(self.initial_tev)
        assert.are.equal(self.initial_tev.x, self.current_tev.x)
        return "dummy_gesture"
      end

      -- Feed the event!
      local gestures = gd:feedEvent({ mock_event })

      -- Verify it was successfully parsed, the healing block was hit, and state didn't crash!
      assert.are.equal(#gestures, 1)
      assert.are.equal(gestures[1], "dummy_gesture")
      assert.is_table(contact.initial_tev)
      assert.are.equal(contact.initial_tev.x, 20)
    end
  )

  it(
    "should treat swiping to the edge of screen as end of touch (lift)",
    function()
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = mock_input,
        active_contacts = {},
        contact_count = 0,
      })

      -- Use a single event table and mutate it, simulating Input.ev_slots
      local ev = { slot = 0, timev = 1000, x = 100, y = 100, id = 1 }

      -- 1. Initial touch down (starts tapState, returns touch)
      local gestures = gd:feedEvent({ ev })
      assert.are.equal(1, #gestures)
      assert.are.equal("touch", gestures[1].ges)

      -- 2. Move to trigger panState (diff is 100, PAN_THRESHOLD is 35)
      ev.timev = 1010
      ev.x = 200
      gestures = gd:feedEvent({ ev })
      assert.are.equal(1, #gestures)
      assert.are.equal("pan", gestures[1].ges)

      -- 3. Move near the edge (x = 597, width - 3) - should NOT trigger lift
      ev.timev = 1020
      ev.x = 597
      gestures = gd:feedEvent({ ev })
      assert.are.equal(1, #gestures)
      assert.are.equal("pan", gestures[1].ges)

      -- 4. Move to the edge threshold (x = 598, width - 2) - should trigger lift
      ev.timev = 1030
      ev.x = 598
      gestures = gd:feedEvent({ ev })
      assert.are.equal(1, #gestures)
      assert.are.equal("swipe", gestures[1].ges)
      assert.are.equal("east", gestures[1].direction)

      -- Contact should have been dropped
      assert.is_nil(gd:getContact(0))
    end
  )

  it("should drop all contacts cleanly via dropContacts", function()
    local gd = GestureDetector:new({
      screen = mock_screen,
      input = mock_input,
      active_contacts = {},
      contact_count = 0,
    })

    local c0 = gd:newContact(0)
    c0.current_tev = { slot = 0, timev = 1000, x = 10, y = 10, id = 1 }
    local c1 = gd:newContact(1)
    c1.current_tev = { slot = 1, timev = 1001, x = 20, y = 20, id = 2 }
    assert.are.equal(2, gd.contact_count)

    gd:dropContacts()
    assert.are.equal(0, gd.contact_count)
    assert.is_nil(gd:getContact(0))
    assert.is_nil(gd:getContact(1))
  end)

  it("should map directions correctly in DIRECTION_TABLE", function()
    assert.are.equal("horizontal", GestureDetector.DIRECTION_TABLE.east)
    assert.are.equal("horizontal", GestureDetector.DIRECTION_TABLE.west)
    assert.are.equal("vertical", GestureDetector.DIRECTION_TABLE.north)
    assert.are.equal("vertical", GestureDetector.DIRECTION_TABLE.south)
    assert.are.equal("diagonal", GestureDetector.DIRECTION_TABLE.northeast)
    assert.are.equal("diagonal", GestureDetector.DIRECTION_TABLE.southwest)
  end)

  it("should calculate rotate angles and path directions correctly", function()
    local p_orig = { x = 0, y = 0 }
    local p_start = { x = 10, y = 0 }
    local p_end = { x = 0, y = 10 }
    local angle = GestureDetector:getRotate(p_orig, p_start, p_end)
    assert.are.equal(90, math.floor(angle + 0.5))

    local gd = GestureDetector:new({
      screen = mock_screen,
      input = mock_input,
      active_contacts = {},
      contact_count = 0,
    })
    local contact = gd:newContact(0)
    contact.initial_tev = { x = 100, y = 100 }
    contact.current_tev = { x = 100, y = 200 }
    local dir, dist = contact:getPath(true, false)
    assert.are.equal("south", dir)
    assert.are.equal(100, dist)
  end)

  describe("Tap, Double Tap & Bounce Detection", function()
    local timeouts
    local createGD = function(disable_double_tap, tap_interval_override)
      timeouts = {}
      local input = {
        main_finger_slot = 0,
        disable_double_tap = disable_double_tap,
        tap_interval_override = tap_interval_override,
        setTimeout = function(self, slot, gesture, callback, timev, delay)
          table.insert(timeouts, {
            slot = slot,
            gesture = gesture,
            cb = callback,
            timev = timev,
            delay = delay,
          })
        end,
        clearTimeout = function(self, slot, gesture)
          for i = #timeouts, 1, -1 do
            if
              timeouts[i].slot == slot
              and (not gesture or timeouts[i].gesture == gesture)
            then
              table.remove(timeouts, i)
            end
          end
        end,
      }
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = input,
        active_contacts = {},
        contact_count = 0,
        previous_tap = {},
      })
      gd:init()
      return gd, input
    end

    it(
      "emits single tap immediately when disable_double_tap is true",
      function()
        local gd = createGD(true)
        local gestures = gd:feedEvent({
          { slot = 0, id = 1, x = 100, y = 100, timev = 1000 },
        })
        assert.is_equal(1, #gestures)
        assert.is_equal("touch", gestures[1].ges)

        gestures = gd:feedEvent({
          { slot = 0, id = -1, x = 100, y = 100, timev = 1010 },
        })
        assert.is_equal(1, #gestures)
        assert.is_equal("tap", gestures[1].ges)
        assert.is_equal(100, gestures[1].pos.x)
        assert.is_equal(100, gestures[1].pos.y)
        assert.is_equal(1010, gestures[1].time)
        assert.is_nil(gd:getContact(0))
      end
    )

    it("emits double_tap on two quick consecutive taps", function()
      local gd = createGD(false)
      -- First tap down and up
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 100, timev = 1000 } })
      local g_up1 = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 100, timev = 1020 },
      })
      assert.is_equal(0, #g_up1)
      assert.is_equal(1, #timeouts)
      assert.is_equal("double_tap", timeouts[1].gesture)

      -- Second tap down and up within interval
      gd:feedEvent({ { slot = 0, id = 2, x = 105, y = 105, timev = 1100 } })
      local g_up2 = gd:feedEvent({
        { slot = 0, id = -1, x = 105, y = 105, timev = 1120 },
      })
      assert.is_equal(1, #g_up2)
      assert.is_equal("double_tap", g_up2[1].ges)
      assert.is_equal(105, g_up2[1].pos.x)
      assert.is_equal(105, g_up2[1].pos.y)
    end)

    it("emits single tap when double_tap timer expires", function()
      local gd = createGD(false)
      gd:feedEvent({ { slot = 0, id = 1, x = 150, y = 150, timev = 1000 } })
      gd:feedEvent({ { slot = 0, id = -1, x = 150, y = 150, timev = 1020 } })
      assert.is_equal(1, #timeouts)

      -- Trigger double tap timeout callback
      local timer_ges = timeouts[1].cb()
      assert.is_table(timer_ges)
      assert.is_equal("tap", timer_ges.ges)
      assert.is_equal(150, timer_ges.pos.x)
      assert.is_equal(150, timer_ges.pos.y)
      assert.is_nil(gd:getContact(0))
    end)

    it("filters out bounced taps within tap interval", function()
      local gd = createGD(true, 100) -- 100ms bounce interval
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 100, timev = 1000 } })
      local g1 = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 100, timev = 1010 },
      })
      assert.is_equal(1, #g1)
      assert.is_equal("tap", g1[1].ges)

      -- Bounced tap arrives 20ms later at nearby position
      gd:feedEvent({ { slot = 0, id = 2, x = 102, y = 102, timev = 1030 } })
      local g2 = gd:feedEvent({
        { slot = 0, id = -1, x = 102, y = 102, timev = 1040 },
      })
      assert.is_equal(0, #g2)
    end)
  end)

  describe("Hold & Hold Pan Gestures", function()
    local timeouts
    local createGD = function()
      timeouts = {}
      local input = {
        main_finger_slot = 0,
        disable_double_tap = true,
        setTimeout = function(self, slot, gesture, callback, timev, delay)
          table.insert(timeouts, {
            slot = slot,
            gesture = gesture,
            cb = callback,
            timev = timev,
            delay = delay,
          })
        end,
        clearTimeout = function(self, slot, gesture)
          for i = #timeouts, 1, -1 do
            if
              timeouts[i].slot == slot
              and (not gesture or timeouts[i].gesture == gesture)
            then
              table.remove(timeouts, i)
            end
          end
        end,
      }
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = input,
        active_contacts = {},
        contact_count = 0,
        previous_tap = {},
      })
      gd:init()
      return gd
    end

    it("detects hold, hold_pan, and hold_release", function()
      local gd = createGD()
      -- 1. Contact down
      local g1 = gd:feedEvent({
        { slot = 0, id = 1, x = 200, y = 200, timev = 1000 },
      })
      assert.is_equal(1, #g1)
      assert.is_equal("touch", g1[1].ges)
      assert.is_equal(1, #timeouts)
      assert.is_equal("hold", timeouts[1].gesture)

      -- 2. Hold timer fires
      local hold_cb = timeouts[1].cb
      local g_hold = hold_cb()
      assert.is_table(g_hold)
      assert.is_equal("hold", g_hold.ges)
      assert.is_equal(200, g_hold.pos.x)
      assert.is_equal(200, g_hold.pos.y)

      -- 3. Move after hold triggers hold_pan
      local g2 = gd:feedEvent({
        { slot = 0, id = 1, x = 260, y = 200, timev = 1600 },
      })
      assert.is_equal(1, #g2)
      assert.is_equal("hold_pan", g2[1].ges)
      assert.is_equal("east", g2[1].direction)

      -- 4. Contact lift triggers hold_release
      local g3 = gd:feedEvent({
        { slot = 0, id = -1, x = 260, y = 200, timev = 1700 },
      })
      assert.is_equal(1, #g3)
      assert.is_equal("hold_release", g3[1].ges)
      assert.is_equal(260, g3[1].pos.x)
      assert.is_nil(gd:getContact(0))
    end)
  end)

  describe("Pan, Swipe & Multi-swipe Gestures", function()
    local createGD = function()
      local input = {
        main_finger_slot = 0,
        disable_double_tap = true,
        setTimeout = function() end,
        clearTimeout = function() end,
      }
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = input,
        active_contacts = {},
        contact_count = 0,
        previous_tap = {},
      })
      gd:init()
      return gd
    end

    it(
      "detects pan and pan_release when lift occurs after swipe interval",
      function()
        local time = require("ui/time")
        local gd = createGD()
        gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 100, timev = time.s(1) } })
        local g_pan = gd:feedEvent({
          { slot = 0, id = 1, x = 160, y = 100, timev = time.s(1) + time.ms(100) },
        })
        assert.is_equal(1, #g_pan)
        assert.is_equal("pan", g_pan[1].ges)
        assert.is_equal("east", g_pan[1].direction)
        assert.is_equal(60, g_pan[1].distance)

        -- Lift > 900ms after start (1s + 1.5s = 2.5s)
        local g_rel = gd:feedEvent({
          { slot = 0, id = -1, x = 160, y = 100, timev = time.s(1) + time.ms(1500) },
        })
        assert.is_equal(1, #g_rel)
        assert.is_equal("pan_release", g_rel[1].ges)
        assert.is_equal(160, g_rel[1].pos.x)
        assert.is_nil(gd:getContact(0))
      end
    )

    it("detects swipe when lift occurs within swipe interval", function()
      local gd = createGD()
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 100, timev = 1000 } })
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 200, timev = 1050 } })
      local g_swipe = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 200, timev = 1100 },
      })
      assert.is_equal(1, #g_swipe)
      assert.is_equal("swipe", g_swipe[1].ges)
      assert.is_equal("south", g_swipe[1].direction)
      assert.is_equal(100, g_swipe[1].pos.y)
      assert.is_equal(200, g_swipe[1].end_pos.y)
      assert.is_nil(gd:getContact(0))
    end)

    it("detects multiswipe with direction changes", function()
      local gd = createGD()
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 100, timev = 1000 } })
      -- Leg 1: East
      gd:feedEvent({ { slot = 0, id = 1, x = 200, y = 100, timev = 1050 } })
      -- Leg 2: South
      gd:feedEvent({ { slot = 0, id = 1, x = 200, y = 200, timev = 1100 } })
      -- Leg 3: West
      gd:feedEvent({ { slot = 0, id = 1, x = 100, y = 200, timev = 1150 } })

      local g_ms = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 200, timev = 1200 },
      })
      assert.is_equal(1, #g_ms)
      assert.is_equal("multiswipe", g_ms[1].ges)
      assert.is_equal("east south west", g_ms[1].multiswipe_directions)
    end)
  end)

  describe("Multi-touch Gestures", function()
    local timeouts
    local createGD = function()
      timeouts = {}
      local input = {
        main_finger_slot = 0,
        disable_double_tap = true,
        setTimeout = function(self, slot, gesture, callback, timev, delay)
          table.insert(timeouts, {
            slot = slot,
            gesture = gesture,
            cb = callback,
            timev = timev,
            delay = delay,
          })
        end,
        clearTimeout = function(self, slot, gesture)
          for i = #timeouts, 1, -1 do
            if
              timeouts[i].slot == slot
              and (not gesture or timeouts[i].gesture == gesture)
            then
              table.remove(timeouts, i)
            end
          end
        end,
      }
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = input,
        active_contacts = {},
        contact_count = 0,
        previous_tap = {},
      })
      gd:init()
      return gd
    end

    it("detects two_finger_tap", function()
      local gd = createGD()
      gd:feedEvent({
        { slot = 0, id = 1, x = 100, y = 100, timev = 1000 },
        { slot = 1, id = 2, x = 120, y = 100, timev = 1000 },
      })
      local g_up = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 100, timev = 1050 },
        { slot = 1, id = -1, x = 120, y = 100, timev = 1050 },
      })
      assert.is_equal(1, #g_up)
      assert.is_equal("two_finger_tap", g_up[1].ges)
      assert.is_equal(110, g_up[1].pos.x)
      assert.is_equal(20, g_up[1].span)
      assert.is_nil(gd:getContact(0))
      assert.is_nil(gd:getContact(1))
    end)

    it("detects two_finger_hold and two_finger_hold_release", function()
      local gd = createGD()
      gd:feedEvent({
        { slot = 0, id = 1, x = 100, y = 100, timev = 1000 },
        { slot = 1, id = 2, x = 200, y = 100, timev = 1000 },
      })
      assert.is_true(#timeouts >= 1)
      local hold_cb = timeouts[1].cb
      local g_hold = hold_cb()
      assert.is_table(g_hold)
      assert.is_equal("two_finger_hold", g_hold.ges)
      assert.is_equal(150, g_hold.pos.x)
      assert.is_equal(100, g_hold.span)

      local g_rel = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 100, timev = 1700 },
        { slot = 1, id = -1, x = 200, y = 100, timev = 1700 },
      })
      assert.is_equal(1, #g_rel)
      assert.is_equal("two_finger_hold_release", g_rel[1].ges)
      assert.is_equal(150, g_rel[1].pos.x)
    end)

    it("detects two_finger_pan and two_finger_swipe", function()
      local gd = createGD()
      gd:feedEvent({
        { slot = 0, id = 1, x = 100, y = 100, timev = 1000 },
        { slot = 1, id = 2, x = 100, y = 200, timev = 1000 },
      })
      -- Move both south
      local g_pan = gd:feedEvent({
        { slot = 0, id = 1, x = 100, y = 160, timev = 1050 },
        { slot = 1, id = 2, x = 100, y = 260, timev = 1050 },
      })
      assert.is_equal(1, #g_pan)
      assert.is_equal("two_finger_pan", g_pan[1].ges)
      assert.is_equal("south", g_pan[1].direction)

      -- Lift both
      local g_swipe = gd:feedEvent({
        { slot = 0, id = -1, x = 100, y = 160, timev = 1100 },
        { slot = 1, id = -1, x = 100, y = 260, timev = 1100 },
      })
      assert.is_equal(1, #g_swipe)
      assert.is_equal("two_finger_swipe", g_swipe[1].ges)
      assert.is_equal("south", g_swipe[1].direction)
    end)

    it("detects pinch and spread gestures", function()
      local gd_pinch = createGD()
      -- Pinch: start span 200 -> end span 80
      gd_pinch:feedEvent({
        { slot = 0, id = 1, x = 100, y = 200, timev = 1000 },
        { slot = 1, id = 2, x = 300, y = 200, timev = 1000 },
      })
      gd_pinch:feedEvent({
        { slot = 0, id = 1, x = 160, y = 200, timev = 1050 },
        { slot = 1, id = 2, x = 240, y = 200, timev = 1050 },
      })
      local g_pinch = gd_pinch:feedEvent({
        { slot = 0, id = -1, x = 160, y = 200, timev = 1100 },
        { slot = 1, id = -1, x = 240, y = 200, timev = 1100 },
      })
      assert.is_equal(1, #g_pinch)
      assert.is_equal("pinch", g_pinch[1].ges)
      assert.is_equal("horizontal", g_pinch[1].direction)

      -- Spread: start span 40 -> end span 200
      local gd_spread = createGD()
      gd_spread:feedEvent({
        { slot = 0, id = 1, x = 180, y = 200, timev = 1000 },
        { slot = 1, id = 2, x = 220, y = 200, timev = 1000 },
      })
      gd_spread:feedEvent({
        { slot = 0, id = 1, x = 100, y = 200, timev = 1050 },
        { slot = 1, id = 2, x = 300, y = 200, timev = 1050 },
      })
      local g_spread = gd_spread:feedEvent({
        { slot = 0, id = -1, x = 100, y = 200, timev = 1100 },
        { slot = 1, id = -1, x = 300, y = 200, timev = 1100 },
      })
      assert.is_equal(1, #g_spread)
      assert.is_equal("spread", g_spread[1].ges)
      assert.is_equal("horizontal", g_spread[1].direction)
    end)
  end)

  describe("Clock Source Probing", function()
    it("probes realtime and monotonic clock sources", function()
      local time = require("ui/time")
      local ffi = require("ffi")
      local C = ffi.C
      local gd = GestureDetector:new({
        screen = mock_screen,
        input = mock_input,
        active_contacts = {},
        contact_count = 0,
      })

      gd:resetClockSource()
      assert.is_nil(gd:getClockSource())

      gd:probeClockSource(time.realtime_coarse())
      assert.is_equal(C.CLOCK_REALTIME, gd:getClockSource())

      gd:resetClockSource()
      gd:probeClockSource(time.monotonic_coarse())
      assert.is_equal(C.CLOCK_MONOTONIC, gd:getClockSource())

      gd:resetClockSource()
      gd:probeClockSource(0)
      assert.is_equal(-1, gd:getClockSource())
    end)
  end)

  describe("Coordinate and Relative Adjustments", function()
    it(
      "adjusts relative pan offsets and pinch/spread orientations for rotations",
      function()
        local gd = GestureDetector:new({
          screen = {
            scaleByDPI = function(self, v)
              return v
            end,
            getWidth = function()
              return 600
            end,
            getHeight = function()
              return 800
            end,
            getTouchRotation = function()
              return 1
            end, -- DEVICE_ROTATED_CLOCKWISE (90)
            DEVICE_ROTATED_UPRIGHT = 0,
            DEVICE_ROTATED_CLOCKWISE = 1,
            DEVICE_ROTATED_UPSIDE_DOWN = 2,
            DEVICE_ROTATED_COUNTER_CLOCKWISE = 3,
          },
          input = mock_input,
        })

        -- Test pinch direction rotation in 90 deg
        local ges_pinch = { ges = "pinch", direction = "horizontal" }
        gd:adjustGesCoordinate(ges_pinch)
        assert.is_equal("vertical", ges_pinch.direction)

        -- Test pan relative offset and pos in 90 deg
        local ges_pan = {
          ges = "pan",
          direction = "north",
          pos = { x = 100, y = 150 },
          relative = { x = 10, y = 20 },
        }
        gd:adjustGesCoordinate(ges_pan)
        assert.is_equal(600 - 150, ges_pan.pos.x)
        assert.is_equal(100, ges_pan.pos.y)
        assert.is_equal(-20, ges_pan.relative.x)
        assert.is_equal(10, ges_pan.relative.y)

        -- Test 270 deg
        gd.screen.getTouchRotation = function()
          return 3
        end
        local ges_pan270 = {
          ges = "pan",
          direction = "north",
          pos = { x = 100, y = 150 },
          relative = { x = 10, y = 20 },
        }
        gd:adjustGesCoordinate(ges_pan270)
        assert.is_equal(150, ges_pan270.pos.x)
        assert.is_equal(800 - 100, ges_pan270.pos.y)
        assert.is_equal(20, ges_pan270.relative.x)
        assert.is_equal(-10, ges_pan270.relative.y)

        -- Test 180 deg
        gd.screen.getTouchRotation = function()
          return 2
        end
        local ges_pan180 = {
          ges = "pan",
          direction = "north",
          pos = { x = 100, y = 150 },
          relative = { x = 10, y = 20 },
        }
        gd:adjustGesCoordinate(ges_pan180)
        assert.is_equal(600 - 100, ges_pan180.pos.x)
        assert.is_equal(800 - 150, ges_pan180.pos.y)
        assert.is_equal(-10, ges_pan180.relative.x)
        assert.is_equal(-20, ges_pan180.relative.y)
      end
    )
  end)
end)
