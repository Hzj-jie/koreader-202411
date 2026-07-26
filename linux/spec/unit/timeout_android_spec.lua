describe("TimeoutAndroid element", function()
  local TimeoutAndroid

  setup(function()
    require("commonrequire")
    TimeoutAndroid = require("ui/elements/timeout_android")
  end)

  it("should handle non-android platform gracefully", function()
    assert.is_true(
      TimeoutAndroid == true
        or type(TimeoutAndroid) == "table"
        or type(TimeoutAndroid) == "function"
    )
  end)
end)
