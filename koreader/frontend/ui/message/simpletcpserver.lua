local logger = require("logger")
local socket = require("socket")

-- Reference:
-- https://lunarmodules.github.io/luasocket/tcp.html

-- Drop-in alternative to streammessagequeueserver.lua, using
-- LuaSocket instead of ZeroMQ.
-- This SimpleTCPServer is still tied to HTTP, expecting lines of headers,
-- a blank like marking the end of the input request.

local SimpleTCPServer = {
  host = nil,
  port = nil,
}

function SimpleTCPServer:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  if o.init then
    o:init()
  end
  return o
end

function SimpleTCPServer:start()
  for i = 1, 10 do
    self.server = socket.bind(self.host, self.port)
    if self.server then
      self.server:settimeout(0.01) -- set timeout (10ms)
      local _, actual_port = self.server:getsockname()
      if actual_port then
        self.port = actual_port
      end
      logger.dbg("SimpleTCPServer: Server listening on port " .. self.port)
      return
    end
    logger.warn(
      string.format(
        "Failed to start SimpleTCPServer on port %s, retrying in 200ms (attempt %d/10)...",
        tostring(self.port),
        i
      )
    )
    socket.select(nil, nil, 0.2)
  end
  logger.err(
    "Failed to start SimpleTCPServer on port "
      .. self.port
      .. " after 10 attempts"
  )
end

function SimpleTCPServer:stop()
  if self.server then
    self.server:close()
  end
end

function SimpleTCPServer:waitEvent()
  if not self.server then
    return
  end
  local client = self.server:accept() -- wait for a client to connect
  if not client then
    return
  end
  -- We expect to get all headers in 100ms. We will block during this timeframe.
  client:settimeout(0.1, "t")
  local lines = {}
  while true do
    local data = client:receive("*l") -- read a line from input
    if not data then -- timeout
      client:close()
      break
    end
    if data == "" then -- proper empty line after request headers
      table.insert(lines, data) -- keep it in content
      data = table.concat(lines, "\r\n")
      logger.dbg("SimpleTCPServer: Received data: ", data)
      -- Give us more time to process the request and send the response
      client:settimeout(0.5, "t")
      self.receiveCallback(data, client)
      -- This should call SimpleTCPServer:send() to send
      -- the response and close this connection.
    else
      table.insert(lines, data)
    end
  end
end

function SimpleTCPServer:send(data, client)
  client:send(data) -- send the response back to the client
  client:close() -- close the connection to the client
end

return SimpleTCPServer
