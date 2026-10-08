describe("AnnotationSync sync_callback (7-case 3-way merge)", function()
  local annotations_mod, test_utils, utils_mod, json, util
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_callback_tmp"
  local old_getDataDir
  local local_file = test_data_dir .. "/local.json"
  local last_sync_file = test_data_dir .. "/last_sync.json"
  local income_file = test_data_dir .. "/income.json"

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
      drawer = "lighten",
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
        local_file,
        last_sync_file,
        income_file
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
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("added locally", active[1].note)

    local written = utils_mod.read_json(local_file)
    assert.is_table(written[1])
    assert.is_nil(written[1].deleted)
  end)

  it("Case 3: pulls remote additions into local active list", function()
    local h_remote = create_highlight(3, 15, 25, 80, 50, "added remotely")
    write_json(local_file, {})
    write_json(last_sync_file, {})
    write_json(income_file, { ["3|15|25||80|50"] = h_remote })

    local success, active = annotations_mod.sync_callback(
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
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
    end
  )

  it(
    "preserves two highlights of the same passage with different datetimes as distinct annotations",
    function()
      local h1 = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "first highlight",
        "2026-01-01 10:00:00"
      )
      local h2 = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "second highlight",
        "2026-01-01 11:00:00"
      )
      write_json(local_file, { ["1|10|20||100|40@10"] = h1 })
      write_json(last_sync_file, {})
      write_json(income_file, { ["1|10|20||100|40@11"] = h2 })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(2, #active)
      assert.are.equal("first highlight", active[1].note)
      assert.are.equal("second highlight", active[2].note)

      local written = utils_mod.read_json(local_file)
      assert.are.equal(2, #written)
    end
  )

  it(
    "propagates updated note from remote when income copy has newer datetime_updated",
    function()
      local h_local = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "old note on device B",
        "2026-01-01 10:00:00"
      )
      local h_income = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "edited note on device A",
        "2026-01-01 10:00:00",
        "2026-01-01 10:05:00"
      )
      write_json(local_file, { ["1|10|20||100|40"] = h_local })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h_local })
      write_json(income_file, { ["1|10|20||100|40"] = h_income })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("edited note on device A", active[1].note)
      assert.are.equal("2026-01-01 10:05:00", active[1].datetime_updated)

      local written = utils_mod.read_json(local_file)
      assert.are.equal(1, #written)
      assert.are.equal("edited note on device A", written[1].note)
      assert.are.equal("2026-01-01 10:05:00", written[1].datetime_updated)
    end
  )

  it(
    "preserves local updated note when local copy has newer datetime_updated than remote",
    function()
      local h_local = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "newer note on device B",
        "2026-01-01 10:00:00",
        "2026-01-01 10:10:00"
      )
      local h_income = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "older edit on device A",
        "2026-01-01 10:00:00",
        "2026-01-01 10:05:00"
      )
      write_json(local_file, { ["1|10|20||100|40"] = h_local })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h_income })
      write_json(income_file, { ["1|10|20||100|40"] = h_income })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("newer note on device B", active[1].note)
      assert.are.equal("2026-01-01 10:10:00", active[1].datetime_updated)

      local written = utils_mod.read_json(local_file)
      assert.are.equal(1, #written)
      assert.are.equal("newer note on device B", written[1].note)
      assert.are.equal("2026-01-01 10:10:00", written[1].datetime_updated)
    end
  )

  it(
    "does not delete re-highlighted passage when old highlight at same passage is tombstoned",
    function()
      local h_old = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "old highlight",
        "2026-01-01 10:00:00"
      )
      local h_old_tombstone = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "old highlight",
        "2026-01-01 10:00:00",
        "2026-01-01 12:00:00",
        true
      )
      local h_new = create_highlight(
        1,
        10,
        20,
        100,
        40,
        "re-highlighted passage",
        "2026-01-02 09:00:00"
      )

      write_json(local_file, { ["1|10|20||100|40@new"] = h_new })
      write_json(last_sync_file, { ["1|10|20||100|40@old"] = h_old })
      write_json(income_file, { ["1|10|20||100|40@old_del"] = h_old_tombstone })

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("re-highlighted passage", active[1].note)
      assert.are.equal("2026-01-02 09:00:00", active[1].datetime)
      assert.is_nil(active[1].deleted)

      local written = utils_mod.read_json(local_file)
      assert.are.equal(2, #written)
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
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("kept locally", active[1].note)

    local written = utils_mod.read_json(local_file)
    assert.is_table(written[1])
    assert.is_true(written[1].deleted)
    assert.is_string(written[1].datetime_updated)
    assert.is_nil(written[2].deleted)
  end)

  it(
    "Case 6: preserves local highlight and does not delete on remote omission",
    function()
      local h_synced = create_highlight(1, 10, 20, 100, 40, "synced highlight")
      write_json(local_file, { ["1|10|20||100|40"] = h_synced })
      write_json(last_sync_file, { ["1|10|20||100|40"] = h_synced })
      write_json(income_file, {}) -- remote does not have it (omitted, no tombstone)

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(1, #active)
      assert.are.equal("synced highlight", active[1].note)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.is_nil(written[1].deleted)
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
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_true(success)
      assert.are.equal(0, #active)

      local written = utils_mod.read_json(local_file)
      assert.is_table(written[1])
      assert.is_true(written[1].deleted)
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
        local_file,
        last_sync_file,
        income_file
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
        local_file,
        last_sync_file,
        income_file,
        404
      )

      assert.is_nil(success)
      assert.are.equal(0, #active)
    end
  )

  it(
    "returns nil from sync_callback when remote exists as empty table and local is empty",
    function()
      write_json(local_file, {})
      write_json(income_file, {})

      local success, active = annotations_mod.sync_callback(
        local_file,
        last_sync_file,
        income_file
      )

      assert.is_nil(success)
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
        local_file,
        last_sync_file,
        income_file
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

  describe("annotations.merge (list-level 3-way merge)", function()
    it(
      "merges live edits with the snapshot base and the upload income",
      function()
        local s_x = create_highlight(1, 10, 20, 100, 40, "note_orig", "2026-01-01 10:00:00")
        local s_d = create_highlight(2, 10, 20, 100, 40, "to_delete_local", "2026-01-01 10:00:00")
        local s_k = create_highlight(3, 10, 20, 100, 40, "keep", "2026-01-01 10:00:00")

        -- Base (Snapshot S)
        local base = { s_x, s_d, s_k }

        -- Local at callback time: x edited note, d deleted locally, k unchanged, h added locally
        local l_x = create_highlight(1, 10, 20, 100, 40, "note_edited", "2026-01-01 10:00:00", "2026-01-01 12:00:00")
        local l_h = create_highlight(4, 10, 20, 100, 40, "new_local_hl", "2026-01-01 12:00:00")
        local l_k = create_highlight(3, 10, 20, 100, 40, "keep", "2026-01-01 10:00:00")
        local local_list = { l_x, l_k, l_h }

        -- Income (Uploaded M): remote added r, x has original note, d was in S, k was in S
        local m_x = create_highlight(1, 10, 20, 100, 40, "note_orig", "2026-01-01 10:00:00")
        local m_d = create_highlight(2, 10, 20, 100, 40, "to_delete_local", "2026-01-01 10:00:00")
        local m_k = create_highlight(3, 10, 20, 100, 40, "keep", "2026-01-01 10:00:00")
        local m_r = create_highlight(5, 10, 20, 100, 40, "remote_added", "2026-01-01 11:00:00")
        local income = { m_x, m_d, m_k, m_r }

        local merged, active = annotations_mod.merge(local_list, base, income)

        -- Active must have: l_x (with edited note), l_k, l_h (new local), m_r (remote added)
        -- and NOT s_d (which was deleted locally)
        assert.are.equal(4, #active)
        local active_texts = {}
        for _, a in ipairs(active) do
          table.insert(active_texts, a.note or a.text)
        end
        table.sort(active_texts)
        assert.are.same({ "keep", "new_local_hl", "note_edited", "remote_added" }, active_texts)

        -- Merged must have the tombstone for s_d
        local has_d_tombstone = false
        for _, m in ipairs(merged) do
          if m.page == s_d.page and m.deleted == true then
            has_d_tombstone = true
          end
        end
        assert.is_true(has_d_tombstone)
      end
    )

    it(
      "Issue-23 guard: protects empty local list when base has items",
      function()
        local base = { create_highlight(1, 10, 20, 100, 40, "item1") }
        local income = {
          create_highlight(1, 10, 20, 100, 40, "item1"),
          create_highlight(2, 10, 20, 100, 40, "item2"),
        }
        local local_list = {}

        local merged, active = annotations_mod.merge(local_list, base, income)
        assert.are.equal(2, #active)
      end
    )


    it(
      "returns M minus tombstones in active when local_list == base_list",
      function()
        local s_str = json.encode({
          create_highlight(1, 10, 20, 100, 40, "live1", "2026-01-01 10:00:00"),
          create_highlight(2, 10, 20, 100, 40, "to_be_deleted", "2026-01-01 10:00:00"),
        })
        local local_list = json.decode(s_str)
        local base_list = json.decode(s_str)
        local tomb = create_highlight(2, 10, 20, 100, 40, "to_be_deleted", "2026-01-01 10:00:00")
        tomb.deleted = true
        tomb.datetime_updated = "2026-01-02 10:00:00"
        local income_list = {
          create_highlight(1, 10, 20, 100, 40, "live1", "2026-01-01 10:00:00"),
          tomb,
          create_highlight(3, 10, 20, 100, 40, "remote_live", "2026-01-02 10:00:00"),
        }

        local merged, active =
          annotations_mod.merge(local_list, base_list, income_list)
        assert.are.equal(2, #active)
        local active_notes = { active[1].note, active[2].note }
        table.sort(active_notes)
        assert.are.same({ "live1", "remote_live" }, active_notes)

        local has_tomb = false
        for _, m in ipairs(merged) do
          if m.note == "to_be_deleted" and m.deleted == true then
            has_tomb = true
          end
        end
        assert.is_true(has_tomb)
      end
    )

    it(
      "preserves restored annotations when local is missing them and base holds tombstones",
      function()
        local h = create_highlight(1, 10, 20, 100, 40, "live_h", "2026-01-01 10:00:00")
        local base_a = create_highlight(
          2,
          10,
          20,
          100,
          40,
          "tomb_a",
          "2026-01-01 10:00:00",
          "2026-01-02 10:00:00",
          true
        )
        local base_b = create_highlight(
          3,
          10,
          20,
          100,
          40,
          "tomb_b",
          "2026-01-01 10:00:00",
          "2026-01-02 10:00:00",
          true
        )
        local base = { base_a, base_b, h }

        local inc_a = create_highlight(
          2,
          10,
          20,
          100,
          40,
          "tomb_a",
          "2026-01-01 10:00:00",
          "2026-01-03 10:00:00",
          false
        )
        local inc_b = create_highlight(
          3,
          10,
          20,
          100,
          40,
          "tomb_b",
          "2026-01-01 10:00:00",
          "2026-01-03 10:00:00",
          false
        )
        local income = { inc_a, inc_b, h }

        local local_list = { h }

        local merged, active = annotations_mod.merge(local_list, base, income)

        assert.are.equal(3, #active)
        local active_notes = {}
        for _, a in ipairs(active) do
          table.insert(active_notes, a.note)
        end
        table.sort(active_notes)
        assert.are.same({ "live_h", "tomb_a", "tomb_b" }, active_notes)

        for _, m in ipairs(merged) do
          assert.are_not.equal(true, m.deleted)
        end
      end
    )

    it(
      "preserves restored annotation when local is empty and base holds only tombstone",
      function()
        local base_a = create_highlight(
          1,
          10,
          20,
          100,
          40,
          "item_a",
          "2026-01-01 10:00:00",
          "2026-01-02 10:00:00",
          true
        )
        local inc_a = create_highlight(
          1,
          10,
          20,
          100,
          40,
          "item_a",
          "2026-01-01 10:00:00",
          "2026-01-03 10:00:00",
          false
        )
        local base = { base_a }
        local income = { inc_a }
        local local_list = {}

        local merged, active = annotations_mod.merge(local_list, base, income)

        assert.are.equal(1, #active)
        assert.are.equal("item_a", active[1].note)
        assert.are.equal(1, #merged)
        assert.are_not.equal(true, merged[1].deleted)
      end
    )
  end)
end)
