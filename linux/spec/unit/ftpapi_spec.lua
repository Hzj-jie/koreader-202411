describe("FtpApi", function()
  local FtpApi
  local mock_ftp
  local mock_url
  local mock_ffiutil
  local mock_doc_reg
  local mock_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    mock_ftp = {
      get_called = false,
      get = function(p)
        mock_ftp.get_called = true
        mock_ftp.get_p = p
        if p.sink and mock_ftp.mock_response then
          p.sink(mock_ftp.mock_response)
        end
        if mock_ftp.get_result == nil then
          return nil, mock_ftp.get_err or "error"
        end
        return mock_ftp.get_result, mock_ftp.get_err
      end,
      command_called = false,
      command = function(p)
        mock_ftp.command_called = true
        mock_ftp.command_p = p
        if mock_ftp.command_result == nil then
          return nil, mock_ftp.command_err or "error"
        end
        return mock_ftp.command_result, mock_ftp.command_err
      end,
    }
    package.loaded["socket.ftp"] = mock_ftp

    mock_url = {
      parse = function(u)
        local user, password, host, path =
          u:match("ftp://([^:]+):([^@]+)@([^/]+)(.*)")
        if not user then
          user, host, path = u:match("ftp://([^@]+)@([^/]+)(.*)")
        end
        if not user then
          host, path = u:match("ftp://([^/]+)(.*)")
        end
        return {
          user = user or "",
          password = password or "",
          host = host or u,
          path = path or "",
        }
      end,
    }
    package.loaded["socket.url"] = mock_url

    mock_ffiutil = {
      strcoll = function(a, b)
        if a < b then
          return true
        end
        return false
      end,
    }
    package.loaded["ffi/util"] = mock_ffiutil

    mock_doc_reg = {
      hasProvider = function(self, file)
        return file:match("%.epub$") ~= nil or file:match("%.pdf$") ~= nil
      end,
    }
    package.loaded["document/documentregistry"] = mock_doc_reg

    mock_util = {
      urlDecode = function(str)
        return str
      end,
    }
    package.loaded["util"] = mock_util

    package.loaded["ltn12"] = {
      sink = {
        table = function(tbl)
          return function(chunk)
            if chunk then
              table.insert(tbl, chunk)
            end
            return true
          end
        end,
      },
    }

    _G.G_reader_settings = {
      is_true_value = false,
      isTrue = function(self, key)
        if key == "show_unsupported" then
          return self.is_true_value
        end
        return false
      end,
    }

    package.loaded["apps/cloudstorage/ftpapi"] = nil
    FtpApi = require("apps/cloudstorage/ftpapi")
  end)

  after_each(function()
    package.loaded["apps/cloudstorage/ftpapi"] = nil
    package.loaded["socket.ftp"] = nil
    package.loaded["socket.url"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["util"] = nil
    package.loaded["ltn12"] = nil
    _G.G_reader_settings = nil
  end)

  describe("generateUrl", function()
    it("should generate standard ftp url with credentials", function()
      local res = FtpApi:generateUrl("192.168.1.100:21", "user", "pass")
      assert.are.equal("ftp://user:pass@192.168.1.100:21", res)
    end)

    it("should generate ftp url without password", function()
      local res = FtpApi:generateUrl("192.168.1.100:21", "user", "")
      assert.are.equal("ftp://user@192.168.1.100:21", res)
    end)

    it("should generate ftp url without credentials", function()
      local res = FtpApi:generateUrl("192.168.1.100:21", "", "")
      assert.are.equal("ftp://192.168.1.100:21", res)
    end)

    it("should strip existing ftp prefix from address", function()
      local res = FtpApi:generateUrl("ftp://192.168.1.100:21", "user", "pass")
      assert.are.equal("ftp://user:pass@192.168.1.100:21", res)
    end)
  end)

  describe("ftpGet", function()
    it("should invoke socket.ftp.get with parsed properties", function()
      mock_ftp.get_result = 1
      local sink_mock = function() end
      local r, e = FtpApi:ftpGet("ftp://user:pass@host/path", "nlst", sink_mock)

      assert.are.equal(1, r)
      assert.is_nil(e)
      assert.is_true(mock_ftp.get_called)

      local p = mock_ftp.get_p
      assert.truthy(p)
      assert.are.equal("user", p.user)
      assert.are.equal("pass", p.password)
      assert.are.equal("nlst", p.command)
      assert.are.equal("i", p.type)
      assert.are.equal(sink_mock, p.sink)
    end)
  end)

  describe("listFolder", function()
    it("should list files and folders properly and sort them", function()
      mock_ftp.get_result = 1
      mock_ftp.mock_response =
        "folderA\r\nfileB.epub\r\nfolderC\r\nfileD.pdf\r\nfileE.txt\r\n"

      local list = FtpApi:listFolder("ftp://host/books", "/books")

      -- Should contain:
      -- folders: folderA/, folderC/
      -- supported files: fileB.epub, fileD.pdf
      -- unsupported files (fileE.txt) should be filtered out by default (G_reader_settings:isTrue("show_unsupported") is false)

      assert.truthy(list)
      assert.are.equal(4, #list)

      -- Folders first, sorted alphabetically
      assert.are.equal("folderA/", list[1].text)
      assert.are.equal("/books/folderA", list[1].url)
      assert.are.equal("folder", list[1].type)

      assert.are.equal("folderC/", list[2].text)
      assert.are.equal("/books/folderC", list[2].url)
      assert.are.equal("folder", list[2].type)

      -- Files next, sorted alphabetically
      assert.are.equal("fileB.epub", list[3].text)
      assert.are.equal("/books/fileB.epub", list[3].url)
      assert.are.equal("file", list[3].type)

      assert.are.equal("fileD.pdf", list[4].text)
      assert.are.equal("/books/fileD.pdf", list[4].url)
      assert.are.equal("file", list[4].type)
    end)

    it(
      "should include unsupported files if show_unsupported setting is enabled",
      function()
        _G.G_reader_settings.is_true_value = true
        mock_ftp.get_result = 1
        mock_ftp.mock_response = "fileE.txt\r\nfolderA\r\n"

        local list = FtpApi:listFolder("ftp://host/books", "/books")

        assert.truthy(list)
        assert.are.equal(2, #list)

        -- Sorted folders first, then files
        assert.are.equal("folderA/", list[1].text)
        assert.are.equal("folder", list[1].type)

        assert.are.equal("fileE.txt", list[2].text)
        assert.are.equal("file", list[2].type)
      end
    )

    it("should handle root folder path correctly", function()
      mock_ftp.get_result = 1
      mock_ftp.mock_response = "folderA\r\n"

      local list = FtpApi:listFolder("ftp://host/", "/")

      assert.truthy(list)
      assert.are.equal(1, #list)
      assert.are.equal("/folderA", list[1].url) -- should not be //folderA
    end)

    it("should return false and error if ftp get fails", function()
      mock_ftp.get_result = nil
      mock_ftp.get_err = "connection timeout"

      local success, err = FtpApi:listFolder("ftp://host/", "/")
      assert.is_false(success)
      assert.are.equal("connection timeout", err)
    end)
  end)

  describe("delete", function()
    it("should call ftp.command with dele parameters", function()
      mock_ftp.command_result = 1
      local r, e = FtpApi:delete("ftp://user:pass@host/books/file.epub")

      assert.are.equal(1, r)
      assert.is_nil(e)
      assert.is_true(mock_ftp.command_called)

      local p = mock_ftp.command_p
      assert.truthy(p)
      assert.are.equal("user", p.user)
      assert.are.equal("pass", p.password)
      assert.are.equal("dele", p.command)
      assert.are.equal(250, p.check)
      assert.are.equal("books/file.epub", p.argument)
    end)
  end)
end)
