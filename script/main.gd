extends Node

const Player = preload("res://prefabs/player.tscn")
const PORT_LOCAL = 7778
const PORT_GLOBAL = 22097
const SERVER_LOCAL = "10.1.102.48"
const SERVER_GLOBAL = "understand-uncanny.gl.at.ply.gg"

var my_room: String = ""
var room_peers: Array = []

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _connect_to_server(ip: String, port: int):
	var peer = WebSocketMultiplayerPeer.new()
	peer.create_client("ws://%s:%d" % [ip, port])
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", ip, ":", port)
	while multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		await get_tree().process_frame
		print("Status: ", multiplayer.multiplayer_peer.get_connection_status())
	print("Connected as ", multiplayer.get_unique_id())

func host():
	request_create_room.rpc_id(1)

func join(code: String):
	request_join_room.rpc_id(1, code.to_upper())

func _on_peer_connected(_id: int):
	pass

func _on_peer_disconnected(id: int):
	room_peers.erase(id)
	if has_node("Players") and $Players.has_node(str(id)):
		$Players.get_node(str(id)).queue_free()

@rpc("authority", "reliable")
func _room_created(code: String):
	my_room = code
	room_peers = [multiplayer.get_unique_id()]
	print("Room created: ", code)
	$UI/RoomCode.text = "Room Code: " + code
	$UI/HostButton.hide()
	$UI/JoinButton.hide()
	$UI/ConnectButton.hide()
	$UI/ServerIP.hide()
	$UI/RoomInput.hide()
	$UI/LANToggle.hide()
	_spawn_player(multiplayer.get_unique_id())

@rpc("authority", "reliable")
func _room_joined(code: String, players: Array):
	my_room = code
	room_peers = players.duplicate()
	print("Joined room: ", code)
	$UI.hide()
	await get_tree().process_frame
	for id in players:
		_spawn_player(id)

@rpc("authority", "reliable")
func _join_failed(reason: String):
	print("Join failed: ", reason)
	$UI/Error.text = reason

@rpc("authority", "reliable")
func _player_joined(id: int, _code: String):
	print("Player joined my room: ", id)
	room_peers.append(id)
	_spawn_player(id)

@rpc("authority", "reliable")
func _player_left(id: int, _code: String):
	room_peers.erase(id)
	if $Players.has_node(str(id)):
		$Players.get_node(str(id)).queue_free()

func _spawn_player(id: int):
	if not has_node("Players"):
		return
	if $Players.has_node(str(id)):
		return
	var player = Player.instantiate()
	player.name = str(id)
	player.set_multiplayer_authority(id)
	$Players.add_child(player)
	for p in $Players.get_children():
		p.room_peers = room_peers

@rpc("any_peer", "reliable")
func request_create_room():
	pass

@rpc("any_peer", "reliable")
func request_join_room(_code: String):
	pass

func _on_connect_pressed():
	var ip: String
	var port: int
	if $UI/LANToggle.button_pressed:
		ip = SERVER_LOCAL
		port = PORT_LOCAL
	else:
		ip = SERVER_GLOBAL
		port = PORT_GLOBAL
	await _connect_to_server(ip, port)
	$UI/ConnectButton.hide()
	$UI/ServerIP.hide()
	$UI/HostButton.show()
	$UI/JoinButton.show()
	$UI/RoomInput.show()

func _on_host_pressed():
	host()

func _on_join_pressed():
	join($UI/RoomInput.text)
