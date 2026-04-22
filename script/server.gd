extends Node

const PORT = 7778
var rooms = {}

func _ready():
	var peer = WebSocketMultiplayerPeer.new()
	var err = peer.create_server(PORT)
	if err != OK:
		print("Failed to start server: ", err)
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Server started on port ", PORT)

func _on_peer_connected(id: int):
	print("Player connected: ", id)

func _on_peer_disconnected(id: int):
	print("Player disconnected: ", id)
	for code in rooms.keys():
		if id in rooms[code].players:
			rooms[code].players.erase(id)
			_player_left.rpc_id(0, id, code)
			if rooms[code].players.is_empty():
				rooms.erase(code)
				print("Room ", code, " deleted")
			break

func _generate_code() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code = ""
	for i in 4:
		code += CHARS[randi() % CHARS.length()]
	return code

@rpc("any_peer", "reliable")
func request_create_room():
	var id = multiplayer.get_remote_sender_id()
	var code = _generate_code()
	while rooms.has(code):
		code = _generate_code()
	rooms[code] = { "host": id, "players": [id] }
	print("Room created: ", code, " by ", id)
	_room_created.rpc_id(id, code)

@rpc("any_peer", "reliable")
func request_join_room(code: String):
	var id = multiplayer.get_remote_sender_id()
	if not rooms.has(code):
		_join_failed.rpc_id(id, "Room not found")
		return
	rooms[code].players.append(id)
	print("Player ", id, " joined room ", code)
	_room_joined.rpc_id(id, code, rooms[code].players)
	for pid in rooms[code].players:
		if pid != id:
			_player_joined.rpc_id(pid, id, code)

@rpc("any_peer", "reliable")
func _room_created(code: String):
	pass

@rpc("any_peer", "reliable")
func _room_joined(code: String, players: Array):
	pass

@rpc("any_peer", "reliable")
func _join_failed(reason: String):
	pass

@rpc("any_peer", "reliable")
func _player_joined(id: int, code: String):
	pass

@rpc("any_peer", "reliable")
func _player_left(id: int, code: String):
	pass
