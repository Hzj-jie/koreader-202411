-- Unit tests for SDL Power Daemon (linux/frontend/device/sdl/powerd.lua)

describe("SDL PowerD", function()
    local SDLPowerD
    local mock_SDL
    local mock_device

    setup(function()
        require("commonrequire")
        package.unloadAll() --luacheck: ignore
    end)

    teardown(function()
        package.unloadAll() --luacheck: ignore
    end)

    before_each(function()
        -- Mock FFI SDL 2.0 library
        mock_SDL = {
            getPowerInfo = spy.new(function()
                -- Returns: batt, charging, plugged, percent
                return true, false, false, 85
            end)
        }
        package.loaded["ffi/SDL2_0"] = mock_SDL

        -- Spy on logger
        local logger = require("logger")
        spy.on(logger, "info")

        -- Mock Device
        mock_device = {
            hasFrontlight = spy.new(function() return true end),
            hasNaturalLight = spy.new(function() return true end),
            _beforeSuspend = spy.new(function() end),
            _afterResume = spy.new(function() end),
        }

        package.loaded["device/sdl/powerd"] = nil
        SDLPowerD = require("device/sdl/powerd")
        SDLPowerD.device = mock_device
        SDLPowerD.fl_intensity = SDLPowerD:frontlightIntensityHW()
        SDLPowerD.fl_warmth = SDLPowerD:frontlightWarmthHW()
    end)

    after_each(function()
        local logger = require("logger")
        if type(logger.info) == "table" and logger.info.revert then
            logger.info:revert()
        end
        package.loaded["ffi/SDL2_0"] = nil
        package.loaded["device/sdl/powerd"] = nil
    end)

    describe("intensity and warmth defaults", function()
        it("should return default hardware intensity and warmth", function()
            assert.are.equal(50, SDLPowerD:frontlightIntensityHW())
            assert.are.equal(50, SDLPowerD:frontlightWarmthHW())
        end)
    end)

    describe("setIntensityHW", function()
        it("should update hw_intensity and log the change", function()
            SDLPowerD:setIntensityHW(75)
            assert.are.equal(75, SDLPowerD:frontlightIntensityHW())
            assert.spy(require("logger").info).was.called_with("set brightness to", 75)
        end)

        it("should keep current hw_intensity if nil is passed", function()
            SDLPowerD:setIntensityHW(nil)
            assert.are.equal(50, SDLPowerD:frontlightIntensityHW())
        end)
    end)

    describe("getCapacityHW", function()
        it("should return battery percent when SDL returns a valid capacity", function()
            mock_SDL.getPowerInfo = spy.new(function()
                return true, false, false, 85
            end)
            assert.are.equal(85, SDLPowerD:getCapacityHW())
        end)

        it("should return 0 when SDL returns percent as -1", function()
            mock_SDL.getPowerInfo = spy.new(function()
                return false, false, true, -1
            end)
            assert.are.equal(0, SDLPowerD:getCapacityHW())
        end)
    end)

    describe("isChargingHW", function()
        it("should return true if SDL indicates charging is true", function()
            mock_SDL.getPowerInfo = spy.new(function()
                return true, true, true, 85
            end)
            assert.is_true(SDLPowerD:isChargingHW())
        end)

        it("should return false if SDL indicates charging is false", function()
            mock_SDL.getPowerInfo = spy.new(function()
                return true, false, false, 85
            end)
            assert.is_false(SDLPowerD:isChargingHW())
        end)

        it("should return false if SDL getPowerInfo call does not succeed", function()
            mock_SDL.getPowerInfo = spy.new(function()
                return false, false, false, 0
            end)
            assert.is_false(SDLPowerD:isChargingHW())
        end)
    end)

    describe("suspend and resume lifecycle", function()
        it("should call device:_beforeSuspend on beforeSuspend", function()
            SDLPowerD:beforeSuspend()
            assert.spy(mock_device._beforeSuspend).was.called()
        end)

        it("should call device:_afterResume and invalidate capacity cache on afterResume", function()
            SDLPowerD:afterResume()
            assert.spy(mock_device._afterResume).was.called()
            local time = require("ui/time")
            assert.are.equal(time.s(-61), SDLPowerD.last_capacity_pull_time)
            assert.are.equal(time.s(-61), SDLPowerD.last_aux_capacity_pull_time)
        end)
    end)
end)
