describe("AnnotationSync sync_callback (7-case 3-way merge)", function()
  local annotations_mod, test_utils, utils_mod, json, util
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_callback_tmp"
  local old_getDataDir
  local local_file = test_data_dir .. "/local.json"
  local last_sync_file = test_data_dir .. "/last_sync.json"
  local income_file = test_data_dir .. "/income.json"
  local dummy_doc = { file = "dummy.epub" }

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")
    utils_mod = require("plugins/AnnotationSync.koplugin/utils")
    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
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

  local function create_highlight(
    page,
    x0,
    y0,
    x1,
    y1,
    note,
    datetime,
    datetime_updated,
    deleted
  )
    return {
      page = page,
      pos0 = { page = page, x = x0, y = y0 },
      pos1 = { page = page, x = x1, y = y1 },
      text = "Sample text",
      note = note,
      datetime = datetime or "2026-01-01 10:00:00",
      datetime_updated = datetime_updated or datetime or "2026-01-01 10:00:00",
      deleted = deleted,
    }
  end

  local function create_bookmark(page, datetime, datetime_updated, deleted)
    return {
      page = page,
      text = "Bookmark on page " .. page,
      datetime = datetime or "2026-01-01 10:00:00",
      datetime_updated = datetime_updated or datetime or "2026-01-01 10:00:00",
      deleted = deleted,
    }
  end

  it(
    "Case 1: keeps unchanged annotations present in all three lists",
    function()
      local h1 = create_highlight(1, 10, 20, 100, 40, "note1")
      write_json(local_file, { ["1|10|20||100|40"] = h1 })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h1 })
      write_json(income_file, { ["1|10|20||100|40"] = h1 })

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("note1", active[1].note)
    end
  )

  it("Case 1 (LWW): Remote newer update wins over local older", function()
    local h_local = create_highlight(
      1,
      10,
      20,
      100,
      40,
      "local note",
      "2026-01-01 10:00:00",
      "2026-01-01 10:00:00"
    )
    local h_remote = create_highlight(
      1,
      10,
      20,
      100,
      40,
      "remote note",
      "2026-01-01 10:00:00",
      "2026-01-01 11:00:00"
    )
    write_json(local_file, { ["1|10|20||100|40"] = h_local })
    write_json(last_sync_file, { ["1|10|20||100|40"] = h_local })
    write_json(income_file, { ["1|10|20||100|40"] = h_remote })

    local success, active = annotations_mod.sync_callback(
      dummy_doc,
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("remote note", active[1].note)
  end)

  it("Case 1 (LWW): Local newer update wins over remote older", function()
    local h_local = create_highlight(
      1,
      10,
      20,
      100,
      40,
      "local newer",
      "2026-01-01 10:00:00",
      "2026-01-01 12:00:00"
    )
    local h_remote = create_highlight(
      1,
      10,
      20,
      100,
      40,
      "remote older",
      "2026-01-01 10:00:00",
      "2026-01-01 11:00:00"
    )
    write_json(local_file, { ["1|10|20||100|40"] = h_local })
    write_json(last_sync_file, { ["1|10|20||100|40"] = h_remote })
    write_json(income_file, { ["1|10|20||100|40"] = h_remote })

    local success, active = annotations_mod.sync_callback(
      dummy_doc,
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("local newer", active[1].note)
  end)

  it("Case 2: keeps local additions and prepares them for upload", function()
    local h_new = create_highlight(2, 5, 10, 50, 30, "added locally")
    write_json(local_file, { ["2|5|10||50|30"] = h_new })
    write_json(last_sync_file, {})
    write_json(income_file, {})

    local success, active = annotations_mod.sync_callback(
      dummy_doc,
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("added locally", active[1].note)

    local written = utils_mod.read_json(local_file)
    assert.is_table(written["2|5|10||50|30"])
    assert.is_nil(written["2|5|10||50|30"].deleted)
  end)

  it("Case 3: pulls remote additions into local active list", function()
    local h_remote = create_highlight(3, 15, 25, 80, 50, "added remotely")
    write_json(local_file, {})
    write_json(last_sync_file, {})
    write_json(income_file, { ["3|15|25||80|50"] = h_remote })

    local success, active = annotations_mod.sync_callback(
      dummy_doc,
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("added remotely", active[1].note)
  end)

  it(
    "Case 4: merges concurrent additions of the same highlight without duplicates",
    function()
      local h_local =
        create_highlight(1, 10, 20, 100, 40, "same location local")
      local h_remote =
        create_highlight(1, 10, 20, 100, 40, "same location remote")
      write_json(local_file, { ["1|10|20||100|40"] = h_local })
      write_json(last_sync_file, {})
      write_json(income_file, { ["1|10|20||100|40"] = h_remote })

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
    end
  )

  it("Case 5: detects local deletion and turns it into a tombstone", function()
    local h_synced = create_highlight(1, 10, 20, 100, 40, "deleted locally")
    local h_kept = create_highlight(1, 10, 50, 100, 70, "kept locally")
    write_json(local_file, { ["1|10|50||100|70"] = h_kept }) -- user deleted h_synced
    write_json(last_sync_file, {
      ["1|10|20||100|40"] = h_synced,
      ["1|10|50||100|70"] = h_kept,
    })
    write_json(income_file, {
      ["1|10|20||100|40"] = h_synced,
      ["1|10|50||100|70"] = h_kept,
    })

    local success, active = annotations_mod.sync_callback(
      dummy_doc,
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("kept locally", active[1].note)

    local written = utils_mod.read_json(local_file)
    assert.is_table(written["1|10|20||100|40"])
    assert.is_true(written["1|10|20||100|40"].deleted)
    assert.is_string(written["1|10|20||100|40"].datetime_updated)
    assert.is_nil(written["1|10|50||100|70"].deleted)
  end)

  it(
    "Case 6: preserves local highlight and does not delete on remote omission",
    function()
      local h_synced = create_highlight(1, 10, 20, 100, 40, "synced highlight")
      write_json(local_file, { ["1|10|20||100|40"] = h_synced })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h_synced })
      write_json(income_file, {}) -- remote does not have it (omitted, no tombstone)

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("synced highlight", active[1].note)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written["1|10|20||100|40"])
      assert.is_nil(written["1|10|20||100|40"].deleted)
    end
  )

  it(
    "Case 6 (with tombstone): receives remote tombstone and removes from active",
    function()
      local h_local = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "active locally",
        "2026-01-01 10:00:00",
        "2026-01-01 10:00:00"
      )
      local h_remote_tombstone = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "tombstone",
        "2026-01-01 10:00:00",
        "2026-01-01 11:00:00",
        true
      )
      write_json(local_file, { ["1|10|20||100|40"] = h_local })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h_local })
      write_json(income_file, { ["1|10|20||100|40"] = h_remote_tombstone })

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(0, #active)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written["1|10|20||100|40"])
      assert.is_true(written["1|10|20||100|40"].deleted)
    end
  )

  it(
    "handles remote tombstone for an item local never had without crashing",
    function()
      local h_remote_tombstone = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "tombstone",
        "2026-01-01 10:00:00",
        "2026-01-01 11:00:00",
        true
      )
      write_json(local_file, {})
      write_json(last_sync_file, {})
      write_json(income_file, { ["1|10|20||100|40"] = h_remote_tombstone })

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(0, #active)
    end
  )

  it(
    "skips server upload when remote file is missing and local is empty",
    function()
      write_json(local_file, {})
      -- income_file intentionally missing (simulating 404 / new book)

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_false(success)
      assert.are.equal(0, #active)
    end
  )

  it(
    "orders mixed bookmarks and highlights strictly by page-then-position",
    function()
      local bm = create_bookmark(1)
      local hl1 = create_highlight(1, 10, 50, 100, 70, "highlight 1")
      local hl2 = create_highlight(2, 5, 10, 50, 30, "highlight 2")

      write_json(local_file, {
        ["BOOKMARK|1"] = bm,
        ["1|10|50||100|70"] = hl1,
        ["2|5|10||50|30"] = hl2,
      })
      write_json(last_sync_file, {})
      write_json(income_file, {})

      local success, active = annotations_mod.sync_callback(
        dummy_doc,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(success)
      assert.are.equal(3, #active)
      -- Page 1 Bookmark comes before Page 1 Highlight
      assert.is_nil(active[1].pos0)
      assert.are.equal(1, active[1].page)
      -- Page 1 Highlight comes second
      assert.is_table(active[2].pos0)
      assert.are.equal(1, active[2].page)
      -- Page 2 Highlight comes third
      assert.are.equal(2, active[3].page)
    end
  )
end)
