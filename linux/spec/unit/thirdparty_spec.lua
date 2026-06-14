describe("thirdparty", function()
  local ThirdParty
  local mock_logger

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    -- Mock logger to avoid cluttering output and to verify logs
    mock_logger = {
      info = spy.new(function() end),
      warn = spy.new(function() end),
      err = spy.new(function() end),
      debug = spy.new(function() end),
    }
    package.loaded["logger"] = mock_logger

    package.loaded["device/thirdparty"] = nil
    ThirdParty = require("device/thirdparty")
  end)

  after_each(function()
    package.loaded["logger"] = nil
    package.loaded["device/thirdparty"] = nil
  end)

  describe("new", function()
    it("should initialize with default settings when no user files exist", function()
      local tp = ThirdParty:new{
        dicts = {
          {"Dict1", "Dict 1", false, "app.dict1", "action.dict1"},
          {"Dict2", "Dict 2", false, "app.dict2", "action.dict2"},
        },
        translators = {
          {"Trans1", "Trans 1", false, "app.trans1", "action.trans1"},
        },
        check = function(_, app)
          return app == "app.dict1"
        end
      }

      assert.is_nil(tp.is_user_list)
      assert.is_true(tp.dicts[1][3]) -- Dict1 should be available because check returned true
      assert.is_false(tp.dicts[2][3]) -- Dict2 should not be available
      assert.is_false(tp.translators[1][3]) -- Trans1 should not be available
    end)

    it("should load user settings if dictionaries.lua exists", function()
      -- Mock dofile to return user dictionaries
      local old_dofile = _G.dofile
      local mock_user_dicts = {
        {"UserDict1", "User Dict 1", false, "app.userdict1", "action.userdict1"},
      }

      _G.dofile = function(path)
        if path:match("dictionaries.lua$") then
          return mock_user_dicts
        end
        return old_dofile(path)
      end

      local tp = ThirdParty:new{
        check = function(_, app)
          return app == "app.userdict1"
        end
      }

      _G.dofile = old_dofile -- Restore dofile

      assert.is_true(tp.is_user_list)
      assert.are_same(mock_user_dicts, tp.dicts)
      assert.is_true(tp.dicts[1][3]) -- UserDict1 should be available
      assert.spy(mock_logger.info).was.called()
    end)
  end)

  describe("checkMethod", function()
    it("should return true and details if method exists", function()
      local tp = ThirdParty:new{
        dicts = {
          {"Dict1", "Dict 1", false, "app.dict1", "action.dict1"},
        }
      }

      local ok, tool, action = tp:checkMethod("dict", "Dict1")
      assert.is_true(ok)
      assert.are.equal("app.dict1", tool)
      assert.are.equal("action.dict1", action)
    end)

    it("should return false if method does not exist", function()
      local tp = ThirdParty:new{
        dicts = {
          {"Dict1", "Dict 1", false, "app.dict1", "action.dict1"},
        }
      }

      local ok = tp:checkMethod("dict", "NonExistent")
      assert.is_false(ok)
    end)
  end)

  describe("dump", function()
    it("should return formatted string of apps", function()
      local tp = ThirdParty:new{
        dicts = {
          {"Dict1", "Dict 1", true, "app.dict1", "action.dict1"},
        },
        translators = {
          {"Trans1", "Trans 1", false, "app.trans1", "action.trans1"},
        }
      }

      local expected_dump = "user defined third-party apps\n" ..
        "-> Dict1 (app.dict1), role: dict, available: true\n" ..
        "-> Trans1 (app.trans1), role: translator, available: false\n"

      assert.are.equal(expected_dump, tp:dump())
    end)
  end)
end)
