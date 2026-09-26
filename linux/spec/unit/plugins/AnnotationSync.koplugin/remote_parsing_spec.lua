describe("Remote Response Parsing (Issue #39)", function()
  local annotations_mod, test_utils, json
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_remote_parsing_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")
    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    json = require("json")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  teardown(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
  end)

  local function run_sync_callback(income_content)
    local document = { file = "test.epub" }
    local local_path = test_utils.write_mock_json(test_data_dir, "local.json", {
      ["annot_1"] = {
        datetime = "2024-01-01 12:00:00",
        text = "sample text",
        page = 1,
      },
    })
    local last_sync_path =
      test_utils.write_mock_json(test_data_dir, "last.json", {})
    local income_path = test_data_dir .. "/income.json"

    local f = io.open(income_path, "w")
    f:write(income_content)
    f:close()

    return annotations_mod.sync_callback(
      document,
      local_path,
      last_sync_path,
      income_path,
      false
    )
  end

  it("accepts valid 404 HTML as empty remote state", function()
    local html_404 =
      "<html><head><title>404 Not Found</title></head><body><h1>404 Not Found</h1></body></html>"
    local ok, merged = run_sync_callback(html_404)
    assert.truthy(ok, "Should accept 404 HTML")
    assert.is_table(merged)
  end)

  it("accepts SabreDAV XML error as empty remote state", function()
    local sabre_xml =
      '<?xml version="1.0" encoding="utf-8"?> <d:error xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns"> <s:exception>Sabre\\DAV\\Exception\\NotFound</s:exception> <s:message>File with name annots/9b6b3500ac06199cb8a8b3a46c73d963.json could not be located</s:message> </d:error>'
    local ok, merged = run_sync_callback(sabre_xml)
    assert.truthy(ok, "Should accept SabreDAV XML as 404")
    assert.is_table(merged)
  end)

  it(
    "overrides valid JSON that is not an annotation map (schema check)",
    function()
      local invalid_schema_json = '{"status": "ok", "count": 0}'
      local ok, merged = run_sync_callback(invalid_schema_json)
      assert.truthy(ok, "Should override non-annotation JSON schema with local state")
      assert.is_table(merged)
      assert.is_equal(1, #merged)
    end
  )

  it("overrides random HTML error page with local state", function()
    local html_500 =
      "<html><head><title>500 Internal Server Error</title></head><body>Something went wrong</body></html>"
    local ok, merged = run_sync_callback(html_500)
    assert.truthy(ok, "Should override HTML error page with local state")
    assert.is_table(merged)
    assert.is_equal(1, #merged)
  end)

  it("overrides valid JSON error object with local state", function()
    local error_json = '{"error": "Forbidden", "code": 403}'
    local ok, merged = run_sync_callback(error_json)
    assert.truthy(ok, "Should override JSON error objects with local state")
    assert.is_table(merged)
    assert.is_equal(1, #merged)
  end)

  it("overrides garbage text response with local state", function()
    local garbage = "This is not JSON and not HTML"
    local ok, merged = run_sync_callback(garbage)
    assert.truthy(ok, "Should override garbage text with local state")
    assert.is_table(merged)
    assert.is_equal(1, #merged)
  end)

  it("accepts Dropbox 'path not found' error as empty state", function()
    local dropbox_error =
      '{"error_summary": "path/not_found/...", "error": {".tag": "path", "path": {".tag": "not_found"}}}'
    local ok, merged = run_sync_callback(dropbox_error)
    assert.truthy(ok, "Should accept Dropbox path not found")
  end)
end)
