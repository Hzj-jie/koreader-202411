describe("FindKeyboard module", function()
  local FindKeyboard, lfs

  setup(function()
    require("commonrequire")
    package.unloadAll()

    lfs = require("libs/libkoreader-lfs")
    FindKeyboard = require("plugins/externalkeyboard.koplugin/find-keyboard")
  end)

  it("should check capabilities and return nil for missing device", function()
    local old_open = io.open
    io.open = function(path, mode)
      if path:find("nonexistent") then
        return nil
      end
      return old_open(path, mode)
    end

    local res = FindKeyboard:check("nonexistent_event999")
    assert.is_nil(res)

    io.open = old_open
  end)

  it("should find external keyboards from input events directory", function()
    local old_check = FindKeyboard.check
    FindKeyboard.check = function(self, name)
      if name == "event0" then
        return { event_path = "/dev/input/event0", has_dpad = true }
      end
      return nil
    end

    local old_dir = lfs.dir
    lfs.dir = function(path)
      local files = { "event0", "event1", "mouse0" }
      local idx = 0
      return function()
        idx = idx + 1
        return files[idx]
      end
    end

    local found = FindKeyboard:find()
    assert.is_table(found)
    assert.are.equal(1, #found)
    assert.are.equal("/dev/input/event0", found[1].event_path)

    lfs.dir = old_dir
    FindKeyboard.check = old_check
  end)
end)
