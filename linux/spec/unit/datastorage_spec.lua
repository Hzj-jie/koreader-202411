describe("DataStorage module", function()
    local DataStorage
    local original_getenv = os.getenv
    local env_mock = {}

    setup(function()
        require("commonrequire")
    end)

    before_each(function()
        env_mock = {}
        os.getenv = function(var)
            if env_mock[var] ~= nil then
                return env_mock[var]
            end
            return original_getenv(var)
        end
    end)

    after_each(function()
        os.getenv = original_getenv
        package.loaded["datastorage"] = nil
    end)

    it("should return correct default paths", function()
        DataStorage = require("datastorage")

        assert.are.equal(".", DataStorage:getDataDir())
        assert.are.equal("./history", DataStorage:getHistoryDir())
        assert.are.equal("./settings", DataStorage:getSettingsDir())
        assert.are.equal("./docsettings", DataStorage:getDocSettingsDir())
        assert.are.equal("./hashdocsettings", DataStorage:getDocSettingsHashDir())

        local full_dir = DataStorage:getFullDataDir()
        assert.truthy(full_dir)
        assert.are.equal("/", string.sub(full_dir, 1, 1))
    end)

    it("should honor KO_MULTIUSER and XDG_CONFIG_HOME", function()
        env_mock["KO_MULTIUSER"] = "true"
        env_mock["XDG_CONFIG_HOME"] = "/tmp/my_xdg_config"

        local lfs = require("libs/libkoreader-lfs")
        local original_mkdir = lfs.mkdir
        local original_attributes = lfs.attributes

        lfs.mkdir = function() return true end
        lfs.attributes = function(path, mode)
            if path == "/tmp/my_xdg_config" or path == "/tmp/my_xdg_config/koreader" then
                return "directory"
            end
            return original_attributes(path, mode)
        end

        DataStorage = require("datastorage")
        assert.are.equal("/tmp/my_xdg_config/koreader", DataStorage:getDataDir())

        lfs.mkdir = original_mkdir
        lfs.attributes = original_attributes
    end)

    it("should honor KO_MULTIUSER and fallback to HOME", function()
        env_mock["KO_MULTIUSER"] = "true"
        env_mock["HOME"] = "/home/testuser"

        local lfs = require("libs/libkoreader-lfs")
        local original_mkdir = lfs.mkdir
        local original_attributes = lfs.attributes

        lfs.mkdir = function() return true end
        lfs.attributes = function(path, mode)
            if path == "/home/testuser/.config" or path == "/home/testuser/.config/koreader" then
                return "directory"
            end
            return original_attributes(path, mode)
        end

        DataStorage = require("datastorage")
        assert.are.equal("/home/testuser/.config/koreader", DataStorage:getDataDir())

        lfs.mkdir = original_mkdir
        lfs.attributes = original_attributes
    end)

    it("should honor UBUNTU_APPLICATION_ISOLATION", function()
        env_mock["UBUNTU_APPLICATION_ISOLATION"] = "true"
        env_mock["APP_ID"] = "com.koreader.app_12345"
        env_mock["XDG_DATA_HOME"] = "/xdg/data"

        local lfs = require("libs/libkoreader-lfs")
        local original_mkdir = lfs.mkdir
        local original_attributes = lfs.attributes

        lfs.mkdir = function() return true end
        lfs.attributes = function(path, mode)
            if path == "/xdg/data/com.koreader.app" then
                return "directory"
            end
            return original_attributes(path, mode)
        end

        DataStorage = require("datastorage")
        assert.are.equal("/xdg/data/com.koreader.app", DataStorage:getDataDir())

        lfs.mkdir = original_mkdir
        lfs.attributes = original_attributes
    end)
end)
