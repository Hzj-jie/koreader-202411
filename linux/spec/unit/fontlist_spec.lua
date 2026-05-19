local FontList
local CanvasContext
local util
local Persist
local lfs
local HB

describe("FontList", function()
    setup(function()
        require("commonrequire")
        FontList = require("fontlist")
        CanvasContext = require("document/canvascontext")
        util = require("util")
        Persist = require("persist")
        lfs = require("libs/libkoreader-lfs")
        HB = require("ffi/harfbuzz")
    end)

    before_each(function()
        -- Clear internal tables before each test
        FontList.fontlist = {}
        FontList.fontinfo = {}
        FontList.fontnames = {}
    end)

    describe("Blacklist Check (isInFontsBlacklist)", function()
        local original_findFiles
        local original_isKindle

        before_each(function()
            original_findFiles = util.findFiles
            original_isKindle = CanvasContext.isKindle
        end)

        after_each(function()
            util.findFiles = original_findFiles
            CanvasContext.isKindle = original_isKindle
        end)

        it("does not blacklist Kindle system fonts when NOT on Kindle", function()
            CanvasContext.isKindle = function() return false end

            util.findFiles = function(dir, cb)
                cb("/mock/fonts/NormalFont.ttf", "NormalFont.ttf", { change = 100 })
                cb("/mock/fonts/DiwanMuna-Bold.ttf", "DiwanMuna-Bold.ttf", { change = 100 })
            end

            FontList.fontinfo["/mock/fonts/NormalFont.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/fonts/DiwanMuna-Bold.ttf"] = { change = 100 }

            local mark = {}
            FontList:_readList("/mock/fonts", mark)

            assert.is.same({
                "/mock/fonts/NormalFont.ttf",
                "/mock/fonts/DiwanMuna-Bold.ttf"
            }, FontList.fontlist)

            assert.is_true(mark["/mock/fonts/NormalFont.ttf"])
            assert.is_true(mark["/mock/fonts/DiwanMuna-Bold.ttf"])
        end)

        it("blacklists Kindle system fonts when ON Kindle", function()
            CanvasContext.isKindle = function() return true end

            util.findFiles = function(dir, cb)
                cb("/mock/fonts/NormalFont.ttf", "NormalFont.ttf", { change = 100 })
                cb("/mock/fonts/DiwanMuna-Bold.ttf", "DiwanMuna-Bold.ttf", { change = 100 })
                cb("/mock/fonts/Amazon-Ember-Regular.ttf", "Amazon-Ember-Regular.ttf", { change = 100 })
            end

            FontList.fontinfo["/mock/fonts/NormalFont.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/fonts/DiwanMuna-Bold.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/fonts/Amazon-Ember-Regular.ttf"] = { change = 100 }

            local mark = {}
            FontList:_readList("/mock/fonts", mark)

            assert.is.same({
                "/mock/fonts/NormalFont.ttf",
                "/mock/fonts/Amazon-Ember-Regular.ttf"
            }, FontList.fontlist)

            assert.is_true(mark["/mock/fonts/NormalFont.ttf"])
            assert.is_nil(mark["/mock/fonts/DiwanMuna-Bold.ttf"])
            assert.is_true(mark["/mock/fonts/Amazon-Ember-Regular.ttf"])
        end)
    end)

    describe("External Font Directory (getExternalFontDir)", function()
        local original_findFiles
        local original_isKindle
        local original_hasSystemFonts
        local original_getenv
        local original_persist_new
        local original_mkdir
        local mock_cache_save_called = false

        before_each(function()
            original_findFiles = util.findFiles
            original_isKindle = CanvasContext.isKindle
            original_hasSystemFonts = CanvasContext.hasSystemFonts
            original_getenv = os.getenv
            original_persist_new = Persist.new
            original_mkdir = lfs.mkdir
            mock_cache_save_called = false

            -- Stub Persist:new to return dummy cache
            Persist.new = function(self, opts)
                return {
                    load = function() return {} end,
                    save = function()
                        mock_cache_save_called = true
                        return true
                    end
                }
            end

            lfs.mkdir = function() return true end
        end)

        after_each(function()
            util.findFiles = original_findFiles
            CanvasContext.isKindle = original_isKindle
            CanvasContext.hasSystemFonts = original_hasSystemFonts
            os.getenv = original_getenv
            Persist.new = original_persist_new
            lfs.mkdir = original_mkdir
            package.loaded["frontend/ui/elements/font_settings"] = nil
        end)

        it("reads from os.getenv when hasSystemFonts is false", function()
            CanvasContext.isKindle = function() return false end
            CanvasContext.hasSystemFonts = function() return false end

            os.getenv = function(name)
                if name == "EXT_FONT_DIR" then
                    return "/mock/ext/fonts1;/mock/ext/fonts2"
                end
                return original_getenv(name)
            end

            local searched_dirs = {}
            util.findFiles = function(dir, cb)
                table.insert(searched_dirs, dir)
                cb(dir .. "/f.ttf", "f.ttf", { change = 100 })
            end

            FontList.fontinfo["./fonts/f.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/ext/fonts1/f.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/ext/fonts2/f.ttf"] = { change = 100 }

            local list = FontList:getFontList()

            assert.is.same({
                "./fonts",
                "/mock/ext/fonts1",
                "/mock/ext/fonts2"
            }, searched_dirs)

            assert.is.same({
                "./fonts/f.ttf",
                "/mock/ext/fonts1/f.ttf",
                "/mock/ext/fonts2/f.ttf"
            }, list)
        end)

        it("reads from font_settings module when hasSystemFonts is true", function()
            CanvasContext.isKindle = function() return false end
            CanvasContext.hasSystemFonts = function() return true end

            package.loaded["frontend/ui/elements/font_settings"] = {
                getPath = function() return "/mock/sys/fonts1;/mock/sys/fonts2" end
            }

            local searched_dirs = {}
            util.findFiles = function(dir, cb)
                table.insert(searched_dirs, dir)
                cb(dir .. "/f.ttf", "f.ttf", { change = 100 })
            end

            FontList.fontinfo["./fonts/f.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/sys/fonts1/f.ttf"] = { change = 100 }
            FontList.fontinfo["/mock/sys/fonts2/f.ttf"] = { change = 100 }

            local list = FontList:getFontList()

            assert.is.same({
                "./fonts",
                "/mock/sys/fonts1",
                "/mock/sys/fonts2"
            }, searched_dirs)

            assert.is.same({
                "./fonts/f.ttf",
                "/mock/sys/fonts1/f.ttf",
                "/mock/sys/fonts2/f.ttf"
            }, list)
        end)
    end)

    describe("Localized Font Name (getLocalizedFontName)", function()
        local original_reader_settings_read
        local mock_lang

        before_each(function()
            original_reader_settings_read = G_reader_settings.read
            G_reader_settings.read = function(self, key)
                if key == "language" then
                    return mock_lang
                end
                return original_reader_settings_read(self, key)
            end

            assert.is_not_nil(HB.HB_OT_NAME_ID_FULL_NAME)
            assert.is_not_nil(HB.HB_OT_NAME_ID_FONT_FAMILY)
        end)

        after_each(function()
            G_reader_settings.read = original_reader_settings_read
        end)

        it("returns nil if language setting is missing", function()
            mock_lang = nil
            local name = FontList:getLocalizedFontName("/mock/fonts/f.ttf", 0)
            assert.is_nil(name)
        end)

        it("returns translated full name for exact language match", function()
            mock_lang = "zh_CN"

            FontList.fontinfo["/mock/fonts/f.ttf"] = {
                [1] = { -- index 0
                    names = {
                        ["zh-cn"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] = "Exact Zh-CN Full Name",
                            [tonumber(HB.HB_OT_NAME_ID_FONT_FAMILY)] = "Exact Zh-CN Family Name"
                        },
                        ["zh"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] = "Base Zh Full Name"
                        }
                    }
                }
            }

            local name = FontList:getLocalizedFontName("/mock/fonts/f.ttf", 0)
            assert.is.same("Exact Zh-CN Full Name", name)
        end)

        it("falls back to base language match when exact match is missing", function()
            mock_lang = "zh_TW"

            FontList.fontinfo["/mock/fonts/f.ttf"] = {
                [1] = { -- index 0
                    names = {
                        ["zh"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] = "Base Zh Full Name",
                            [tonumber(HB.HB_OT_NAME_ID_FONT_FAMILY)] = "Base Zh Family Name"
                        }
                    }
                }
            }

            local name = FontList:getLocalizedFontName("/mock/fonts/f.ttf", 0)
            assert.is.same("Base Zh Full Name", name)
        end)

        it("falls back to font family if full name is missing in translation", function()
            mock_lang = "fr_FR"

            FontList.fontinfo["/mock/fonts/f.ttf"] = {
                [1] = { -- index 0
                    names = {
                        ["fr"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FONT_FAMILY)] = "French Family Name"
                        }
                    }
                }
            }

            local name = FontList:getLocalizedFontName("/mock/fonts/f.ttf", 0)
            assert.is.same("French Family Name", name)
        end)

        it("returns nil if no translation is matching the language", function()
            mock_lang = "de_DE"

            FontList.fontinfo["/mock/fonts/f.ttf"] = {
                [1] = { -- index 0
                    names = {
                        ["fr"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] = "French Full Name"
                        }
                    }
                }
            }

            local name = FontList:getLocalizedFontName("/mock/fonts/f.ttf", 0)
            assert.is_nil(name)
        end)
    end)

    describe("Font Argument Function (getFontArgFunc)", function()
        local original_reader_settings_read
        local mock_lang

        before_each(table.clear)

        before_each(function()
            original_reader_settings_read = G_reader_settings.read
            G_reader_settings.read = function(self, key)
                if key == "language" then
                    return mock_lang
                end
                return original_reader_settings_read(self, key)
            end

            -- Mock document/credocument
            package.loaded["document/credocument"] = {
                engineInit = function()
                    return {
                        getFontFaces = function()
                            return { "FontFace1", "FontFace2" }
                        end,
                        getFontFaceFilenameAndFaceIndex = function(face)
                            if face == "FontFace1" then
                                return "/mock/fonts/f1.ttf", 0
                            else
                                return "/mock/fonts/f2.ttf", 1
                            end
                        end
                    }
                end
            }
        end)

        after_each(function()
            G_reader_settings.read = original_reader_settings_read
            package.loaded["document/credocument"] = nil
        end)

        it("returns font face names and localized toggle labels", function()
            mock_lang = "zh_CN"

            -- Pre-populate fontinfo to return localized name for face1 but not face2
            FontList.fontinfo["/mock/fonts/f1.ttf"] = {
                [1] = { -- index 0
                    names = {
                        ["zh"] = {
                            [tonumber(HB.HB_OT_NAME_ID_FULL_NAME)] = "Localized Face 1 Full Name"
                        }
                    }
                }
            }

            local face_list, toggle = FontList:getFontArgFunc()

            assert.is.same({ "FontFace1", "FontFace2" }, face_list)

            -- Face1 should be localized, Face2 should fall back to itself ("FontFace2")
            assert.is.same({ "Localized Face 1 Full Name", "FontFace2" }, toggle)
        end)
    end)

    describe("Font List and Cache Management (getFontList)", function()
        local original_findFiles
        local original_isKindle
        local original_hasSystemFonts
        local original_getenv
        local original_persist_new
        local original_mkdir
        local mock_cache_save_called
        local mock_cache_saved_data
        local mock_cache_data

        before_each(function()
            original_findFiles = util.findFiles
            original_isKindle = CanvasContext.isKindle
            original_hasSystemFonts = CanvasContext.hasSystemFonts
            original_getenv = os.getenv
            original_persist_new = Persist.new
            original_mkdir = lfs.mkdir
            mock_cache_save_called = false
            mock_cache_saved_data = nil
            mock_cache_data = {}

            -- Default stubs
            CanvasContext.isKindle = function() return false end
            CanvasContext.hasSystemFonts = function() return false end
            lfs.mkdir = function() return true end
            os.getenv = function(name) return nil end

            Persist.new = function(self, opts)
                return {
                    path = opts.path,
                    load = function() return mock_cache_data, nil end,
                    save = function(self_cache, data)
                        mock_cache_save_called = true
                        mock_cache_saved_data = data
                        return true
                    end
                }
            end
        end)

        after_each(function()
            util.findFiles = original_findFiles
            CanvasContext.isKindle = original_isKindle
            CanvasContext.hasSystemFonts = original_hasSystemFonts
            os.getenv = original_getenv
            Persist.new = original_persist_new
            lfs.mkdir = original_mkdir
        end)

        it("does not save cache if files match cache exactly", function()
            -- Pre-populate cache
            mock_cache_data = {
                ["./fonts/f1.ttf"] = {
                    change = 100,
                    {
                        name = "FontOne",
                        path = "./fonts/f1.ttf",
                        index = 0,
                    }
                }
            }

            util.findFiles = function(dir, cb)
                if dir == "./fonts" then
                    cb("./fonts/f1.ttf", "f1.ttf", { change = 100 })
                end
            end

            local list = FontList:getFontList()

            assert.is.same({ "./fonts/f1.ttf" }, list)
            assert.is_false(mock_cache_save_called)
            assert.is.same(mock_cache_data, FontList.fontinfo)
            assert.is.same({
                FontOne = {
                    {
                        name = "FontOne",
                        path = "./fonts/f1.ttf",
                        index = 0,
                    }
                }
            }, FontList.fontnames)
        end)

        it("prunes missing files from cache and saves it", function()
            -- Pre-populate cache with 2 files
            mock_cache_data = {
                ["./fonts/f1.ttf"] = {
                    change = 100,
                    {
                        name = "FontOne",
                        path = "./fonts/f1.ttf",
                        index = 0,
                    }
                },
                ["./fonts/f2.ttf"] = {
                    change = 100,
                    {
                        name = "FontTwo",
                        path = "./fonts/f2.ttf",
                        index = 0,
                    }
                }
            }

            -- Only f1.ttf is actually found on disk
            util.findFiles = function(dir, cb)
                if dir == "./fonts" then
                    cb("./fonts/f1.ttf", "f1.ttf", { change = 100 })
                end
            end

            local list = FontList:getFontList()

            -- f2.ttf should be pruned from the returned list
            assert.is.same({ "./fonts/f1.ttf" }, list)

            -- Cache should have been saved
            assert.is_true(mock_cache_save_called)

            -- Saved data should only contain f1.ttf
            local expected_saved_data = {
                ["./fonts/f1.ttf"] = {
                    change = 100,
                    {
                        name = "FontOne",
                        path = "./fonts/f1.ttf",
                        index = 0,
                    }
                }
            }
            assert.is.same(expected_saved_data, mock_cache_saved_data)
            assert.is.same(expected_saved_data, FontList.fontinfo)

            -- Fontnames should only contain FontOne
            assert.is.same({
                FontOne = {
                    {
                        name = "FontOne",
                        path = "./fonts/f1.ttf",
                        index = 0,
                    }
                }
            }, FontList.fontnames)
        end)
    end)
end)
