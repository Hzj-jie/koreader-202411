describe("AnnotationSync cloud calls and remote operations", function()
  local remote, SyncService, NetworkMgr, UIManager, json, utils, util, test_utils
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_cloud_calls_tmp"
  local old_getDataDir
  local old_sync, old_isOnline, old_show
  local shown = {}

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

  local function widget()
    return {
      settings = {
        sync_server = {
          url = "http://mock",
          type = "webdav",
        },
      },
      manager = {
        getDeviceName = function()
          return "Me"
        end,
      },
    }
  end

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()

    remote = require("plugins/AnnotationSync.koplugin/remote")
    SyncService = require("apps/cloudstorage/syncservice")
    NetworkMgr = require("ui/network/manager")
    UIManager = require("ui/uimanager")
    json = require("json")
    utils = require("plugins/AnnotationSync.koplugin/utils")
    util = require("util")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  teardown(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/remote"] = nil
    package.loaded["plugins/AnnotationSync.koplugin/utils"] = nil
  end)

  before_each(function()
    old_sync = SyncService.sync
    old_isOnline = NetworkMgr.isOnline
    old_show = UIManager.show

    NetworkMgr.isOnline = function()
      return true
    end

    shown = {}
    UIManager.show = function(_, w)
      table.insert(shown, w)
    end
  end)

  after_each(function()
    SyncService.sync = old_sync
    NetworkMgr.isOnline = old_isOnline
    UIManager.show = old_show
  end)

  it("an offline book sync removes its temporary files and fails without calling the cloud", function()
    NetworkMgr.isOnline = function()
      return false
    end
    local json_path = test_data_dir .. "/offline.json"
    util.writeToFile("[]", json_path)
    util.writeToFile("[]", json_path .. ".temp")
    util.writeToFile("[]", json_path .. ".sync")

    local sync_calls = 0
    SyncService.sync = function()
      sync_calls = sync_calls + 1
    end

    local completed_res = nil
    remote.sync_annotations(widget(), json_path, function(res)
      completed_res = res
    end)

    assert.is_false(completed_res)
    assert.are.equal(0, sync_calls)
    assert.is_nil(io.open(json_path, "r"))
    assert.is_nil(io.open(json_path .. ".temp", "r"))
    assert.is_nil(io.open(json_path .. ".sync", "r"))
  end)

  it("a book sync without a cloud fails quietly", function()
    local w = widget()
    w.settings.sync_server = nil
    local json_path = test_data_dir .. "/no_cloud.json"
    util.writeToFile("[]", json_path)

    local sync_calls = 0
    SyncService.sync = function()
      sync_calls = sync_calls + 1
    end

    local completed_res = nil
    remote.sync_annotations(w, json_path, function(res)
      completed_res = res
    end)

    assert.is_false(completed_res)
    assert.are.equal(0, #shown)
    assert.are.equal(0, sync_calls)
    assert.is_nil(io.open(json_path, "r"))
  end)

  it("a book sync that uploads returns the live annotations and the uploaded list", function()
    local json_path = test_data_dir .. "/upload.json"
    local A = hl(1, 0)
    local B = hl(2, 0)
    util.writeToFile(json.encode({ A }), json_path)

    local recorded_silent = nil
    SyncService.sync = function(_, path, sync_cb, is_silent, finish_cb)
      recorded_silent = is_silent
      local income_path = path .. ".income"
      util.writeToFile(json.encode({ B }), income_path)
      local sync_res = sync_cb(path, path .. ".sync", income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local res_success, res_active, res_uploaded_json
    remote.sync_annotations(widget(), json_path, function(success, active, uploaded_json)
      res_success = success
      res_active = active
      res_uploaded_json = uploaded_json
    end)

    assert.is_true(res_success)
    assert.is_true(recorded_silent)
    assert.is_not_nil(res_active)
    assert.are.equal(2, #res_active)
    assert.are.same({ "p1x0", "p2x0" }, { res_active[1].text, res_active[2].text })

    assert.is_not_nil(res_uploaded_json)
    local decoded = json.decode(res_uploaded_json)
    assert.are.same({ "p1x0", "p2x0" }, { decoded[1].text, decoded[2].text })

    assert.is_nil(io.open(json_path, "r"))
    assert.is_nil(io.open(json_path .. ".temp", "r"))
    assert.is_nil(io.open(json_path .. ".sync", "r"))
  end)

  it("a book sync with nothing to upload succeeds without an uploaded list", function()
    local json_path = test_data_dir .. "/empty.json"
    util.writeToFile("[]", json_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local sync_res = sync_cb(path, path .. ".sync", path .. ".income", 404)
      finish_cb(sync_res)
    end

    local res_success, res_active, res_uploaded_json
    remote.sync_annotations(widget(), json_path, function(success, active, uploaded_json)
      res_success = success
      res_active = active
      res_uploaded_json = uploaded_json
    end)

    assert.is_true(res_success)
    assert.are.same({}, res_active)
    assert.is_nil(res_uploaded_json)
  end)

  it("a book sync merges against the given merge base", function()
    local json_path = test_data_dir .. "/merge_base.json"
    local cached_path = test_data_dir .. "/base.json"
    local A = hl(1, 0)
    local B = hl(2, 0)
    util.writeToFile(json.encode({ A }), json_path)
    util.writeToFile(json.encode({ A, B }), cached_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local income_path = path .. ".income"
      util.writeToFile(json.encode({ A, B }), income_path)
      local sync_res = sync_cb(path, path .. ".sync", income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local res_success, res_active, res_uploaded_json
    remote.sync_annotations(widget(), json_path, function(success, active, uploaded_json)
      res_success = success
      res_active = active
      res_uploaded_json = uploaded_json
    end, cached_path)

    assert.is_true(res_success)
    assert.are.equal(1, #res_active)
    assert.are.equal("p1x0", res_active[1].text)

    local uploaded = json.decode(res_uploaded_json)
    assert.are.equal(2, #uploaded)
    local found_b = false
    for _, item in ipairs(uploaded) do
      if item.text == "p2x0" then
        found_b = true
        assert.is_true(item.deleted)
      end
    end
    assert.is_true(found_b)
  end)

  it("a sync the cloud service postpones is an error and fails", function()
    local json_path = test_data_dir .. "/postponed.json"
    util.writeToFile("[]", json_path)

    SyncService.sync = function()
      -- does nothing (postpones)
    end

    local cb_res = nil
    local ok, err = pcall(remote.sync_annotations, widget(), json_path, function(res)
      cb_res = res
    end)

    assert.is_false(ok)
    assert.is_truthy(string.find(err, "SyncService postponed the sync"))
    assert.is_false(cb_res)
    assert.is_nil(io.open(json_path, "r"))
  end)

  it("a settings push keeps the other devices' entries and replaces this device's", function()
    local json_path = test_data_dir .. "/settings_push.json"
    util.writeToFile(json.encode({ Me = { settings = { x = 2 } } }), json_path)

    local recorded_silent = nil
    SyncService.sync = function(_, path, sync_cb, is_silent, finish_cb)
      recorded_silent = is_silent
      local income_path = test_data_dir .. "/settings_income.json"
      util.writeToFile(
        json.encode({
          Me = { settings = { x = 1 } },
          Other = { settings = { y = 3 } },
        }),
        income_path
      )
      local sync_res = sync_cb(path, nil, income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local completed_res = nil
    remote.push_settings(widget(), json_path, function(res)
      completed_res = res
    end)

    assert.is_true(completed_res)
    assert.is_false(recorded_silent)
    local updated = utils.read_json(json_path)
    assert.are.equal(3, updated.Other.settings.y)
    assert.are.equal(2, updated.Me.settings.x)
  end)

  it("a settings push without a cloud file uploads this device's entry as it is", function()
    local json_path = test_data_dir .. "/settings_push_404.json"
    local initial_data = { Me = { settings = { x = 2 } } }
    util.writeToFile(json.encode(initial_data), json_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local sync_res = sync_cb(path, nil, nil, 404)
      finish_cb(sync_res)
    end

    local completed_res = nil
    remote.push_settings(widget(), json_path, function(res)
      completed_res = res
    end)

    assert.is_true(completed_res)
    local updated = utils.read_json(json_path)
    assert.are.same(initial_data, updated)
  end)

  it("a settings push with an unreadable cloud file is aborted", function()
    local json_path = test_data_dir .. "/settings_push_bad.json"
    local initial_data = { Me = { settings = { x = 2 } } }
    util.writeToFile(json.encode(initial_data), json_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local income_path = test_data_dir .. "/settings_income_bad.json"
      util.writeToFile("<html>error</html>", income_path)
      local sync_res = sync_cb(path, nil, income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local completed_res = nil
    remote.push_settings(widget(), json_path, function(res)
      completed_res = res
    end)

    assert.is_false(completed_res)
    local updated = utils.read_json(json_path)
    assert.are.same(initial_data, updated)
  end)

  it("a settings push without a cloud says so", function()
    local w = widget()
    w.settings.sync_server = nil
    local json_path = test_data_dir .. "/settings_no_cloud.json"
    util.writeToFile("{}", json_path)

    local sync_calls = 0
    SyncService.sync = function()
      sync_calls = sync_calls + 1
    end

    local completed_res = nil
    remote.push_settings(w, json_path, function(res)
      completed_res = res
    end)

    assert.is_false(completed_res)
    assert.are.equal(0, sync_calls)
    assert.are.equal(1, #shown)
    assert.are.equal("No cloud destination set in settings.", shown[1].text)
  end)

  it("a settings pull returns the devices in the cloud file", function()
    local json_path = test_data_dir .. "/settings_pull.json"
    util.writeToFile("{}", json_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local income_path = test_data_dir .. "/settings_pull_income.json"
      util.writeToFile(json.encode({ Alpha = { timestamp = "t" } }), income_path)
      local sync_res = sync_cb(path, nil, income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local res_success, res_data
    remote.pull_settings(widget(), json_path, function(success, data)
      res_success = success
      res_data = data
    end)

    assert.is_true(res_success)
    assert.is_not_nil(res_data)
    assert.are.equal("t", res_data.Alpha.timestamp)
  end)

  it("a settings pull with an unreadable cloud file fails", function()
    local json_path = test_data_dir .. "/settings_pull_bad.json"
    util.writeToFile("{}", json_path)

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local income_path = test_data_dir .. "/settings_pull_bad_income.json"
      util.writeToFile("<html>error</html>", income_path)
      local sync_res = sync_cb(path, nil, income_path, 200)
      os.remove(income_path)
      finish_cb(sync_res)
    end

    local res_success, res_data
    remote.pull_settings(widget(), json_path, function(success, data)
      res_success = success
      res_data = data
    end)

    assert.is_false(res_success)
    assert.is_nil(res_data)
  end)
end)
