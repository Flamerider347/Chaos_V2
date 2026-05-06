extends Node

var room_code: String = ""
var username: String = ""
var paused: bool = false
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false

func _ready() -> void:
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.start_multiplayer()

func _on_connected() -> void:
	connected = true
	if is_joining:
		GDSync.lobby_join(room_code)
	else:
		room_code = generate_room_code()
		GDSync.lobby_create(room_code)

func _on_connection_failed(_error: int) -> void:
	print("Multiplayer unavailable")

func _on_lobby_created(lobby_name: String) -> void:
	GDSync.lobby_join(lobby_name)

func _on_lobby_joined(lobby_name: String) -> void:
	room_code = lobby_name
	if not in_game:
		get_node("/root/main_menu/menu_UI/status").text = "Connected!"

func generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
	var code = "KC_"
	for i in range(4):
		code += CHARS[randi() % CHARS.length()]
	return code
