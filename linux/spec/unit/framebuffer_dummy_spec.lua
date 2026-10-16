-- luacheck: ignore 122
describe("FramebufferDummy module", function()
  local FramebufferDummy, BB

  setup(function()
    require("commonrequire")
    BB = require("ffi/blitbuffer")
    FramebufferDummy = require("ffi/framebuffer_dummy")
  end)

  it("should initialize dummy framebuffer with 600x800 blitbuffer", function()
    local fb = FramebufferDummy:new()
    assert.is_table(fb)
    assert.is_not_nil(fb.bb)
    assert.are.equal(600, fb.bb:getWidth())
    assert.are.equal(800, fb.bb:getHeight())
    fb.bb:free()
  end)

  it(
    "should allocate fresh buffers on _newBB without flash emulation",
    function()
      local fb = FramebufferDummy:new()
      fb:_newBB(400, 600)
      assert.is_not_nil(fb.bb)
      assert.is_not_nil(fb.invert_bb)
      assert.are.equal(400, fb.bb:getWidth())
      assert.are.equal(600, fb.bb:getHeight())
      fb.bb:free()
      fb.invert_bb:free()
    end
  )

  it("supports EMULATE_READER_FLASH environment flag", function()
    local orig_getenv = os.getenv
    os.getenv = function(var)
      if var == "EMULATE_READER_FLASH" then
        return "1"
      end
      return orig_getenv(var)
    end
    finally(function()
      os.getenv = orig_getenv
    end)

    local fb = FramebufferDummy:new()
    fb:_newBB(300, 400)
    assert.is_not_nil(fb.bb)
    assert.is_not_nil(fb.invert_bb)
    assert.are.equal(300, fb.bb:getWidth())
    assert.are.equal(400, fb.bb:getHeight())
    fb.bb:free()
    fb.invert_bb:free()
  end)
end)
