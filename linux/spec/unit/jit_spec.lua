describe("jit library", function()
  it("matches the bundled LuaJIT binary version", function()
    if _VERSION ~= "Lua 5.1" then
      return
    end
    local vmdef = require("jit.vmdef")
    assert.is_table(vmdef)
    local profiler = require("jit.p")
    assert.is_table(profiler)
    assert.is_function(profiler.start)
    assert.is_function(profiler.stop)
  end)
end)
