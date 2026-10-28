describe("FileChooser module", function()
  local FileChooser, DocSettings, Screen
  local sample_epub = "spec/front/unit/data/leaves.epub"

  setup(function()
    require("commonrequire")
    -- Make sure canvas context is initialized
    require("document/canvascontext"):init(require("device"))
    FileChooser = require("ui/widget/filechooser")
    DocSettings = require("docsettings")
    Screen = require("device").screen
  end)

  it(
    "should safely sort by percent_natural when sidecar has nil summary table",
    function()
      -- Ensure sidecar has NO summary table (mock or purge first)
      local doc_settings = DocSettings:open(sample_epub)
      doc_settings:save("summary", nil) -- Explicitly nil the summary table!
      doc_settings:save("percent_finished", 0.5)
      doc_settings:close()

      local filechooser = FileChooser:new({
        dimen = Screen:getSize(),
        path = "spec/front/unit/data",
      })

      -- Build mock item list to be sorted
      local items = {
        { text = "leaves.epub", path = sample_epub, attr = { size = 1000 } },
        {
          text = "another.epub",
          path = "spec/front/unit/data/another.epub",
          attr = { size = 2000 },
        },
      }

      -- Get the percent_natural sorting structure
      local collate = filechooser.collates.percent_natural
      assert.is_table(collate)

      -- Initialize items using collate.item_func (which populates item.sort_percent!)
      -- This is the code path containing the bug!
      assert.has_no.errors(function()
        collate.item_func(items[1])
        collate.item_func(items[2])
      end)

      -- Verify sort_percent is populated successfully without raising a nil index error
      assert.is_number(items[1].sort_percent)
      assert.is_number(items[2].sort_percent)

      -- Clean up doc settings cache residues
      DocSettings:open(sample_epub):purge()
    end
  )

  it("should respect instance's show_finished setting", function()
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local original_getStatus = filemanagerutil.getStatus

    filemanagerutil.getStatus = function(path)
      if path == "test_complete.epub" then
        return "complete"
      end
      return "incomplete"
    end

    local fc_show = FileChooser:new({
      dimen = Screen:getSize(),
      show_finished = true,
    })
    assert.is_true(
      fc_show:show_file("test_complete.epub", "test_complete.epub")
    )

    local fc_hide = FileChooser:new({
      dimen = Screen:getSize(),
      show_finished = false,
    })
    assert.is_false(
      fc_hide:show_file("test_complete.epub", "test_complete.epub")
    )

    filemanagerutil.getStatus = original_getStatus
  end)

  describe("path climbing when directory does not exist", function()
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local test_root

    setup(function()
      local tmp = os.getenv("TMPDIR") or "/tmp"
      test_root = tmp .. "/fc_test_" .. os.time()
      lfs.mkdir(test_root)
    end)

    teardown(function()
      local function rm_rf(dir)
        for entry in lfs.dir(dir) do
          if entry ~= "." and entry ~= ".." then
            local p = dir .. "/" .. entry
            local mode = lfs.attributes(p, "mode")
            if mode == "directory" then
              rm_rf(p)
            else
              os.remove(p)
            end
          end
        end
        lfs.rmdir(dir)
      end
      rm_rf(test_root)
    end)

    it("climbs to ancestor on onFolderUp when current directory is deleted", function()
      local x = test_root .. "/x"
      local a = x .. "/a"
      local b = a .. "/b"
      lfs.mkdir(x)
      lfs.mkdir(a)
      lfs.mkdir(b)
      local real_x = ffiUtil.realpath(x)
      local real_a = ffiUtil.realpath(a)
      local real_b = ffiUtil.realpath(b)

      local fc = FileChooser:new({
        dimen = Screen:getSize(),
        path = b,
      })
      assert.are.equal(real_b, fc.path)

      -- Case 1: remove b, onFolderUp climbs to a
      lfs.rmdir(b)
      fc:onFolderUp()
      assert.are.equal(real_a, fc.path)

      -- Case 2: remove both a and recreated b, onFolderUp climbs to x
      lfs.mkdir(b)
      fc:changeToPath(b)
      lfs.rmdir(b)
      lfs.rmdir(a)
      fc:onFolderUp()
      assert.are.equal(real_x, fc.path)
    end)

    it("stays in current directory and refreshes when selecting deleted child folder", function()
      local x = test_root .. "/child_test"
      local child = x .. "/deleted_child"
      lfs.mkdir(x)
      lfs.mkdir(child)
      local real_x = ffiUtil.realpath(x)

      local fc = FileChooser:new({
        dimen = Screen:getSize(),
        path = x,
      })
      assert.are.equal(real_x, fc.path)

      -- Verify deleted_child is in item_table
      local found = false
      for _, it in ipairs(fc.item_table) do
        if it.path == child or it.text == "deleted_child/" then
          found = true
          break
        end
      end
      assert.is_true(found)

      -- Remove deleted_child on disk, then select it via onMenuSelect
      lfs.rmdir(child)
      fc:onMenuSelect({ path = child, is_file = false })

      -- Path remains real_x
      assert.are.equal(real_x, fc.path)

      -- Refreshed item_table no longer contains deleted_child
      local still_found = false
      for _, it in ipairs(fc.item_table) do
        if it.path == child or it.text == "deleted_child/" then
          still_found = true
          break
        end
      end
      assert.is_false(still_found)
    end)
  end)
end)
