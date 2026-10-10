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

  it(
    "does not leave internal __orderedIndex key on table when loop breaks early",
    function()
      local t = { a = 1, b = 2, c = 3, d = 4 }
      for k in orderedPairs(t) do
        if k == "b" then
          break
        end
      end

      -- In expected behavior, early exit should not leave hidden internal keys on the caller table
      -- In production, orderedNext attaches __orderedIndex to t and only clears it at end of loop
      assert.is_nil(rawget(t, "__orderedIndex"))
    end
  )

  it("preserves pre-existing user __orderedIndex key on the table", function()
    local t = { a = 1, b = 2, __orderedIndex = "important_user_value" }
    for _ in orderedPairs(t) do
      -- Iterate through all elements
    end

    -- In expected behavior, user's key should not be clobbered and deleted
    assert.are.equal("important_user_value", rawget(t, "__orderedIndex"))
  end)
end)
