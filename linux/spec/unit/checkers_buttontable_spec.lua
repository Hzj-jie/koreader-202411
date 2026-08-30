describe("Checkers ButtonTable widget", function()
  local CheckersButtonTable

  setup(function()
    require("commonrequire")
    CheckersButtonTable = require("plugins/checkers.koplugin/buttontable")
  end)

  it("should initialize CheckersButtonTable widget", function()
    local widget = CheckersButtonTable:new({
      buttons = {
        { { text = "OK" } },
      },
    })
    assert.is_table(widget)
  end)
end)
