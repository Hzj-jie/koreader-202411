describe("named_settings", function()
    local named_settings
    local Device, Util
    local orig_hasEinkScreen, orig_isTouchDevice, orig_backup_dir

    local mock_has_eink = false
    local mock_is_touch = true

    setup(function()
        require("commonrequire")
        Device = require("device")
        Util = require("util")

        orig_hasEinkScreen = Device.hasEinkScreen
        orig_isTouchDevice = Device.isTouchDevice
        orig_backup_dir = Util.backup_dir

        named_settings = require("named_settings")

        Device.hasEinkScreen = function() return mock_has_eink end
        Device.isTouchDevice = function() return mock_is_touch end
        Util.backup_dir = function() return "/mock/backup/dir" end
    end)

    teardown(function()
        Device.hasEinkScreen = orig_hasEinkScreen
        Device.isTouchDevice = orig_isTouchDevice
        Util.backup_dir = orig_backup_dir
    end)

    before_each(function()
        local keys = {
            "home_dir", "lastdir", "activate_menu", "auto_standby_timeout_seconds",
            "back_in_filemanager", "back_in_reader", "back_to_exit", "dict_font_size",
            "dimension_units", "document_metadata_folder", "duration_format",
            "show_file_in_bold", "low_pan_rate", "full_refresh_count", "collate",
            "show_bottom_menu", "avoid_flashing_ui"
        }
        for _, key in ipairs(keys) do
            G_reader_settings:delete(key)
        end
        G_reader_settings:flush()

        mock_has_eink = false
        mock_is_touch = true
    end)

    describe("directory settings", function()
        it("should return home_dir setting if present, or fallback to backup_dir", function()
            assert.are.same("/mock/backup/dir", named_settings.home_dir())

            G_reader_settings:save("home_dir", "/my/home/dir")
            assert.are.same("/my/home/dir", named_settings.home_dir())
        end)

        it("should return lastdir setting if present, or fallback to backup_dir", function()
            assert.are.same("/mock/backup/dir", named_settings.lastdir())

            G_reader_settings:save("lastdir", "/my/last/dir")
            assert.are.same("/my/last/dir", named_settings.lastdir())
        end)
    end)

    describe("standard accessors", function()
        it("should return default or saved value for activate_menu", function()
            assert.are.same("swipe_tap", named_settings.activate_menu())
            named_settings.set.activate_menu("double_tap")
            assert.are.same("double_tap", named_settings.activate_menu())
        end)

        it("should return default or saved value for auto_standby_timeout_seconds", function()
            assert.are.same(-1, named_settings.auto_standby_timeout_seconds())
            G_reader_settings:save("auto_standby_timeout_seconds", 300)
            assert.are.same(300, named_settings.auto_standby_timeout_seconds())
        end)

        it("should return default or saved value for back_in_filemanager", function()
            assert.are.same("default", named_settings.back_in_filemanager())
            G_reader_settings:save("back_in_filemanager", "parent")
            assert.are.same("parent", named_settings.back_in_filemanager())
        end)

        it("should return default or saved value for back_in_reader", function()
            assert.are.same("previous_location", named_settings.back_in_reader())
            G_reader_settings:save("back_in_reader", "exit")
            assert.are.same("exit", named_settings.back_in_reader())
        end)

        it("should return default or saved value for back_to_exit", function()
            assert.are.same("prompt", named_settings.back_to_exit())
            G_reader_settings:save("back_to_exit", "never")
            assert.are.same("never", named_settings.back_to_exit())
        end)

        it("should return default or saved value for dict_font_size", function()
            assert.are.same(20, named_settings.dict_font_size())
            G_reader_settings:save("dict_font_size", 25)
            assert.are.same(25, named_settings.dict_font_size())
        end)

        it("should return default or saved value for dimension_units", function()
            assert.are.same("mm", named_settings.dimension_units())
            G_reader_settings:save("dimension_units", "inch")
            assert.are.same("inch", named_settings.dimension_units())
        end)

        it("should return default or saved value for document_metadata_folder", function()
            assert.are.same("doc", named_settings.document_metadata_folder())
            G_reader_settings:save("document_metadata_folder", "metadata")
            assert.are.same("metadata", named_settings.document_metadata_folder())
        end)

        it("should return default or saved value for duration_format", function()
            assert.are.same("classic", named_settings.duration_format())
            G_reader_settings:save("duration_format", "hms")
            assert.are.same("hms", named_settings.duration_format())
        end)

        it("should return default or saved value for show_file_in_bold", function()
            assert.are.same("new", named_settings.show_file_in_bold())
            named_settings.set.show_file_in_bold("always")
            assert.are.same("always", named_settings.show_file_in_bold())
        end)

        it("should return default or saved value for collate", function()
            assert.are.same("strcoll", named_settings.collate())
            named_settings.set.collate("nocase")
            assert.are.same("nocase", named_settings.collate())
        end)
    end)

    describe("E-Ink / refresh rate logic", function()
        it("should fallback to device:hasEinkScreen() for low_pan_rate", function()
            mock_has_eink = false
            assert.is_false(named_settings.low_pan_rate())

            mock_has_eink = true
            assert.is_true(named_settings.low_pan_rate())

            G_reader_settings:save("low_pan_rate", false)
            assert.is_false(named_settings.low_pan_rate())
        end)

        it("should return full rate value or default based on low_pan_rate", function()
            mock_has_eink = false
            assert.are.same(30, named_settings.low_pan_rate_or_full(10))

            mock_has_eink = true
            assert.are.same(10, named_settings.low_pan_rate_or_full(10))
        end)

        it("should return scroll rate value or default based on low_pan_rate", function()
            mock_has_eink = false
            assert.are.same(5, named_settings.low_pan_rate_or_scroll(3))

            mock_has_eink = true
            assert.are.same(3, named_settings.low_pan_rate_or_scroll(3))
            assert.are.same(2, named_settings.low_pan_rate_or_scroll())
        end)

        it("should flip low_pan_rate correctly", function()
            mock_has_eink = false
            named_settings.flip.low_pan_rate()
            assert.is_true(named_settings.low_pan_rate())

            named_settings.flip.low_pan_rate()
            assert.is_false(named_settings.low_pan_rate())
        end)

        it("should handle full_refresh_count correctly", function()
            assert.are.same(24, named_settings.default.full_refresh_count())
            assert.are.same(24, named_settings.full_refresh_count())

            named_settings.set.full_refresh_count(15)
            assert.are.same(15, named_settings.full_refresh_count())
        end)

        it("should return correct fast_screen_refresh status", function()
            mock_has_eink = false
            assert.is_true(named_settings.fast_screen_refresh())

            mock_has_eink = true
            assert.is_false(named_settings.fast_screen_refresh())

            G_reader_settings:save("avoid_flashing_ui", false)
            assert.is_true(named_settings.fast_screen_refresh())

            G_reader_settings:save("avoid_flashing_ui", true)
            assert.is_false(named_settings.fast_screen_refresh())

            named_settings.set.full_refresh_count(10)
            assert.is_true(named_settings.fast_screen_refresh())
        end)
    end)

    describe("show_bottom_menu", function()
        it("should return true for non-touch devices", function()
            mock_is_touch = false
            assert.is_true(named_settings.show_bottom_menu())
        end)

        it("should return nilOrTrue for touch devices", function()
            mock_is_touch = true
            assert.is_true(named_settings.show_bottom_menu())

            G_reader_settings:save("show_bottom_menu", false)
            assert.is_false(named_settings.show_bottom_menu())

            G_reader_settings:save("show_bottom_menu", true)
            assert.is_true(named_settings.show_bottom_menu())
        end)
    end)
end)
