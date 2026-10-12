-- luacheck: ignore 122
require("commonrequire")
local SDL = require("ffi/SDL2_0")
local SDLDevice = require("device/sdl/device")

describe("SDL device", function()
  local orig_execute = os.execute
  local orig_set_fullscreen = SDL.setWindowFullscreen
  local fullscreen_mode_set = nil

  before_each(function()
    fullscreen_mode_set = nil
    SDL.setWindowFullscreen = function(mode)
      fullscreen_mode_set = mode
      return true
    end
  end)

  after_each(function()
    os.execute = orig_execute
    SDL.setWindowFullscreen = orig_set_fullscreen
  end)

  describe("properties and capabilities", function()
    it("reports correct capabilities for Emulator", function()
      assert.is_true(SDLDevice:isSDL())
      assert.is_true(SDLDevice:isEmulator())
      assert.is_true(SDLDevice:hasColorScreen())
      assert.is_true(SDLDevice:hasEinkScreen())
      assert.is_false(SDLDevice:isDefaultFullscreen())
      assert.is_true(SDLDevice:supportsScreensaver())
    end)

    it(
      "manages page press pressure and feedback settings on Emulator",
      function()
        SDLDevice:setPagePressPressure(1)
        assert.are.equal(1, SDLDevice:pagePressPressure())

        SDLDevice:setPagePressFeedback(2)
        assert.are.equal(2, SDLDevice:pagePressFeedback())

        assert.has_error(function()
          SDLDevice:setPagePressPressure(5)
        end)
        assert.has_error(function()
          SDLDevice:setPagePressFeedback(5)
        end)
      end
    )
  end)

  describe("setDateTime", function()
    local executed_cmds = {}

    before_each(function()
      executed_cmds = {}
      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end
    end)

    it("executes date and hwclock for complete date and time", function()
      local res = SDLDevice:setDateTime(2026, 10, 10, 16, 20, 0)
      assert.is_true(res)
      assert.are.equal("date -s '2026-10-10 16:20:0'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("executes date time-only when date parts omitted", function()
      local res = SDLDevice:setDateTime(nil, nil, nil, 8, 30, 0)
      assert.is_true(res)
      assert.are.equal("date -s '8:30'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("returns true without executing when hour or min is nil", function()
      local res = SDLDevice:setDateTime(2026, 10, 10, nil, 30, 0)
      assert.is_true(res)
      assert.are.equal(0, #executed_cmds)
    end)
  end)

  describe("toggleFullscreen", function()
    it("toggles fullscreen mode on standard desktop SDL device", function()
      local dev = SDLDevice:extend({
        fullscreen = nil,
      })
      dev:toggleFullscreen()
      assert.is_true(dev.fullscreen)
      assert.is_true(fullscreen_mode_set)

      dev:toggleFullscreen()
      assert.is_false(dev.fullscreen)
    end)
  end)

  describe("openLink", function()
    it("should escape single quotes in link", function()
      -- Bug: line 92 does `runCommand(tool .. " '" .. link .. "'")`.
      -- If link contains single quotes, it breaks the shell argument quoting.
      local executed_cmd = nil
      os.execute = function(cmd)
        executed_cmd = cmd
        return 0
      end

      local dev = SDLDevice:extend({
        canOpenLink = function()
          return true, "xdg-open"
        end,
      })

      dev:openLink("https://example.com/path?q=don't")
      assert.is_not_nil(executed_cmd)
      -- If properly escaped, the command should not contain an unescaped single quote
      -- that breaks the shell string. For example, `'https://example.com/path?q=don'\''t'`
      assert.is_nil(
        executed_cmd:match("xdg%-open 'https://example%.com/path%?q=don't'"),
        "single quotes in link should be escaped before passing to shell: "
          .. tostring(executed_cmd)
      )
    end)
  end)
end)
