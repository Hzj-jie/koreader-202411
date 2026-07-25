describe("Wikipedia module", function()
  local Wikipedia
  setup(function()
    require("commonrequire")
    Wikipedia = require("ui/wikipedia")
  end)

  it("should return Wikipedia server", function()
    local expected_server_default = "https://en.wikipedia.org"
    local expected_server_nl = "https://nl.wikipedia.org"
    assert.is.same(expected_server_default, Wikipedia:getWikiServer())
    assert.is.same(expected_server_nl, Wikipedia:getWikiServer("nl"))
  end)

  it("should manage trap widget", function()
    local dummy_trap = { name = "dummy" }
    Wikipedia:setTrapWidget(dummy_trap)
    assert.is.same(dummy_trap, Wikipedia.trap_widget)
    Wikipedia:resetTrapWidget()
    assert.is_nil(Wikipedia.trap_widget)
  end)

  it("should prettify plain text headers and whitespace", function()
    local input = "\n\n== Section Header ==\n\nSome paragraph text.\n\n\n"
    local prettified = Wikipedia:prettifyText(input)
    assert.truthy(prettified:find("Section Header"))
    assert.is_not.same(input, prettified)
  end)
end)
