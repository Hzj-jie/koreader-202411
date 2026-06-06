describe("NaturalLightWidget UI component", function()
    local Device, PowerD, NaturalLightWidget

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Device = require("device")
        PowerD = require("device/generic/powerd")
        NaturalLightWidget = require("ui/widget/naturallightwidget")
    end)

    before_each(function()
        Device.isKobo = function() return true end
        Device.model = "Kobo_dahlia"
        Device.hasFrontlight = function() return true end
        Device.hasNaturalLight = function() return true end

        local powerd_mock = PowerD:new({
            fl_min = 1,
            fl_max = 5,
            fl_intensity = 2,
            is_fl_on = true,
            device = Device,
        })
        -- Mock properties needed by NaturalLightWidget
        powerd_mock.fl = {
            white_gain = 10,
            white_offset = 20,
            red_gain = 30,
            red_offset = 40,
            green_gain = 50,
            green_offset = 60,
            exponent = 70,
            setNaturalBrightness = function() end,
        }
        powerd_mock.frontlightWarmth = function() return 2 end

        Device.powerd = powerd_mock
        Device.getPowerDevice = function() return powerd_mock end
    end)

    it("should instantiate without crashing", function()
        local nlw
        assert.has_no.errors(function()
            nlw = NaturalLightWidget:new{}
        end)
        assert.is_not_nil(nlw)
    end)
end)
