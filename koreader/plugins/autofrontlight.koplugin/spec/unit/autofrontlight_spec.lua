describe("AutoFrontlight widget tests", function()
    local Device, PowerD, MockTime, class, AutoFrontlight, UIManager

    local function setAmbientBrightnessAndRun(brightness)
        Device.brightness = brightness
        MockTime:increase(2)
        UIManager:handleInput()
    end

    local function assertFrontlightLevel(expected)
        assert.are.equal(expected, Device:getPowerDevice().frontlight)
    end

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))

        MockTime = require("mock_time")
        MockTime:install()

        PowerD = require("device/generic/powerd"):new{
            frontlight = 0,
        }
        PowerD.frontlightIntensityHW = function()
            return 2
        end
        PowerD.setIntensityHW = function(self, intensity)
            self.frontlight = intensity
        end
        PowerD.resetT1Timeout = function() end
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        Device = require("device")
        Device.isKindle = function() return true end
        Device.model = "KindleVoyage"
        Device.brightness = 0
        Device.hasFrontlight = function() return true end
        Device.hasLightSensor = function() return true end
        Device.powerd = PowerD:new{
            device = Device,
        }
        Device.ambientBrightnessLevel = function(self)
            return self.brightness
        end
        Device.input.waitEvent = function() end
        require("luasettings"):
            open(require("datastorage"):getSettingsDir() .. "/autofrontlight.lua"):
            save("enable", true):
            close()

        UIManager = require("ui/uimanager")
        UIManager:setRunForeverMode()

        requireBackgroundRunner()
        class = dofile("plugins/autofrontlight.koplugin/main.lua")
        AutoFrontlight = class:new()
        notifyBackgroundJobsUpdated()

        -- Ensure the background runner has succeeded set the job.insert_sec.
        MockTime:increase(2)
        UIManager:handleInput()
    end)

    after_each(function()
        AutoFrontlight:onClose()
        -- Ensure the scheduled task from this test case won't impact others.
        MockTime:increase(2)
        UIManager:handleInput()
        AutoFrontlight = nil
        stopBackgroundRunner()
    end)

    it("should automatically turn on or off frontlight", function()
        -- Set the initial state to AutoFrontlight widget.
        setAmbientBrightnessAndRun(0)

        setAmbientBrightnessAndRun(3)
        assertFrontlightLevel(0)
        setAmbientBrightnessAndRun(0)
        assertFrontlightLevel(2)
        setAmbientBrightnessAndRun(1)
        assertFrontlightLevel(2)
        setAmbientBrightnessAndRun(2)
        assertFrontlightLevel(2)
        setAmbientBrightnessAndRun(3)
        assertFrontlightLevel(0)
        setAmbientBrightnessAndRun(4)
        assertFrontlightLevel(0)
        setAmbientBrightnessAndRun(3)
        assertFrontlightLevel(0)
        setAmbientBrightnessAndRun(2)
        assertFrontlightLevel(0)
        setAmbientBrightnessAndRun(1)
        assertFrontlightLevel(2)
        setAmbientBrightnessAndRun(0)
        assertFrontlightLevel(2)
    end)

    it("should turn on frontlight at the beginning", function()
        -- Set the initial state to AutoFrontlight widget.
        setAmbientBrightnessAndRun(3)

        Device:getPowerDevice():turnOffFrontlight()
        setAmbientBrightnessAndRun(0)
        assertFrontlightLevel(2)
    end)

    it("should turn off frontlight at the beginning", function()
        -- Set the initial state to AutoFrontlight widget.
        setAmbientBrightnessAndRun(0)

        Device:getPowerDevice():turnOnFrontlight()
        setAmbientBrightnessAndRun(3)
        assertFrontlightLevel(0)
    end)

    it("should handle configuration update", function()
        -- Set the initial state to AutoFrontlight widget.
        setAmbientBrightnessAndRun(3)

        Device:getPowerDevice():turnOffFrontlight()
        setAmbientBrightnessAndRun(0)
        assertFrontlightLevel(2)
        AutoFrontlight:flipSetting()
        -- The last AutoFrontlight job is in the queue and will be executed first before the flipped setting to take effect.
        setAmbientBrightnessAndRun(0)
        setAmbientBrightnessAndRun(3)
        assertFrontlightLevel(2)
    end)
end)
