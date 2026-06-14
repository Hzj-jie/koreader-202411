describe("key", function()
  local Key

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    package.loaded["device/key"] = nil
    Key = require("device/key")
  end)

  after_each(function()
    package.loaded["device/key"] = nil
  end)

  describe("new", function()
    it("should initialize a new Key instance", function()
      local k = Key:new("K", { Alt = true, Ctrl = false })
      assert.are.equal("K", k.key)
      assert.are_same({ Alt = true, Ctrl = false }, k.modifiers)
      assert.is_true(k.K)
      assert.is_true(k.Alt)
      assert.is_nil(k.Ctrl) -- Ctrl is false, so it shouldn't be set as true on the instance
    end)
  end)

  describe("modifiers helper methods", function()
    it("should correctly report modifier counts and existence", function()
      local k0 = Key:new("K", { Alt = false, Ctrl = false })
      assert.are.equal(0, k0:numOfModifiers())
      assert.is_false(k0:hasModifiers())
      assert.is_false(k0:hasSingleModifier())
      assert.is_false(k0:hasMultipleModifiers())

      local k1 = Key:new("K", { Alt = true, Ctrl = false })
      assert.are.equal(1, k1:numOfModifiers())
      assert.is_true(k1:hasModifiers())
      assert.is_true(k1:hasSingleModifier())
      assert.is_false(k1:hasMultipleModifiers())

      local k2 = Key:new("K", { Alt = true, Ctrl = true })
      assert.are.equal(2, k2:numOfModifiers())
      assert.is_true(k2:hasModifiers())
      assert.is_false(k2:hasSingleModifier())
      assert.is_true(k2:hasMultipleModifiers())
    end)
  end)

  describe("getSequence", function()
    it("should return the key sequence table", function()
      local k = Key:new("K", { Alt = true })
      local seq = k:getSequence()
      -- If the bug exists, seq will be nil and this assert will fail
      assert.is_not_nil(seq)
      assert.are_same({ "Alt", "K" }, seq)
    end)
  end)

  describe("tostring", function()
    it("should return hyphen-separated sequence", function()
      local k = Key:new("K", { Alt = true })
      -- If the bug exists, tostring(k) will fail with an error
      local ok, res = pcall(function() return tostring(k) end)
      assert.is_true(ok)
      assert.are.equal("Alt-K", res)
    end)
  end)

  describe("match", function()
    local k

    before_each(function()
      k = Key:new("K", { Alt = true })
    end)

    it("should match exact key and modifier", function()
      assert.is_true(k:match({ "Alt", "K" }))
    end)

    it("should not match if modifier is missing", function()
      assert.is_false(k:match({ "K" }))
    end)

    it("should not match if extra modifier is present in key but not in sequence", function()
      -- Key has Alt. Sequence requires Alt and K. Matches.
      assert.is_true(k:match({ "Alt", "K" }))

      -- Key has Alt. Sequence only requires K.
      -- Wait, Key:match logic:
      -- "additional modifier keys are pressed, don't match"
      -- If sequence doesn't include 'Alt', but key has 'Alt' pressed, it should NOT match.
      assert.is_false(k:match({ "K" }))
    end)

    it("should match with alternative keys", function()
      assert.is_true(k:match({ "Alt", { "K", "L" } }))
      assert.is_true(k:match({ "Alt", { "J", "K" } }))
      assert.is_false(k:match({ "Alt", { "J", "L" } }))
    end)

    it("should not match if additional modifiers are pressed", function()
      local k_two = Key:new("K", { Alt = true, Ctrl = true })
      -- Sequence only expects Alt+K, but Ctrl is also pressed
      assert.is_false(k_two:match({ "Alt", "K" }))
    end)
  end)
end)
