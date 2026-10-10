-- luacheck: ignore 122
local ffi
local S

describe("ffi/SDL2_0 module", function()
  local orig_SDL

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    S = require("ffi/SDL2_0")

    local _, sdl_upval = debug.getupvalue(S.waitForEvent, 3)
    orig_SDL = sdl_upval
  end)

  after_each(function()
    debug.setupvalue(S.waitForEvent, 3, orig_SDL)
  end)

  it("returns timeout error when no event arrives", function()
    local mock_SDL = setmetatable({
      SDL_WaitEventTimeout = function()
        return 0
      end,
    }, {
      __index = orig_SDL,
    })

    debug.setupvalue(S.waitForEvent, 3, mock_SDL)
    local ok, err = S.waitForEvent(0, 500)
    assert.is_false(ok)
    assert.are.equal(ffi.C.ETIME, err)
  end)

  it("frees dropped file memory via SDL_free on SDL_DROPFILE", function()
    local dummy_str = ffi.new("char[16]", "/path/book.epub")
    local freed_ptrs = {}

    local mock_SDL = setmetatable({
      SDL_WaitEventTimeout = function(event)
        event.type = ffi.C.SDL_DROPFILE
        event.drop.file = dummy_str
        return 1
      end,
      SDL_free = function(ptr)
        freed_ptrs[tostring(ptr)] = true
      end,
    }, {
      __index = orig_SDL,
    })

    debug.setupvalue(S.waitForEvent, 3, mock_SDL)

    -- In production lines 520-522:
    --   elseif event.type == SDL.SDL_DROPFILE then
    --     local dropped_file_path = ffi.string(event.drop.file)
    --     genEmuEvent(C.EV_SDL, SDL.SDL_DROPFILE, dropped_file_path)
    -- SDL-allocated event.drop.file char* is never freed with SDL_free, leaking memory.
    S.waitForEvent(0, 1000)

    assert.is_true(freed_ptrs[tostring(dummy_str)])
  end)
end)
