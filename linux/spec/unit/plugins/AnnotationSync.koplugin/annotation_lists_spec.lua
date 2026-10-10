describe("AnnotationSync annotation lists, merge, and pure functions", function()
  local annotations, utils, json, UIManager, util, test_utils
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_annotation_lists_tmp"
  local old_getDataDir

  local function hl(page, x, fields)
    local item = {
      page = page,
      drawer = "lighten",
      pos0 = { x = x, y = 10 },
      pos1 = { x = x + 50, y = 10 },
      datetime = "2026-01-01 10:00:00",
      text = "p" .. page .. "x" .. x,
    }
    if fields then
      for k, v in pairs(fields) do
        item[k] = v
      end
    end
    return item
  end

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    json = require("json")
    util = require("util")
    utils = require("plugins/AnnotationSync.koplugin/utils")
    annotations = require("plugins/AnnotationSync.koplugin/annotations")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  teardown(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/annotations"] = nil
    package.loaded["plugins/AnnotationSync.koplugin/utils"] = nil
  end)

  it("keeps an annotation only this device has", function()
    local local_list = { hl(1, 0) }
    local base_list = {}
    local income_list = {}

    local _, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(1, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.is_falsy(active[1].deleted)
  end)

  it("adds an annotation another device made", function()
    local local_list = { hl(1, 0) }
    local base_list = { hl(1, 0) }
    local income_list = { hl(1, 0), hl(2, 0) }

    local _, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(2, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.are.equal("p2x0", active[2].text)
  end)

  it("turns an annotation deleted on this device into a tombstone", function()
    local local_list = { hl(1, 0) }
    local base_list = { hl(1, 0), hl(2, 0) }
    local income_list = { hl(1, 0), hl(2, 0) }

    local merged, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(1, #active)
    assert.are.equal("p1x0", active[1].text)

    local tombstone
    for _, item in ipairs(merged) do
      if item.text == "p2x0" then
        tombstone = item
        break
      end
    end
    assert.is_not_nil(tombstone)
    assert.is_true(tombstone.deleted)
    assert.is_truthy(tombstone.datetime_updated:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"))
  end)

  it("drops an annotation another device deleted", function()
    local b_prime = hl(2, 0, { deleted = true, datetime_updated = "2026-02-01 00:00:00" })
    local local_list = { hl(1, 0), hl(2, 0) }
    local base_list = { hl(1, 0), hl(2, 0) }
    local income_list = { hl(1, 0), b_prime }

    local merged, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(1, #active)
    assert.are.equal("p1x0", active[1].text)

    local tombstone
    for _, item in ipairs(merged) do
      if item.text == "p2x0" then
        tombstone = item
        break
      end
    end
    assert.is_not_nil(tombstone)
    assert.is_true(tombstone.deleted)
  end)

  it("keeps the later edit of an annotation changed on both devices", function()
    local a_loc = hl(1, 0, { note = "here", datetime_updated = "2026-03-01 10:00:00" })
    local a_base = hl(1, 0)
    local a_inc = hl(1, 0, { note = "there", datetime_updated = "2026-03-02 10:00:00" })

    local _, active = annotations.merge({ a_loc }, { a_base }, { a_inc })
    assert.are.equal(1, #active)
    assert.are.equal("there", active[1].note)

    local a_loc2 = hl(1, 0, { note = "here", datetime_updated = "2026-03-03 10:00:00" })
    local a_inc2 = hl(1, 0, { note = "there", datetime_updated = "2026-03-02 10:00:00" })
    local _, active2 = annotations.merge({ a_loc2 }, { a_base }, { a_inc2 })
    assert.are.equal(1, #active2)
    assert.are.equal("here", active2[1].note)
  end)

  it("keeps this device's edit when both edits have the same time", function()
    local a_loc = hl(1, 0, { note = "here", datetime_updated = "2026-03-01 10:00:00" })
    local a_base = hl(1, 0)
    local a_inc = hl(1, 0, { note = "there", datetime_updated = "2026-03-01 10:00:00" })

    local _, active = annotations.merge({ a_loc }, { a_base }, { a_inc })
    assert.are.equal(1, #active)
    assert.are.equal("here", active[1].note)
  end)

  it("brings back an annotation another device restored, although this device's base has its tombstone", function()
    local local_list = { hl(2, 0) }
    local base_list = { hl(1, 0, { deleted = true }) }
    local income_list = {
      hl(1, 0, { deleted = false, datetime_updated = "2026-02-01 00:00:00" }),
      hl(2, 0),
    }

    local _, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(2, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.are.equal("p2x0", active[2].text)
  end)

  it("deletes nothing when the book is empty but the base is not", function()
    local local_list = {}
    local base_list = { hl(1, 0), hl(2, 0) }
    local income_list = { hl(1, 0), hl(2, 0) }

    local _, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(2, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.are.equal("p2x0", active[2].text)
    assert.is_falsy(active[1].deleted)
    assert.is_falsy(active[2].deleted)
  end)

  it("keeps an annotation the cloud dropped without a tombstone", function()
    local local_list = { hl(1, 0), hl(2, 0) }
    local base_list = { hl(1, 0), hl(2, 0) }
    local income_list = { hl(1, 0) }

    local _, active = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(2, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.are.equal("p2x0", active[2].text)
  end)

  it("returns the merged list in page order", function()
    local local_list = { hl(5, 0), hl(1, 0) }
    local base_list = {}
    local income_list = { hl(3, 0) }

    local merged, _ = annotations.merge(local_list, base_list, income_list)
    assert.are.equal(3, #merged)
    assert.are.equal(1, merged[1].page)
    assert.are.equal(3, merged[2].page)
    assert.are.equal(5, merged[3].page)
  end)

  it("a first sync of an empty book uploads nothing", function()
    local local_file = test_data_dir .. "/sync_cb_11.json"
    finally(function()
      os.remove(local_file)
    end)
    util.writeToFile("[]", local_file)

    local success, active = annotations.sync_callback(local_file, nil, nil, 404)
    assert.is_nil(success)
    assert.is_truthy(util.tableEquals(active, {}))
  end)

  it("a first sync uploads the book when the cloud has no file", function()
    local local_file = test_data_dir .. "/sync_cb_12.json"
    finally(function()
      os.remove(local_file)
    end)
    util.writeToFile(json.encode({ hl(1, 0) }), local_file)

    local s1, a1 = annotations.sync_callback(local_file, nil, nil, 404)
    assert.is_true(s1)
    assert.are.equal(1, #a1)
    assert.are.equal("p1x0", a1[1].text)

    local s2, a2 = annotations.sync_callback(local_file, nil, nil, 409)
    assert.is_true(s2)
    assert.are.equal(1, #a2)
    assert.are.equal("p1x0", a2[1].text)
  end)

  it("a cloud file that isn't JSON aborts the sync", function()
    local local_file = test_data_dir .. "/sync_cb_13_loc.json"
    local income_file = test_data_dir .. "/sync_cb_13_inc.json"
    finally(function()
      os.remove(local_file)
      os.remove(income_file)
    end)
    util.writeToFile(json.encode({ hl(1, 0) }), local_file)
    util.writeToFile("<html>error</html>", income_file)

    local success, _ = annotations.sync_callback(local_file, nil, income_file, 200)
    assert.is_false(success)
  end)

  it("a cloud file without one valid annotation aborts the sync", function()
    local local_file = test_data_dir .. "/sync_cb_14_loc.json"
    local income_file = test_data_dir .. "/sync_cb_14_inc.json"
    finally(function()
      os.remove(local_file)
      os.remove(income_file)
    end)
    util.writeToFile(json.encode({ hl(1, 0) }), local_file)
    util.writeToFile('[{"foo":1}]', income_file)

    local success, _ = annotations.sync_callback(local_file, nil, income_file, 200)
    assert.is_false(success)
  end)

  it("writes the merged list into the local file and returns the live annotations", function()
    local local_file = test_data_dir .. "/sync_cb_15_loc.json"
    local income_file = test_data_dir .. "/sync_cb_15_inc.json"
    finally(function()
      os.remove(local_file)
      os.remove(income_file)
    end)
    util.writeToFile(json.encode({ hl(1, 0) }), local_file)
    util.writeToFile(json.encode({ hl(2, 0) }), income_file)

    local success, active = annotations.sync_callback(local_file, nil, income_file, 200)
    assert.is_true(success)
    assert.are.equal(2, #active)
    assert.are.equal("p1x0", active[1].text)
    assert.are.equal("p2x0", active[2].text)

    local on_disk = utils.read_json(local_file)
    assert.is_not_nil(on_disk)
    assert.are.equal(2, #on_disk)
  end)

  it("both sides empty uploads nothing", function()
    local local_file = test_data_dir .. "/sync_cb_16_loc.json"
    local income_file = test_data_dir .. "/sync_cb_16_inc.json"
    finally(function()
      os.remove(local_file)
      os.remove(income_file)
    end)
    util.writeToFile("[]", local_file)
    util.writeToFile("[]", income_file)

    local success, active = annotations.sync_callback(local_file, nil, income_file, 200)
    assert.is_nil(success)
    assert.is_truthy(util.tableEquals(active, {}))
  end)

  it("a missing local file is an error, not an empty book", function()
    local missing_path = test_data_dir .. "/missing_file_for_17.json"
    local ok, err = pcall(annotations.sync_callback, missing_path, nil, nil, 404)
    assert.is_false(ok)
    assert.is_truthy(err and err:find("missing or unreadable local sync file", 1, true))
  end)

  it("drops invalid entries of the local file", function()
    local local_file = test_data_dir .. "/sync_cb_18.json"
    finally(function()
      os.remove(local_file)
    end)
    util.writeToFile(json.encode({ hl(1, 0), { page = "" } }), local_file)

    local success, active = annotations.sync_callback(local_file, nil, nil, 404)
    assert.is_true(success)
    assert.are.equal(1, #active)
    assert.are.equal("p1x0", active[1].text)
  end)

  it("orders PDF annotations by page, bookmarks first on a page, then top to bottom and left to right", function()
    local a = { page = 2, pos0 = { x = 5, y = 50 }, pos1 = { x = 9, y = 50 }, drawer = "lighten", text = "a" }
    local b = { page = 2, text = "b" }
    local c = { page = 1, pos0 = { x = 1, y = 1 }, pos1 = { x = 2, y = 1 }, drawer = "lighten", text = "c" }
    local d = { page = 2, pos0 = { x = 30, y = 10 }, pos1 = { x = 40, y = 10 }, drawer = "lighten", text = "d" }
    local e = { page = 2, pos0 = { x = 5, y = 10 }, pos1 = { x = 9, y = 10 }, drawer = "lighten", text = "e" }

    local items = { a, b, c, d, e }
    annotations.sort(items)

    assert.are.equal("c", items[1].text)
    assert.are.equal("b", items[2].text)
    assert.are.equal("e", items[3].text)
    assert.are.equal("d", items[4].text)
    assert.are.equal("a", items[5].text)
  end)

  it("orders EPUB annotations by position, comparing numbers as numbers", function()
    local x = {
      page = "/body/DocFragment[2]/body/p[10]/text().0",
      pos0 = "/body/DocFragment[2]/body/p[10]/text().0",
      pos1 = "/body/DocFragment[2]/body/p[10]/text().10",
      drawer = "lighten",
      text = "x",
    }
    local y = {
      page = "/body/DocFragment[2]/body/p[9]/text().0",
      pos0 = "/body/DocFragment[2]/body/p[9]/text().0",
      pos1 = "/body/DocFragment[2]/body/p[9]/text().10",
      drawer = "lighten",
      text = "y",
    }
    local z = {
      page = "/body/DocFragment[10]/body/p[1]/text().0",
      pos0 = "/body/DocFragment[10]/body/p[1]/text().0",
      pos1 = "/body/DocFragment[10]/body/p[1]/text().10",
      drawer = "lighten",
      text = "z",
    }

    local items = { x, y, z }
    annotations.sort(items)

    assert.are.equal("y", items[1].text)
    assert.are.equal("x", items[2].text)
    assert.are.equal("z", items[3].text)
  end)

  it("compares edit times, falls back to creation times and counts equal times as before", function()
    assert.is_true(
      annotations.is_before(
        { datetime = "2026-01-02 00:00:00" },
        { datetime = "2026-01-01 00:00:00", datetime_updated = "2026-01-03 00:00:00" }
      )
    )
    assert.is_false(
      annotations.is_before(
        { datetime_updated = "2026-01-05 00:00:00" },
        { datetime = "2026-01-04 00:00:00" }
      )
    )
    assert.is_true(
      annotations.is_before(
        { datetime = "2026-01-01 00:00:00" },
        { datetime = "2026-01-01 00:00:00" }
      )
    )
  end)

  it("writes the list as JSON and returns its path, or false when it can't", function()
    local path = annotations.write_annotations_json({ hl(1, 0) }, test_data_dir, "w.json")
    finally(function()
      if path then
        os.remove(path)
      end
    end)
    assert.are.equal(test_data_dir .. "/w.json", path)

    local read_back = utils.read_json(path)
    assert.is_not_nil(read_back)
    assert.are.equal("p1x0", read_back[1].text)

    assert.is_false(annotations.write_annotations_json({ hl(1, 0) }, nil, "w.json"))
    assert.is_false(annotations.write_annotations_json({ hl(1, 0) }, test_data_dir .. "/no_such_dir", "w.json"))
  end)

  it("read_json returns nil for a bad path, a missing or empty file, non-JSON and cloud error replies", function()
    assert.is_nil(utils.read_json(nil))
    assert.is_nil(utils.read_json(42))
    assert.is_nil(utils.read_json(test_data_dir .. "/missing.json"))

    local empty_file = test_data_dir .. "/empty.json"
    local html_file = test_data_dir .. "/error.html"
    local broken_file = test_data_dir .. "/broken.json"
    local err1 = test_data_dir .. "/err1.json"
    local err2 = test_data_dir .. "/err2.json"
    local valid1 = test_data_dir .. "/valid1.json"
    local valid2 = test_data_dir .. "/valid2.json"

    finally(function()
      os.remove(empty_file)
      os.remove(html_file)
      os.remove(broken_file)
      os.remove(err1)
      os.remove(err2)
      os.remove(valid1)
      os.remove(valid2)
    end)

    util.writeToFile("", empty_file)
    assert.is_nil(utils.read_json(empty_file))

    util.writeToFile("<html>", html_file)
    assert.is_nil(utils.read_json(html_file))

    util.writeToFile("{broken", broken_file)
    assert.is_nil(utils.read_json(broken_file))

    util.writeToFile('{"error_summary":"path/not_found/"}', err1)
    assert.is_nil(utils.read_json(err1))

    util.writeToFile('{"error":{"code":409}}', err2)
    assert.is_nil(utils.read_json(err2))

    util.writeToFile('{"a":1}', valid1)
    assert.are.equal(1, utils.read_json(valid1).a)

    util.writeToFile("[1,2]", valid2)
    assert.are.same({ 1, 2 }, utils.read_json(valid2))
  end)

  it("get_nested_value follows dotted keys and stops at a missing or non-table value", function()
    local t = { a = { b = { c = 1 } }, s = "x" }
    assert.are.equal(1, utils.get_nested_value(t, "a.b.c"))
    assert.is_nil(utils.get_nested_value(t, "s.t"))
    assert.is_nil(utils.get_nested_value(t, "a.missing.c"))
    assert.is_nil(utils.get_nested_value(nil, "a.b.c"))
  end)

  it("show_msg shows the text for 3 seconds", function()
    local shown_widget
    local orig_show = UIManager.show
    finally(function()
      UIManager.show = orig_show
      if shown_widget then
        UIManager:closeIfShown(shown_widget)
      end
    end)

    UIManager.show = function(_, w)
      shown_widget = w
    end

    utils.show_msg("hello")
    assert.is_not_nil(shown_widget)
    assert.are.equal("hello", shown_widget.text)
    assert.are.equal(3, shown_widget.timeout)
  end)
end)
