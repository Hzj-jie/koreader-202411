describe("HttpClient module", function()
  local HttpClient

  setup(function()
    require("commonrequire")
    HttpClient = require("httpclient")
  end)

  it("should expose HttpClient table or functions", function()
    assert.is_table(HttpClient)
  end)
end)
