describe("ReaderZooming module", function()
  local ReaderZooming

  setup(function()
    require("commonrequire")
    ReaderZooming = require("apps/reader/modules/readerzooming")
  end)

  it("should convert zoom modes and combos correctly", function()
    local mock_ui = {}
    local zooming = ReaderZooming:new({
      ui = mock_ui,
    })

    assert.is_not_nil(zooming)

    -- Test mode_to_combo
    local genus, ztype = zooming:mode_to_combo("pagewidth")
    assert.is_not_nil(genus)
    assert.is_not_nil(ztype)

    -- Test combo_to_mode
    local mode = zooming:combo_to_mode(genus, ztype)
    assert.are.equal("pagewidth", mode)
  end)
end)
