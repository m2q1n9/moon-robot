-- robot.moon, created by mzq. -*- mode: moon -*-

skynet = require "skynet"
socket = require "socket"
config = require "config"
moon = require "moon"
net = require "net"
sp = require "sp"

trace_req = {}
trace_send = {}

class Robot
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
      log.assert type == "REQUEST"
      name, req, pack_rsp = ...
      rsp = @dispatch_req name, req
      @send_data pack_rsp rsp if pack_rsp

  dispatch_msg: =>
    @dispatch_rpc sp.unpack @recv_data!

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
    socket.read @fd, net.unpack socket.read @fd, 2

  send_data: (msg) =>
    socket.write @fd, net.pack msg

  send: (name, req, rsp_handler) =>
    moon.trace_call! if trace_send[name]
    session = nil
    if rsp_handler then
      @session += 1
      session = @session
      @response[session] = rsp_handler
    @send_data sp.pack name, req, session

  open_connect: (host, port, service) =>
    @close_connect! if @fd
    log.debug "connect #{service} #{host}:#{port}"
    @fd = socket.open host, port
    log.assert @fd, "connect #{service} failed"

  close_connect: =>
    socket.close @fd

  Login: (host = config.login.host, port = config.login.port, req) =>
    @open_connect host, port, "login"
    @send "Login", req, (rsp) ->
      log.assert rsp.result == 0, "Login failed"
      log.debug "Login ok, start Handshake"
      {gid:@gid, uid:@uid, token:@token} = rsp
      @open_connect host, port + @gid, "gate"
      @Handshake!

  Handshake: =>
    skynet.sleep 10
    log.debug "Handshake #{@uid} #{@token}"
    @send "Handshake", {uid:@uid, token:@token}, (rsp) ->
      log.assert rsp.result == 0, "Handshake failed"
      log.debug "Handshake ok, start game"
      @start_game!

  EnterScene: (req) =>
    return if @scenename == req.scenename
    @wait = true
    @send "EnterScene", req, (rsp) ->
      log.assert rsp.result == 0, "EnterScene %s failed", req.scenename
      @scenename = req.scenename
      @wait = nil


skynet.start () ->
  sp.save "proto/sproto.spb", true
  sp.load!

  login_req =
    username: skynet.getenv "user_name"
    password: "moon"

  login_host = skynet.getenv "login_host"
  login_port = skynet.getenv "login_port"
  robot_num = skynet.getenv "robot_num"

  for i = 1, robot_num
    log.debug "-> start robot #{i}"
    robot = Robot!
    robot\Login login_host, login_port, login_req

    skynet.fork () -> while true do robot\dispatch_msg!
    skynet.fork () -> while true do robot\update_game!
    skynet.sleep 300
