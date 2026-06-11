describe("gesturedetector module", function()
    local GestureDetector
    local mock_screen = {
        scaleByDPI = function(self, v) return v end,
        getWidth = function(self) return 600 end,
        getHeight = function(self) return 800 end,
        getTouchRotation = function(self) return 0 end,
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
            GestureDetector.screen.getTouchRotation = function() return rotation_mode end

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

    it("should handle isTwoFingerTap safely when buddy contact has nil initial_tev", function()
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
    end)

    it("should automatically heal a contact missing initial_tev during feedEvent", function()
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
    end)

    it("should treat swiping to the edge of screen as end of touch (lift)", function()
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
    end)
end)
