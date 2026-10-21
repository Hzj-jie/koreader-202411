local orderedPairs

describe("ffi/SortedIteration module", function()
  setup(function()
    require("commonrequire")
    orderedPairs = require("ffi/SortedIteration")
  end)

  it("iterates over table keys in natural sorted order", function()
    local t = { z = 26, a = 1, m = 13 }
    local visited_keys = {}
    local visited_values = {}

    for k, v in orderedPairs(t) do
      table.insert(visited_keys, k)
      table.insert(visited_values, v)
    end

    assert.are.same({ "a", "m", "z" }, visited_keys)
    assert.are.same({ 1, 13, 26 }, visited_values)
    assert.is_nil(t.__orderedIndex)
  end)

  it("handles mixed key types by falling back to string comparison", function()
    local t = { [1] = "one", [2] = "two", apple = "fruit" }
    local keys = {}
    for k in orderedPairs(t) do
      table.insert(keys, tostring(k))
    end

    assert.are.equal(3, #keys)
  end)
end)
