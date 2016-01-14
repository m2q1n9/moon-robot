-- robot.moon, created by mzq. -*- mode: moon -*-

moon = require "moon"
config = require "config"
skynet = require "skynet"
socket = require "socket"
sproto = require "sprotoloader"

rpc = nil
pack_req = nil

trace_req = {}
trace_send = {}

class Robot
  @login_req =
    username: nil
    password: "moon"
    gatename: "moon_1001"

  new: =>
    @wait = true
    @session = 0
    @response = {}
    @request =
      SyncState: (req) ->

  dispatch_req: (name, req) =>
    moon.trace_call! if trace_req[name]
    @request[name] req if @request[name]

  dispatch_rpc: (type, ...) =>
    if type == "RESPONSE" then
      session, rsp = ...
      @response[session] rsp
    else
      moon.assert type == "REQUEST"
      name, req, pack_rsp = ...
      rsp = @dispatch_req name, req
      @send_data pack_rsp rsp if pack_rsp

  dispatch_msg: =>
    @dispatch_rpc rpc\dispatch @recv_data!

  start_game: =>
    file = io.open "data/robot_data"
    data = file\read "a"
    file\close!

    @robot_data = moon.load data\gsub "robot", @uid
    @data_index = 1
    @wait = nil

  update_game: =>
    skynet.sleep 7
    return if @wait

    {name, req} = @robot_data[@data_index or 1]
    if @data_index < #@robot_data then
      @data_index += 1
    else
      @data_index = 1

    if name == "EnterScene" then @EnterScene req else @send name, req

  recv_data: =>
    socket.read @fd, moon.unpack socket.read @fd, 2

  send_data: (msg) =>
    socket.write @fd, moon.pack msg

  send: (name, req, rsp_handler) =>
    moon.trace_call! if trace_send[name]
    session = nil
    if rsp_handler then
      @session += 1
      session = @session
      @response[session] = rsp_handler
    @send_data pack_req name, req, session

  open_connect: (host, port, service) =>
    @close_connect! if @fd
    @fd = socket.open host, port
    moon.assert @fd, "connect #{service} failed"

  close_connect: =>
    socket.close @fd

  Login: (host = config.login.host, port = config.login.port) =>
    moon.debug "Login #{host} #{port}"
    @open_connect host, port, "login"
    @send "Login", @@login_req, (rsp) ->
      moon.assert rsp.result == 0, "Login failed"
      moon.debug "Login ok, start Handshake"
      {uid:@uid, token:@token, :host, :port} = rsp
      @open_connect host, port, "gate"
      @Handshake!

  Handshake: =>
    skynet.sleep 10
    moon.debug "Handshake #{@uid} #{@token}"
    @send "Handshake", {uid:@uid, token:@token}, (rsp) ->
      moon.assert rsp.result == 0, "Handshake failed"
      moon.debug "Handshake ok, start game"
      @start_game!

  EnterScene: (req) =>
    return if @scenename == req.scenename
    @wait = true
    @send "EnterScene", req, (rsp) ->
      moon.assert rsp.result == 0, "EnterScene %s failed", req.scenename
      @scenename = req.scenename
      @wait = nil


skynet.start () ->
  skynet.uniqueservice "debug_console", 8998

  sproto.register "proto/proto.sproto", 1
  sp = sproto.load 1

  rpc = sp\host!
  pack_req = rpc\attach sp

  login_host = skynet.getenv "login_host"
  login_port = skynet.getenv "login_port"
  robot_num = skynet.getenv "robot_num"

  for i = 1, robot_num
    moon.debug "-> start robot #{i}"
    robot = Robot!
    robot\Login login_host, login_port

    skynet.fork () -> while true do robot\dispatch_msg!
    skynet.fork () -> while true do robot\update_game!
    skynet.sleep 300
