-- luacheck: ignore 122
describe("FindHistory plugin", function()
  local FindHistory
  local UIManager, ReadHistory, lfs

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FindHistory = require("plugins/findhistory.koplugin/main")
    UIManager = require("ui/uimanager")
    ReadHistory = require("readhistory")
    lfs = require("libs/libkoreader-lfs")
  end)

  it("should initialize FindHistory plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })
    assert.is_table(fh)
  end)

  it("should register menu item in main menu", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })

    local menu_items = {}
    fh:addToMainMenu(menu_items)
    assert.is_table(menu_items.findhistory)
    assert.is_string(menu_items.findhistory.text)
    assert.is_function(menu_items.findhistory.callback)
  end)

  it("should open MultiConfirmBox on menu callback", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })

    local menu_items = {}
    fh:addToMainMenu(menu_items)

    local shown_dialog
    local old_show = UIManager.show
    UIManager.show = function(_, widget)
      shown_dialog = widget
    end

    menu_items.findhistory.callback()
    UIManager.show = old_show

    assert.is_table(shown_dialog)
    assert.is_string(shown_dialog.text)
    assert.is_function(shown_dialog.choice1_callback)
    assert.is_function(shown_dialog.choice2_callback)
  end)

  it("handles restoreHistory success and failure paths", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })
    local menu_items = {}
    fh:addToMainMenu(menu_items)

    local shown_dialog
    local old_show = UIManager.show
    UIManager.show = function(_, widget)
      shown_dialog = widget
    end
    menu_items.findhistory.callback()

    -- 1. Success path: os.execute("mv ...") returns 0
    local old_execute = os.execute
    local old_reload = ReadHistory.reload
    local reload_called = false
    os.execute = function()
      return 0
    end
    ReadHistory.reload = function()
      reload_called = true
    end

    shown_dialog.choice2_callback()
    assert.is_true(reload_called)
    assert.are.equal(0, ReadHistory.last_read_time)
    assert.is_table(shown_dialog)
    assert.is_truthy(shown_dialog.text:find("restored"))

    -- 2. Failure path: os.execute returns 1
    os.execute = function()
      return 1
    end
    menu_items.findhistory.callback()
    shown_dialog.choice2_callback()
    assert.is_table(shown_dialog)
    assert.is_truthy(shown_dialog.text:find("Failed to restore"))

    os.execute = old_execute
    ReadHistory.reload = old_reload
    UIManager.show = old_show
  end)

  it("handles buildHistory confirmation when backup file exists", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local fh = FindHistory:new({
      ui = mock_ui,
    })
    local menu_items = {}
    fh:addToMainMenu(menu_items)

    local shown_dialog
    local old_show = UIManager.show
    UIManager.show = function(_, widget)
      shown_dialog = widget
    end
    menu_items.findhistory.callback()

    local old_attr = lfs.attributes
    lfs.attributes = function()
      return { mode = "file" }
    end

    shown_dialog.choice1_callback()
    assert.is_table(shown_dialog)
    assert.is_truthy(
      shown_dialog.text:find("Found an existing history backup file")
    )
    assert.is_function(shown_dialog.ok_callback)

    lfs.attributes = old_attr
    UIManager.show = old_show
  end)

  it(
    "extracts clean file path without single quotes from stat output (fails: line 32 single-quoted stat)",
    function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local fh = FindHistory:new({
        ui = mock_ui,
      })
      local menu_items = {}
      fh:addToMainMenu(menu_items)

      local shown_dialog
      local old_show = UIManager.show
      UIManager.show = function(_, widget)
        shown_dialog = widget
      end
      menu_items.findhistory.callback()

      -- Simulate backup file not existing so backupAndBuildHistory proceeds directly
      local old_attr = lfs.attributes
      lfs.attributes = function()
        return nil
      end

      local old_execute = os.execute
      os.execute = function()
        return 0
      end

      local old_run_with = UIManager.runWith
      UIManager.runWith = function(_, fn)
        fn()
      end

      -- Output from GNU stat -c '%N %Y' quotes the file path with '%N'
      local stat_output =
        "'/home/books/novel.sdr/metadata.epub.lua' 1700000000\n"
      local mock_file = {
        lines = function()
          return coroutine.wrap(function()
            coroutine.yield(stat_output)
          end)
        end,
        close = function() end,
      }

      local old_popen = io.popen
      io.popen = function()
        return mock_file
      end

      local old_flush = ReadHistory._flush
      local old_reload = ReadHistory.reload
      ReadHistory._flush = function() end
      ReadHistory.reload = function() end

      shown_dialog.choice1_callback()

      io.popen = old_popen
      os.execute = old_execute
      lfs.attributes = old_attr
      UIManager.show = old_show
      UIManager.runWith = old_run_with
      ReadHistory._flush = old_flush
      ReadHistory.reload = old_reload

      assert.is_table(ReadHistory.hist)
      assert.are.equal(1, #ReadHistory.hist)
      assert.are.equal(1700000000, ReadHistory.hist[1].time)
      -- Production bug in findhistory main.lua line 32:
      -- stat -c '%N %Y' formats the filename with '%N', which outputs single-quoted filenames.
      -- The regex line:match("(.+) (%d+)") captures the single quotes into f, and getFilePathFromMetadata
      -- retains the single quotes, yielding "'/home/books/novel.epub'" instead of "/home/books/novel.epub".
      assert.are.equal("/home/books/novel.epub", ReadHistory.hist[1].file)
    end
  )
end)
