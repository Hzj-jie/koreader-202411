local Dispatcher
local Profiles
local UIManager

describe("Profiles plugin", function()
  local mock_ui
  local test_profiles_file = "/tmp/test_profiles_" .. os.time() .. ".lua"

  setup(function()
    require("commonrequire")
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")
    Profiles = require("plugins/profiles.koplugin/main")
    Dispatcher:init()
  end)

  before_each(function()
    os.remove(test_profiles_file)
    UIManager.nextTick = function(_, fn)
      fn()
    end
    mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
      document = {
        file = "/books/test.epub",
        configurable = {
          font_size = 20,
          line_spacing = 100,
        },
      },
      doc_props = {
        display_title = "Test Book",
        authors = "Test Author",
      },
    }
  end)

  after_each(function()
    os.remove(test_profiles_file)
  end)

  describe("Lifecycle and configuration", function()
    it("initializes and loads profiles from file", function()
      local profiles = Profiles:new({
        ui = mock_ui,
        profiles_file = test_profiles_file,
      })

      assert.is_table(profiles)
      profiles:loadProfiles()
      assert.is_table(profiles.data)

      -- Add a profile and verify persistence flag
      profiles.data["Night"] = {
        night_mode = true,
        settings = {},
      }
      profiles.updated = true
      profiles:onFlushSettings()
      assert.is_false(profiles.updated)

      -- Reload from disk
      profiles.profiles = nil
      profiles:loadProfiles()
      assert.is_not_nil(profiles.data["Night"])
      assert.are.equal("Night", profiles.data["Night"].settings.name)
    end)

    it("manages profile entries via save, rename, and delete", function()
      local profiles = Profiles:new({
        ui = mock_ui,
        profiles_file = test_profiles_file,
      })
      profiles:loadProfiles()

      -- Save profile
      profiles.data["Custom"] = {
        font_size = 24,
        settings = { name = "Custom", order = { "font_size" } },
      }
      profiles.updated = true
      profiles:onFlushSettings()

      -- Rename profile
      profiles.autoexec = {
        start = { ["Custom"] = true },
      }
      profiles.data["Custom_Renamed"] = profiles.data["Custom"]
      profiles.data["Custom_Renamed"].settings.name = "Custom_Renamed"
      profiles.data["Custom"] = nil
      profiles.autoexec.start["Custom_Renamed"] = true
      profiles.autoexec.start["Custom"] = nil

      assert.is_nil(profiles.data["Custom"])
      assert.is_not_nil(profiles.data["Custom_Renamed"])
      assert.is_true(profiles.autoexec.start["Custom_Renamed"])

      -- Delete profile
      profiles.data["Custom_Renamed"] = nil
      profiles.autoexec.start["Custom_Renamed"] = nil
      assert.is_nil(profiles.data["Custom_Renamed"])
      assert.is_nil(profiles.autoexec.start["Custom_Renamed"])
    end)

    it("updates action names across existing profiles", function()
      local profiles = Profiles:new({
        ui = mock_ui,
        profiles_file = test_profiles_file,
      })
      profiles:loadProfiles()

      profiles.data["TestProf"] = {
        old_action = true,
        settings = {
          name = "TestProf",
          order = { "old_action" },
        },
      }

      profiles:updateProfiles("old_action", "new_action")
      assert.is_nil(profiles.data["TestProf"].old_action)
      assert.is_true(profiles.data["TestProf"].new_action)
      assert.are.equal(
        "new_action",
        profiles.data["TestProf"].settings.order[1]
      )
    end)
  end)

  describe("Execution and autoexec triggers", function()
    it("executes profile via Dispatcher", function()
      local profiles = Profiles:new({
        ui = mock_ui,
        profiles_file = test_profiles_file,
      })
      profiles:loadProfiles()

      local executed_settings
      local orig_execute = Dispatcher.execute
      Dispatcher.execute = function(_, settings)
        executed_settings = settings
      end

      profiles.data["Day"] = {
        reading_progress = true,
        settings = { name = "Day" },
      }
      profiles:executeAutoExec("Day")

      Dispatcher.execute = orig_execute
      assert.is_not_nil(executed_settings)
      assert.is_true(executed_settings.reading_progress)
    end)

    it("evaluates conditional doc autoexec triggers", function()
      local profiles = Profiles:new({
        ui = mock_ui,
        profiles_file = test_profiles_file,
      })
      profiles:loadProfiles()

      local executed_profiles = {}
      local orig_execute = Dispatcher.execute
      Dispatcher.execute = function(_, settings)
        table.insert(executed_profiles, settings.settings.name)
      end

      profiles.data["EpubProfile"] = {
        some_setting = true,
        settings = { name = "EpubProfile" },
      }
      profiles.autoexec = {
        doc_open = {
          ["EpubProfile"] = {
            filepath = "epub,pdf",
          },
        },
      }

      profiles:executeAutoExecDocConditional("doc_open")
      Dispatcher.execute = orig_execute

      assert.are.equal(1, #executed_profiles)
      assert.are.equal("EpubProfile", executed_profiles[1])
    end)
  end)

  describe("Defect verifications", function()
    it(
      "getProfileFromCurrentBookSettings reads configurable from self.ui.document",
      function()
        local mock_doc = {
          configurable = {
            font_size = 22,
            line_spacing = 100,
            embedded_fonts = 1,
            smooth_scaling = 0,
            nightmode_images = 0,
            trim_page = 0,
            zoom_mode_genus = 0,
            zoom_mode_type = 0,
            page_scroll = 0,
          },
        }
        local profiles = Profiles:new({
          ui = {
            menu = { registerToMainMenu = function() end },
            document = mock_doc,
          },
          profiles_file = test_profiles_file,
        })

        assert.has_no.errors(function()
          local p = profiles:getProfileFromCurrentBookSettings("BookProfile")
          assert.is_table(p)
          assert.are.equal("BookProfile", p.settings.name)
        end)
      end
    )

    it(
      "executeAutoExecDocConditional handles documents with nil metadata properties table",
      function()
        local profiles = Profiles:new({
          ui = {
            menu = { registerToMainMenu = function() end },
            document = { file = "/books/sample.epub" },
            doc_props = nil,
          },
          profiles_file = test_profiles_file,
        })
        profiles.data = {
          ["MangaProfile"] = {
            some_action = true,
            settings = { name = "MangaProfile" },
          },
        }
        profiles.autoexec = {
          doc_open = {
            ["MangaProfile"] = {
              doc_props = {
                series = "Naruto",
              },
            },
          },
        }

        assert.has_no.errors(function()
          profiles:executeAutoExecDocConditional("doc_open")
        end)
      end
    )
  end)
end)
