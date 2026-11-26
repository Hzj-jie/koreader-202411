describe("Gestures settings recovery", function()
  local FileManager, Gestures, InputContainer
  local gestures_path, instances, orig_fm, orig_gestures, orig_rtl

  local function writeGesturesFile(content)
    local f = assert(io.open(gestures_path, "wb"))
    f:write(content)
    f:close()
  end

  local function openGestures(with_document)
    local instance = Gestures:new({
      ui = {
        menu = { registerToMainMenu = function() end },
        document = with_document and { configurable = {} } or nil,
        registerTouchZones = function() end,
      },
      path = "plugins/gestures.koplugin",
    })
    table.insert(instances, instance)
    return instance
  end

  local function assertMenuAndActivation(gestures)
    local menu_items = {}
    gestures:addToMainMenu(menu_items)
    assert.is_table(menu_items.gesture_manager)
    assert.is_falsy(InputContainer:isGestureAlwaysActive("tap_corner", nil))
  end

  local function assertActiveModeRecovered(gestures, with_document)
    assert.is_table(gestures.custom_multiswipes)
    assert.are.same({}, gestures.custom_multiswipes)
    assert.is_table(
      gestures.settings_data.data[with_document and "gesture_reader" or "gesture_fm"]
    )
    assert.is_false(gestures.updated)
  end

  setup(function()
    require("commonrequire")

    FileManager = require("apps/filemanager/filemanager")
    Gestures = require("plugins/gestures.koplugin/main")
    InputContainer = require("ui/widget/container/inputcontainer")

    local settings_dir = require("datastorage"):getSettingsDir()
    require("util").makePath(settings_dir)
    gestures_path = settings_dir .. "/gestures.lua"

    local orig_file = io.open(gestures_path, "rb")
    if orig_file then
      orig_gestures = orig_file:read("*a")
      orig_file:close()
    end
  end)

  before_each(function()
    instances = {}
    orig_fm = FileManager.instance
    FileManager.instance = {
      menu = { registerToMainMenu = function() end },
      document = nil,
      registerTouchZones = function() end,
    }
    orig_rtl = {
      gesture_fmui_lang_direction_rtl = G_reader_settings:read(
        "gesture_fmui_lang_direction_rtl"
      ),
      gesture_readerui_lang_direction_rtl = G_reader_settings:read(
        "gesture_readerui_lang_direction_rtl"
      ),
    }
  end)

  after_each(function()
    for i = #instances, 1, -1 do
      instances[i]:onClose()
    end
    instances = nil
    InputContainer.isGestureAlwaysActive = InputContainer._isGestureAlwaysActive
    FileManager.instance = orig_fm

    for key, value in pairs(orig_rtl) do
      if value ~= nil then
        G_reader_settings:save(key, value)
      else
        G_reader_settings:delete(key)
      end
    end

    if orig_gestures ~= nil then
      writeGesturesFile(orig_gestures)
    else
      os.remove(gestures_path)
    end
  end)

  it(
    "preserves gesture_fm, keeps inactive gesture_reader nil in FM mode, and recovers reader mode cleanly",
    function()
      writeGesturesFile(
        "return { gesture_fm = { tap_top_left_corner = { full_refresh = true } } }\n"
      )

      local fm_gestures = openGestures(false)
      assertMenuAndActivation(fm_gestures)
      assert.are.same(
        { full_refresh = true },
        fm_gestures.gestures.tap_top_left_corner
      )
      assertActiveModeRecovered(fm_gestures, false)
      assert.is_nil(fm_gestures.settings_data.data.gesture_reader)

      writeGesturesFile(
        "return { gesture_fm = { tap_top_left_corner = { full_refresh = true } } }\n"
      )

      local reader_gestures = openGestures(true)
      assertMenuAndActivation(reader_gestures)
      assertActiveModeRecovered(reader_gestures, true)
      assert.are.same(
        { full_refresh = true },
        reader_gestures.settings_data.data.gesture_fm.tap_top_left_corner
      )
      assert.are.same(reader_gestures.defaults, reader_gestures.gestures)
      assert.are_not.equal(reader_gestures.defaults, reader_gestures.gestures)
      reader_gestures.gestures.short_diagonal_swipe.extra = true
      assert.is_nil(reader_gestures.defaults.short_diagonal_swipe.extra)
    end
  )

  it(
    "clears non-table inactive mode and stray scalars to nil and recovers defaults when that mode opens",
    function()
      writeGesturesFile(
        "return { gesture_fm = { hold_top_right_corner = { full_refresh = true } }, gesture_reader = 5, extra_scalar = 123 }\n"
      )

      local fm_gestures = openGestures(false)
      assertMenuAndActivation(fm_gestures)
      assert.are.same(
        { full_refresh = true },
        fm_gestures.gestures.hold_top_right_corner
      )
      assertActiveModeRecovered(fm_gestures, false)
      assert.is_nil(fm_gestures.settings_data.data.gesture_reader)
      assert.is_nil(fm_gestures.settings_data.data.extra_scalar)

      writeGesturesFile(
        "return { gesture_fm = { hold_top_right_corner = { full_refresh = true } }, gesture_reader = 5, extra_scalar = 123 }\n"
      )

      local reader_gestures = openGestures(true)
      assertMenuAndActivation(reader_gestures)
      assertActiveModeRecovered(reader_gestures, true)
      assert.are.same(
        { full_refresh = true },
        reader_gestures.settings_data.data.gesture_fm.hold_top_right_corner
      )
      assert.is_nil(reader_gestures.settings_data.data.extra_scalar)
      assert.are.same(reader_gestures.defaults, reader_gestures.gestures)
      assert.are_not.equal(reader_gestures.defaults, reader_gestures.gestures)
    end
  )

  it(
    "replaces non-table active mode with deep-copied defaults while keeping valid inactive mode",
    function()
      writeGesturesFile(
        'return { gesture_fm = "x", gesture_reader = { tap_top_left_corner = { toggle_page_flipping = false } } }\n'
      )

      local gestures = openGestures(false)
      assertMenuAndActivation(gestures)
      assertActiveModeRecovered(gestures, false)
      assert.are.same(
        { tap_top_left_corner = { toggle_page_flipping = false } },
        gestures.settings_data.data.gesture_reader
      )
      assert.are.same(gestures.defaults, gestures.gestures)
      assert.are_not.equal(gestures.defaults, gestures.gestures)
      gestures.gestures.short_diagonal_swipe.extra = true
      assert.is_nil(gestures.defaults.short_diagonal_swipe.extra)
    end
  )

  it("restores missing custom_multiswipes when both modes exist", function()
    writeGesturesFile("return { gesture_fm = {}, gesture_reader = {} }\n")

    local gestures = openGestures(false)
    assertMenuAndActivation(gestures)
    assertActiveModeRecovered(gestures, false)
    assert.is_table(gestures.settings_data.data.gesture_reader)
  end)

  it("replaces non-table custom_multiswipes with empty table", function()
    writeGesturesFile(
      'return { gesture_fm = {}, gesture_reader = {}, custom_multiswipes = "corrupted" }\n'
    )

    local gestures = openGestures(false)
    assertMenuAndActivation(gestures)
    assertActiveModeRecovered(gestures, false)
    assert.is_table(gestures.settings_data.data.gesture_reader)
  end)

  for _, case in ipairs({
    { name = "truncated gestures.lua", content = "{" },
    { name = "empty gestures.lua", content = "" },
    { name = "non-table gestures.lua", content = "return true\n" },
  }) do
    it(
      "recovers defaults lazily without aliasing on "
        .. case.name
        .. " in FM and reader modes",
      function()
        for _, with_document in ipairs({ false, true }) do
          writeGesturesFile(case.content)

          local gestures = openGestures(with_document)
          assertMenuAndActivation(gestures)
          assertActiveModeRecovered(gestures, with_document)
          assert.is_nil(
            gestures.settings_data.data[with_document and "gesture_fm" or "gesture_reader"]
          )
          assert.are.same(gestures.defaults, gestures.gestures)
          assert.are_not.equal(gestures.defaults, gestures.gestures)
          gestures.gestures.short_diagonal_swipe.extra = true
          assert.is_nil(gestures.defaults.short_diagonal_swipe.extra)
        end
      end
    )
  end

  it(
    "removes custom multiswipe safely when inactive mode section is nil",
    function()
      writeGesturesFile(
        "return { gesture_fm = { multiswipe_north_east_south_west = { next_page = true } }, custom_multiswipes = { multiswipe_north_east_south_west = true } }\n"
      )

      local gestures = openGestures(false)
      assert.is_false(gestures.updated)

      local show_stub = stub(require("ui/uimanager"), "show")
      finally(function()
        show_stub:revert()
      end)

      gestures:genCustomMultiswipeSubmenu()[2].hold_callback({
        item_table = {},
        updateItems = function() end,
      })
      local confirm_box = show_stub.calls[1].vals[2]
      assert.is_table(confirm_box)
      confirm_box.ok_callback()

      assert.is_nil(
        gestures.custom_multiswipes.multiswipe_north_east_south_west
      )
      assert.is_nil(gestures.gestures.multiswipe_north_east_south_west)
      assert.is_nil(gestures.settings_data.data.gesture_reader)
      assert.is_true(gestures.updated)
    end
  )

  it("updates profiles safely when inactive mode section is nil", function()
    writeGesturesFile(
      "return { gesture_fm = { tap_top_left_corner = { profile_exec_old = true, settings = { order = { 'profile_exec_old' } } } }, custom_multiswipes = {} }\n"
    )

    local gestures = openGestures(false)
    assert.is_false(gestures.updated)

    gestures:updateProfiles("profile_exec_old", "profile_exec_new")
    assert.is_nil(gestures.gestures.tap_top_left_corner.profile_exec_old)
    assert.is_true(gestures.gestures.tap_top_left_corner.profile_exec_new)
    assert.are.equal(
      "profile_exec_new",
      gestures.gestures.tap_top_left_corner.settings.order[1]
    )
    assert.is_true(gestures.updated)
    assert.is_nil(gestures.settings_data.data.gesture_reader)

    gestures:updateProfiles("profile_exec_new", nil)
    assert.is_nil(gestures.gestures.tap_top_left_corner)
    assert.is_nil(gestures.settings_data.data.gesture_reader)
  end)
end)
