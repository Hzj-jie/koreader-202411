describe("KOSyncClient plugin module", function()
  local KOSyncClient, NetworkMgr, socketutil

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    NetworkMgr = require("ui/network/manager")
    socketutil = require("socketutil")
    KOSyncClient = require("plugins/kosync.koplugin/KOSyncClient")
    KOSyncClient.service_spec = "{}"
  end)

  before_each(function()
    stub(NetworkMgr, "isOnline", function()
      return true
    end)
    stub(socketutil, "set_timeout")
    stub(socketutil, "reset_timeout")
  end)

  after_each(function()
    NetworkMgr.isOnline:revert()
    socketutil.set_timeout:revert()
    socketutil.reset_timeout:revert()
  end)

  it("should instantiate KOSyncClient instance", function()
    local mock_client = {
      reset_middlewares = function() end,
      enable = function() end,
      register = function()
        return { status = 201, body = { message = "User created" } }
      end,
      authorize = function()
        return { status = 200, body = { key = "secret_key" } }
      end,
      update_progress = function()
        return { status = 200, body = { progress = "10" } }
      end,
      get_progress = function()
        return { status = 200, body = { progress = "10" } }
      end,
    }

    local inst = setmetatable(
      { client = mock_client },
      { __index = KOSyncClient }
    )
    assert.is_table(inst)
    assert.are.equal(mock_client, inst.client)
  end)

  it("should initialize with Spore spec safely", function()
    local mock_spore = {
      new_from_spec = function()
        return {
          reset_middlewares = function() end,
          enable = function() end,
        }
      end,
    }
    package.loaded["Spore"] = mock_spore

    local client = KOSyncClient:new({ service_spec = "{}" })
    assert.is_table(client)
  end)

  describe("register", function()
    it("returns true and body on successful registration (status 201)", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        register = function(self, args)
          assert.are.equal("testuser", args.username)
          assert.are.equal("password123", args.password)
          return {
            status = 201,
            body = { username = "testuser" },
          }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:register("testuser", "password123")
      assert.is_true(success)
      assert.is_table(body)
      assert.are.equal("testuser", body.username)
      assert.stub(socketutil.set_timeout).was_called()
      assert.stub(socketutil.reset_timeout).was_called()
    end)

    it("returns false when registration returns status other than 201", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        register = function()
          return {
            status = 402,
            body = { message = "Username taken" },
          }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:register("existing", "pass")
      assert.is_false(success)
      assert.are.equal("Username taken", body.message)
    end)

    it("returns false when register throws error", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        register = function()
          error("network error")
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:register("testuser", "pass")
      assert.is_false(success)
      assert.is_nil(body)
      assert.stub(socketutil.reset_timeout).was_called()
    end)

    it("returns false and offline when network is offline", function()
      NetworkMgr.isOnline.returns(false)
      local inst = setmetatable(
        { client = {} },
        { __index = KOSyncClient }
      )
      local success, err = inst:register("testuser", "pass")
      assert.is_false(success)
      assert.are.equal("offline", err)
    end)
  end)

  describe("authorize", function()
    it("returns true and body on successful authorization (status 200)", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        authorize = function()
          return { status = 200, body = { key = "auth_key" } }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:authorize("testuser", "auth_key")
      assert.is_true(success)
      assert.are.equal("auth_key", body.key)
      assert.stub(socketutil.set_timeout).was_called()
      assert.stub(socketutil.reset_timeout).was_called()
    end)

    it("returns false when authorization returns non-200 status", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        authorize = function()
          return { status = 401, body = { message = "Unauthorized" } }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:authorize("testuser", "wrong_key")
      assert.is_false(success)
      assert.are.equal("Unauthorized", body.message)
    end)

    it("returns false when authorize throws error", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        authorize = function()
          error("timeout")
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:authorize("testuser", "key")
      assert.is_false(success)
      assert.is_nil(body)
    end)

    it("returns false and offline when network is offline", function()
      NetworkMgr.isOnline.returns(false)
      local inst = setmetatable(
        { client = {} },
        { __index = KOSyncClient }
      )
      local success, err = inst:authorize("testuser", "key")
      assert.is_false(success)
      assert.are.equal("offline", err)
    end)
  end)

  describe("update_progress", function()
    it("returns true and body on successful progress update (status 200)", function()
      local captured_args
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        update_progress = function(self, args)
          captured_args = args
          return { status = 200, body = { document = args.document, timestamp = 12345 } }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:update_progress(
        "testuser",
        "testkey",
        "doc123",
        50,
        0.5,
        "Kobo",
        "dev1"
      )
      assert.is_true(success)
      assert.are.equal("doc123", body.document)
      assert.are.equal("50", captured_args.progress) -- tostring conversion
      assert.are.equal(0.5, captured_args.percentage)
      assert.are.equal("Kobo", captured_args.device)
      assert.are.equal("dev1", captured_args.device_id)
      assert.stub(socketutil.set_timeout).was_called()
      assert.stub(socketutil.reset_timeout).was_called()
    end)

    it("returns false on update_progress error status or exception", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        update_progress = function()
          return { status = 401, body = { message = "Unauthorized" } }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:update_progress(
        "testuser", "key", "doc", 1, 0.1, "d", "id"
      )
      assert.is_false(success)
      assert.are.equal("Unauthorized", body.message)

      -- Exception
      mock_client.update_progress = function()
        error("connection reset")
      end
      local err_success, _ = inst:update_progress(
        "testuser", "key", "doc", 1, 0.1, "d", "id"
      )
      assert.is_false(err_success)
    end)

    it("returns false and offline when network is offline", function()
      NetworkMgr.isOnline.returns(false)
      local inst = setmetatable(
        { client = {} },
        { __index = KOSyncClient }
      )
      local success, err = inst:update_progress(
        "testuser", "key", "doc", 1, 0.1, "d", "id"
      )
      assert.is_false(success)
      assert.are.equal("offline", err)
    end)
  end)

  describe("get_progress", function()
    it("returns true and body on successful get_progress (status 200)", function()
      local captured_args
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        get_progress = function(self, args)
          captured_args = args
          return {
            status = 200,
            body = {
              progress = "80",
              percentage = 0.8,
              device = "DeviceB",
              timestamp = 54321,
            },
          }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:get_progress("testuser", "testkey", "doc123")
      assert.is_true(success)
      assert.are.equal("doc123", captured_args.document)
      assert.are.equal("80", body.progress)
      assert.are.equal(0.8, body.percentage)
      assert.are.equal("DeviceB", body.device)
      assert.stub(socketutil.set_timeout).was_called()
      assert.stub(socketutil.reset_timeout).was_called()
    end)

    it("returns false on get_progress error status or exception", function()
      local mock_client = {
        reset_middlewares = function() end,
        enable = function() end,
        get_progress = function()
          return { status = 404, body = { message = "Not found" } }
        end,
      }

      local inst = setmetatable(
        { client = mock_client },
        { __index = KOSyncClient }
      )
      local success, body = inst:get_progress("testuser", "key", "doc")
      assert.is_false(success)
      assert.are.equal("Not found", body.message)

      -- Exception
      mock_client.get_progress = function()
        error("broken pipe")
      end
      local err_success, _ = inst:get_progress("testuser", "key", "doc")
      assert.is_false(err_success)
    end)

    it("returns false and offline when network is offline", function()
      NetworkMgr.isOnline.returns(false)
      local inst = setmetatable(
        { client = {} },
        { __index = KOSyncClient }
      )
      local success, err = inst:get_progress("testuser", "key", "doc")
      assert.is_false(success)
      assert.are.equal("offline", err)
    end)
  end)
end)
