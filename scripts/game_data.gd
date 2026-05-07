extends Node

var room_code: String = ""
var username: String = ""
var paused: bool = false
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false
var join_error = null

func _ready() -> void:
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	GDSync.start_multiplayer()

func _on_connected() -> void:
	connected = true
	if not in_game:
		get_node("/root/main_menu/menu_UI/status").text = "Connected!"
		get_node("/root/main_menu/menu_UI/join_button").disabled = false
	if in_game:
		room_code = generate_room_code()
		GDSync.lobby_create(room_code)

func _on_connection_failed(_error: int) -> void:
	print("Multiplayer unavailable")

func _on_lobby_created(lobby_name: String) -> void:
	GDSync.lobby_join(lobby_name)

func _on_lobby_joined(lobby_name: String) -> void:
	room_code = lobby_name
	join_error = null


func _on_lobby_join_failed(_thing, error):
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")
	if str(error) == "1":
		join_error = "Lobby closed"
	else:
		join_error = "Lobby full"
	if not in_game:
		get_node("/root/main_menu/menu_UI/status").text = "Unable to join lobby :( "

func generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
	var code = "KC_"
	for i in range(4):
		code += CHARS[randi() % CHARS.length()]
	return code
