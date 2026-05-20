describe("WebDavApi", function()
  local WebDavApi
  local mock_http
  local mock_socket
  local mock_ffiutil
  local mock_doc_reg
  local mock_util
  local mock_lfs
  local original_io_open

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    original_io_open = io.open
    -- luacheck: ignore 122
    io.open = function(path, mode)
      if path:sub(1, 7) == "/dummy/" then
        return {
          close = function() end,
          write = function() end,
          read = function()
            return nil
          end,
        }
      end
      return original_io_open(path, mode)
    end

    mock_http = {
      request_called = false,
      request = function(req)
        mock_http.request_called = true
        mock_http.last_request = req
        if req.source and mock_http.mock_source_handler then
          mock_http.mock_source_handler(req.source)
        end
        if req.sink and mock_http.mock_response then
          req.sink(mock_http.mock_response)
        end
        -- socket.skip(1, ...) expects 4 return values where the first is skipped
        -- e.g. return result, code, headers, status
        return true,
          mock_http.code or 200,
          mock_http.headers or { etag = "etag_webdav_123" },
          mock_http.status or "HTTP/1.1 200 OK"
      end,
    }
    package.loaded["socket.http"] = mock_http

    mock_socket = {
      skip = function(d, ...)
        local args = { ... }
        for _ = 1, d do
          table.remove(args, 1)
        end
        return unpack(args)
      end,
    }
    package.loaded["socket"] = mock_socket

    package.loaded["socketutil"] = {
      set_timeout = function() end,
      reset_timeout = function() end,
      FILE_BLOCK_TIMEOUT = 10,
      FILE_TOTAL_TIMEOUT = 60,
    }

    mock_ffiutil = {
      basename = function(path)
        local clean_path = path:gsub("/*$", "")
        if clean_path == "" then
          return "/"
        end
        return clean_path:match("([^/]+)$") or clean_path
      end,
      strcoll = function(a, b)
        return a < b
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
      htmlEntitiesToUtf8 = function(str)
        return str
      end,
    }
    package.loaded["util"] = mock_util

    mock_lfs = {
      attributes = function(_, field)
        if field == "size" then
          return 999
        end
      end,
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

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
        file = function(_)
          return function(_)
            return true
          end
        end,
      },
      source = {
        string = function(str)
          local sent = false
          return function()
            if not sent then
              sent = true
              return str
            end
            return nil
          end
        end,
        file = function(_)
          local sent = false
          return function()
            if not sent then
              sent = true
              return "dummy_file_content"
            end
            return nil
          end
        end,
      },
    }

    package.loaded["logger"] = {
      dbg = function() end,
      warn = function() end,
      err = function() end,
    }

    package.loaded["gettext"] = function(text)
      return text
    end

    _G.G_reader_settings = {
      is_true_value = false,
      isTrue = function(self, key)
        if key == "show_unsupported" then
          return self.is_true_value
        end
        return false
      end,
    }

    package.loaded["apps/cloudstorage/webdavapi"] = nil
    WebDavApi = require("apps/cloudstorage/webdavapi")
  end)

  after_each(function()
    -- luacheck: ignore 122
    io.open = original_io_open
    package.loaded["apps/cloudstorage/webdavapi"] = nil
    package.loaded["socket.http"] = nil
    package.loaded["socket"] = nil
    package.loaded["socketutil"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["util"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["ltn12"] = nil
    package.loaded["logger"] = nil
    package.loaded["gettext"] = nil
    _G.G_reader_settings = nil
  end)

  describe("trim_slashes", function()
    it("should trim leading and trailing slashes", function()
      assert.are.equal(
        "books/fiction",
        WebDavApi.trim_slashes("/books/fiction/")
      )
      assert.are.equal(
        "books/fiction",
        WebDavApi.trim_slashes("///books/fiction///")
      )
      assert.are.equal("", WebDavApi.trim_slashes("/"))
      assert.are.equal("", WebDavApi.trim_slashes("///"))
      assert.are.equal("books", WebDavApi.trim_slashes("books"))
    end)
  end)

  describe("rtrim_slashes", function()
    it("should trim trailing slashes", function()
      assert.are.equal(
        "/books/fiction",
        WebDavApi.rtrim_slashes("/books/fiction/")
      )
      assert.are.equal(
        "/books/fiction",
        WebDavApi.rtrim_slashes("/books/fiction///")
      )
      assert.are.equal("", WebDavApi.rtrim_slashes("/"))
      assert.are.equal("", WebDavApi.rtrim_slashes("///"))
      assert.are.equal("books", WebDavApi.rtrim_slashes("books"))
    end)
  end)

  describe("urlEncode", function()
    it("should encode special characters but leave slashes alone", function()
      assert.are.equal("books/fiction", WebDavApi.urlEncode("books/fiction"))
      assert.are.equal(
        "books%20and%20more/fiction!",
        WebDavApi.urlEncode("books and more/fiction!")
      )
      assert.is_nil(WebDavApi.urlEncode(nil))
    end)
  end)

  describe("getJoinedPath", function()
    it("should join address and path correctly", function()
      assert.are.equal(
        "http://example.com/books/fiction",
        WebDavApi:getJoinedPath("http://example.com/", "/books/fiction/")
      )
      assert.are.equal(
        "http://example.com/books%20fiction",
        WebDavApi:getJoinedPath("http://example.com///", "///books fiction///")
      )
    end)
  end)

  describe("listFolder", function()
    it(
      "should perform PROPFIND request and parse the XML multi-status response",
      function()
        mock_http.code = 207
        mock_http.mock_response = [[
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/books/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/books/folderB/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype><d:collection/></d:resourcetype>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/books/fileA.epub</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/books/fileC.txt</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
]]

        local list = WebDavApi:listFolder(
          "http://example.com/",
          "user",
          "pass",
          "/books",
          false
        )

        assert.is_true(mock_http.request_called)
        local req = mock_http.last_request
        assert.are.equal("http://example.com/books/", req.url)
        assert.are.equal("PROPFIND", req.method)
        assert.are.equal("user", req.user)
        assert.are.equal("pass", req.password)
        assert.are.equal("application/xml", req.headers["Content-Type"])
        assert.are.equal("1", req.headers["Depth"])

        assert.truthy(list)
        -- We should have:
        -- 1 folder: folderB (books/ itself is ignored because it matches the current dir folder_path end)
        -- 1 file: fileA.epub (fileC.txt is ignored since show_unsupported is false)
        assert.are.equal(2, #list)

        -- Folders first
        assert.are.equal("folderB/", list[1].text)
        assert.are.equal("books/folderB", list[1].url)
        assert.are.equal("folder", list[1].type)

        -- Files next
        assert.are.equal("fileA.epub", list[2].text)
        assert.are.equal("books/fileA.epub", list[2].url)
        assert.are.equal("file", list[2].type)
      end
    )

    it(
      "should include unsupported files if show_unsupported setting is enabled",
      function()
        _G.G_reader_settings.is_true_value = true
        mock_http.code = 207
        mock_http.mock_response = [[
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/books/fileC.txt</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
      </d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
]]
        local list = WebDavApi:listFolder(
          "http://example.com/",
          "user",
          "pass",
          "/books",
          false
        )
        assert.truthy(list)
        assert.are.equal(1, #list)
        assert.are.equal("fileC.txt", list[1].text)
      end
    )

    it("should prepend long press message in folder mode", function()
      mock_http.code = 207
      mock_http.mock_response = [[
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/books/</d:href>
    <d:propstat>
      <d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
    </d:propstat>
  </d:response>
</d:multistatus>
]]

      local list = WebDavApi:listFolder(
        "http://example.com/",
        "user",
        "pass",
        "/books",
        true
      )
      assert.truthy(list)
      assert.are.equal(1, #list)
      assert.are.equal("Long-press to choose current folder", list[1].text)
      assert.are.equal("folder_long_press", list[1].type)
    end)

    it("should return nil if HTTP request fails", function()
      mock_http.code = 500
      mock_http.mock_response = "Internal Server Error"

      local list = WebDavApi:listFolder(
        "http://example.com/",
        "user",
        "pass",
        "/books",
        false
      )
      assert.is_nil(list)
    end)
  end)

  describe("downloadFile", function()
    it("should perform GET request and return code and etag", function()
      mock_http.code = 200
      mock_http.headers = { etag = "etag_download_123" }

      local code, etag = WebDavApi:downloadFile(
        "http://example.com/books/file.epub",
        "user",
        "pass",
        "/dummy/file.epub"
      )

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal("http://example.com/books/file.epub", req.url)
      assert.are.equal("GET", req.method)
      assert.are.equal("user", req.user)
      assert.are.equal("pass", req.password)
      assert.truthy(req.sink)

      assert.are.equal(200, code)
      assert.are.equal("etag_download_123", etag)
    end)
  end)

  describe("uploadFile", function()
    it("should perform PUT request with Content-Length and If-Match", function()
      mock_http.code = 204

      local code = WebDavApi:uploadFile(
        "http://example.com/books/file.epub",
        "user",
        "pass",
        "/dummy/file.epub",
        "etag_match_abc"
      )

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal("http://example.com/books/file.epub", req.url)
      assert.are.equal("PUT", req.method)
      assert.are.equal("user", req.user)
      assert.are.equal("pass", req.password)
      assert.are.equal(999, req.headers["Content-Length"]) -- from mock_lfs
      assert.are.equal("etag_match_abc", req.headers["If-Match"])
      assert.truthy(req.source)

      assert.are.equal(204, code)
    end)
  end)

  describe("createFolder", function()
    it("should perform MKCOL request", function()
      mock_http.code = 201

      local code = WebDavApi:createFolder(
        "http://example.com/books/newfolder",
        "user",
        "pass"
      )

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal("http://example.com/books/newfolder", req.url)
      assert.are.equal("MKCOL", req.method)
      assert.are.equal("user", req.user)
      assert.are.equal("pass", req.password)

      assert.are.equal(201, code)
    end)
  end)
end)
