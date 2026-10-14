describe("Wikipedia module", function()
  local Wikipedia
  local http
  local orig_http_request

  setup(function()
    require("commonrequire")
    Wikipedia = require("ui/wikipedia")
    http = require("socket.http")
    orig_http_request = http.request
  end)

  teardown(function()
    if http and orig_http_request then
      http.request = orig_http_request
    end
  end)

  describe("getWikiServer", function()
    it("should return default Wikipedia server", function()
      assert.is.same("https://en.wikipedia.org", Wikipedia:getWikiServer())
    end)

    it("should return Wikipedia server for specified language", function()
      assert.is.same("https://nl.wikipedia.org", Wikipedia:getWikiServer("nl"))
      assert.is.same("https://fr.wikipedia.org", Wikipedia:getWikiServer("fr"))
      assert.is.same("https://zh.wikipedia.org", Wikipedia:getWikiServer("zh"))
    end)
  end)

  describe("isWikipediaLanguageRTL", function()
    it("should return true for RTL language codes", function()
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("fa"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("ar"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("he"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("ur"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("yi"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("AR"))
      assert.is_true(Wikipedia:isWikipediaLanguageRTL("Fa"))
    end)

    it("should return false for LTR language codes or nil", function()
      assert.is_false(Wikipedia:isWikipediaLanguageRTL("en"))
      assert.is_false(Wikipedia:isWikipediaLanguageRTL("fr"))
      assert.is_false(Wikipedia:isWikipediaLanguageRTL("de"))
      assert.is_false(Wikipedia:isWikipediaLanguageRTL(nil))
    end)
  end)

  describe("setTrapWidget and resetTrapWidget", function()
    it("should set and reset trap widget", function()
      local dummy_widget = { id = "trap" }
      Wikipedia:setTrapWidget(dummy_widget)
      assert.is.same(dummy_widget, Wikipedia.trap_widget)

      Wikipedia:resetTrapWidget()
      assert.is_nil(Wikipedia.trap_widget)
    end)
  end)

  describe("prettifyText", function()
    it("should prettify wikipedia section headers and formatting", function()
      local input =
        "\n= Title =\n\n== Section 2 ==\n\n=== Section 3 ===\nText\n"
      local output = Wikipedia:prettifyText(input)
      assert.is.truthy(output)
      assert.is_nil(output:find("\n= "))
      assert.is_nil(output:find("\n== "))
      assert.is_nil(output:find("\n=== "))
    end)

    it("should fix clumsy editor 'Modifier ==' headers", function()
      local input = "\n== Heading Modifier ==\n"
      local output = Wikipedia:prettifyText(input)
      assert.is.truthy(output)
      assert.is_nil(output:find("Modifier =="))
    end)

    it("should trim leading and trailing newlines", function()
      local input = "\n\n\nSome text\n\n\n"
      local output = Wikipedia:prettifyText(input)
      assert.is.same("Some text", output)
    end)
  end)

  describe("loadPage and getUrlContent error handling", function()
    after_each(function()
      http.request = orig_http_request
      Wikipedia:resetTrapWidget()
    end)

    it("should return nil for invalid page_type", function()
      local res = Wikipedia:loadPage("test", "en", 999)
      assert.is_nil(res)
    end)

    it("should fail gracefully on unsupported protocol", function()
      local orig_server = Wikipedia.wiki_server
      Wikipedia.wiki_server = "ftp://%s.wikipedia.org"
      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Unsupported protocol")
      Wikipedia.wiki_server = orig_server
    end)

    it("should fail gracefully on network or HTTP error status", function()
      http.request = function(request)
        if request.sink then
          request.sink("Error body")
        end
        return 1, 404, {}, "HTTP/1.1 404 Not Found"
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Remote server error or unavailable")
    end)

    it("should fail gracefully when HTTP headers are missing", function()
      http.request = function()
        return 1, nil, nil, "Network unreachable"
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Network or remote server unavailable")
    end)

    it("should fail gracefully on incomplete content length", function()
      http.request = function(request)
        if request.sink then
          request.sink("short")
        end
        return 1, 200, { ["content-length"] = "100" }, "HTTP/1.1 200 OK"
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Incomplete content received")
    end)

    it("should fail gracefully on non-JSON response", function()
      local body = "<html>Not JSON</html>"
      http.request = function(request)
        if request.sink then
          request.sink(body)
        end
        return 1,
          200,
          { ["content-length"] = tostring(#body) },
          "HTTP/1.1 200 OK"
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Response is not JSON")
    end)

    it("should fail gracefully on malformed JSON response", function()
      http.request = function(request)
        if request.sink then
          request.sink("{ invalid json }")
        end
        return 1, 200, { ["content-length"] = "16" }, "HTTP/1.1 200 OK"
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, "Failed decoding JSON")
    end)

    it("should handle trap widget user cancellation", function()
      local dummy_widget = { id = "trap" }
      Wikipedia:setTrapWidget(dummy_widget)

      local Trapper = require("ui/trapper")
      local orig_run = Trapper.dismissableRunInSubprocess
      Trapper.dismissableRunInSubprocess = function()
        return false, nil, nil
      end

      assert.has_error(function()
        Wikipedia:loadPage("test", "en", 1)
      end, Wikipedia.dismissed_error_code)

      Trapper.dismissableRunInSubprocess = orig_run
    end)
  end)

  describe("searchAndGetIntros", function()
    after_each(function()
      http.request = orig_http_request
    end)

    it(
      "should search wikipedia and parse search results with intros",
      function()
        local json_resp = [[{
        "query": {
          "pages": {
            "123": {
              "pageid": 123,
              "title": "Lua",
              "extract": "Lua is a programming language.",
              "thumbnail": {
                "source": "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0a/Lua-logo.svg/100px-Lua-logo.svg.png",
                "width": 100,
                "height": 100
              },
              "pageimage": "Lua-logo.svg.png"
            }
          }
        }
      }]]

        http.request = function(request)
          if request.sink then
            request.sink(json_resp)
          end
          return 1,
            200,
            { ["content-length"] = tostring(#json_resp) },
            "HTTP/1.1 200 OK"
        end

        G_reader_settings:save("wikipedia_show_image", true)
        local pages = Wikipedia:searchAndGetIntros("Lua", "en")
        assert.is.truthy(pages)
        assert.is.truthy(pages["123"])
        assert.is.same("Lua", pages["123"].title)
        assert.is.truthy(pages["123"].images)
        assert.is.same(1, #pages["123"].images)
        assert.is.same("Lua-logo.svg.png", pages["123"].images[1].title)
      end
    )

    it(
      "should respect wikipedia_show_image setting when set to false",
      function()
        local json_resp = [[{
        "query": {
          "pages": {
            "123": {
              "pageid": 123,
              "title": "Lua",
              "extract": "Lua is a programming language.",
              "thumbnail": {
                "source": "https://upload.wikimedia.org/wikipedia/commons/thumb/0/0a/Lua-logo.svg/100px-Lua-logo.svg.png",
                "width": 100,
                "height": 100
              },
              "pageimage": "Lua-logo.svg.png"
            }
          }
        }
      }]]

        http.request = function(request)
          if request.sink then
            request.sink(json_resp)
          end
          return 1,
            200,
            { ["content-length"] = tostring(#json_resp) },
            "HTTP/1.1 200 OK"
        end

        G_reader_settings:save("wikipedia_show_image", false)
        local pages = Wikipedia:searchAndGetIntros("Lua", "en")
        assert.is.truthy(pages)
        assert.is.truthy(pages["123"])
        assert.is_nil(pages["123"].images)
        G_reader_settings:save("wikipedia_show_image", true)
      end
    )
  end)

  describe("getFullPage", function()
    after_each(function()
      http.request = orig_http_request
    end)

    it("should fetch full page content and apply prettification", function()
      local json_resp = [[{
        "query": {
          "pages": {
            "456": {
              "pageid": 456,
              "title": "E-book",
              "extract": "\n== Overview ==\nAn e-book is a book publication in digital form."
            }
          }
        }
      }]]

      http.request = function(request)
        if request.sink then
          request.sink(json_resp)
        end
        return 1,
          200,
          { ["content-length"] = tostring(#json_resp) },
          "HTTP/1.1 200 OK"
      end

      Wikipedia.wiki_prettify = true
      local pages = Wikipedia:getFullPage("E-book", "en")
      assert.is.truthy(pages)
      assert.is.truthy(pages["456"])
      assert.is_nil(pages["456"].extract:find("\n== Overview =="))
    end)
  end)

  describe("getFullPageHtml", function()
    after_each(function()
      http.request = orig_http_request
    end)

    it("should fetch parsed HTML structure", function()
      local json_resp = [[{
        "parse": {
          "title": "E-book",
          "pageid": 456,
          "revid": 789,
          "text": { "*": "<div>Content</div>" },
          "displaytitle": "E-book",
          "sections": []
        }
      }]]

      http.request = function(request)
        if request.sink then
          request.sink(json_resp)
        end
        return 1,
          200,
          { ["content-length"] = tostring(#json_resp) },
          "HTTP/1.1 200 OK"
      end

      local parse = Wikipedia:getFullPageHtml("E-book", "en")
      assert.is.truthy(parse)
      assert.is.same("E-book", parse.title)
      assert.is.same(456, parse.pageid)
    end)

    it("should raise error on API error response", function()
      local json_resp = [[{
        "error": {
          "info": "The page title you specified is invalid."
        }
      }]]

      http.request = function(request)
        if request.sink then
          request.sink(json_resp)
        end
        return 1,
          200,
          { ["content-length"] = tostring(#json_resp) },
          "HTTP/1.1 200 OK"
      end

      assert.has_error(function()
        Wikipedia:getFullPageHtml("InvalidPageTitle", "en")
      end, "The page title you specified is invalid.")
    end)
  end)

  describe("getFullPageImages", function()
    after_each(function()
      http.request = orig_http_request
    end)

    it(
      "should parse images from HTML content in figure and gallerybox tags",
      function()
        local html_content = [[
        <div>
          <figure typeof="mw:File/Thumb">
            <a href="/wiki/File:Main_Image.jpg" class="mw.file.description">
              <img src="//upload.wikimedia.org/wikipedia/commons/main.jpg" width="450" height="300"/>
            </a>
            <div>Caption for main image</div>
          </figure>
          <ul class="gallery">
            <li class="gallerybox">
              <div class="thumb">
                <a href="/wiki/File:Gallery_Image.png" class="mw.file.description">
                  <img src="/wiki/gallery.png" width="900" height="450"/>
                </a>
              </div>
              <div class="gallerytext">Gallery item caption</div>
            </li>
          </ul>
        </div>
      ]]

        local json_resp = string.format(
          [[{
        "parse": {
          "text": {
            "*": %s
          }
        }
      }]],
          require("json").encode(html_content)
        )

        http.request = function(request)
          if request.sink then
            request.sink(json_resp)
          end
          return 1,
            200,
            { ["content-length"] = tostring(#json_resp) },
            "HTTP/1.1 200 OK"
        end

        local images = Wikipedia:getFullPageImages("Sample_Page", "en")
        assert.is.truthy(images)
        assert.is.same(2, #images)
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/main.jpg",
          images[1].source
        )
        assert.is.same("Main_Image.jpg", images[1].filename)
        assert.is.same(100, images[1].width) -- ceil(450 / 4.5)
        assert.is.same(67, images[1].height) -- ceil(300 / 4.5)

        assert.is.same(
          "https://en.wikipedia.org/wiki/gallery.png",
          images[2].source
        )
        assert.is.same("Gallery_Image.png", images[2].filename)
      end
    )
  end)

  describe("addImages and load_bb_func", function()
    after_each(function()
      http.request = orig_http_request
    end)

    it("should format image metadata and attach load_bb_func", function()
      local page = {
        title = "Test Page",
        thumbnail = {
          source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/100px-test.jpg",
          width = 100,
          height = 150,
          filename = "test.jpg",
        },
        pageimage = "test.jpg",
      }

      Wikipedia:addImages(page, "en", false, 1.0, 4.0)
      assert.is.truthy(page.images)
      assert.is.same(1, #page.images)

      local img = page.images[1]
      assert.is.same("test.jpg", img.title)
      assert.is.same(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/120px-test.jpg",
        img.source
      )
      assert.is.same(
        "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/500px-test.jpg",
        img.hi_source
      )
      assert.is.same(100, img.width)
      assert.is.same(150, img.height)
      assert.is.same(400, img.hi_width)
      assert.is.same(600, img.hi_height)
      assert.is.truthy(img.load_bb_func)

      -- Mock http request for image data fetch inside load_bb_func
      http.request = function(request)
        if request.sink then
          request.sink("FAKE_IMAGE_DATA")
        end
        return 1, 200, { ["content-length"] = "15" }, "HTTP/1.1 200 OK"
      end

      local RenderImage = require("ui/renderimage")
      local orig_render = RenderImage.renderImageData
      RenderImage.renderImageData = function(_, _, _, _, _)
        return { w = 100, h = 150 }
      end

      img.load_bb_func(false) -- Lowres load
      assert.is.truthy(img.bb)
      assert.is.same(100, img.bb.w)

      img.load_bb_func(true) -- Highres load
      assert.is.truthy(img.hi_bb)
      assert.is.same(100, img.hi_bb.w)

      RenderImage.renderImageData = orig_render
    end)

    it(
      "should snap requested widths to standard Wikimedia thumbnail sizes",
      function()
        local test_cases = {
          { width = 15, expected_url_w = 20 },
          { width = 35, expected_url_w = 40 },
          { width = 55, expected_url_w = 60 },
          { width = 100, expected_url_w = 120 },
          { width = 210, expected_url_w = 250 },
          { width = 300, expected_url_w = 330 },
          { width = 400, expected_url_w = 500 },
          { width = 800, expected_url_w = 960 },
          { width = 1000, expected_url_w = 1280 },
          { width = 1500, expected_url_w = 1920 },
          { width = 3000, expected_url_w = 3840 },
          { width = 5000, expected_url_w = 3840 },
        }
        for _, tc in ipairs(test_cases) do
          local page = {
            thumbnail = {
              source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/50px-test.jpg",
              width = tc.width,
              height = tc.width,
            },
            pageimage = "test.jpg",
          }
          Wikipedia:addImages(page, "en", false, 1.0, 1.0)
          assert.is.same(
            "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/"
              .. tc.expected_url_w
              .. "px-test.jpg",
            page.images[1].source
          )
        end
      end
    )

    it(
      "should boost aspect ratio for thin images and apply correct thumbnail sizes",
      function()
        -- Thin portrait image: width < height / 2
        local portrait_page = {
          thumbnail = {
            source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/portrait.jpg/50px-portrait.jpg",
            width = 40,
            height = 100,
          },
          pageimage = "portrait.jpg",
        }
        Wikipedia:addImages(portrait_page, "en", false, 1.0, 4.0)
        local portrait_img = portrait_page.images[1]
        -- width was boosted from 40 -> floor(40*1.3) = 52, snapped to 60px
        assert.is.same(52, portrait_img.width)
        assert.is.same(130, portrait_img.height)
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/portrait.jpg/60px-portrait.jpg",
          portrait_img.source
        )
        -- hi_width = 52 * 4 = 208, snapped to 250px
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/portrait.jpg/250px-portrait.jpg",
          portrait_img.hi_source
        )

        -- Thin landscape image: height < width / 2
        local landscape_page = {
          thumbnail = {
            source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/landscape.jpg/50px-landscape.jpg",
            width = 100,
            height = 40,
          },
          pageimage = "landscape.jpg",
        }
        Wikipedia:addImages(landscape_page, "en", false, 1.0, 4.0)
        local landscape_img = landscape_page.images[1]
        -- width was boosted from 100 -> floor(100*1.3) = 130, snapped to 250px
        assert.is.same(130, landscape_img.width)
        assert.is.same(52, landscape_img.height)
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/landscape.jpg/250px-landscape.jpg",
          landscape_img.source
        )
      end
    )

    it(
      "should handle default dimensions when width or height is nil",
      function()
        local page = {
          thumbnail = {
            source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/default.jpg/50px-default.jpg",
          },
          pageimage = "default.jpg",
        }
        Wikipedia:addImages(page, "en", false, 1.0, 4.0)
        local img = page.images[1]
        -- Default width/height = 100, snapped to 120px for source and 500px for hi_source
        assert.is.same(100, img.width)
        assert.is.same(100, img.height)
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/default.jpg/120px-default.jpg",
          img.source
        )
        assert.is.same(
          "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/default.jpg/500px-default.jpg",
          img.hi_source
        )
      end
    )

    it(
      "should handle image_load_bb_func errors gracefully (HTTP 400, 404, 500, corrupt data)",
      function()
        local page = {
          thumbnail = {
            source = "https://upload.wikimedia.org/wikipedia/commons/thumb/1/11/test.jpg/100px-test.jpg",
            width = 100,
            height = 100,
          },
          pageimage = "test.jpg",
        }
        Wikipedia:addImages(page, "en", false, 1.0, 4.0)
        local img = page.images[1]

        -- 1. HTTP 400 Bad Request (e.g. invalid thumbnail requested)
        http.request = function(_)
          return 1,
            400,
            { ["content-length"] = "0" },
            "HTTP/1.1 400 Bad Request"
        end
        img.load_bb_func(false)
        assert.is.falsy(img.bb)

        -- 2. HTTP 404 Not Found
        http.request = function(_)
          return 1, 404, { ["content-length"] = "0" }, "HTTP/1.1 404 Not Found"
        end
        img.load_bb_func(false)
        assert.is.falsy(img.bb)

        -- 3. HTTP 500 Internal Server Error
        http.request = function(_)
          return 1,
            500,
            { ["content-length"] = "0" },
            "HTTP/1.1 500 Internal Server Error"
        end
        img.load_bb_func(false)
        assert.is.falsy(img.bb)

        -- 4. Network error / nil return
        http.request = function(_)
          return nil, "connection timed out"
        end
        img.load_bb_func(false)
        assert.is.falsy(img.bb)

        -- 5. Corrupted image binary data (RenderImage fails to decode)
        http.request = function(request)
          if request.sink then
            request.sink("CORRUPTED_BYTES")
          end
          return 1, 200, { ["content-length"] = "15" }, "HTTP/1.1 200 OK"
        end
        local RenderImage = require("ui/renderimage")
        local orig_render = RenderImage.renderImageData
        RenderImage.renderImageData = function()
          return nil
        end

        img.load_bb_func(false)
        assert.is.falsy(img.bb)

        RenderImage.renderImageData = orig_render
      end
    )
  end)

  describe("createEpub and createEpubWithUI", function()
    local temp_epub_path = require("datastorage"):getDataDir()
      .. "/test_wikipedia_article.epub"
    local temp_epub_ui_path = require("datastorage"):getDataDir()
      .. "/test_wikipedia_article_ui.epub"

    after_each(function()
      http.request = orig_http_request
      os.remove(temp_epub_path)
      os.remove(temp_epub_path .. ".tmp")
      os.remove(temp_epub_ui_path)
      os.remove(temp_epub_ui_path .. ".tmp")
    end)

    it("should generate epub file successfully without images", function()
      os.remove(temp_epub_path)
      os.remove(temp_epub_path .. ".tmp")

      local parse_response = {
        parse = {
          title = "Lua Programming",
          pageid = 999,
          revid = 888,
          displaytitle = "Lua Programming",
          text = {
            ["*"] = [[
              <div>
                <h2>Overview</h2>
                <p>Lua is powerful and fast.</p>
                <math xmlns="http://www.w3.org/1998/Math/MathML">x^2</math>
                <a href="/wiki/Scripting_language">Scripting</a>
              </div>
            ]],
          },
          sections = {
            {
              anchor = "Overview",
              line = "Overview",
              number = "1",
              toclevel = 1,
            },
          },
        },
      }

      local json_resp = require("json").encode(parse_response)

      http.request = function(request)
        if request.sink then
          request.sink(json_resp)
        end
        return 1,
          200,
          { ["content-length"] = tostring(#json_resp) },
          "HTTP/1.1 200 OK"
      end

      G_reader_settings:save("wikipedia_epub_include_images", false)

      local res =
        Wikipedia:createEpub(temp_epub_path, "Lua_Programming", "en", false)
      assert.is_true(res)

      local lfs = require("libs/libkoreader-lfs")
      assert.is.same("file", lfs.attributes(temp_epub_path, "mode"))
    end)

    it(
      "should handle createEpub failure when page HTML cannot be retrieved",
      function()
        http.request = function(request)
          if request.sink then
            request.sink([[{"error": {"info": "Not found"}}]])
          end
          return 1, 200, { ["content-length"] = "30" }, "HTTP/1.1 200 OK"
        end

        local res =
          Wikipedia:createEpub(temp_epub_path, "NonExistentPage", "en", false)
        assert.is_false(res)
      end
    )

    it(
      "should wrap createEpub with createEpubWithUI and trigger callback",
      function()
        os.remove(temp_epub_ui_path)
        os.remove(temp_epub_ui_path .. ".tmp")

        local Trapper = require("ui/trapper")
        local orig_wrap = Trapper.wrap
        Trapper.wrap = function(_, func)
          func()
        end

        local parse_response = {
          parse = {
            title = "Lua Programming",
            pageid = 999,
            revid = 888,
            displaytitle = "Lua Programming",
            text = { ["*"] = "<div>Test</div>" },
            sections = {},
          },
        }

        local json_resp = require("json").encode(parse_response)

        http.request = function(request)
          if request.sink then
            request.sink(json_resp)
          end
          return 1,
            200,
            { ["content-length"] = tostring(#json_resp) },
            "HTTP/1.1 200 OK"
        end

        G_reader_settings:save("wikipedia_epub_include_images", false)

        local callback_called = false
        local callback_result = nil

        Wikipedia:createEpubWithUI(
          temp_epub_ui_path,
          "Lua_Programming",
          "en",
          function(success)
            callback_called = true
            callback_result = success
          end
        )

        Trapper.wrap = orig_wrap

        assert.is_true(callback_called)
        assert.is_true(callback_result)
      end
    )
  end)
end)

describe("Wikipedia HTML with Images & Math", function()
  local Wikipedia = require("ui/wikipedia")
  local http = require("socket.http")
  local temp_epub_img = "/tmp/test_wiki_images.epub"

  it(
    "should process html with img tags, srcset, math svg/png and create epub",
    function()
      os.remove(temp_epub_img)
      os.remove(temp_epub_img .. ".tmp")

      local parse_response = {
        parse = {
          title = "Complex Page",
          pageid = 12345,
          revid = 67890,
          displaytitle = "Complex Page",
          text = {
            ["*"] = [[
                        <div>
                            <h1>Complex Page</h1>
                            <p>Here is an image: <img src="//upload.wikimedia.org/wikipedia/commons/thumb/a/a1/Test.jpg/300px-Test.jpg" srcset="//upload.wikimedia.org/wikipedia/commons/thumb/a/a1/Test.jpg/600px-Test.jpg 2x" width="300" height="200" /></p>
                            <p>Math SVG: <img src="/math/render/svg/abcdef123456" width="50" height="20" /></p>
                            <p>Math PNG: <img src="/math/render/png/123456abcdef" width="50" height="20" /></p>
                            <p>Relative image: <img src="/w/extensions/wikihiero/img/hiero_D22.png?0b8f1" width="30" height="30" /></p>
                            <p>No src: <img></img></p>
                        </div>
                    ]],
          },
          sections = {},
        },
      }

      local json_resp = require("json").encode(parse_response)
      local sample_img_data =
        "\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"

      local orig_req = http.request
      http.request = function(request)
        if type(request) == "table" and request.url then
          if request.url:find("action=parse") then
            if request.sink then
              request.sink(json_resp)
            end
            return 1,
              200,
              { ["content-length"] = tostring(#json_resp) },
              "HTTP/1.1 200 OK"
          elseif request.url:find("action=query") then
            local query_resp = require("json").encode({
              query = {
                pages = {
                  ["1"] = {
                    title = "File:Test.jpg",
                    imageinfo = {
                      {
                        thumburl = "https://upload.wikimedia.org/test.jpg",
                        thumbwidth = 300,
                        thumbheight = 200,
                        descriptionurl = "https://commons.wikimedia.org/wiki/File:Test.jpg",
                        extmetadata = {
                          ImageDescription = { value = "A test caption" },
                          Artist = { value = "Photographer" },
                          LicenseShortName = { value = "CC-BY-SA-4.0" },
                        },
                      },
                    },
                  },
                },
              },
            })
            if request.sink then
              request.sink(query_resp)
            end
            return 1,
              200,
              { ["content-length"] = tostring(#query_resp) },
              "HTTP/1.1 200 OK"
          else
            if request.sink then
              request.sink(sample_img_data)
            end
            return 1,
              200,
              { ["content-length"] = tostring(#sample_img_data) },
              "HTTP/1.1 200 OK"
          end
        end
        return 1, 200, {}, "HTTP/1.1 200 OK"
      end

      G_reader_settings:save("wikipedia_epub_include_images", true)
      local res =
        Wikipedia:createEpub(temp_epub_img, "Complex_Page", "en", false)
      http.request = orig_req
      os.remove(temp_epub_img)
      assert.is_true(res)
    end
  )
end)
