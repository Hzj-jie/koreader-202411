describe("FrontLightWidget UI component", function()
    local Device, PowerD, FrontLightWidget

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Device = require("device")
        PowerD = require("device/generic/powerd")
        FrontLightWidget = require("ui/widget/frontlightwidget")
    end)

    before_each(function()
        Device.isKobo = function() return true end
        Device.model = "Kobo_dahlia"
        Device.hasFrontlight = function() return true end
        Device.hasNaturalLight = function() return false end

        local current_intensity = 2
        local powerd_mock = PowerD:new({
            fl_min = 1,
            fl_max = 5,
            fl_intensity = 2,
            is_fl_on = true,
            device = Device,
        })
        powerd_mock.frontlightIntensityHW = function() return current_intensity end
        powerd_mock.frontlightIntensity = function() return current_intensity end
        powerd_mock.setIntensityHW = function(self, val)
            current_intensity = val
        end

        Device.powerd = powerd_mock
        Device.getPowerDevice = function() return powerd_mock end
    end)

    it("should initialize frontlight properties correctly", function()
        local flw = FrontLightWidget:new{}
        assert.is_not_nil(flw)
        assert.is.same(1, flw.fl.min)
        assert.is.same(5, flw.fl.max)
        assert.is.same(2, flw.fl.cur)
    end)

    it("should set frontlight brightness intensity", function()
        local UIManager = require("ui/uimanager")
        local flw = FrontLightWidget:new{}
        spy.on(flw.powerd, "setIntensityHW")

        local old_stack = UIManager._window_stack
        UIManager._window_stack = { { widget = flw } }

        flw:setBrightness(4)

        UIManager._window_stack = old_stack

        assert.is.same(4, flw.fl.cur)
        assert.spy(flw.powerd.setIntensityHW).is_called_with(flw.powerd, 4)
    end)
end)
