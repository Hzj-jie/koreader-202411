describe("CoverImage plugin tests", function()
  local CoverImage, Device, UIManager, DataStorage, lfs, ffiutil, util, Screen
  local FileManagerBookInfo, RenderImage, Blitbuffer, ConfirmBox, InputDialog, PathChooser, SpinWidget, InfoMessage
  local test_dir, test_cover_file, test_fallback_file, test_cache_dir

  local function createMockCoverImage(w, h)
    local mock = {
      w = w or 400,
      h = h or 600,
      freed = false,
      written = false,
    }
    function mock:getWidth()
      return self.w
    end
    function mock:getHeight()
      return self.h
    end
    function mock:rotatedCopy()
      return createMockCoverImage(self.w, self.h)
    end
    function mock:free()
      self.freed = true
    end
    function mock:writeToFile(path, format, quality, grayscale)
      self.written = true
      local f = io.open(path, "w")
      if f then
        f:write("dummy")
        f:close()
        return true
      end
      return false
    end
    function mock:getType()
      return 1
    end
    return mock
  end

  local function createMockUI(opts)
    opts = opts or {}
    local doc_settings_data = opts.doc_settings_data or {}
    local doc_settings = {
      read = function(self, key)
        if key == "partial_md5_checksum" then
          return opts.md5
        end
        return doc_settings_data[key]
      end,
      nilOrFalse = function(self, key)
        return not doc_settings_data[key]
      end,
      isTrue = function(self, key)
        return doc_settings_data[key] == true
      end,
      makeTrue = function(self, key)
        doc_settings_data[key] = true
      end,
      makeFalse = function(self, key)
        doc_settings_data[key] = false
      end,
    }
    return {
      document = opts.document or { file = test_dir .. "/test_book.epub" },
      doc_settings = doc_settings,
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      saveSettings = spy.new(function() end),
    }
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    DataStorage = require("datastorage")
    test_dir = DataStorage:getDataDir() .. "/coverimage_test_dir"
    test_cover_file = test_dir .. "/cover.png"
    test_fallback_file = test_dir .. "/fallback.png"
    test_cache_dir = test_dir .. "/cache/"
    require("document/canvascontext"):init(require("device"))
  end)

  teardown(function()
    if test_dir then
      require("ffi/util").purgeDir(test_dir)
    end
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Device = require("device")
    UIManager = require("ui/uimanager")
    DataStorage = require("datastorage")
    lfs = require("libs/libkoreader-lfs")
    ffiutil = require("ffi/util")
    util = require("util")
    Screen = Device.screen

    FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    RenderImage = require("ui/renderimage")
    Blitbuffer = require("ffi/blitbuffer")
    ConfirmBox = require("ui/widget/confirmbox")
    InputDialog = require("ui/widget/inputdialog")
    PathChooser = require("ui/widget/pathchooser")
    SpinWidget = require("ui/widget/spinwidget")
    InfoMessage = require("ui/widget/infomessage")

    stub(UIManager, "show")
    stub(UIManager, "close")

    -- Setup filesystem fixtures
    lfs.mkdir(test_dir)
    lfs.mkdir(test_cache_dir)
    local f1 = io.open(test_cover_file, "w")
    if f1 then
      f1:write("cover")
      f1:close()
    end
    local f2 = io.open(test_fallback_file, "w")
    if f2 then
      f2:write("fallback")
      f2:close()
    end

    -- Setup G_reader_settings defaults
    G_reader_settings:save("cover_image_path", test_cover_file)
    G_reader_settings:save("cover_image_fallback_path", test_fallback_file)
    G_reader_settings:save("cover_image_cache_path", test_cache_dir)
    G_reader_settings:save("cover_image_enabled", true)
    G_reader_settings:save("cover_image_fallback", true)

    package.loaded["plugins/coverimage.koplugin/main"] = nil
    CoverImage = require("plugins/coverimage.koplugin/main")
  end)

  after_each(function()
    UIManager.show:revert()
    UIManager.close:revert()

    -- Clean up filesystem fixtures
    os.remove(test_cover_file)
    os.remove(test_fallback_file)
    for entry in lfs.dir(test_cache_dir) do
      if entry ~= "." and entry ~= ".." then
        os.remove(test_cache_dir .. entry)
      end
    end
    lfs.rmdir(test_cache_dir)
    lfs.rmdir(test_dir)

    G_reader_settings:delete("cover_image_path")
    G_reader_settings:delete("cover_image_format")
    G_reader_settings:delete("cover_image_quality")
    G_reader_settings:delete("cover_image_grayscale")
    G_reader_settings:delete("cover_image_stretch_limit")
    G_reader_settings:delete("cover_image_background")
    G_reader_settings:delete("cover_image_fallback_path")
    G_reader_settings:delete("cover_image_cache_path")
    G_reader_settings:delete("cover_image_cache_maxfiles")
    G_reader_settings:delete("cover_image_cache_maxsize")
    G_reader_settings:delete("cover_image_enabled")
    G_reader_settings:delete("cover_image_fallback")
  end)

  it(
    "should return disabled table when running on unsupported device",
    function()
      stub(Device, "isAndroid")
      stub(Device, "isEmulator")
      stub(Device, "isRemarkable")
      stub(Device, "isPocketBook")
      stub(Device, "isKindle")
      stub(Device, "isKobo")

      Device.isAndroid.returns(false)
      Device.isEmulator.returns(false)
      Device.isRemarkable.returns(false)
      Device.isPocketBook.returns(false)
      Device.isKindle.returns(false)
      Device.isKobo.returns(false)

      package.loaded["plugins/coverimage.koplugin/main"] = nil
      local plugin = require("plugins/coverimage.koplugin/main")
      assert.is_table(plugin)
      assert.is_true(plugin.disabled)

      Device.isAndroid:revert()
      Device.isEmulator:revert()
      Device.isRemarkable:revert()
      Device.isPocketBook:revert()
      Device.isKindle:revert()
      Device.isKobo:revert()
    end
  )

  it("should initialize with default and saved settings", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })

    assert.are.equal(test_cover_file, instance.cover_image_path)
    assert.are.equal("auto", instance.cover_image_format)
    assert.are.equal(75, instance.cover_image_quality)
    assert.are.equal(8, instance.cover_image_stretch_limit)
    assert.are.equal("black", instance.cover_image_background)
    assert.are.equal(test_fallback_file, instance.cover_image_fallback_path)
    assert.are.equal(test_cache_dir, instance.cover_image_cache_path)
    assert.are.equal(36, instance.cover_image_cache_maxfiles)
    assert.are.equal(5, instance.cover_image_cache_maxsize)
    assert.is_true(instance.cover)
    assert.is_true(instance.fallback)
    assert
      .spy(mock_ui.menu.registerToMainMenu)
      .was_called_with(mock_ui.menu, instance)
  end)

  it(
    "should trigger createCoverImage during init if partial_md5_checksum present",
    function()
      local mock_ui = createMockUI({ md5 = "123456" })
      stub(CoverImage, "createCoverImage")

      local instance = CoverImage:new({ ui = mock_ui })
      assert
        .stub(CoverImage.createCoverImage)
        .was_called_with(instance, mock_ui.doc_settings)

      CoverImage.createCoverImage:revert()
    end
  )

  it("should check coverEnabled and fallbackEnabled correctly", function()
    local instance = CoverImage:new({ ui = createMockUI() })

    assert.is_true(instance:coverEnabled())
    assert.is_true(instance:fallbackEnabled())

    instance.cover = false
    assert.is_false(instance:coverEnabled())

    instance.fallback = false
    assert.is_false(instance:fallbackEnabled())

    instance.cover = true
    -- Directory path makes isFileOk return false
    instance.cover_image_path = test_dir
    assert.is_false(instance:coverEnabled())

    instance.fallback = true
    -- Disallowed path makes isFileOk return false
    instance.cover_image_fallback_path = "./cache/fallback.png"
    assert.is_false(instance:fallbackEnabled())
  end)

  it("should perform cleanUpImage properly", function()
    local instance = CoverImage:new({ ui = createMockUI() })

    -- Fallback disabled: removes cover_image_path
    instance.fallback = false
    instance:cleanUpImage()
    assert.is_nil(lfs.attributes(test_cover_file, "mode"))

    -- Re-create cover file for next step
    local f1 = io.open(test_cover_file, "w")
    f1:write("cover")
    f1:close()

    -- Fallback enabled & valid fallback file: copies fallback to cover
    instance.fallback = true
    instance:cleanUpImage()
    assert.are.equal("file", lfs.attributes(test_cover_file, "mode"))

    -- Fallback enabled but invalid fallback path: shows InfoMessage and removes cover
    instance.cover_image_fallback_path = test_dir .. "/invalid_fallback.png"
    instance:cleanUpImage()
    assert.stub(UIManager.show).was_called()
    assert.is_nil(lfs.attributes(test_cover_file, "mode"))
  end)

  it(
    "should handle event callbacks onCloseDocument, onReaderReady, onSetRotationMode",
    function()
      local mock_ui = createMockUI()
      local instance = CoverImage:new({ ui = mock_ui })

      stub(instance, "cleanUpImage")
      stub(instance, "createCoverImage")

      instance:onCloseDocument()
      assert.stub(instance.cleanUpImage).was_called()

      instance:onReaderReady(mock_ui.doc_settings)
      assert
        .stub(instance.createCoverImage)
        .was_called_with(instance, mock_ui.doc_settings)

      instance:onSetRotationMode(0)
      assert
        .stub(instance.createCoverImage)
        .was_called_with(instance, mock_ui.doc_settings)

      instance.cleanUpImage:revert()
      instance.createCoverImage:revert()
    end
  )

  it("should process createCoverImage with cache hit", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })
    local mock_cover = createMockCoverImage(400, 600)

    stub(FileManagerBookInfo, "getCoverImage")
    FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)

    local cache_file = instance:getCacheFile()
    local fc = io.open(cache_file, "w")
    fc:write("cached")
    fc:close()

    instance:createCoverImage(mock_ui.doc_settings)

    assert.are.equal("file", lfs.attributes(instance.cover_image_path, "mode"))
    assert.is_false(mock_cover.written)

    FileManagerBookInfo.getCoverImage:revert()
  end)

  it(
    "should process createCoverImage in background=none or scale_factor=1 mode",
    function()
      local mock_ui = createMockUI()
      local instance = CoverImage:new({ ui = mock_ui })
      instance.cover_image_background = "none"

      local mock_cover = createMockCoverImage(600, 800) -- matches screen size (600x800)
      stub(FileManagerBookInfo, "getCoverImage")
      FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)

      instance:createCoverImage(mock_ui.doc_settings)

      assert.is_true(mock_cover.written)
      assert.is_true(mock_cover.freed)

      FileManagerBookInfo.getCoverImage:revert()
    end
  )

  it("should handle error when cover_image:writeToFile fails", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })
    instance.cover_image_background = "none"

    local mock_cover = createMockCoverImage(600, 800)
    mock_cover.writeToFile = function()
      return false
    end

    stub(FileManagerBookInfo, "getCoverImage")
    FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)

    instance:createCoverImage(mock_ui.doc_settings)

    assert.stub(UIManager.show).was_called()

    FileManagerBookInfo.getCoverImage:revert()
  end)

  it("should process createCoverImage stretch mode", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })
    instance.cover_image_background = "black"
    instance.cover_image_stretch_limit = 20 -- high stretch threshold

    -- screen is 600x800. scale_factor must be != 1.
    -- 300x390 gives scale_factor = min(600/300, 800/390) = 2
    -- screen_ratio = 0.75, image_ratio = 300/390 = 0.76923, divergence = 2.56% < 20%
    local mock_cover = createMockCoverImage(300, 390)
    local mock_stretched = createMockCoverImage(600, 800)

    stub(FileManagerBookInfo, "getCoverImage")
    FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)
    stub(RenderImage, "scaleBlitBuffer")
    RenderImage.scaleBlitBuffer.returns(mock_stretched)

    instance:createCoverImage(mock_ui.doc_settings)

    assert.is_true(mock_stretched.written)
    assert.is_true(mock_cover.freed)

    FileManagerBookInfo.getCoverImage:revert()
    RenderImage.scaleBlitBuffer:revert()
  end)

  it(
    "should process createCoverImage scale & fit mode with background colors",
    function()
      local mock_ui = createMockUI()
      local instance = CoverImage:new({ ui = mock_ui })

      local backgrounds = { "black", "white", "gray" }
      for _, bg in ipairs(backgrounds) do
        instance.cover_image_background = bg
        instance.cover_image_stretch_limit = 1 -- low stretch limit forces scale & blit

        local mock_cover = createMockCoverImage(300, 600)
        local mock_scaled = createMockCoverImage(300, 400)
        local mock_buffer = createMockCoverImage(600, 800)
        stub(mock_buffer, "fill")
        stub(mock_buffer, "blitFrom")

        stub(FileManagerBookInfo, "getCoverImage")
        FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)
        stub(RenderImage, "scaleBlitBuffer")
        RenderImage.scaleBlitBuffer.returns(mock_scaled)
        stub(Blitbuffer, "new")
        Blitbuffer.new.returns(mock_buffer)

        instance:createCoverImage(mock_ui.doc_settings)

        assert.stub(Blitbuffer.new).was_called_with(600, 800, 1)
        if bg == "white" then
          assert
            .stub(mock_buffer.fill)
            .was_called_with(match.ref(mock_buffer), Blitbuffer.COLOR_WHITE)
        elseif bg == "gray" then
          assert
            .stub(mock_buffer.fill)
            .was_called_with(match.ref(mock_buffer), Blitbuffer.COLOR_GRAY)
        end
        assert.stub(mock_buffer.blitFrom).was_called()
        assert.is_true(mock_buffer.written)

        FileManagerBookInfo.getCoverImage:revert()
        RenderImage.scaleBlitBuffer:revert()
        Blitbuffer.new:revert()
      end
    end
  )

  it("should handle rotated screen cover creation", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })

    stub(Screen, "getRotationMode")
    Screen.getRotationMode.returns(Screen.DEVICE_ROTATED_UPSIDE_DOWN)

    local mock_cover = createMockCoverImage(600, 800)
    stub(mock_cover, "rotatedCopy")
    local mock_rotated = createMockCoverImage(600, 800)
    mock_cover.rotatedCopy.returns(mock_rotated)

    stub(FileManagerBookInfo, "getCoverImage")
    FileManagerBookInfo.getCoverImage.returns(mock_cover, nil)

    instance:createCoverImage(mock_ui.doc_settings)

    assert
      .stub(mock_cover.rotatedCopy)
      .was_called_with(match.ref(mock_cover), 180)
    assert.is_true(mock_cover.freed)

    Screen.getRotationMode:revert()
    FileManagerBookInfo.getCoverImage:revert()
  end)

  it(
    "should perform cache operations emptyCache, getCacheFiles, cleanCache, migrateCache, migrateCover",
    function()
      local instance = CoverImage:new({ ui = createMockUI() })

      -- Create test cache files
      local f1 = io.open(test_cache_dir .. "cover_test1.png", "w")
      f1:write("cache1")
      f1:close()
      local f2 = io.open(test_cache_dir .. "cover_test2.png", "w")
      f2:write("cache2")
      f2:close()

      local count, size, files =
        instance:getCacheFiles(test_cache_dir, "cover_")
      assert.are.equal(2, count)
      assert.is_number(size)
      assert.are.equal(2, #files)

      -- Test cleanCache with maxfiles limit
      instance.cover_image_cache_maxfiles = 1
      instance.cover_image_cache_maxsize = 0
      instance:cleanCache()
      local new_count = instance:getCacheFiles(test_cache_dir, "cover_")
      assert.are.equal(1, new_count)

      -- Test emptyCache
      instance:emptyCache()
      local empty_count = instance:getCacheFiles(test_cache_dir, "cover_")
      assert.are.equal(0, empty_count)

      -- Test migrateCache
      local old_cache = test_dir .. "/old_cache/"
      lfs.mkdir(old_cache)
      local fo = io.open(old_cache .. "cover_old.png", "w")
      fo:write("oldcache")
      fo:close()

      instance:migrateCache(old_cache, test_cache_dir)
      assert.are.equal(
        "file",
        lfs.attributes(test_cache_dir .. "cover_old.png", "mode")
      )
      lfs.rmdir(old_cache)

      -- Test migrateCover
      local old_cover = test_dir .. "/old_cover.png"
      local new_cover = test_dir .. "/new_cover.png"
      local fc = io.open(old_cover, "w")
      fc:write("oldcover")
      fc:close()

      instance:migrateCover(old_cover, new_cover)
      assert.are.equal("file", lfs.attributes(new_cover, "mode"))
      os.remove(new_cover)
    end
  )

  it("should build main menu items and handle callbacks", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })

    local menu_items = {}
    instance:addToMainMenu(menu_items)

    local main_item = menu_items.coverimage
    assert.is_table(main_item)
    assert.are.equal("Cover image", main_item.text)
    assert.is_true(main_item.checked_func())

    local sub_items = main_item.sub_item_table
    assert.is_table(sub_items)

    -- 1. About cover image
    sub_items[1].callback()
    assert.stub(UIManager.show).was_called()

    -- 3. Save cover image
    local save_item = sub_items[3]
    assert.is_true(save_item.checked_func())
    assert.is_true(save_item.enabled_func())
    stub(instance, "createCoverImage")
    stub(instance, "cleanUpImage")

    save_item.callback()
    assert.is_false(instance.cover)
    assert.stub(instance.cleanUpImage).was_called()

    save_item.callback()
    assert.stub(instance.createCoverImage).was_called()

    instance.createCoverImage:revert()
    instance.cleanUpImage:revert()

    -- 4. Size, background and format submenu
    local sbf_item = sub_items[4]
    assert.is_true(sbf_item.enabled_func())
    local sbf_sub = sbf_item.sub_item_table
    assert.is_table(sbf_sub)

    -- Aspect ratio stretch threshold spinner item
    local dummy_menu = { updateItems = spy.new(function() end) }
    assert.is_string(sbf_sub[1].text_func())
    assert.is_string(sbf_sub[1].help_text_func())
    stub(instance, "sizeSpinner")
    sbf_sub[1].callback(dummy_menu)
    assert.stub(instance.sizeSpinner).was_called()
    instance.sizeSpinner:revert()

    -- Background items (black, white, gray, none)
    stub(instance, "createCoverImage")
    local black_bg = sbf_sub[2]
    assert.is_true(black_bg.checked_func())
    local white_bg = sbf_sub[3]
    white_bg.callback()
    assert.are.equal("white", instance.cover_image_background)
    assert.stub(instance.createCoverImage).was_called()
    instance.createCoverImage:revert()

    -- Format items (auto, jpg, png, bmp color, bmp grayscale)
    stub(instance, "createCoverImage")
    local png_fmt = sbf_sub[8]
    png_fmt.callback()
    assert.are.equal("png", instance.cover_image_format)
    assert.stub(instance.createCoverImage).was_called()
    instance.createCoverImage:revert()

    -- 5. Exclude this book cover
    stub(instance, "createCoverImage")
    stub(instance, "cleanUpImage")
    local exclude_item = sub_items[5]
    assert.is_false(exclude_item.checked_func())
    exclude_item.callback()
    assert.is_true(mock_ui.doc_settings:isTrue("exclude_cover_image"))
    assert.stub(instance.cleanUpImage).was_called()
    assert.spy(mock_ui.saveSettings).was_called()

    exclude_item.callback()
    assert.is_false(mock_ui.doc_settings:isTrue("exclude_cover_image"))
    assert.stub(instance.createCoverImage).was_called()

    instance.createCoverImage:revert()
    instance.cleanUpImage:revert()

    -- 7. Turn on fallback image
    local fallback_item = sub_items[7]
    assert.is_true(fallback_item.checked_func())
    assert.is_true(fallback_item.enabled_func())
    fallback_item.callback()
    assert.is_false(instance.fallback)

    -- 8. Cache settings submenu
    local cache_menu = sub_items[8]
    assert.is_true(cache_menu.checked_func())
    local cache_sub = cache_menu.sub_item_table
    assert.is_table(cache_sub)

    assert.is_string(cache_sub[1].text_func())
    assert.is_string(cache_sub[2].text_func())
    assert.is_string(cache_sub[4].help_text_func())

    -- Clear cache callback
    cache_sub[4].callback()
    assert.stub(UIManager.show).was_called()
  end)

  it("should handle choosePathFile and sizeSpinner dialog callbacks", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })
    local dummy_menu = { updateItems = spy.new(function() end) }

    -- choosePathFile folder_only
    instance:choosePathFile(
      dummy_menu,
      "cover_image_cache_path",
      true,
      false,
      nil
    )
    assert.stub(UIManager.show).was_called()

    local path_chooser_widget =
      UIManager.show.calls[#UIManager.show.calls].refs[2]
    assert.is_table(path_chooser_widget)

    -- Simulate directory confirm in PathChooser callback
    path_chooser_widget.onConfirm(test_dir)
    assert.are.equal(test_dir .. "/", instance.cover_image_cache_path)
    assert.spy(dummy_menu.updateItems).was_called()

    -- choosePathFile existing file
    instance:choosePathFile(dummy_menu, "cover_image_path", false, false, nil)
    local file_chooser_widget =
      UIManager.show.calls[#UIManager.show.calls].refs[2]
    file_chooser_widget.onConfirm(test_cover_file)
    assert.are.equal(test_cover_file, instance.cover_image_path)

    -- sizeSpinner
    local callback_spy = spy.new(function() end)
    instance:sizeSpinner(
      dummy_menu,
      "cover_image_quality",
      "Quality",
      1,
      100,
      75,
      callback_spy,
      "%"
    )
    assert.stub(UIManager.show).was_called()

    local spin_widget = UIManager.show.calls[#UIManager.show.calls].refs[2]
    assert.is_table(spin_widget)
    spin_widget.callback({ value = 90 })

    assert.are.equal(90, instance.cover_image_quality)
    assert.spy(callback_spy).was_called()
    assert.spy(dummy_menu.updateItems).was_called()
  end)

  it("should handle choosePathFile new_file mode with InputDialog", function()
    local mock_ui = createMockUI()
    local instance = CoverImage:new({ ui = mock_ui })
    local dummy_menu = { updateItems = spy.new(function() end) }

    instance:choosePathFile(dummy_menu, "cover_image_path", false, true, nil)
    local path_chooser_widget =
      UIManager.show.calls[#UIManager.show.calls].refs[2]

    -- Confirm directory path triggers InputDialog creation
    path_chooser_widget.onConfirm(test_dir)
    assert.stub(UIManager.show).was_called()

    local input_dialog_widget =
      UIManager.show.calls[#UIManager.show.calls].refs[2]
    assert.is_table(input_dialog_widget)

    local save_btn = input_dialog_widget.buttons[1][2]
    assert.are.equal("Save", save_btn.text)

    input_dialog_widget.getInputText = function()
      return test_dir .. "/new_cover.png"
    end
    save_btn.callback()
    assert.are.equal(test_dir .. "/new_cover.png", instance.cover_image_path)
    assert.spy(dummy_menu.updateItems).was_called()
  end)
end)
