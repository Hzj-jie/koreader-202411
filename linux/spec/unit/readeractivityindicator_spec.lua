describe("ReaderActivityIndicator module", function()
  local ReaderActivityIndicator

  setup(function()
    require("commonrequire")
    ReaderActivityIndicator =
      require("apps/reader/modules/readeractivityindicator")
  end)

  it("should initialize activity indicator module stub", function()
    assert.is_table(ReaderActivityIndicator)
    assert.is_boolean(ReaderActivityIndicator:isStub())
  end)
end)
