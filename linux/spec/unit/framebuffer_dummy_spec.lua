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

  it("does not leak blitbuffer when EMULATE_READER_FLASH is enabled", function()
    local fb = FramebufferDummy:new()
    -- Clear initial allocations from :new() / :init()
    if fb.bb then
      fb.bb:free()
      fb.bb = nil
    end

    local created = {}
    local freed = {}
    local orig_new = BB.new
    local orig_free = BB.free
    BB.new = function(...)
      local b = orig_new(...)
      table.insert(created, b)
      return b
    end
    BB.free = function(b)
      freed[b] = true
      return orig_free(b)
    end

    local orig_getenv = os.getenv
    os.getenv = function(var)
      if var == "EMULATE_READER_FLASH" then
        return "1"
      end
      return orig_getenv(var)
    end

    finally(function()
      BB.new = orig_new
      BB.free = orig_free
      os.getenv = orig_getenv
    end)

    fb:_newBB(300, 400)

    for _, b in ipairs(created) do
      local is_held = (fb.bb == b or fb.invert_bb == b)
      assert.is_true(is_held or freed[b] == true)
    end
  end)
end)
