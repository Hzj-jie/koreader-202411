describe("MassStorage element", function()
  local MassStorage

  setup(function()
    require("commonrequire")
    MassStorage = require("ui/elements/mass_storage")
  end)

  it(
    "should return mass storage menu table or nil depending on device",
    function()
      assert.is_true(MassStorage == nil or type(MassStorage) == "table")
    end
  )
end)
