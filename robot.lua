local moon = require("moon")
local config = require("config")
local skynet = require("skynet")
local socket = require("socket")
local sproto = require("sprotoloader")
local rpc = nil
local pack_req = nil
local trace_req = { }
local trace_send = { }
local Robot
do
  local _class_0
  local _base_0 = {
    dispatch_req = function(self, name, req)
      if trace_req[name] then
        moon.trace_call()
      end
      if self.request[name] then
        return self.request[name](req)
      end
    end,
    dispatch_rpc = function(self, type, ...)
      if type == "RESPONSE" then
        local session, rsp = ...
        return self.response[session](rsp)
      else
        moon.assert(type == "REQUEST")
        local name, req, pack_rsp = ...
        local rsp = self:dispatch_req(name, req)
        if pack_rsp then
          return self:send_data(pack_rsp(rsp))
        end
      end
    end,
    dispatch_msg = function(self)
      return self:dispatch_rpc(rpc:dispatch(self:recv_data()))
    end,
    start_game = function(self)
      local file = io.open("data/robot_data")
      local data = file:read("a")
      file:close()
      self.robot_data = moon.load(data:gsub("robot", self.uid))
      self.data_index = 1
      self.wait = nil
    end,
    update_game = function(self)
      skynet.sleep(7)
      if self.wait then
        return 
      end
      local name, req
      do
        local _obj_0 = self.robot_data[self.data_index or 1]
        name, req = _obj_0[1], _obj_0[2]
      end
      if self.data_index < #self.robot_data then
        self.data_index = self.data_index + 1
      else
        self.data_index = 1
      end
      if name == "EnterScene" then
        return self:EnterScene(req)
      else
        return self:send(name, req)
      end
    end,
    recv_data = function(self)
      return socket.read(self.fd, moon.unpack(socket.read(self.fd, 2)))
    end,
    send_data = function(self, msg)
      return socket.write(self.fd, moon.pack(msg))
    end,
    send = function(self, name, req, rsp_handler)
      if trace_send[name] then
        moon.trace_call()
      end
      local session = nil
      if rsp_handler then
        self.session = self.session + 1
        session = self.session
        self.response[session] = rsp_handler
      end
      return self:send_data(pack_req(name, req, session))
    end,
    open_connect = function(self, host, port, service)
      if self.fd then
        self:close_connect()
      end
      self.fd = socket.open(host, port)
      return moon.assert(self.fd, "connect " .. tostring(service) .. " failed")
    end,
    close_connect = function(self)
      return socket.close(self.fd)
    end,
    Login = function(self, host, port)
      if host == nil then
        host = config.login.host
      end
      if port == nil then
        port = config.login.port
      end
      moon.debug("Login " .. tostring(host) .. " " .. tostring(port))
      self:open_connect(host, port, "login")
      return self:send("Login", self.__class.login_req, function(rsp)
        moon.assert(rsp.result == 0, "Login failed")
        moon.debug("Login ok, start Handshake")
        self.uid, self.token, host, port = rsp.uid, rsp.token, rsp.host, rsp.port
        self:open_connect(host, port, "gate")
        return self:Handshake()
      end)
    end,
    Handshake = function(self)
      skynet.sleep(10)
      moon.debug("Handshake " .. tostring(self.uid) .. " " .. tostring(self.token))
      return self:send("Handshake", {
        uid = self.uid,
        token = self.token
      }, function(rsp)
        moon.assert(rsp.result == 0, "Handshake failed")
        moon.debug("Handshake ok, start game")
        return self:start_game()
      end)
    end,
    EnterScene = function(self, req)
      if self.scenename == req.scenename then
        return 
      end
      self.wait = true
      return self:send("EnterScene", req, function(rsp)
        moon.assert(rsp.result == 0, "EnterScene %s failed", req.scenename)
        self.scenename = req.scenename
        self.wait = nil
      end)
    end
  }
  _base_0.__index = _base_0
  _class_0 = setmetatable({
    __init = function(self)
      self.wait = true
      self.session = 0
      self.response = { }
      self.request = {
        SyncState = function(req) end
      }
    end,
    __base = _base_0,
    __name = "Robot"
  }, {
    __index = _base_0,
    __call = function(cls, ...)
      local _self_0 = setmetatable({}, _base_0)
      cls.__init(_self_0, ...)
      return _self_0
    end
  })
  _base_0.__class = _class_0
  local self = _class_0
  self.login_req = {
    username = nil,
    password = "moon",
    gatename = "moon_1001"
  }
  Robot = _class_0
end
return skynet.start(function()
  skynet.uniqueservice("debug_console", 8998)
  sproto.register("proto/proto.sproto", 1)
  local sp = sproto.load(1)
  rpc = sp:host()
  pack_req = rpc:attach(sp)
  local login_host = skynet.getenv("login_host")
  local login_port = skynet.getenv("login_port")
  local robot_num = skynet.getenv("robot_num")
  for i = 1, robot_num do
    moon.debug("-> start robot " .. tostring(i))
    local robot = Robot()
    robot:Login(login_host, login_port)
    skynet.fork(function()
      while true do
        robot:dispatch_msg()
      end
    end)
    skynet.fork(function()
      while true do
        robot:update_game()
      end
    end)
    skynet.sleep(300)
  end
end)
