describe("Merge Logic Tie-Break (Issue #39)", function()
  local annotations_mod, test_utils, utils_mod, json, util
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_tiebreak_tmp"
  local old_getDataDir
  local local_file = test_data_dir .. "/local.json"
  local last_sync_file = test_data_dir .. "/last_sync.json"
  local income_file = test_data_dir .. "/income.json"

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")
    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    utils_mod = require("plugins/AnnotationSync.koplugin/utils")
    json = require("json")
    util = require("util")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  teardown(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
  end)

  before_each(function()
    os.remove(local_file)
    os.remove(last_sync_file)
    os.remove(income_file)
  end)

  local function write_json(path, data)
    util.writeToFile(json.encode(data), path)
  end

  local function create_mock_ann(
    page,
    note,
    deleted,
    datetime,
    datetime_updated
  )
    return {
      page = page or 1,
      pos0 = { page = page or 1, x = 10, y = 20 },
      pos1 = { page = page or 1, x = 100, y = 40 },
      text = "Test Annotation",
      note = note,
      deleted = deleted,
      datetime = datetime or "2026-01-01 12:00:00",
      datetime_updated = datetime_updated or datetime or "2026-01-01 12:00:00",
    }
  end

  local function create_mock_bookmark(
    page,
    text,
    deleted,
    datetime,
    datetime_updated
  )
    return {
      page = page,
      deleted = deleted,
      datetime = datetime or "2026-01-01 12:00:00",
      datetime_updated = datetime_updated or datetime or "2026-01-01 12:00:00",
      text = text or ("Bookmark on page " .. page),
    }
  end

  it(
    "favors local ACTIVE highlight over remote DELETED when timestamps are identical",
    function()
      local timestamp = "2026-01-01 12:00:00"
      local local_ann = create_mock_ann(1, "Local Active", false, timestamp)
      local income_ann = create_mock_ann(1, "Remote Deleted", true, timestamp)

      write_json(local_file, { local_ann })
      write_json(last_sync_file, { local_ann })
      write_json(income_file, { income_ann })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("Local Active", active[1].note)
      assert.is_falsy(active[1].deleted)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.is_falsy(written[1].deleted)
      assert.are.equal("Local Active", written[1].note)
    end
  )

  it(
    "favors local DELETED highlight over remote ACTIVE when timestamps are identical",
    function()
      local timestamp = "2026-01-01 12:00:00"
      local local_ann = create_mock_ann(1, "Local Deleted", true, timestamp)
      local income_ann = create_mock_ann(1, "Remote Active", false, timestamp)

      write_json(local_file, { local_ann })
      write_json(last_sync_file, { income_ann })
      write_json(income_file, { income_ann })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(0, #active)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.is_true(written[1].deleted)
      assert.are.equal("Local Deleted", written[1].note)
    end
  )

  it(
    "favors local ACTIVE bookmark over remote DELETED when timestamps are identical",
    function()
      local timestamp = "2026-01-01 12:00:00"
      local page = 5
      local local_bm =
        create_mock_bookmark(page, "Local Bookmark", false, timestamp)
      local income_bm =
        create_mock_bookmark(page, "Remote Bookmark", true, timestamp)

      write_json(local_file, { local_bm })
      write_json(last_sync_file, { local_bm })
      write_json(income_file, { income_bm })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("Local Bookmark", active[1].text)
      assert.is_falsy(active[1].deleted)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.is_falsy(written[1].deleted)
      assert.are.equal("Local Bookmark", written[1].text)
    end
  )

  it(
    "retains 'Latest-Wins' for non-identical timestamps (Remote newer)",
    function()
      local local_ann =
        create_mock_ann(1, "Local Old", false, "2026-01-01 12:00:00")
      local income_ann =
        create_mock_ann(1, "Remote Newer", false, "2026-01-01 12:00:01")

      write_json(local_file, { local_ann })
      write_json(last_sync_file, { local_ann })
      write_json(income_file, { income_ann })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("Remote Newer", active[1].note)
      assert.are.equal("2026-01-01 12:00:01", active[1].datetime_updated)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.are.equal("Remote Newer", written[1].note)
      assert.are.equal("2026-01-01 12:00:01", written[1].datetime_updated)
    end
  )

  it(
    "retains 'Latest-Wins' for non-identical timestamps (Local newer)",
    function()
      local local_ann =
        create_mock_ann(1, "Local Newer", false, "2026-01-01 12:00:01")
      local income_ann =
        create_mock_ann(1, "Remote Old", false, "2026-01-01 12:00:00")

      write_json(local_file, { local_ann })
      write_json(last_sync_file, { income_ann })
      write_json(income_file, { income_ann })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("Local Newer", active[1].note)
      assert.are.equal("2026-01-01 12:00:01", active[1].datetime_updated)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.are.equal("Local Newer", written[1].note)
      assert.are.equal("2026-01-01 12:00:01", written[1].datetime_updated)
    end
  )

  describe("is_before comparator unit behavior", function()
    it("orders earlier timestamps before later timestamps", function()
      local older = { datetime = "2026-01-01 10:00:00" }
      local newer = { datetime = "2026-01-01 11:00:00" }
      assert.is_true(annotations_mod.is_before(older, newer))
      assert.is_false(annotations_mod.is_before(newer, older))
    end)

    it("prefers datetime_updated over datetime", function()
      local a = {
        datetime = "2026-01-01 10:00:00",
        datetime_updated = "2026-01-01 12:00:00",
      }
      local b = { datetime = "2026-01-01 11:00:00" }
      assert.is_false(annotations_mod.is_before(a, b))
      assert.is_true(annotations_mod.is_before(b, a))
    end)

    it(
      "orders missing timestamps before timestamped entries without comparing number with string",
      function()
        local missing = {}
        local timestamped = { datetime = "2026-01-01 10:00:00" }
        assert.is_true(annotations_mod.is_before(missing, timestamped))
        assert.is_false(annotations_mod.is_before(timestamped, missing))
      end
    )
  end)
end)
