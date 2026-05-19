require("commonrequire")

describe("LanguageSupport", function()
    local LanguageSupport
    local mock_ui
    local mock_menu
    local mock_document

    setup(function()
        LanguageSupport = require("languagesupport")
    end)

    before_each(function()
        -- Reset the shared plugins list between test runs for insulation
        for name, _ in pairs(LanguageSupport.plugins) do
            LanguageSupport.plugins[name] = nil
        end

        -- Setup mock dependencies
        mock_menu = {
            registerToMainMenu = spy.new(function() end)
        }
        mock_ui = {
            menu = mock_menu,
            doc_props = {
                language = "en"
            }
        }
        mock_document = {
            info = {
                has_pages = false
            },
            getPrevVisibleChar = spy.new(function() end),
            getNextVisibleChar = spy.new(function() end),
            getTextFromXPointers = spy.new(function() end),
            getScreenBoxesFromPositions = spy.new(function() end)
        }
    end)

    it("should instantiate correctly and register to main menu", function()
        local ls = LanguageSupport:new({
            ui = mock_ui,
            document = mock_document
        })

        assert.are.equal(mock_document, ls.document)
        assert.are.equal(mock_ui, ls.ui)
        assert.spy(mock_menu.registerToMainMenu).was.called_with(mock_menu, ls)
    end)

    describe("plugin registration", function()
        it("should register a valid plugin successfully", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            local plugin = {
                name = "test_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end
            }

            assert.is_true(ls:registerPlugin(plugin))
            assert.is_true(ls:hasActiveLanguagePlugins())
            assert.are.equal(plugin, ls.plugins["test_plugin"])
        end)

        it("should overwrite an existing plugin with the same name", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            local plugin1 = { name = "test_plugin", id = 1 }
            local plugin2 = { name = "test_plugin", id = 2 }

            assert.is_true(ls:registerPlugin(plugin1))
            assert.is_true(ls:registerPlugin(plugin2))
            assert.are.equal(plugin2, ls.plugins["test_plugin"])
        end)

        it("should reject a plugin with empty or nil name", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            local bad_plugin1 = { name = "" }
            local bad_plugin2 = {}

            assert.is_false(ls:registerPlugin(bad_plugin1))
            assert.is_false(ls:registerPlugin(bad_plugin2))
            assert.is_false(ls:hasActiveLanguagePlugins())
        end)
    end)

    describe("improveWordSelection", function()
        it("should return early if no active plugins are registered", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            local selection = { text = "hello", pos0 = 1, pos1 = 5 }
            
            assert.is_nil(ls:improveWordSelection(selection))
        end)

        it("should return early if no document is attached", function()
            local ls = LanguageSupport:new({ ui = mock_ui })
            local plugin = {
                name = "test_plugin",
                supportsLanguage = function() return true end,
                onWordSelection = function() return { 2, 6 } end
            }
            ls:registerPlugin(plugin)

            local selection = { text = "hello", pos0 = 1, pos1 = 5 }
            assert.is_nil(ls:improveWordSelection(selection))
        end)

        it("should call matching language plugin and return improved selection", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            mock_ui.doc_props.language = "ja"

            local mock_plugin = {
                name = "ja_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end,
                onWordSelection = spy.new(function(self, args)
                    -- simulate calling callbacks
                    local text = args.callbacks.get_text_in_range(args.pos0, args.pos1)
                    assert.are.equal("hello", text)
                    return { 2, 6 } -- improved positions
                end)
            }
            ls:registerPlugin(mock_plugin)

            -- setup document behavior
            mock_document.getTextFromXPointers = spy.new(function(self, p0, p1, clean)
                if clean then
                    return "ellow"
                else
                    return "hello"
                end
            end)
            mock_document.getScreenBoxesFromPositions = spy.new(function(self, p0, p1, flag)
                return { { x = 10, y = 20 } }
            end)

            local selection = { text = "hello", pos0 = 1, pos1 = 5 }
            local result = ls:improveWordSelection(selection)

            assert.is_truthy(result)
            assert.are.equal("ellow", result.text)
            assert.are.equal(2, result.pos0)
            assert.are.equal(6, result.pos1)
            assert.are.same({ { x = 10, y = 20 } }, result.sboxes)

            assert.spy(mock_plugin.onWordSelection).was.called()
            assert.spy(mock_document.getTextFromXPointers).was.called_with(mock_document, 2, 6, true)
            assert.spy(mock_document.getScreenBoxesFromPositions).was.called_with(mock_document, 2, 6, true)
        end)

        it("should fall back to other plugins if the preferred plugin does not exist or returns nil", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            mock_ui.doc_props.language = "ja" -- looking for Japanese plugin

            local ja_plugin = {
                name = "ja_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end,
                onWordSelection = spy.new(function() return nil end) -- fails to improve
            }
            local fallback_plugin = {
                name = "fallback_plugin",
                supportsLanguage = function(self, lang) return lang == "fallback" end,
                onWordSelection = spy.new(function() return { 3, 7 } end) -- succeeds!
            }

            ls:registerPlugin(ja_plugin)
            ls:registerPlugin(fallback_plugin)

            mock_document.getTextFromXPointers = function(self, p0, p1) return "llow" end
            mock_document.getScreenBoxesFromPositions = function() return {} end

            local selection = { text = "hello", pos0 = 1, pos1 = 5 }
            local result = ls:improveWordSelection(selection)

            assert.is_truthy(result)
            assert.are.equal(3, result.pos0)
            assert.are.equal(7, result.pos1)
            assert.spy(ja_plugin.onWordSelection).was.called()
            assert.spy(fallback_plugin.onWordSelection).was.called()
        end)

        it("should return nil if no plugin changes the selection range", function()
            local ls = LanguageSupport:new({ ui = mock_ui, document = mock_document })
            mock_ui.doc_props.language = "ja"

            local mock_plugin = {
                name = "ja_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end,
                onWordSelection = spy.new(function(self, args)
                    return { args.pos0, args.pos1 } -- returns unchanged positions
                end)
            }
            ls:registerPlugin(mock_plugin)

            local selection = { text = "hello", pos0 = 1, pos1 = 5 }
            local result = ls:improveWordSelection(selection)

            assert.is_nil(result)
            assert.spy(mock_plugin.onWordSelection).was.called()
        end)
    end)

    describe("extraDictionaryFormCandidates", function()
        it("should return early if no active plugins are registered", function()
            local ls = LanguageSupport:new({ ui = mock_ui })
            assert.is_nil(ls:extraDictionaryFormCandidates("hello"))
        end)

        it("should call WordLookup on preferred language plugin and return candidates", function()
            local ls = LanguageSupport:new({ ui = mock_ui })
            mock_ui.doc_props = { language = "ja" }

            local mock_plugin = {
                name = "ja_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end,
                onWordLookup = spy.new(function(self, args)
                    assert.are.equal("taberu", args.text)
                    return { "tabe", "taberu" }
                end)
            }
            ls:registerPlugin(mock_plugin)

            local candidates = ls:extraDictionaryFormCandidates("taberu")
            assert.are.same({ "tabe", "taberu" }, candidates)
            assert.spy(mock_plugin.onWordLookup).was.called()
        end)

        it("should fall back to other plugins if preferred plugin returns nil", function()
            local ls = LanguageSupport:new({ ui = mock_ui })
            mock_ui.doc_props = { language = "ja" }

            local ja_plugin = {
                name = "ja_plugin",
                supportsLanguage = function(self, lang) return lang == "ja" end,
                onWordLookup = spy.new(function() return nil end)
            }
            local fallback_plugin = {
                name = "fallback_plugin",
                supportsLanguage = function(self, lang) return lang == "fallback" end,
                onWordLookup = spy.new(function() return { "fallback_candidate" } end)
            }

            ls:registerPlugin(ja_plugin)
            ls:registerPlugin(fallback_plugin)

            local candidates = ls:extraDictionaryFormCandidates("something")
            assert.are.same({ "fallback_candidate" }, candidates)
            assert.spy(ja_plugin.onWordLookup).was.called()
            assert.spy(fallback_plugin.onWordLookup).was.called()
        end)
    end)

    describe("addToMainMenu", function()
        it("should do nothing if no active plugins are registered", function()
            local ls = LanguageSupport:new({ ui = mock_ui })
            local menu_items = {}
            ls:addToMainMenu(menu_items)
            assert.is_nil(menu_items.language_support)
        end)

        it("should add language_support item with submenus sorted alphabetically", function()
            local ls = LanguageSupport:new({ ui = mock_ui })

            local plugin_b = {
                name = "b_plugin",
                pretty_name = "B Plugin",
                description = "B Desc"
            }
            local plugin_a = {
                name = "a_plugin",
                description = "A Desc",
                genMenuItem = spy.new(function()
                    return { text = "A Menu Item" }
                end)
            }

            ls:registerPlugin(plugin_b)
            ls:registerPlugin(plugin_a)

            local menu_items = {}
            ls:addToMainMenu(menu_items)

            assert.is_truthy(menu_items.language_support)
            assert.are.equal("Language support plugins", menu_items.language_support.text)

            local sub = menu_items.language_support.sub_item_table
            assert.are.equal(2, #sub)

            -- A should be first (alphabetical sort by name "a_plugin" < "b_plugin")
            assert.are.equal("A Menu Item", sub[1].text)
            assert.are.equal("A Desc", sub[1].help_text) -- help_text fell back to description

            -- B should be second
            assert.are.equal("B Plugin", sub[2].text)
            assert.are.equal("B Desc", sub[2].help_text)

            assert.spy(plugin_a.genMenuItem).was.called()
        end)
    end)
end)
