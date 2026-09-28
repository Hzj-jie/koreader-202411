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

    it("should return nil when reading non-existent JSON file", function()
      local missing_data =
        utils.read_json("/tmp/non_existent_file_annotationsync.json")
      assert.is_nil(missing_data)
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

    it(
      "should return nil when reading HTML or Dropbox error JSON payload",
      function()
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
      end
    )
  end)

  describe("Annotations Schema Validation", function()
    it("should expose sync_callback function", function()
      assert.is_function(annotations.sync_callback)
    end)

    it("should correctly validate bookmarks", function()
      assert.is_true(annotations.is_bookmark({ page = 1 }))
      assert.is_true(annotations.is_bookmark({ page = "chapter1" }))
      -- Invalid bookmarks
      assert.is_false(annotations.is_bookmark(nil))
      assert.is_false(annotations.is_bookmark(1))
      assert.is_false(annotations.is_bookmark({ text = "note without page" }))
      assert.is_false(annotations.is_bookmark({ page = "" }))
      -- Cannot have highlight positions
      assert.is_false(
        annotations.is_bookmark({ page = 1, pos0 = { x = 10, y = 20 } })
      )
    end)

    it("should correctly validate highlights", function()
      -- Valid paging highlight
      assert.is_true(annotations.is_annotation({
        page = 1,
        pos0 = { x = 10, y = 20 },
        pos1 = { x = 30, y = 40 },
      }))
      -- Valid rolling highlight
      assert.is_true(annotations.is_annotation({
        page = 1,
        pos0 = "p1",
        pos1 = "p2",
      }))
      -- Invalid: missing page
      assert.is_false(annotations.is_annotation({
        pos0 = { x = 10, y = 20 },
        pos1 = { x = 30, y = 40 },
      }))
      -- Invalid: missing pos1
      assert.is_false(annotations.is_annotation({
        page = 1,
        pos0 = { x = 10, y = 20 },
      }))
      -- Invalid: pos0 is empty table without coords
      assert.is_false(annotations.is_annotation({
        page = 1,
        pos0 = {},
        pos1 = {},
      }))
      -- Invalid: non-numeric coordinates
      assert.is_false(annotations.is_annotation({
        page = 1,
        pos0 = { x = "bad", y = 20 },
        pos1 = { x = 30, y = 40 },
      }))
      -- Invalid: empty string xpointers
      assert.is_false(annotations.is_annotation({
        page = 1,
        pos0 = "",
        pos1 = "p2",
      }))
    end)

    it(
      "should compare timestamps cleanly without crashing on missing datetime",
      function()
        local t1 = { datetime = "2026-01-01 12:00:00" }
        local t2 = { datetime = "2026-01-01 12:00:01" }
        local no_time = { page = 1 }

        assert.is_true(annotations.is_before(t1, t2))
        assert.is_false(annotations.is_before(t2, t1))
        assert.is_true(annotations.is_before(t1, t1))

        -- Missing datetime fallback to empty string
        assert.is_true(annotations.is_before(no_time, t1))
        assert.is_false(annotations.is_before(t1, no_time))
        assert.is_true(annotations.is_before(no_time, no_time))
      end
    )

    it(
      "should return annotations sorted ascending by position order from map_to_list",
      function()
        local map = {
          hl_p3 = {
            page = 3,
            pos0 = { x = 10, y = 50 },
            pos1 = { x = 40, y = 50 },
            text = "Page 3 highlight",
          },
          bm_p1 = { page = 1 },
          hl_p2_lower = {
            page = 2,
            pos0 = { x = 10, y = 200 },
            pos1 = { x = 40, y = 200 },
            text = "Page 2 lower",
          },
          bm_p2 = { page = 2 },
          hl_p2_upper = {
            page = 2,
            pos0 = { x = 10, y = 50 },
            pos1 = { x = 40, y = 50 },
            text = "Page 2 upper",
          },
          deleted_bm = { page = 1, deleted = true },
        }

        local list = annotations.map_to_list(map)
        assert.is_equal(5, #list)
        assert.is_equal(1, list[1].page)
        assert.is_nil(list[1].pos0)
        assert.is_equal(2, list[2].page)
        assert.is_nil(list[2].pos0)
        assert.is_equal(2, list[3].page)
        assert.is_equal(50, list[3].pos0.y)
        assert.is_equal(2, list[4].page)
        assert.is_equal(200, list[4].pos0.y)
        assert.is_equal(3, list[5].page)
      end
    )
  end)

  describe("Position Comparison and Sorting", function()
    it(
      "should sort annotations correctly across pages, coordinates, and types",
      function()
        -- Page bookmarks
        local b1 = { page = 1 }
        local b2 = { page = 2 }
        local sorted_b = annotations.sort({ b2, b1 })
        assert.are.equal(1, sorted_b[1].page)
        assert.are.equal(2, sorted_b[2].page)

        -- Strings (XPointers with natural sort)
        local xp1 = { page = "/body/DocFragment[1]" }
        local xp2 = { page = "/body/DocFragment[2]" }
        local xp10 = { page = "/body/DocFragment[10]" }
        local xp_text72 = { page = 1, pos0 = "/body/DocFragment[3]/text().72" }
        local xp_text210 =
          { page = 1, pos0 = "/body/DocFragment[3]/text().210" }

        local sorted_xp = annotations.sort({ xp10, xp2, xp1 })
        assert.are.equal("/body/DocFragment[1]", sorted_xp[1].page)
        assert.are.equal("/body/DocFragment[2]", sorted_xp[2].page)
        assert.are.equal("/body/DocFragment[10]", sorted_xp[3].page)

        local sorted_text = annotations.sort({ xp_text210, xp_text72 })
        assert.are.equal("/body/DocFragment[3]/text().72", sorted_text[1].pos0)
        assert.are.equal("/body/DocFragment[3]/text().210", sorted_text[2].pos0)

        -- Tables on different pages
        local t_p1 = { page = 1, pos0 = { x = 10, y = 20 } }
        local t_p2 = { page = 2, pos0 = { x = 10, y = 20 } }
        local sorted_p = annotations.sort({ t_p2, t_p1 })
        assert.are.equal(1, sorted_p[1].page)
        assert.are.equal(2, sorted_p[2].page)

        -- Tables on same page with coordinates (top-to-bottom)
        local t_top = { page = 1, pos0 = { x = 10, y = 20 } }
        local t_bottom = { page = 1, pos0 = { x = 10, y = 80 } }
        local sorted_tb = annotations.sort({ t_bottom, t_top })
        assert.are.equal(20, sorted_tb[1].pos0.y)
        assert.are.equal(80, sorted_tb[2].pos0.y)

        -- Tables on same page, same y, different x (left-to-right)
        local t_left = { page = 1, pos0 = { x = 10, y = 20 } }
        local t_right = { page = 1, pos0 = { x = 50, y = 20 } }
        local sorted_lr = annotations.sort({ t_right, t_left })
        assert.are.equal(10, sorted_lr[1].pos0.x)
        assert.are.equal(50, sorted_lr[2].pos0.x)

        -- Bookmark vs highlight on different pages
        local sorted_bp = annotations.sort({ t_p2, b1 })
        assert.are.equal(1, sorted_bp[1].page)
        assert.are.equal(2, sorted_bp[2].page)

        -- Bookmark vs highlight on same page (bookmark is ordered before highlight)
        local sorted_same = annotations.sort({ t_p1, b1 })
        assert.are.same(b1, sorted_same[1])
        assert.are.same(t_p1, sorted_same[2])

        -- Assertions: non-table arguments must error
        assert.has_error(function()
          annotations.sort(1)
        end)
        assert.has_error(function()
          annotations.sort(nil)
        end)
        assert.has_error(function()
          annotations.sort("foo")
        end)
        assert.has_error(function()
          annotations.sort({ 1, 2 })
        end)
      end
    )

    it(
      "should not mark annotations as deleted on no-op sync with mixed PDF bookmarks and highlights",
      function()
        local json = require("json")
        local util = require("util")
        local local_path = os.tmpname()
        local last_path = os.tmpname()
        local income_path = os.tmpname()

        local data = {
          b1 = { page = 1 },
          h1 = {
            page = 1,
            pos0 = { page = 1, x = 10, y = 20 },
            pos1 = { page = 1, x = 50, y = 20 },
            datetime = "2026-01-01 10:00:00",
          },
          b2 = { page = 2 },
          h2 = {
            page = 2,
            pos0 = { page = 2, x = 10, y = 20 },
            pos1 = { page = 2, x = 50, y = 20 },
            datetime = "2026-01-01 10:00:00",
          },
        }

        util.writeToFile(json.encode(data), local_path)
        util.writeToFile(json.encode(data), last_path)
        util.writeToFile(json.encode(data), income_path)

        local success, active = annotations.sync_callback(
          nil,
          local_path,
          last_path,
          income_path,
          false
        )

        assert.is_true(success)
        assert.are.equal(4, #active)

        local written = utils.read_json(local_path)
        for _, ann in pairs(written) do
          assert.is_nil(ann.deleted)
        end

        os.remove(local_path)
        os.remove(last_path)
        os.remove(income_path)
      end
    )
  end)
end)
