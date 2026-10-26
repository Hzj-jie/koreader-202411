describe("CalibreExtensions module", function()
  local CalibreExtensions

  setup(function()
    require("commonrequire")
    CalibreExtensions = require("plugins/calibre.koplugin/extensions")
  end)

  it("should provide valid default outputs and format list", function()
    assert.is_table(CalibreExtensions.outputs)
    assert.are.equal("epub", CalibreExtensions.default_output)

    local ext_list = CalibreExtensions:get()
    assert.is_table(ext_list)
    assert.are.equal("epub", ext_list[1])
    assert.is_true(#ext_list > 10)

    local info = CalibreExtensions:getInfo()
    assert.is_string(info)
    assert.is_true(info:find("^epub, ") ~= nil)
  end)

  it("should prioritize custom user overrides table when provided", function()
    local orig_overrides = CalibreExtensions.user_overrides
    finally(function()
      CalibreExtensions.user_overrides = orig_overrides
    end)

    local custom_table = { "mobi", "azw3", "pdf" }
    CalibreExtensions.user_overrides = custom_table

    assert.are.equal(custom_table, CalibreExtensions:get())
    assert.are.equal("mobi, azw3, pdf", CalibreExtensions:getInfo())
    assert.is_true(CalibreExtensions:isCustom())
  end)

  it("should return false for isCustom when user_overrides is nil", function()
    local orig_overrides = CalibreExtensions.user_overrides
    finally(function()
      CalibreExtensions.user_overrides = orig_overrides
    end)

    CalibreExtensions.user_overrides = nil
    assert.is_false(CalibreExtensions:isCustom())
  end)

  it(
    "returns false for isCustom when user_overrides is a non-table value",
    function()
      local orig_overrides = CalibreExtensions.user_overrides
      finally(function()
        CalibreExtensions.user_overrides = orig_overrides
      end)

      -- If calibre-extensions.lua returns false or a non-table, get() returns default formats.
      CalibreExtensions.user_overrides = false
      assert.is_false(CalibreExtensions:isCustom())
    end
  )
end)
