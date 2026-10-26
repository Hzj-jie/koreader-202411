-- luacheck: ignore 122
local ffi
local S

describe("ffi/SDL2_0 module", function()
  local orig_SDL
  local toluastring_fn

  local function get_upval(fn, name)
    local i = 1
    while true do
      local n, v = debug.getupvalue(fn, i)
      if not n then
        return nil
      end
      if n == name then
        return i, v
      end
      i = i + 1
    end
  end

  local function set_upval(fn, name, val)
    local i = get_upval(fn, name)
    if i then
      debug.setupvalue(fn, i, val)
    end
  end

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    S = require("ffi/SDL2_0")

    local _, sdl_upval = get_upval(S.waitForEvent, "SDL")
    orig_SDL = sdl_upval
    local _, t_fn = get_upval(S.waitForEvent, "toluastring")
    toluastring_fn = t_fn
  end)

  after_each(function()
    set_upval(S.waitForEvent, "SDL", orig_SDL)
    if toluastring_fn then
      set_upval(toluastring_fn, "SDL", orig_SDL)
    end
  end)

  it("returns timeout error when no event arrives", function()
    local mock_SDL = setmetatable({
      SDL_WaitEventTimeout = function()
        return 0
      end,
    }, {
      __index = orig_SDL,
    })

    set_upval(S.waitForEvent, "SDL", mock_SDL)
    local ok, err = S.waitForEvent(0, 500)
    assert.is_false(ok)
    assert.are.equal(ffi.C.ETIME, err)
  end)

  it("frees dropped file memory via SDL_free on SDL_DROPFILE", function()
    local dummy_str = ffi.new("char[16]", "/path/book.epub")
    local freed = false

    local mock_SDL = setmetatable({
      SDL_WaitEventTimeout = function(ev)
        ev.type = orig_SDL.SDL_DROPFILE
        ev.drop.file = dummy_str
        return 1
      end,
      SDL_free = function(ptr)
        if ffi.cast("uintptr_t", ptr) == ffi.cast("uintptr_t", dummy_str) then
          freed = true
        end
      end,
    }, {
      __index = orig_SDL,
    })

    set_upval(S.waitForEvent, "SDL", mock_SDL)
    if toluastring_fn then
      set_upval(toluastring_fn, "SDL", mock_SDL)
    end

    S.waitForEvent(0, 1000)

    assert.is_true(freed)
  end)
end)
