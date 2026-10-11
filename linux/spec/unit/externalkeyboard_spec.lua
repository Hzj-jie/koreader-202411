-- luacheck: ignore 122
describe("FindKeyboard module", function()
  local FindKeyboard

  setup(function()
    require("commonrequire")
    FindKeyboard = require("plugins/externalkeyboard.koplugin/find-keyboard")
  end)

  it("should return nil when device has fewer than 64 keys", function()
    local orig_open = io.open
    io.open = function(path, mode)
      if path:find("capabilities/key$") then
        return {
          read = function()
            -- Only 4 keys enabled
            return "f"
          end,
          close = function() end,
        }
      end
      return orig_open(path, mode)
    end
    finally(function()
      io.open = orig_open
    end)

    local kb = FindKeyboard:check("event0")
    assert.is_nil(kb)
  end)

  it("detects DPAD capability when KEY_UP is set on 64-bit word", function()
    local orig_open = io.open
    io.open = function(path, mode)
      if path:find("capabilities/key$") then
        return {
          read = function()
            -- Word 2: 32 keys (0xffffffff)
            -- Word 1: bit 39 set (KEY_UP = 103, 1ULL << 39 = 0x8000000000)
            -- Word 0: 32 keys (0xffffffff) -> total keys = 64+
            return "ffffffff 8000000000 ffffffff"
          end,
          close = function() end,
        }
      end
      return orig_open(path, mode)
    end
    finally(function()
      io.open = orig_open
    end)

    local kb = FindKeyboard:check("event1")
    assert.is_not_nil(kb)
    assert.are.equal("/dev/input/event1", kb.event_path)
    assert.is_true(kb.has_dpad)
  end)

  it("does not report DPAD capability when only KEY_KP7 is set", function()
    local orig_open = io.open
    io.open = function(path, mode)
      if path:find("capabilities/key$") then
        return {
          read = function()
            -- Word 2: 32 keys (0xffffffff)
            -- Word 1: bit 7 set (KEY_KP7 = 71, 0x80), bit 39 clear (KEY_UP = 0)
            -- Word 0: 32 keys (0xffffffff) -> total keys = 64+
            return "ffffffff 80 ffffffff"
          end,
          close = function() end,
        }
      end
      return orig_open(path, mode)
    end
    finally(function()
      io.open = orig_open
    end)

    local kb = FindKeyboard:check("event2")
    assert.is_not_nil(kb)
    assert.is_false(kb.has_dpad)
  end)
end)
