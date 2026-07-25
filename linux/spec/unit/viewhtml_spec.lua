describe("ViewHTML module", function()
  local ViewHTML

  setup(function()
    require("commonrequire")
    ViewHTML = require("ui/viewhtml")
  end)

  it("should expose ViewHtml methods and views", function()
    assert.is_table(ViewHTML)
    assert.is_table(ViewHTML.VIEWS)
  end)
end)
