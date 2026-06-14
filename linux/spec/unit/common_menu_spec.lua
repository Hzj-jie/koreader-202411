describe("CommonMenu apps helper", function()
    local CommonMenu
    local mock_confirm_box_instance
    local mock_confirm_box_class
    local mock_power_device
    local mock_device
    local mock_uimanager
    local gettext_called_with

    setup(function()
        require("commonrequire")
    end)

    before_each(function()
        -- Reset mocks for each test
        gettext_called_with = {}
        mock_confirm_box_instance = {}
        mock_confirm_box_class = {
            new = function(self, args)
                mock_confirm_box_instance.args = args
                return mock_confirm_box_instance
            end
        }
        package.loaded["ui/widget/confirmbox"] = mock_confirm_box_class

        mock_power_device = {
            turnOnFrontlight_called = false,
            turnOnFrontlight = function(self)
                self.turnOnFrontlight_called = true
            end
        }

        mock_device = {
            startup_script_up_to_date = true,
            isStartupScriptUpToDate = function(self)
                return self.startup_script_up_to_date
            end,
            getPowerDevice = function(self)
                return mock_power_device
            end
        }
        package.loaded["device"] = mock_device

        mock_uimanager = {
            shown_widget = nil,
            next_tick_callback = nil,
            show = function(self, widget)
                self.shown_widget = widget
            end,
            nextTick = function(self, cb)
                self.next_tick_callback = cb
            end
        }
        package.loaded["ui/uimanager"] = mock_uimanager

        package.loaded["gettext"] = function(text)
            table.insert(gettext_called_with, text)
            return text
        end

        -- Force reload CommonMenu so it grabs the mocks
        package.loaded["apps/common_menu"] = nil
        CommonMenu = require("apps/common_menu")
    end)

    after_each(function()
        package.loaded["apps/common_menu"] = nil
        package.loaded["ui/widget/confirmbox"] = nil
        package.loaded["device"] = nil
        package.loaded["ui/uimanager"] = nil
        package.loaded["gettext"] = nil
    end)

    describe("exitOrRestart", function()
        it("should assert if before_exit or ui is missing", function()
            assert.has_error(function()
                CommonMenu:exitOrRestart(nil, {})
            end)
            assert.has_error(function()
                CommonMenu:exitOrRestart(function() end, nil)
            end)
        end)

        it("should perform exit cleanly (without restart)", function()
            local before_exit_called = false
            local on_exit_called = false
            local ui = {
                onExit = function()
                    on_exit_called = true
                end
            }

            CommonMenu:exitOrRestart(
                function() before_exit_called = true end,
                ui
            )

            -- before_exit should be called immediately
            assert.is_true(before_exit_called)
            assert.is_false(on_exit_called)
            assert.is_false(mock_power_device.turnOnFrontlight_called)

            -- Deferral via UIManager nextTick should still be pending execution
            assert.truthy(mock_uimanager.next_tick_callback)

            -- Trigger next tick execution
            mock_uimanager.next_tick_callback()

            assert.is_true(on_exit_called)
            assert.is_true(mock_power_device.turnOnFrontlight_called)
            assert.is_nil(mock_uimanager.shown_widget) -- No confirmation box shown
        end)

        it("should perform restart cleanly when startup script is up to date", function()
            local before_exit_called = false
            local on_exit_called = false
            local after_exit_called = false
            local ui = {
                onExit = function()
                    on_exit_called = true
                end
            }

            mock_device.startup_script_up_to_date = true

            CommonMenu:exitOrRestart(
                function() before_exit_called = true end,
                ui,
                function() after_exit_called = true end
            )

            assert.is_true(before_exit_called)
            assert.is_false(on_exit_called)
            assert.is_false(after_exit_called)

            -- Execute next tick
            assert.truthy(mock_uimanager.next_tick_callback)
            mock_uimanager.next_tick_callback()

            assert.is_true(on_exit_called)
            assert.is_true(after_exit_called)
            assert.is_true(mock_power_device.turnOnFrontlight_called)
            assert.is_nil(mock_uimanager.shown_widget)
        end)

        it("should show confirmation box when startup script is outdated and not forced", function()
            local before_exit_called = false
            local on_exit_called = false
            local after_exit_called = false
            local ui = {
                onExit = function()
                    on_exit_called = true
                end
            }

            mock_device.startup_script_up_to_date = false

            CommonMenu:exitOrRestart(
                function() before_exit_called = true end,
                ui,
                function() after_exit_called = true end
            )

            -- Should NOT exit immediately or schedule next tick
            assert.is_false(before_exit_called)
            assert.is_nil(mock_uimanager.next_tick_callback)

            -- Should show a ConfirmBox
            assert.are.equal(mock_confirm_box_instance, mock_uimanager.shown_widget)
            assert.truthy(mock_confirm_box_instance.args)
            assert.truthy(mock_confirm_box_instance.args.ok_callback)

            -- Verify text is translated
            assert.are.equal(
                "KOReader's startup script has been updated. You'll need to completely exit KOReader to finalize the update.",
                mock_confirm_box_instance.args.text
            )
            assert.are.equal("Restart anyway", mock_confirm_box_instance.args.ok_text)

            -- Simulate user clicking OK (which forces the restart)
            mock_confirm_box_instance.args.ok_callback()

            -- Now it should run with force = true, calling before_exit immediately
            assert.is_true(before_exit_called)
            assert.is_false(on_exit_called)
            assert.is_false(after_exit_called)

            -- Schedule the exit on next tick
            assert.truthy(mock_uimanager.next_tick_callback)
            mock_uimanager.next_tick_callback()

            assert.is_true(on_exit_called)
            assert.is_true(after_exit_called)
            assert.is_true(mock_power_device.turnOnFrontlight_called)
        end)
    end)
end)
