describe("slt2 template engine", function()
  local slt2

  setup(function()
    require("commonrequire")
    slt2 = require("plugins/exporter.koplugin/template/slt2")
  end)

  it(
    "should compile and render basic templates with variable interpolation",
    function()
      local t = slt2.loadstring("Hello #{= name }#!")
      local result = slt2.render(t, { name = "KOReader" })
      assert.are.equal("Hello KOReader!", result)
    end
  )
end)
