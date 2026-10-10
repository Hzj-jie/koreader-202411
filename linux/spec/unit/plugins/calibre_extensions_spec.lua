describe("CalibreExtensions", function()
  local CalibreExtensions, DataStorage

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    CalibreExtensions = require("plugins/calibre.koplugin/extensions")
  end)

  describe("get, getInfo, and isCustom", function()
    local orig_user_overrides, orig_default_output

    before_each(function()
      orig_user_overrides = CalibreExtensions.user_overrides
      orig_default_output = CalibreExtensions.default_output
    end)

    after_each(function()
      CalibreExtensions.user_overrides = orig_user_overrides
      CalibreExtensions.default_output = orig_default_output
    end)

    it(
      "should return sorted extensions with default_output at index 1 without duplicates",
      function()
        CalibreExtensions.user_overrides = nil
        CalibreExtensions.default_output = "epub"

        local ext_list = CalibreExtensions:get()
        assert.is_table(ext_list)
        assert.are.equal(21, #ext_list)
        assert.are.equal("epub", ext_list[1])

        -- Verify no duplicate epub exists in the rest of the list
        local epub_count = 0
        for _, ext in ipairs(ext_list) do
          if ext == "epub" then
            epub_count = epub_count + 1
          end
        end
        assert.are.equal(1, epub_count)

        -- Test custom default output = "pdf"
        CalibreExtensions.default_output = "pdf"
        local pdf_list = CalibreExtensions:get()
        assert.are.equal(21, #pdf_list)
        assert.are.equal("pdf", pdf_list[1])

        local pdf_count = 0
        for _, ext in ipairs(pdf_list) do
          if ext == "pdf" then
            pdf_count = pdf_count + 1
          end
        end
        assert.are.equal(1, pdf_count)
      end
    )

    it(
      "should return user_overrides directly when user_overrides is a table",
      function()
        local custom_table = { "cbz", "pdf", "epub" }
        CalibreExtensions.user_overrides = custom_table

        local ext_list = CalibreExtensions:get()
        assert.are.equal(custom_table, ext_list)
        assert.are.equal(3, #ext_list)
        assert.are.equal("cbz", ext_list[1])
      end
    )

    it("should format comma-separated string in getInfo", function()
      CalibreExtensions.user_overrides = { "mobi", "azw3", "epub" }
      local info = CalibreExtensions:getInfo()
      assert.are.equal("mobi, azw3, epub", info)

      CalibreExtensions.user_overrides = { "single" }
      assert.are.equal("single", CalibreExtensions:getInfo())
    end)

    it("should report custom status accurately in isCustom", function()
      CalibreExtensions.user_overrides = nil
      assert.is_false(CalibreExtensions:isCustom())

      CalibreExtensions.user_overrides = { "pdf" }
      assert.is_true(CalibreExtensions:isCustom())
    end)
  end)

  describe("File-based custom configuration", function()
    it(
      "should load user_overrides from calibre-extensions.lua in dataDir",
      function()
        local config_path = string.format(
          "%s/%s",
          DataStorage:getDataDir(),
          "calibre-extensions.lua"
        )

        local f = io.open(config_path, "w")
        f:write("return { 'fb2', 'epub', 'txt' }\n")
        f:close()

        package.loaded["plugins/calibre.koplugin/extensions"] = nil
        local loaded_ext = require("plugins/calibre.koplugin/extensions")

        local ok, err = pcall(function()
          assert.is_true(loaded_ext:isCustom())
          local exts = loaded_ext:get()
          assert.are.equal(3, #exts)
          assert.are.equal("fb2", exts[1])
          assert.are.equal("epub", exts[2])
          assert.are.equal("txt", exts[3])
        end)

        os.remove(config_path)
        package.loaded["plugins/calibre.koplugin/extensions"] = nil
        CalibreExtensions = require("plugins/calibre.koplugin/extensions")

        if not ok then
          error(err)
        end
      end
    )
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes isCustom returning true when user_overrides is a non-table value",
      function()
        local orig_overrides = CalibreExtensions.user_overrides
        finally(function()
          CalibreExtensions.user_overrides = orig_overrides
        end)

        -- In extensions.lua:80-82:
        -- function CalibreExtensions:isCustom()
        --   return self.user_overrides ~= nil
        -- end
        -- But line 53 checks `type(self.user_overrides) == "table"` to use overrides.
        -- When user_overrides is a non-table value (false or string), get() ignores
        -- it, but isCustom() returns true, mistakenly hiding "File formats" menu.
        CalibreExtensions.user_overrides = false
        assert.is_false(CalibreExtensions:isCustom())

        CalibreExtensions.user_overrides = "epub"
        assert.is_false(CalibreExtensions:isCustom())
      end
    )
  end)
end)
