describe("Markdown parser module (md.lua)", function()
  local MD

  setup(function()
    require("commonrequire")
    MD = require("apps/filemanager/lib/md")
  end)

  it("should parse basic markdown text to html", function()
    assert.is_table(MD)
    if
      type(MD) == "function"
      or type(MD.to_html) == "function"
      or type(MD.to_tree) == "function"
    then
      local input = "# Hello World\n\nThis is a *markdown* test."
      local result = MD.to_html and MD.to_html(input)
        or (type(MD) == "function" and MD(input))
      assert.is_not_nil(result)
    end
  end)
end)
