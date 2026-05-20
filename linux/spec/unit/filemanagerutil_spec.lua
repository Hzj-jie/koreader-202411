describe("filemanagerutil", function()
  local filemanagerutil
  local mock_doc_settings
  local mock_ffiutil
  local mock_lfs
  local mock_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      nilOrTrue = function(self, key)
        if key == "shorten_home_dir" then
          return true
        end
        return nil
      end,
    }
    _G.G_named_settings = {
      home_dir = function()
        return "/home/user"
      end,
    }

    mock_doc_settings = {
      sidecar_exists = false,
      mock_summary = {},
      instances = {},
      hasSidecarFile = function(self, _file)
        return mock_doc_settings.sidecar_exists
      end,
      open = function(self, file)
        if not mock_doc_settings.instances[file] then
          mock_doc_settings.instances[file] = {
            data = {
              annotations = "kept",
              bookmarks = "kept",
              cre_dom_version = "kept",
              last_page = "kept",
              font_size = "deleted",
              style_tweaks = "deleted",
            },
            read = function(self, key)
              if key == "doc_path" then
                return file
              end
              return nil
            end,
            readTableRef = function(self, key)
              if key == "summary" then
                return mock_doc_settings.mock_summary
              end
              return {}
            end,
            save = function(self, key, val)
              if key == "summary" then
                mock_doc_settings.mock_summary = val
              end
            end,
            flush = function(self) end,
            delete = function(self, key)
              self.data[key] = nil
            end,
          }
        end
        return mock_doc_settings.instances[file]
      end,
    }
    package.loaded["docsettings"] = mock_doc_settings

    mock_ffiutil = {
      realpath = function(path)
        return "/abs/" .. path
      end,
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
    }
    package.loaded["ffi/util"] = mock_ffiutil

    mock_lfs = {
      files = {},
      dir = function(_dir_path)
        local idx = 0
        return function()
          idx = idx + 1
          return mock_lfs.files[idx]
        end, {}
      end,
      attributes = function(_filepath, field)
        local attr = {
          mode = "file",
          size = 123,
        }
        if field then
          return attr[field]
        end
        return attr
      end,
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

    mock_util = {
      splitFilePathName = function(path)
        local dir = path:match("^(.*)/") or ""
        local file = path:match("([^/]+)$") or path
        return dir, file
      end,
      splitFileNameSuffix = function(filename)
        local base = filename:match("^(.*)%.") or filename
        local ext = filename:match("%.([^%.]+)$") or ""
        return base, ext
      end,
      arrayContains = function(arr, val)
        for _, v in ipairs(arr) do
          if v == val then
            return true
          end
        end
        return false
      end,
    }
    package.loaded["util"] = mock_util

    package.loaded["ui/bidi"] = {
      dirpath = function(p)
        return p
      end,
      filepath = function(p)
        return p
      end,
      filename = function(p)
        return p
      end,
    }
    package.loaded["device"] = {}
    package.loaded["ui/event"] = {
      new = function(self, name, ...)
        return { name = name, ... }
      end,
    }
    package.loaded["ui/uimanager"] = {
      broadcastEvent = function() end,
      show = function() end,
      close = function() end,
    }
    package.loaded["gettext"] = function(text)
      return text
    end

    package.loaded["apps/filemanager/filemanagerutil"] = nil
    filemanagerutil = require("apps/filemanager/filemanagerutil")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["util"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["device"] = nil
    package.loaded["ui/event"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    _G.G_reader_settings = nil
    _G.G_named_settings = nil
  end)

  describe("abbreviate", function()
    it("should abbreviate home path to 'Home'", function()
      local res = filemanagerutil.abbreviate("/home/user")
      assert.are.equal("Home", res)

      local res_slash = filemanagerutil.abbreviate("/home/user/")
      assert.are.equal("Home", res_slash)
    end)

    it("should abbreviate home sub-paths by removing home prefix", function()
      local res = filemanagerutil.abbreviate("/home/user/books/epub")
      assert.are.equal("books/epub", res)
    end)

    it("should return original path if not home", function()
      local res = filemanagerutil.abbreviate("/other/path")
      assert.are.equal("/other/path", res)
    end)

    it("should return empty string if path is nil", function()
      assert.are.equal("", filemanagerutil.abbreviate(nil))
    end)
  end)

  describe("splitFileNameType", function()
    it("should split standard files correctly", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/mybook.epub")
      assert.are.equal("mybook", name)
      assert.are.equal("epub", ext)
    end)

    it("should split fb2.zip and log.zip files as sub-types", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/test.fb2.zip")
      assert.are.equal("test", name)
      assert.are.equal("fb2.zip", ext)

      local name2, ext2 =
        filemanagerutil.splitFileNameType("/books/debug.log.zip")
      assert.are.equal("debug", name2)
      assert.are.equal("log.zip", ext2)
    end)

    it("should split unsupported zip files normally", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/archive.zip")
      assert.are.equal("archive", name)
      assert.are.equal("zip", ext)
    end)
  end)

  describe("getRandomFile", function()
    it("should return a random file matching match_func", function()
      mock_lfs.files = { "file1.epub", "file2.txt", "dir1" }
      mock_lfs.attributes = function(filepath, field)
        local mode = filepath:match("dir1$") and "directory" or "file"
        if field == "mode" then
          return mode
        end
      end

      local file = filemanagerutil.getRandomFile("/books", function(f)
        return f:match("%.epub$") ~= nil
      end)

      assert.are.equal("/books/file1.epub", file)
    end)

    it("should return nil if no files match", function()
      mock_lfs.files = { "file2.txt" }
      local file = filemanagerutil.getRandomFile("/books", function(f)
        return f:match("%.epub$") ~= nil
      end)
      assert.is_nil(file)
    end)
  end)

  describe("getStatus", function()
    it("should return 'new' if no sidecar file exists", function()
      mock_doc_settings.sidecar_exists = false
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("new", status)
    end)

    it("should return 'reading' if sidecar exists but has no status", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.mock_summary = {}
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("reading", status)
    end)

    it("should return correct status if specified in summary", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.mock_summary = { status = "complete" }
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("complete", status)
    end)
  end)

  describe("saveSummary", function()
    it("should save summary with modified date", function()
      local summary = { progress = 0.5 }
      local doc = filemanagerutil.saveSummary("book.epub", summary)

      assert.truthy(mock_doc_settings.mock_summary.modified)
      assert.are.equal(0.5, mock_doc_settings.mock_summary.progress)
      assert.truthy(doc)
    end)
  end)

  describe("statusToString", function()
    it("should translate statuses to human readable text", function()
      assert.are.equal("Unread", filemanagerutil.statusToString("new"))
      assert.are.equal("Reading", filemanagerutil.statusToString("reading"))
      assert.are.equal("On hold", filemanagerutil.statusToString("abandoned"))
      assert.are.equal("Finished", filemanagerutil.statusToString("complete"))
    end)
  end)

  describe("resetDocumentSettings", function()
    it("should delete non-kept settings from docsettings", function()
      local realpath_called = false
      mock_ffiutil.realpath = function(path)
        realpath_called = true
        return "/abs/" .. path
      end

      local doc_settings = mock_doc_settings:open("/abs/book.epub")
      assert.are.equal("kept", doc_settings.data.annotations)
      assert.are.equal("deleted", doc_settings.data.font_size)

      filemanagerutil.resetDocumentSettings("book.epub")

      assert.is_true(realpath_called)
      assert.are.equal("kept", doc_settings.data.annotations)
      assert.are.equal("kept", doc_settings.data.bookmarks)
      assert.is_nil(doc_settings.data.font_size)
      assert.is_nil(doc_settings.data.style_tweaks)
    end)
  end)
end)
