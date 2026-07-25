describe("WaveformLevel element", function()
  local WaveformLevel

  setup(function()
    require("commonrequire")
    WaveformLevel = require("ui/elements/waveform_level")
  end)

  it(
    "should return waveform level menu table or nil depending on device",
    function()
      assert.is_true(WaveformLevel == nil or type(WaveformLevel) == "table")
    end
  )
end)
