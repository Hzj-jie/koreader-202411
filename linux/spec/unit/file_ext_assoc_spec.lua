describe("FileExtAssoc element", function()
  local FileExtAssoc

  setup(function()
    require("commonrequire")
    FileExtAssoc = require("ui/elements/file_ext_assoc")
  end)

  it("should return file extension association menu table or nil", function()
    assert.is_true(FileExtAssoc == nil or type(FileExtAssoc) == "table")
  end)
end)
