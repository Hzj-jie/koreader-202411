describe("SunTime module for Autowarmth", function()
  local SunTime

  setup(function()
    require("commonrequire")
    SunTime = require("plugins/autowarmth.koplugin/suntime")
  end)

  describe("setPosition and coordinate clamping", function()
    it("should set position in radians and degrees, clamping out-of-range coordinates", function()
      -- Sane coordinates
      SunTime:setPosition("Berlin", 52.52, 13.405, 1, 50, true)
      assert.are.equal("Berlin", SunTime.pos.name)
      assert.is_number(SunTime.pos.latitude)
      assert.is_number(SunTime.pos.longitude)
      assert.are.equal(50, SunTime.pos.altitude)
      assert.are.equal(1, SunTime.time_zone)
      assert.is_number(SunTime.sin_latitude)
      assert.is_number(SunTime.cos_latitude)
      assert.is_number(SunTime.refract)

      -- Clamping north/south beyond 90 degrees
      SunTime:setPosition("NorthPoleOverflow", 120.0, 0.0, 0, 0, true)
      assert.is_true(SunTime.pos.latitude <= math.pi / 2)

      SunTime:setPosition("SouthPoleOverflow", -120.0, 0.0, 0, 0, true)
      assert.is_true(SunTime.pos.latitude >= -math.pi / 2)

      -- Clamping east/west beyond 180 degrees
      SunTime:setPosition("EastOverflow", 0.0, 200.0, 0, 0, true)
      assert.are.equal(math.pi, SunTime.pos.longitude)

      SunTime:setPosition("WestOverflow", 0.0, -200.0, 0, 0, true)
      assert.are.equal(-math.pi, SunTime.pos.longitude)
    end)
  end)

  describe("setDate and leap year handling", function()
    it("should correctly handle leap years and non-leap years", function()
      -- Leap year 2024
      SunTime:setDate(2024, 3, 1)
      -- 31 (Jan) + 29 (Feb leap) + 1 (March) = 61
      assert.are.equal(61, SunTime.date.yday)
      assert.are.equal(2024, SunTime.date.year)
      assert.are.equal(3, SunTime.date.month)
      assert.are.equal(1, SunTime.date.day)

      -- Century non-leap year 1900
      SunTime:setDate(1900, 3, 1)
      -- 31 (Jan) + 28 (Feb non-leap) + 1 (March) = 60
      assert.are.equal(60, SunTime.date.yday)

      -- 400-year leap year 2000
      SunTime:setDate(2000, 3, 1)
      assert.are.equal(61, SunTime.date.yday)

      -- Regular non-leap year 2023
      SunTime:setDate(2023, 3, 1)
      assert.are.equal(60, SunTime.date.yday)

      -- Default date without arguments
      SunTime:setDate()
      assert.is_table(SunTime.date)
      assert.is_number(SunTime.date.year)
      assert.is_number(SunTime.date.yday)
    end)
  end)

  describe("calculateTimes across hemispheres and seasons", function()
    it("should calculate sunrise, sunset, noon, and twilights for temperate northern hemisphere", function()
      SunTime:setPosition("Berlin", 52.52, 13.405, 1, 50, true)
      SunTime:setDate(2024, 3, 20, 0) -- Vernal equinox: all 11 times defined
      SunTime:calculateTimes(false)

      assert.is_number(SunTime.rise)
      assert.is_number(SunTime.set)
      assert.is_number(SunTime.noon)
      assert.is_number(SunTime.midnight)
      assert.is_true(SunTime.rise < SunTime.noon)
      assert.is_true(SunTime.noon < SunTime.set)
      assert.is_number(SunTime.rise_civil)
      assert.is_number(SunTime.set_civil)
      assert.is_true(SunTime.rise_civil < SunTime.rise)
      assert.is_true(SunTime.set < SunTime.set_civil)
      assert.are.equal(11, #SunTime.times)
    end)

    it("should calculate times with fast_twilight option", function()
      SunTime:setPosition("Berlin", 52.52, 13.405, 1, 50, true)
      SunTime:setDate(2024, 3, 20, 0)
      SunTime:calculateTimes(true)

      assert.is_number(SunTime.rise)
      assert.is_number(SunTime.set)
      assert.is_number(SunTime.rise_civil)
      assert.is_number(SunTime.set_civil)
      assert.is_true(SunTime.rise_civil < SunTime.rise)
      assert.is_true(SunTime.set < SunTime.set_civil)
    end)

    it("should calculate times for southern hemisphere (Sydney)", function()
      -- Sydney: -33.8688, 151.2093, timezone 10
      SunTime:setPosition("Sydney", -33.8688, 151.2093, 10, 20, true)
      -- December is summer in Sydney (long days, early rise, late set)
      SunTime:setDate(2024, 12, 21, 0)
      SunTime:calculateTimes()

      assert.is_number(SunTime.rise)
      assert.is_number(SunTime.set)
      assert.is_true(SunTime.rise < 6.5)
      assert.is_true(SunTime.set > 19.5)
    end)

    it("should handle polar night and midnight sun at extreme latitudes", function()
      -- Longyearbyen Svalbard: 78.2232 N, 15.6267 E, timezone 1
      SunTime:setPosition("Longyearbyen", 78.2232, 15.6267, 1, 10, true)

      -- Summer (June 21): Midnight sun -> Sun does not set
      SunTime:setDate(2024, 6, 21, 1)
      SunTime:calculateTimes()
      assert.is_nil(SunTime.set)

      -- Winter (December 21): Polar night -> Sun does not rise
      SunTime:setDate(2024, 12, 21, 0)
      SunTime:calculateTimes()
      assert.is_nil(SunTime.rise)
    end)
  end)

  describe("Sun height, equation of time, and time conversions", function()
    it("should compute solar elevation angle via getHeight", function()
      SunTime:setPosition("Berlin", 52.52, 13.405, 1, 50, true)
      SunTime:setDate(2024, 6, 21, 1)
      SunTime:calculateTimes()

      local height_noon = SunTime:getHeight(SunTime.noon)
      local height_midnight = SunTime:getHeight(SunTime.midnight or 24)

      assert.is_number(height_noon)
      assert.is_true(height_noon > 0)
      if height_midnight then
        assert.is_true(height_midnight < 0)
      end

      -- With numeric eod adjustment
      local height_with_eod = SunTime:getHeight(SunTime.noon, SunTime.eod)
      assert.is_number(height_with_eod)
    end)

    it("should convert time values to seconds via getTimeInSec", function()
      -- Table input
      local sec1 = SunTime:getTimeInSec({ hour = 2, min = 30, sec = 15 })
      assert.are.equal(2 * 3600 + 30 * 60 + 15, sec1)

      -- Number in hours input
      local sec2 = SunTime:getTimeInSec(1.5)
      assert.are.equal(5400, sec2)

      -- Default (current time table)
      local sec3 = SunTime:getTimeInSec()
      assert.is_number(sec3)
      assert.is_true(sec3 >= 0 and sec3 <= 86400)
    end)

    it("should support setAdvanced for equation of time", function()
      SunTime:setAdvanced()
      assert.is_function(SunTime.getZgl)
      assert.are.equal(SunTime.getZglAdvanced, SunTime.getZgl)

      local zgl = SunTime:getZgl()
      assert.is_number(zgl)
    end)

    it("should safely compute timezone offset via getTimezoneOffset", function()
      local offset = SunTime:getTimezoneOffset()
      assert.is_number(offset)
      assert.is_true(offset >= -14 and offset <= 14)
    end)
  end)
end)
