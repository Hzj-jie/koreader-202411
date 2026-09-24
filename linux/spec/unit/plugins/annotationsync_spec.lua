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

  describe("Position Comparison and Sorting", function()
    it("should compare positions correctly across numbers, strings, and tables", function()
      -- Numbers (page bookmarks)
      assert.is_true(annotations.compare_positions(1, 2) > 0)
      assert.is_true(annotations.compare_positions(2, 1) < 0)
      assert.are.equal(0, annotations.compare_positions(2, 2))

      -- Strings (XPointers with natural sort)
      assert.is_true(
        annotations.compare_positions(
          "/body/DocFragment[1]",
          "/body/DocFragment[2]"
        ) > 0
      )
      assert.is_true(
        annotations.compare_positions(
          "/body/DocFragment[2]",
          "/body/DocFragment[1]"
        ) < 0
      )
      assert.is_true(
        annotations.compare_positions(
          "/body/DocFragment[2]",
          "/body/DocFragment[10]"
        ) > 0
      )
      assert.is_true(
        annotations.compare_positions(
          "/body/DocFragment[3]/text().72",
          "/body/DocFragment[3]/text().210"
        ) > 0
      )
      assert.are.equal(
        0,
        annotations.compare_positions(
          "/body/DocFragment[1]",
          "/body/DocFragment[1]"
        )
      )

      -- Tables on different pages
      local t_p1 = { page = 1, x = 10, y = 20 }
      local t_p2 = { page = 2, x = 10, y = 20 }
      assert.is_true(annotations.compare_positions(t_p1, t_p2) > 0)
      assert.is_true(annotations.compare_positions(t_p2, t_p1) < 0)

      -- Tables on same page with coordinates
      local t_top = { page = 1, x = 10, y = 20 }
      local t_bottom = { page = 1, x = 10, y = 80 }
      assert.is_true(annotations.compare_positions(t_top, t_bottom) > 0)
      assert.is_true(annotations.compare_positions(t_bottom, t_top) < 0)

      -- Tables on same page, same y, different x
      local t_left = { page = 1, x = 10, y = 20 }
      local t_right = { page = 1, x = 50, y = 20 }
      assert.is_true(annotations.compare_positions(t_left, t_right) > 0)
      assert.is_true(annotations.compare_positions(t_right, t_left) < 0)

      -- Mixed types: number bookmark vs table highlight on different pages
      assert.is_true(annotations.compare_positions(1, t_p2) > 0)
      assert.is_true(annotations.compare_positions(t_p2, 1) < 0)

      -- Mixed types: number bookmark vs table highlight on same page (bookmark is smaller)
      assert.is_true(annotations.compare_positions(1, t_p1) > 0)
      assert.is_true(annotations.compare_positions(t_p1, 1) < 0)
    end)

    it(
      "should sort mixed bookmarks and highlights strictly by page then position",
      function()
        local map = {
          h10 = { page = 10, pos0 = { x = 20, y = 40 } },
          b10 = { page = 10 },
          h1 = { page = 1, pos0 = { x = 10, y = 30 } },
          b1 = { page = 1 },
        }
        local sorted_keys = annotations.sort_keys_by_position(map)
        assert.are.same({ "b1", "h1", "b10", "h10" }, sorted_keys)
      end
    )

    it(
      "should not mark annotations as deleted on no-op sync with mixed PDF bookmarks and highlights",
      function()
        local local_map = {
          b1 = { page = 1 },
          h1 = {
            page = 1,
            pos0 = { x = 10, y = 20 },
            pos1 = { x = 50, y = 20 },
          },
          b2 = { page = 2 },
          h2 = {
            page = 2,
            pos0 = { x = 10, y = 20 },
            pos1 = { x = 50, y = 20 },
          },
        }
        local last_uploaded_map = {
          b1 = { page = 1 },
          h1 = {
            page = 1,
            pos0 = { x = 10, y = 20 },
            pos1 = { x = 50, y = 20 },
          },
          b2 = { page = 2 },
          h2 = {
            page = 2,
            pos0 = { x = 10, y = 20 },
            pos1 = { x = 50, y = 20 },
          },
        }

        annotations.get_deleted_annotations(
          local_map,
          last_uploaded_map,
          nil,
          false
        )

        assert.is_nil(last_uploaded_map.b1.deleted)
        assert.is_nil(last_uploaded_map.h1.deleted)
        assert.is_nil(last_uploaded_map.b2.deleted)
        assert.is_nil(last_uploaded_map.h2.deleted)
      end
    )
  end)
end)
