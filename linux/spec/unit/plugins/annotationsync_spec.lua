describe("AnnotationSync plugin unit tests", function()
  local utils, annotations

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    utils = require("plugins/AnnotationSync.koplugin/utils")
    annotations = require("plugins/AnnotationSync.koplugin/annotations")
  end)

  describe("Utils Module Functions", function()
    it("should correctly identify potential JSON strings", function()
      assert.is_true(utils.isPossiblyJson('{"key": "value"}'))
      assert.is_true(utils.isPossiblyJson("[1, 2, 3]"))
      assert.is_false(utils.isPossiblyJson("<html>404 Not Found</html>"))
      assert.is_false(utils.isPossiblyJson("plain text string"))
    end)

    it("should safely fetch nested values from tables", function()
      local data = {
        settings = {
          sync = {
            enabled = true,
            interval = 60,
          },
        },
      }

      assert.are.equal(
        true,
        utils.get_nested_value(data, "settings.sync.enabled")
      )
      assert.are.equal(
        60,
        utils.get_nested_value(data, "settings.sync.interval")
      )
      assert.is_nil(utils.get_nested_value(data, "settings.sync.nonexistent"))
      assert.is_nil(utils.get_nested_value(data, "invalid.path.key"))
      assert.is_nil(utils.get_nested_value(nil, "any.path"))
    end)

    it("should return empty table when reading non-existent JSON file", function()
      local missing_data =
        utils.read_json("/tmp/non_existent_file_annotationsync.json")
      assert.is_table(missing_data)
      assert.are.equal(0, #missing_data)
    end)

    it("should parse valid JSON file contents", function()
      local tmp_file = os.tmpname()
      local f = io.open(tmp_file, "w")
      f:write('{"anno1": {"page": 1, "text": "hello"}}')
      f:close()

      local data = utils.read_json(tmp_file)
      assert.is_table(data)
      assert.is_table(data.anno1)
      assert.are.equal("hello", data.anno1.text)

      os.remove(tmp_file)
    end)

    it("should return nil when reading HTML or Dropbox error JSON payload", function()
      local tmp_file = os.tmpname()

      local f = io.open(tmp_file, "w")
      f:write("<html>500 Internal Error</html>")
      f:close()
      assert.is_nil(utils.read_json(tmp_file))

      f = io.open(tmp_file, "w")
      f:write('{"error_summary": "path/not_found/..."}')
      f:close()
      assert.is_nil(utils.read_json(tmp_file))

      os.remove(tmp_file)
    end)
  end)

  describe("Annotations Schema Validation", function()
    it("should expose sync_callback function", function()
      assert.is_function(annotations.sync_callback)
    end)
  end)
end)
