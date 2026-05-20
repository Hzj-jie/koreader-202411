-- luacheck: push ignore
require("commonrequire")

describe("device/generic/powerd", function()
    local BasePowerD
    local mock_device, mock_uimgr, mock_event
    local powerd

    setup(function()
        package.unload("device/generic/powerd")
        package.unload("ui/event")

        mock_event = {
            new = function(self, name, attributes, ges_attributes)
                return {
                    name = name,
                    attributes = attributes,
                    ges_attributes = ges_attributes
                }
            end
        }
        package.loaded["ui/event"] = mock_event

        BasePowerD = require("device/generic/powerd")
    end)

    teardown(function()
        package.unload("device/generic/powerd")
        package.unload("ui/event")
    end)

    before_each(function()
        mock_device = {
            hasFrontlight = stub().returns(true),
            hasNaturalLight = stub().returns(true),
            _beforeSuspend = stub(),
            _afterResume = stub(),
            total_standby_time = 10,
            total_suspend_time = 20,
        }

        mock_uimgr = {
            broadcastEvent = stub(),
            getElapsedTimeSinceBoot = stub().returns(100)
        }

        -- Create an instance of BasePowerD with custom limits
        powerd = BasePowerD:new({
            fl_min = 0,
            fl_max = 24,
            fl_warmth_min = 0,
            fl_warmth_max = 15,
            device = mock_device
        })

        -- Setup stub methods on our instance to simulate hardware
        powerd.frontlightIntensityHW = stub().returns(12)
        powerd.frontlightWarmthHW = stub().returns(6)
        powerd.setIntensityHW = stub()
        powerd.setWarmthHW = stub()
        powerd.getCapacityHW = stub().returns(75)
        powerd.getAuxCapacityHW = stub().returns(35)
        powerd.isAuxBatteryConnectedHW = stub().returns(false)
        powerd.isChargingHW = stub().returns(false)
        powerd.isChargedHW = stub().returns(false)
        powerd.isAuxChargingHW = stub().returns(false)
        powerd.isAuxChargedHW = stub().returns(false)
    end)

    describe("initialization", function()
        it("asserts if fl_min >= fl_max", function()
            assert.has_error(function()
                BasePowerD:new({ fl_min = 10, fl_max = 5 })
            end)
        end)

        it("asserts if fl_warmth_min >= fl_warmth_max", function()
            assert.has_error(function()
                BasePowerD:new({ fl_min = 0, fl_max = 10, fl_warmth_min = 20, fl_warmth_max = 10 })
            end)
        end)

        it("loads default hardware states when frontlight and natural light are present", function()
            local p = BasePowerD:new({
                fl_min = 0,
                fl_max = 24,
                fl_warmth_min = 0,
                fl_warmth_max = 15,
                device = mock_device,
                frontlightIntensityHW = function() return 12 end,
                frontlightWarmthHW = function() return 6 end,
                _decideFrontlightState = stub(),
                updateResumeFrontlightState = stub(),
            })

            assert.are.equal(12, p.fl_intensity)
            assert.are.equal(6, p.fl_warmth)
            assert.spy(p._decideFrontlightState).was.called()
            assert.spy(p.updateResumeFrontlightState).was.called()
        end)
    end)

    describe("frontlight status and toggling", function()
        before_each(function()
            powerd:UIManagerReady(mock_uimgr)
            -- Initialize internal status
            powerd.fl_intensity = 12
            powerd.is_fl_on = true
        end)

        it("correctly checks if frontlight is on or off", function()
            assert.is_true(powerd:isFrontlightOn())
            assert.is_false(powerd:isFrontlightOff())

            powerd.is_fl_on = false
            assert.is_false(powerd:isFrontlightOn())
            assert.is_true(powerd:isFrontlightOff())
        end)

        it("gets frontlight intensity (0 if off)", function()
            assert.are.equal(12, powerd:frontlightIntensity())

            powerd.is_fl_on = false
            assert.are.equal(0, powerd:frontlightIntensity())
        end)

        it("turns off the frontlight", function()
            local my_stub = stub(powerd, "turnOffFrontlightHW").returns(false)
            local cb = stub()

            local ok = powerd:turnOffFrontlight(cb)

            assert.is_true(ok)
            assert.is_false(powerd.is_fl_on)
            assert.spy(powerd.turnOffFrontlightHW).was.called()
            local call = powerd.turnOffFrontlightHW.calls[1]
            assert.are.equal(powerd, call.refs[1])
            assert.are.equal(cb, call.vals[2])
            assert.spy(cb).was.called()
            assert.spy(mock_uimgr.broadcastEvent).was.called()
            assert.are.equal("FrontlightStateChanged", mock_uimgr.broadcastEvent.calls[1].vals[2].name)
        end)

        it("turns on the frontlight", function()
            powerd.is_fl_on = false
            stub(powerd, "turnOnFrontlightHW").returns(false)
            local cb = stub()

            local ok = powerd:turnOnFrontlight(cb)

            assert.is_true(ok)
            assert.is_true(powerd.is_fl_on)
            assert.spy(powerd.turnOnFrontlightHW).was.called()
            local call = powerd.turnOnFrontlightHW.calls[1]
            assert.are.equal(powerd, call.refs[1])
            assert.are.equal(cb, call.vals[2])
            assert.spy(cb).was.called()
        end)

        it("toggles frontlight state", function()
            spy.on(powerd, "turnOffFrontlight")
            spy.on(powerd, "turnOnFrontlight")

            powerd:toggleFrontlight()
            assert.spy(powerd.turnOffFrontlight).was.called()

            powerd.is_fl_on = false
            powerd:toggleFrontlight()
            assert.spy(powerd.turnOnFrontlight).was.called()
        end)
    end)

    describe("intensity and warmth setting", function()
        before_each(function()
            powerd:UIManagerReady(mock_uimgr)
            powerd.fl_intensity = 12
            powerd.is_fl_on = true
        end)

        it("normalizes and sets brightness intensity", function()
            powerd:setIntensity(18)
            assert.spy(powerd.setIntensityHW).was.called_with(powerd, 18)
            assert.are.equal(18, powerd.fl_intensity)

            -- Test boundaries
            powerd:setIntensity(30) -- exceeds max (24)
            assert.are.equal(24, powerd.fl_intensity)

            powerd:setIntensity(-5) -- below min (0)
            assert.are.equal(0, powerd.fl_intensity)
        end)

        it("sets warmth converting KOReader [0..100] to hardware native scale [0..15]", function()
            -- Native scale is 0 to 15. warmth_scale is 100 / 15 = 6.666...
            -- KOReader warmth 50 maps to native warmth Math.round(50 / 6.6666...) = Math.round(7.5) = 8
            powerd:setWarmth(50)
            assert.spy(powerd.setWarmthHW).was.called_with(powerd, 8)
            assert.are.equal(50, powerd.fl_warmth)

            -- KOReader warmth 100 maps to native warmth 15
            powerd:setWarmth(100)
            assert.spy(powerd.setWarmthHW).was.called_with(powerd, 15)
            assert.are.equal(100, powerd.fl_warmth)
        end)
    end)

    describe("battery status and capacity caching", function()
        it("retrieves capacity from hardware and caches it", function()
            local time = require("ui/time")
            powerd:UIManagerReady(mock_uimgr)
            mock_uimgr.getElapsedTimeSinceBoot.returns(time.s(10)) -- t=10s

            local cap = powerd:getCapacity()
            assert.are.equal(75, cap)
            assert.spy(powerd.getCapacityHW).was.called()

            -- t=20s (< 60s limit), should return cached value
            powerd.getCapacityHW:clear()
            mock_uimgr.getElapsedTimeSinceBoot.returns(time.s(20))
            cap = powerd:getCapacity()
            assert.are.equal(75, cap)
            assert.spy(powerd.getCapacityHW).was.not_called()

            -- t=80s (>= 60s limit), should pull from hardware again
            mock_uimgr.getElapsedTimeSinceBoot.returns(time.s(80))
            cap = powerd:getCapacity()
            assert.are.equal(75, cap)
            assert.spy(powerd.getCapacityHW).was.called()
        end)

        it("retrieves capacity using monotonic time if UIManager is not ready", function()
            powerd.device = mock_device
            -- Invalidate cached UIManager reference
            powerd:UIManagerReady(nil)

            -- Setup initial call
            local cap = powerd:getCapacity()
            assert.are.equal(75, cap)
            assert.spy(powerd.getCapacityHW).was.called()
        end)

        it("forces capacity update on cache invalidation", function()
            local time = require("ui/time")
            powerd:UIManagerReady(mock_uimgr)
            mock_uimgr.getElapsedTimeSinceBoot.returns(time.s(10))
            powerd:getCapacity()

            -- Invalidate
            powerd.getCapacityHW:clear()
            powerd:invalidateCapacityCache()

            -- Even if time didn't advance, invalidation triggers refresh
            powerd:getCapacity()
            assert.spy(powerd.getCapacityHW).was.called()
        end)
    end)

    describe("suspend and resume lifecycle", function()
        it("triggers device hooks and invalidates caches on suspend/resume", function()
            powerd:UIManagerReady(mock_uimgr)

            powerd:beforeSuspend()
            assert.spy(mock_device._beforeSuspend).was.called()

            powerd:afterResume()
            assert.spy(mock_device._afterResume).was.called()
            -- Capacity caches should be invalidated (set to -61)
            local time = require("ui/time")
            assert.are.equal(time.s(-61), powerd.last_capacity_pull_time)
            assert.are.equal(time.s(-61), powerd.last_aux_capacity_pull_time)
        end)
    end)

    describe("getBatterySymbol", function()
        it("returns correct battery icon corresponding to capacities and charging state", function()
            -- Charged state
            assert.are.equal("", powerd:getBatterySymbol(true, false, 100))
            -- Charging state
            assert.are.equal("", powerd:getBatterySymbol(false, true, 50))

            -- Normal discharging states
            assert.are.equal("", powerd:getBatterySymbol(false, false, 100))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 95))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 85))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 75))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 65))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 55))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 45))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 35))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 25))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 15))
            assert.are.equal("", powerd:getBatterySymbol(false, false, 5))
        end)
    end)
end)
-- luacheck: pop
