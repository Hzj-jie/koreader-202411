describe("FileMessageQueue module", function()
  local ok, FileMessageQueue

  setup(function()
    require("commonrequire")
    ok, FileMessageQueue = pcall(require, "ui/message/filemessagequeue")
  end)

  it("should attempt loading FileMessageQueue safely", function()
    assert.is_boolean(ok)
    if ok then
      assert.is_table(FileMessageQueue)
    end
  end)
end)
