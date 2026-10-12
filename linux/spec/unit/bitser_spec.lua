local bitser

describe("ffi/bitser module", function()
  setup(function()
    require("commonrequire")
    bitser = require("ffi/bitser")
  end)

  teardown(function()
    bitser.includeMetatables(true)
  end)

  it("serializes and deserializes basic types", function()
    local input = { 123, "hello", true, false, { nested = "data" } }
    local serialized = bitser.dumps(input)
    local output = bitser.loads(serialized)
    assert.are.same(input, output)
  end)

  it("preserves metatables when includeMetatables is enabled", function()
    bitser.includeMetatables(true)
    local mt = { tag = "custom_mt" }
    local input = setmetatable({ x = 10 }, mt)
    local serialized = bitser.dumps(input)
    local output = bitser.loads(serialized)
    assert.are.equal(10, output.x)
    assert.is_not_nil(getmetatable(output))
    assert.are.equal("custom_mt", getmetatable(output).tag)
  end)
end)
