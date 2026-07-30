describe("Profiles plugin", function()
  local ProfilesClass, DataStorage, Dispatcher, UIManager, LuaSettings, util, Device, Screen
  local mock_ui, profiles_instance, test_profiles_file

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")
    LuaSettings = require("luasettings")
    util = require("util")
    Device = require("device")
    Screen = Device.screen
    ProfilesClass = require("plugins/profiles.koplugin/main")
  end)

  before_each(function()
    test_profiles_file = DataStorage:getSettingsDir()
      .. "/test_profiles_"
      .. os.time()
      .. ".lua"
    os.remove(test_profiles_file)

    G_reader_settings:save("profiles_autoexec", {})

    mock_ui = {
      menu = {
        registerToMainMenu = stub(),
      },
      document = nil,
    }

    profiles_instance = ProfilesClass:new({
      ui = mock_ui,
      profiles_file = test_profiles_file,
    })
  end)

  after_each(function()
    if test_profiles_file then
      os.remove(test_profiles_file)
    end
    G_reader_settings:delete("profiles_autoexec")
  end)

  describe("Initialization & Loading", function()
    it(
      "should initialize Profiles plugin class and register to main menu",
      function()
        assert.is_table(profiles_instance)
        assert.are.equal("profiles", profiles_instance.name)
        assert.stub(mock_ui.menu.registerToMainMenu).was.called(1)
      end
    )

    it("should load profiles and assign profile names if missing", function()
      local lua_settings = LuaSettings:open(test_profiles_file)
      lua_settings.data = {
        ["Night Mode"] = {
          toggle_night_mode = true,
          settings = {},
        },
      }
      lua_settings:flush()

      profiles_instance.profiles = nil
      profiles_instance:loadProfiles()

      assert.is_not_nil(profiles_instance.data["Night Mode"])
      assert.are.equal(
        "Night Mode",
        profiles_instance.data["Night Mode"].settings.name
      )
    end)

    it("should flush settings when updated flag is set", function()
      profiles_instance:loadProfiles()
      profiles_instance.updated = true

      stub(profiles_instance.profiles, "flush")
      profiles_instance:onFlushSettings()

      assert.stub(profiles_instance.profiles.flush).was.called(1)
      assert.is_false(profiles_instance.updated)
      profiles_instance.profiles.flush:revert()
    end)
  end)

  describe("Dispatcher Registration", function()
    it(
      "should register profiles with settings.registered = true when action registration is requested",
      function()
        local register_stub = stub(Dispatcher, "registerAction")
        profiles_instance.data = {
          ["RegProfile"] = {
            settings = { name = "RegProfile", registered = true },
          },
        }

        profiles_instance:onDispatcherRegisterActions()

        assert
          .stub(register_stub).was
          .called_with(Dispatcher, "profile_exec_RegProfile", match.is_table())
        register_stub:revert()
      end
    )
  end)

  describe("Profile Creation from Book Settings", function()
    it(
      "should extract profile from current book settings in non-rolling mode",
      function()
        mock_ui.rolling = nil
        mock_ui.document = {
          configurable = {
            rotation_mode = "portrait",
            text_wrap = 1,
            trim_page = 0,
            page_margin = 10,
            zoom_overlap_h = 0,
            zoom_overlap_v = 0,
            max_columns = 2,
            zoom_mode_genus = 1,
            zoom_mode_type = 1,
            zoom_factor = 1.2,
            zoom_direction = 0,
            page_scroll = 0,
            line_spacing = 1.2,
            font_size = 20,
            contrast = 1.0,
            quality = 1,
          },
        }
        profiles_instance.ui = mock_ui
        profiles_instance.document = mock_ui.document

        local profile =
          profiles_instance:getProfileFromCurrentBookSettings("BookProfile")
        assert.are.equal("BookProfile", profile.settings.name)
        assert.are.equal(20, profile.kopt_font_size)
      end
    )

    it(
      "should extract profile from current book settings in rolling mode",
      function()
        mock_ui.rolling = true
        mock_ui.font = { font_face = "Noto Sans" }
        mock_ui.document = {
          configurable = {
            rotation_mode = "portrait",
            font_size = 22,
            font_gamma = 15,
            font_base_weight = 0,
            font_hinting = 1,
            font_kerning = 1,
            word_spacing = 100,
            word_expansion = 0,
            visible_pages = 1,
            h_page_margins = 10,
            sync_t_b_page_margins = true,
            t_page_margin = 5,
            b_page_margin = 5,
            view_mode = "page",
            block_rendering_mode = 0,
            render_dpi = 300,
            line_spacing = 1.5,
            embedded_css = true,
            embedded_fonts = true,
            smooth_scaling = false,
            nightmode_images = false,
            status_line = true,
          },
        }
        profiles_instance.ui = mock_ui
        profiles_instance.document = mock_ui.document

        local profile =
          profiles_instance:getProfileFromCurrentBookSettings("RollingProfile")
        assert.are.equal("RollingProfile", profile.settings.name)
        assert.are.equal(22, profile.font_size)
        assert.are.equal("Noto Sans", profile.set_font)
      end
    )
  end)

  describe("Profile Management Operations", function()
    before_each(function()
      profiles_instance.data = {
        ["ProfileA"] = {
          settings = { name = "ProfileA", registered = true },
          action1 = true,
        },
      }
    end)

    it(
      "should update autoexec entries when profile name changes or is removed",
      function()
        profiles_instance.autoexec = {
          Start = { ProfileA = true },
          Resume = { ProfileA = true },
        }

        profiles_instance:updateAutoExec("ProfileA", "ProfileB")
        assert.is_nil(profiles_instance.autoexec.Start.ProfileA)
        assert.is_true(profiles_instance.autoexec.Start.ProfileB)

        profiles_instance:updateAutoExec("ProfileB", nil)
        assert.is_nil(profiles_instance.autoexec.Start)
        assert.is_nil(profiles_instance.autoexec.Resume)
      end
    )

    it(
      "should update profile actions when action names are renamed or removed",
      function()
        profiles_instance.data = {
          ["Profile1"] = {
            settings = { name = "Profile1", order = { "action_old" } },
            action_old = true,
          },
        }

        profiles_instance:updateProfiles("action_old", "action_new")
        assert.is_nil(profiles_instance.data.Profile1.action_old)
        assert.is_true(profiles_instance.data.Profile1.action_new)
        assert.are.equal(
          "action_new",
          profiles_instance.data.Profile1.settings.order[1]
        )

        profiles_instance:updateProfiles("action_new", nil)
        assert.is_nil(profiles_instance.data.Profile1.action_new)
        assert.is_nil(profiles_instance.data.Profile1.settings.order)
      end
    )
  end)

  describe("Profile Execution", function()
    it("should execute profile via Dispatcher", function()
      profiles_instance.data = {
        ["TestProfile"] = { settings = { name = "TestProfile" } },
      }
      local exec_stub = stub(Dispatcher, "execute")

      profiles_instance:onProfileExecute("TestProfile", { qm_show = false })
      assert
        .stub(exec_stub).was
        .called_with(Dispatcher, profiles_instance.data["TestProfile"], { qm_show = false })
      exec_stub:revert()
    end)

    it(
      "should execute autoexec profile on next tick when ask is not set",
      function()
        profiles_instance.data = {
          ["AutoProfile"] = { settings = { name = "AutoProfile" } },
        }
        local next_tick_stub = stub(UIManager, "nextTick")

        profiles_instance:executeAutoExec("AutoProfile")
        assert.stub(next_tick_stub).was.called(1)
        next_tick_stub:revert()
      end
    )

    it("should show ConfirmBox when auto_exec_ask is true", function()
      profiles_instance.data = {
        ["AskProfile"] = {
          settings = { name = "AskProfile", auto_exec_ask = true },
        },
      }
      local show_stub = stub(UIManager, "show")

      profiles_instance:executeAutoExec("AskProfile")
      assert.stub(show_stub).was.called(1)
      show_stub:revert()
    end)
  end)

  describe("Event Triggers", function()
    before_each(function()
      profiles_instance.data = {
        ["P1"] = { settings = { name = "P1" } },
      }
    end)

    it(
      "should handle executeAutoExecEvent for Start and Resume events",
      function()
        profiles_instance.autoexec = { Start = { P1 = true } }
        local exec_stub = stub(profiles_instance, "executeAutoExec")

        profiles_instance:executeAutoExecEvent("Start")
        assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
        exec_stub:revert()
      end
    )

    it("should handle onResume", function()
      profiles_instance.autoexec = { Resume = { P1 = true } }
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:onResume()
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      exec_stub:revert()
    end)

    it("should handle onSetRotationMode", function()
      profiles_instance.autoexec = {
        SetRotationMode = { P1 = { portrait = true } },
      }
      local broadcast_stub = stub(UIManager, "broadcastEvent")
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:onSetRotationMode("portrait")
      assert.stub(broadcast_stub).was.called_with(UIManager, "CloseConfigMenu")
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      broadcast_stub:revert()
      exec_stub:revert()
    end)

    it(
      "should handle onPathChanged with matching has and has_not patterns",
      function()
        profiles_instance.autoexec = {
          PathChanged = {
            P1 = { has = "books,reading" },
            P2 = { has_not = "private" },
          },
        }
        profiles_instance.data = {
          ["P1"] = { settings = { name = "P1" } },
          ["P2"] = { settings = { name = "P2" } },
        }
        local exec_stub = stub(profiles_instance, "executeAutoExec")

        profiles_instance:onPathChanged("/sdcard/books/fiction")
        assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
        assert.stub(exec_stub).was.called_with(profiles_instance, "P2")
        exec_stub:revert()
      end
    )

    it(
      "should handle onReaderReady and onCloseDocument when not reloading",
      function()
        profiles_instance.autoexec = {
          ReaderReady = { P1 = true },
          CloseDocument = { P1 = true },
        }
        mock_ui.reloading = false
        profiles_instance.ui = mock_ui
        local exec_event_stub = stub(profiles_instance, "executeAutoExecEvent")

        profiles_instance:onReaderReady()
        assert
          .stub(exec_event_stub).was
          .called_with(profiles_instance, "ReaderReady")

        profiles_instance:onCloseDocument()
        assert
          .stub(exec_event_stub).was
          .called_with(profiles_instance, "CloseDocument")
        exec_event_stub:revert()
      end
    )
  end)

  describe("Doc Conditional AutoExec", function()
    it("should execute when orientation matches", function()
      profiles_instance.data = { ["P1"] = { settings = { name = "P1" } } }
      profiles_instance.autoexec = {
        ReaderReadyAll = {
          P1 = { orientation = { portrait = true } },
        },
      }
      local rotation_stub = stub(Screen, "getRotationMode")
      rotation_stub.returns("portrait")
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:executeAutoExecDocConditional("ReaderReadyAll")
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      rotation_stub:revert()
      exec_stub:revert()
    end)

    it("should execute when doc_props matches", function()
      profiles_instance.data = { ["P1"] = { settings = { name = "P1" } } }
      profiles_instance.autoexec = {
        ReaderReadyAll = {
          P1 = { doc_props = { title = "Sci-Fi,Fantasy" } },
        },
      }
      mock_ui.document = {}
      mock_ui.doc_props = { display_title = "Dune Sci-Fi Special" }
      profiles_instance.ui = mock_ui
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:executeAutoExecDocConditional("ReaderReadyAll")
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      exec_stub:revert()
    end)

    it("should execute when filepath matches", function()
      profiles_instance.data = { ["P1"] = { settings = { name = "P1" } } }
      profiles_instance.autoexec = {
        ReaderReadyAll = {
          P1 = { filepath = "downloads" },
        },
      }
      mock_ui.document = { file = "/sdcard/downloads/sample.epub" }
      profiles_instance.ui = mock_ui
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:executeAutoExecDocConditional("ReaderReadyAll")
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      exec_stub:revert()
    end)

    it("should execute when collections match", function()
      profiles_instance.data = { ["P1"] = { settings = { name = "P1" } } }
      profiles_instance.autoexec = {
        ReaderReadyAll = {
          P1 = { collections = { Favorites = true } },
        },
      }
      mock_ui.document = { file = "/sdcard/book.epub" }
      profiles_instance.ui = mock_ui

      local ReadCollection = require("readcollection")
      local is_in_coll_stub = stub(ReadCollection, "isFileInCollection")
      is_in_coll_stub.returns(true)
      local exec_stub = stub(profiles_instance, "executeAutoExec")

      profiles_instance:executeAutoExecDocConditional("ReaderReadyAll")
      assert.stub(exec_stub).was.called_with(profiles_instance, "P1")
      is_in_coll_stub:revert()
      exec_stub:revert()
    end)
  end)

  describe("Menu Generators", function()
    it("should populate main menu items table", function()
      local menu_items = {}
      profiles_instance:addToMainMenu(menu_items)

      assert.is_not_nil(menu_items.profiles)
      assert.is_function(menu_items.profiles.sub_item_table_func)

      local sub_items = menu_items.profiles.sub_item_table_func()
      assert.is_table(sub_items)
      assert.are.equal("New", sub_items[1].text)
    end)

    it("should generate autoexec menu item and handle callback", function()
      profiles_instance.autoexec = {}
      local item =
        profiles_instance:genAutoExecMenuItem("On Start", "Start", "P1")

      assert.is_nil(item.checked_func())
      item.callback()
      assert.is_true(item.checked_func())
      item.callback()
      assert.is_nil(item.checked_func())
    end)

    it("should generate autoexec set rotation mode menu item", function()
      profiles_instance.autoexec = {}
      local item = profiles_instance:genAutoExecSetRotationModeMenuItem(
        "On Rotation",
        "SetRotationMode",
        "P1"
      )

      assert.is_nil(item.checked_func())
      local sub_items = item.sub_item_table_func()
      assert.is_table(sub_items)
      assert.is_true(#sub_items > 0)
    end)

    it("should generate autoexec path changed menu item", function()
      profiles_instance.autoexec = {}
      local item = profiles_instance:genAutoExecPathChangedMenuItem(
        "On Folder",
        "PathChanged",
        "P1"
      )

      assert.is_nil(item.checked_func())
      local sub_items = item.sub_item_table_func()
      assert.is_table(sub_items)
      assert.are.equal(2, #sub_items)
    end)

    it("should generate doc conditional autoexec menu item", function()
      profiles_instance.autoexec = {}
      local item = profiles_instance:genAutoExecDocConditionalMenuItem(
        "On Book Open",
        "ReaderReadyAll",
        "P1"
      )

      assert.is_nil(item.checked_func())
      local sub_items = item.sub_item_table_func()
      assert.is_table(sub_items)
      assert.is_true(#sub_items >= 4)
    end)
  end)
end)
