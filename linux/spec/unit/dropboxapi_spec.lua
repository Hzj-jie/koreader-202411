describe("DropBoxApi", function()
  local DropBoxApi
  local mock_http
  local mock_socket
  local mock_ffiutil
  local mock_doc_reg
  local mock_util
  local mock_lfs
  local mock_json
  local original_io_open

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    original_io_open = io.open
    io.open = function(path, mode) -- luacheck: ignore 122
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
        return true,
          mock_http.code or 200,
          mock_http.headers or { etag = "etag_db_123" },
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
      getFriendlySize = function(bytes)
        return tostring(bytes) .. " B"
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

    package.loaded["ffi/sha2"] = {
      bin_to_base64 = function(str)
        return "b64_" .. str
      end,
    }

    mock_json = {
      decode_queue = {},
      decode = function(_)
        return table.remove(mock_json.decode_queue, 1) or {}
      end,
    }
    package.loaded["json"] = mock_json

    package.loaded["apps/cloudstorage/dropboxapi"] = nil
    DropBoxApi = require("apps/cloudstorage/dropboxapi")
  end)

  after_each(function()
    io.open = original_io_open -- luacheck: ignore 122
    package.loaded["apps/cloudstorage/dropboxapi"] = nil
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
    package.loaded["ffi/sha2"] = nil
    package.loaded["json"] = nil
    _G.G_reader_settings = nil
  end)

  describe("getAccessToken", function()
    it("should request new access token using refresh token", function()
      mock_http.code = 200
      mock_http.mock_response = "dummy_response"
      table.insert(
        mock_json.decode_queue,
        { access_token = "new_access_token_123" }
      )

      local token =
        DropBoxApi:getAccessToken("my_refresh_token", "app_key:app_secret")

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal("https://api.dropbox.com/oauth2/token", req.url)
      assert.are.equal("POST", req.method)
      assert.are.equal(
        "Basic b64_app_key:app_secret",
        req.headers["Authorization"]
      )
      assert.are.equal(
        "application/x-www-form-urlencoded",
        req.headers["Content-Type"]
      )
      assert.are.equal("new_access_token_123", token)
    end)

    it("should return nil and log warning if API fails", function()
      mock_http.code = 400
      mock_http.mock_response = "Bad Request"

      local token =
        DropBoxApi:getAccessToken("my_refresh_token", "app_key:app_secret")
      assert.is_nil(token)
    end)
  end)

  describe("fetchInfo", function()
    it("should fetch current account info", function()
      mock_http.code = 200
      mock_http.mock_response = "dummy"
      local expected_info =
        { email = "user@example.com", name = { display_name = "User" } }
      table.insert(mock_json.decode_queue, expected_info)

      local info = DropBoxApi:fetchInfo("my_token", false)

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal(
        "https://api.dropboxapi.com/2/users/get_current_account",
        req.url
      )
      assert.are.equal("POST", req.method)
      assert.are.equal("Bearer my_token", req.headers["Authorization"])
      assert.are.same(expected_info, info)
    end)

    it("should fetch space usage info if requested", function()
      mock_http.code = 200
      mock_http.mock_response = "dummy"
      local expected_info = { used = 500, allocation = { allocated = 1000 } }
      table.insert(mock_json.decode_queue, expected_info)

      local info = DropBoxApi:fetchInfo("my_token", true)

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal(
        "https://api.dropboxapi.com/2/users/get_space_usage",
        req.url
      )
      assert.are.same(expected_info, info)
    end)
  end)

  describe("fetchListFolders", function()
    it("should fetch folder list without continuation", function()
      mock_http.code = 200
      mock_http.mock_response = "dummy"

      local expected_list = {
        entries = {
          {
            name = "folderA",
            [".tag"] = "folder",
            path_display = "/books/folderA",
          },
        },
        has_more = false,
      }
      table.insert(mock_json.decode_queue, expected_list)

      local res = DropBoxApi:fetchListFolders("/books", "my_token")

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal(
        "https://api.dropboxapi.com/2/files/list_folder",
        req.url
      )
      assert.are.equal("Bearer my_token", req.headers["Authorization"])
      assert.are.equal("application/json", req.headers["Content-Type"])
      assert.are.same(expected_list, res)
    end)

    it(
      "should fetch additional folders recursively if has_more is true",
      function()
        mock_http.code = 200
        mock_http.mock_response = "dummy"

        -- First response has has_more = true
        local first_list = {
          entries = {
            {
              name = "folderA",
              [".tag"] = "folder",
              path_display = "/books/folderA",
            },
          },
          cursor = "cursor_abc_123",
          has_more = true,
        }
        -- Second response (continuation) has has_more = false
        local second_list = {
          entries = {
            {
              name = "fileB.epub",
              [".tag"] = "file",
              path_display = "/books/fileB.epub",
              size = 100,
            },
          },
          cursor = "cursor_xyz_456",
          has_more = false,
        }

        table.insert(mock_json.decode_queue, first_list)
        table.insert(mock_json.decode_queue, second_list)

        -- Spy on fetchAdditionalFolders to verify it was called
        local original_additional = DropBoxApi.fetchAdditionalFolders
        local additional_called = false
        DropBoxApi.fetchAdditionalFolders = function(self, ...)
          additional_called = true
          return original_additional(self, ...)
        end

        local res = DropBoxApi:fetchListFolders("/books", "my_token")

        assert.is_true(additional_called)
        assert.truthy(res)
        -- Total entries should contain both folderA and fileB.epub
        assert.are.equal(2, #res.entries)
        assert.are.equal("folderA", res.entries[1].name)
        assert.are.equal("fileB.epub", res.entries[2].name)
        assert.is_false(res.has_more)
      end
    )
  end)

  describe("downloadFile", function()
    it(
      "should perform GET request with Bearer token and Dropbox-API-Arg",
      function()
        mock_http.code = 200
        mock_http.headers = { etag = "etag_download_db" }

        local code, etag = DropBoxApi:downloadFile(
          "/books/file.epub",
          "my_token",
          "/dummy/file.epub"
        )

        assert.is_true(mock_http.request_called)
        local req = mock_http.last_request
        assert.are.equal(
          "https://content.dropboxapi.com/2/files/download",
          req.url
        )
        assert.are.equal("GET", req.method)
        assert.are.equal("Bearer my_token", req.headers["Authorization"])
        assert.are.equal(
          '{"path": "/books/file.epub"}',
          req.headers["Dropbox-API-Arg"]
        )
        assert.truthy(req.sink)

        assert.are.equal(200, code)
        assert.are.equal("etag_download_db", etag)
      end
    )
  end)

  describe("uploadFile", function()
    it(
      "should perform POST request with autorename true, Bearer token, Content-Length and Etag match",
      function()
        mock_http.code = 200

        local code = DropBoxApi:uploadFile(
          "/books",
          "my_token",
          "/dummy/file.epub",
          "etag_match_db",
          false
        )

        assert.is_true(mock_http.request_called)
        local req = mock_http.last_request
        assert.are.equal(
          "https://content.dropboxapi.com/2/files/upload",
          req.url
        )
        assert.are.equal("POST", req.method)
        assert.are.equal("Bearer my_token", req.headers["Authorization"])
        assert.are.equal(
          '{"path": "/books/file.epub","mode":"add","autorename": true,"mute": false,"strict_conflict": false}',
          req.headers["Dropbox-API-Arg"]
        )
        assert.are.equal(
          "application/octet-stream",
          req.headers["Content-Type"]
        )
        assert.are.equal(999, req.headers["Content-Length"]) -- from mock_lfs
        assert.are.equal("etag_match_db", req.headers["If-Match"])
        assert.truthy(req.source)

        assert.are.equal(200, code)
      end
    )

    it(
      "should perform POST request with mode overwrite and autorename false if overwrite true",
      function()
        mock_http.code = 200

        local code = DropBoxApi:uploadFile(
          "/books",
          "my_token",
          "/dummy/file.epub",
          "etag_match_db",
          true
        )

        assert.is_true(mock_http.request_called)
        local req = mock_http.last_request
        assert.are.equal(
          '{"path": "/books/file.epub","mode":"overwrite","autorename": false,"mute": false,"strict_conflict": false}',
          req.headers["Dropbox-API-Arg"]
        )
        assert.are.equal(200, code)
      end
    )
  end)

  describe("createFolder", function()
    it("should perform POST request to create folder", function()
      mock_http.code = 200

      local code = DropBoxApi:createFolder("/books", "my_token", "newfolder")

      assert.is_true(mock_http.request_called)
      local req = mock_http.last_request
      assert.are.equal(
        "https://api.dropboxapi.com/2/files/create_folder_v2",
        req.url
      )
      assert.are.equal("POST", req.method)
      assert.are.equal("Bearer my_token", req.headers["Authorization"])
      assert.are.equal("application/json", req.headers["Content-Type"])
      assert.are.equal(48, req.headers["Content-Length"])

      assert.are.equal(200, code)
    end)
  end)

  describe("listFolder", function()
    it(
      "should retrieve list of sorted files/folders, filtering out unsupported",
      function()
        mock_http.code = 200
        mock_http.mock_response = "dummy"

        local mock_response_data = {
          entries = {
            {
              name = "folderB",
              [".tag"] = "folder",
              path_display = "/books/folderB",
            },
            {
              name = "fileA.epub",
              [".tag"] = "file",
              path_display = "/books/fileA.epub",
              size = 100,
            },
            {
              name = "fileC.txt",
              [".tag"] = "file",
              path_display = "/books/fileC.txt",
              size = 500,
            },
          },
          has_more = false,
        }
        table.insert(mock_json.decode_queue, mock_response_data)

        local list = DropBoxApi:listFolder("/books", "my_token", false)

        assert.truthy(list)
        -- We should have:
        -- 1 folder: folderB/
        -- 1 file: fileA.epub (size formatted 100 B)
        -- fileC.txt is excluded since show_unsupported is false
        assert.are.equal(2, #list)

        assert.are.equal("folderB/", list[1].text)
        assert.are.equal("/books/folderB", list[1].url)
        assert.are.equal("folder", list[1].type)

        assert.are.equal("fileA.epub", list[2].text)
        assert.are.equal("100 B", list[2].mandatory)
        assert.are.equal("/books/fileA.epub", list[2].url)
        assert.are.equal("file", list[2].type)
      end
    )

    it(
      "should include unsupported files and format size if show_unsupported is enabled",
      function()
        _G.G_reader_settings.is_true_value = true
        mock_http.code = 200
        mock_http.mock_response = "dummy"

        local mock_response_data = {
          entries = {
            {
              name = "fileC.txt",
              [".tag"] = "file",
              path_display = "/books/fileC.txt",
              size = 50000,
            },
          },
          has_more = false,
        }
        table.insert(mock_json.decode_queue, mock_response_data)

        local list = DropBoxApi:listFolder("/books", "my_token", false)

        assert.truthy(list)
        assert.are.equal(1, #list)
        assert.are.equal("fileC.txt", list[1].text)
        assert.are.equal("50000 B", list[1].mandatory)
      end
    )

    it(
      "should prepend Long-press folder selection if folder_mode is enabled",
      function()
        mock_http.code = 200
        mock_http.mock_response = "dummy"

        local mock_response_data = {
          entries = {},
          has_more = false,
        }
        table.insert(mock_json.decode_queue, mock_response_data)

        local list = DropBoxApi:listFolder("/books", "my_token", true)

        assert.truthy(list)
        assert.are.equal(1, #list)
        assert.are.equal("Long-press to choose current folder", list[1].text)
        assert.are.equal("/books", list[1].url)
        assert.are.equal("folder_long_press", list[1].type)
      end
    )
  end)

  describe("showFiles", function()
    it("should only return files, skipping folders", function()
      mock_http.code = 200
      mock_http.mock_response = "dummy"

      local mock_response_data = {
        entries = {
          {
            name = "folderA",
            [".tag"] = "folder",
            path_display = "/books/folderA",
          },
          {
            name = "fileB.epub",
            [".tag"] = "file",
            path_display = "/books/fileB.epub",
            size = 1024,
          },
        },
        has_more = false,
      }
      table.insert(mock_json.decode_queue, mock_response_data)

      local list = DropBoxApi:showFiles("/books", "my_token")

      assert.truthy(list)
      assert.are.equal(1, #list)
      assert.are.equal("fileB.epub", list[1].text)
      assert.are.equal("/books/fileB.epub", list[1].url)
      assert.are.equal(1024, list[1].size)
    end)
  end)
end)
