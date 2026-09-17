describe("CachedTable module", function()
  local CachedTable

  setup(function()
    require("commonrequire")
    CachedTable = require("cachedtable")
  end)
  it("allows reading initial fields without triggering resolver", function()
    local called = false
    local t = CachedTable:new(function()
      called = true
      return { foo = "bar" }
    end, { location = "hash", id = 123 })

    assert.is_false(called)
    assert.is_false(CachedTable.isResolved(t))
    assert.are.equal("hash", t.location)
    assert.are.equal(123, t.id)
    assert.is_false(called)
    assert.is_false(CachedTable.isResolved(t))
  end)

  it(
    "evaluates resolver on demand when unpopulated field is accessed",
    function()
      local call_count = 0
      local t = CachedTable:new(function()
        call_count = call_count + 1
        return {
          file = "/path/to/sidecar.lua",
          dir = "/path/to/sdr",
        }
      end, { location = "hash" })

      assert.are.equal(0, call_count)
      assert.is_false(CachedTable.isResolved(t))

      -- Trigger resolution by accessing an unpopulated field
      assert.are.equal("/path/to/sidecar.lua", t.file)
      assert.are.equal(1, call_count)
      assert.is_true(CachedTable.isResolved(t))

      -- Accessing other resolved fields reuses cached values without calling resolver again
      assert.are.equal("/path/to/sdr", t.dir)
      assert.are.equal(1, call_count)

      -- Accessing previously accessed field reuses cached values
      assert.are.equal("/path/to/sidecar.lua", t.file)
      assert.are.equal(1, call_count)
    end
  )

  it("handles resolver returning nil gracefully", function()
    local call_count = 0
    local t = CachedTable:new(function()
      call_count = call_count + 1
      return nil
    end, { location = "hash" })

    assert.is_false(CachedTable.isResolved(t))
    assert.is_nil(t.file)
    assert.are.equal(1, call_count)
    assert.is_true(CachedTable.isResolved(t))

    -- Subsequent accesses do not re-run resolver
    assert.is_nil(t.dir)
    assert.is_nil(t.unknown)
    assert.are.equal(1, call_count)
  end)

  it("handles missing keys in resolved data", function()
    local call_count = 0
    local t = CachedTable:new(function()
      call_count = call_count + 1
      return { a = 1 }
    end)

    assert.is_nil(t.b)
    assert.are.equal(1, call_count)
    assert.is_true(CachedTable.isResolved(t))

    assert.are.equal(1, t.a)
    assert.is_nil(t.b)
    assert.is_nil(t.c)
    assert.are.equal(1, call_count)
  end)

  it("supports force resolution via CachedTable.resolve", function()
    local call_count = 0
    local t = CachedTable:new(function()
      call_count = call_count + 1
      return { val = 42 }
    end)

    assert.is_false(CachedTable.isResolved(t))
    local resolved_t = CachedTable.resolve(t)
    assert.are.equal(t, resolved_t)
    assert.is_true(CachedTable.isResolved(t))
    assert.are.equal(1, call_count)

    assert.are.equal(42, t.val)
    assert.are.equal(1, call_count)

    -- Calling resolve again is a no-op
    CachedTable.resolve(t)
    assert.are.equal(1, call_count)
  end)

  it(
    "supports dot notation CachedTable.new as well as colon notation",
    function()
      local t1 = CachedTable:new(function()
        return { x = 10 }
      end, { type = "colon" })
      local t2 = CachedTable.new(function()
        return { x = 20 }
      end, { type = "dot" })

      assert.are.equal("colon", t1.type)
      assert.are.equal(10, t1.x)
      assert.are.equal("dot", t2.type)
      assert.are.equal(20, t2.x)
    end
  )

  it("asserts when resolver is not a function", function()
    assert.has_error(function()
      CachedTable:new(nil)
    end)
    assert.has_error(function()
      CachedTable:new("not a function")
    end)
  end)

  it(
    "maintains separate resolution state across independent instances",
    function()
      local count1 = 0
      local count2 = 0
      local t1 = CachedTable:new(function()
        count1 = count1 + 1
        return { name = "t1" }
      end, { tag = 1 })
      local t2 = CachedTable:new(function()
        count2 = count2 + 1
        return { name = "t2" }
      end, { tag = 2 })

      assert.are.equal(1, t1.tag)
      assert.are.equal(2, t2.tag)
      assert.is_false(CachedTable.isResolved(t1))
      assert.is_false(CachedTable.isResolved(t2))

      assert.are.equal("t1", t1.name)
      assert.is_true(CachedTable.isResolved(t1))
      assert.is_false(CachedTable.isResolved(t2))
      assert.are.equal(1, count1)
      assert.are.equal(0, count2)

      assert.are.equal("t2", t2.name)
      assert.is_true(CachedTable.isResolved(t2))
      assert.are.equal(1, count1)
      assert.are.equal(1, count2)
    end
  )

  it(
    "handles manual property assignment before and after resolution",
    function()
      local t = CachedTable:new(function()
        return { auto = "resolved" }
      end, { initial = "init" })

      t.manual_before = "before"
      assert.is_false(CachedTable.isResolved(t))
      assert.are.equal("before", t.manual_before)
      assert.is_false(CachedTable.isResolved(t))

      assert.are.equal("resolved", t.auto)
      assert.is_true(CachedTable.isResolved(t))

      t.manual_after = "after"
      assert.are.equal("after", t.manual_after)
    end
  )

  it(
    "does not clobber initial fields or manual assignments when resolved",
    function()
      local t = CachedTable:new(function()
        return {
          init_key = "from_resolver",
          manual_key = "from_resolver",
          new_key = "from_resolver",
        }
      end, { init_key = "initial_val" })

      t.manual_key = "manual_val"

      assert.is_false(CachedTable.isResolved(t))
      -- Accessing new_key triggers resolution
      assert.are.equal("from_resolver", t.new_key)
      assert.is_true(CachedTable.isResolved(t))

      -- Ensure initial_val and manual_val were NOT overwritten
      assert.are.equal("initial_val", t.init_key)
      assert.are.equal("manual_val", t.manual_key)
    end
  )

  it("supports iterating over keys via CachedTable.pairs", function()
    local call_count = 0
    local t = CachedTable:new(function()
      call_count = call_count + 1
      return { b = 2, c = 3 }
    end, { a = 1 })

    assert.is_false(CachedTable.isResolved(t))

    local collected = {}
    for k, v in CachedTable.pairs(t) do
      collected[k] = v
    end

    assert.is_true(CachedTable.isResolved(t))
    assert.are.equal(1, call_count)
    assert.are.same({ a = 1, b = 2, c = 3 }, collected)
  end)

  it("handles resolver error gracefully via pcall", function()
    local t = CachedTable:new(function()
      error("resolver failure")
    end, { fallback = "safe" })

    assert.is_false(CachedTable.isResolved(t))
    -- Should not throw an unhandled error
    assert.is_nil(t.missing)
    assert.is_true(CachedTable.isResolved(t))
    assert.are.equal("safe", t.fallback)
  end)
end)
