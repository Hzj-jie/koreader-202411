describe("DateTimeWidget module", function()
  local DateTimeWidget

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DateTimeWidget = require("ui/widget/datetimewidget")
  end)

  describe("Initialization", function()
    it("should initialize date/time picker widget", function()
      local widget = DateTimeWidget:new({
        hour = 10,
        min = 30,
        ok_text = "Set time",
        title_text = "Set time",
      })
      assert.is_table(widget)
    end)
  end)
end)
