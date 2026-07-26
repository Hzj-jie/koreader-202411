describe("SunTime module for Autowarmth", function()
  local SunTime

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SunTime = require("plugins/autowarmth.koplugin/suntime")
  end)

  describe("Sunrise & Sunset calculation", function()
    it("should set position and calculate times", function()
      assert.is_table(SunTime)
      SunTime:setPosition("Berlin", 52.52, 13.405, 1, 50, true)
      SunTime:setDate(2024, 6, 21)
      SunTime:calculateTimes()

      assert.is_number(SunTime.rise)
      assert.is_number(SunTime.set)
    end)
  end)
end)
