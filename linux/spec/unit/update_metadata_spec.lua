-- luacheck: ignore 121 122
local gettext = require("gettext")

describe("update-metadata tool", function()
  setup(function()
    require("commonrequire")
  end)

  it(
    "passes non-nil language code to gettext.changeLang in genAppstream",
    function()
      local orig_package_path = package.path
      local nil_lang_calls = 0
      local orig_change_lang = gettext.changeLang
      gettext.changeLang = function(lang)
        if lang == nil then
          nil_lang_calls = nil_lang_calls + 1
        end
      end

      local orig_popen = io.popen
      io.popen = function()
        return {
          lines = function()
            return coroutine.wrap(function()
              coroutine.yield("es")
            end)
          end,
          close = function() end,
        }
      end

      local orig_open = io.open
      io.open = function(path, mode)
        if mode and mode:find("w") then
          return {
            write = function() end,
            close = function() end,
          }
        end
        return orig_open(path, mode)
      end

      local orig_execute = os.execute
      os.execute = function()
        return 0
      end

      local orig_print = print
      print = function() end

      finally(function()
        package.path = orig_package_path
        gettext.changeLang = orig_change_lang
        io.popen = orig_popen
        io.open = orig_open
        os.execute = orig_execute
        print = orig_print
        _G.metadata_dir = nil
        _G.metadata_file = nil
      end)

      dofile("tools/update-metadata.lua")
      assert.are.equal(0, nil_lang_calls)
    end
  )

  it(
    "does not leak metadata_dir and metadata_file into global scope",
    function()
      local orig_package_path = package.path
      local orig_popen = io.popen
      io.popen = function()
        return {
          lines = function()
            return coroutine.wrap(function()
              coroutine.yield("fr")
            end)
          end,
          close = function() end,
        }
      end

      local orig_open = io.open
      io.open = function(path, mode)
        if mode and mode:find("w") then
          return {
            write = function() end,
            close = function() end,
          }
        end
        return orig_open(path, mode)
      end

      local orig_execute = os.execute
      os.execute = function()
        return 0
      end

      local orig_print = print
      print = function() end

      _G.metadata_dir = nil
      _G.metadata_file = nil

      finally(function()
        package.path = orig_package_path
        io.popen = orig_popen
        io.open = orig_open
        os.execute = orig_execute
        print = orig_print
        _G.metadata_dir = nil
        _G.metadata_file = nil
      end)

      dofile("tools/update-metadata.lua")
      assert.is_nil(_G.metadata_dir)
      assert.is_nil(_G.metadata_file)
    end
  )
end)
