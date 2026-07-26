describe("ButtonTable widget module", function()
  local ButtonTable

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ButtonTable = require("ui/widget/buttontable")
  end)

  describe("Initialization", function()
    it("should initialize button table instance with layout", function()
      local buttons = {
        {
          { text = "Btn1", callback = function() end },
          { text = "Btn2", callback = function() end },
        },
      }
      local table_widget = ButtonTable:new({
        buttons = buttons,
        width = 300,
      })
      assert.is_table(table_widget)
    end)
  end)
end)
