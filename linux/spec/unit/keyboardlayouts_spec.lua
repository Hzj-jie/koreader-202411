describe("Keyboard Layouts data modules", function()
  local util, lfs

  local function getLayoutFiles()
    local dir_path = "frontend/ui/data/keyboardlayouts"
    local files = {}
    for file in lfs.dir(dir_path) do
      if file:match("%.lua$") then
        local name = file:sub(1, -5)
        table.insert(files, name)
      end
    end
    table.sort(files)
    return files
  end

  setup(function()
    require("commonrequire")
    util = require("util")
    lfs = require("libs/libkoreader-lfs")
  end)

  it(
    "should dynamically discover and load all keyboard layout files without error",
    function()
      local layout_files = getLayoutFiles()
      assert.is_true(
        #layout_files > 0,
        "No keyboard layout files found in directory"
      )

      for _, name in ipairs(layout_files) do
        local module_path = "ui/data/keyboardlayouts/" .. name
        local ok, layout = pcall(require, module_path)
        assert.is_true(ok, "Failed to require layout: " .. name)
        assert.is_table(
          layout,
          "Layout module did not return a table: " .. name
        )
      end
    end
  )

  it(
    "should ensure requiring dynamically discovered layouts does not leak global variables",
    function()
      local initial_globals = {}
      for k in pairs(_G) do
        initial_globals[k] = true
      end

      local layout_files = getLayoutFiles()
      for _, name in ipairs(layout_files) do
        local module_path = "ui/data/keyboardlayouts/" .. name
        require(module_path)
      end

      for k in pairs(_G) do
        assert.is_true(
          initial_globals[k] == true,
          "Leaked global variable '" .. tostring(k) .. "' during layout loading"
        )
      end
    end
  )

  it(
    "should ensure table isolation across dynamically discovered layout copies",
    function()
      local layout_files = getLayoutFiles()
      local loaded_layouts = {}
      for _, name in ipairs(layout_files) do
        local module_path = "ui/data/keyboardlayouts/" .. name
        local layout = util.copyRequire(module_path)
        loaded_layouts[name] = layout
      end

      -- Mutate en_keyboard copy and verify no other layout table is altered
      local en_layout = loaded_layouts["en_keyboard"]
      if en_layout then
        local rows = en_layout.layout or en_layout
        local original_val = rows[1]
        rows[1] = { "MUTATED_TEST_KEY" }

        for name, other_layout in pairs(loaded_layouts) do
          if name ~= "en_keyboard" then
            local other_rows = other_layout.layout or other_layout
            assert.are_not.same(
              { "MUTATED_TEST_KEY" },
              other_rows[1],
              "Mutation leaked into layout: " .. name
            )
          end
        end

        -- Restore
        rows[1] = original_val
      end
    end
  )

  it(
    "should verify layout table structures contain valid fields or data for all discovered layouts",
    function()
      local layout_files = getLayoutFiles()
      for _, name in ipairs(layout_files) do
        local module_path = "ui/data/keyboardlayouts/" .. name
        local layout = require(module_path)
        assert.is_table(layout, "Layout table is missing for " .. name)
        assert.is_true(
          #layout > 0 or layout.layout ~= nil or next(layout) ~= nil,
          "Empty layout table: " .. name
        )
      end
    end
  )
end)
