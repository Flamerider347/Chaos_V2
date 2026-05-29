extends Node

var room_code: String = ""
var username: String = ""
var closed_lobby = false
var paused: bool = false
var connected: bool = false
var is_joining: bool = false
var in_game: bool = false
var join_error = null
var is_night = false
var lost = false
var current_plates = 0

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
		var status_node = get_node_or_null("/root/main_menu/menu_UI/status")
		var join_btn = get_node_or_null("/root/main_menu/menu_UI/join_button")
		if status_node: status_node.text = "Connected!"
		if join_btn: join_btn.disabled = false
	else:
		room_code = generate_room_code()
		GDSync.lobby_create(room_code)

func _on_connection_failed(_error: int) -> void:
	print("Multiplayer unavailable")

func _on_lobby_created(lobby_name: String) -> void:
	GDSync.lobby_join(lobby_name)
	if closed_lobby:
		GDSync.lobby_close()

func _on_lobby_joined(lobby_name: String) -> void:
	room_code = lobby_name
	join_error = null
	
	# --- FIX: Wait 1 frame for peer IDs to stabilize before setting username ---
	await get_tree().process_frame
	if username != "":
		GDSync.player_set_username(username)
	if lost:
		GDSync.lobby_leave()
		room_code = generate_room_code()
		GDSync.lobby_create(room_code)

func _on_lobby_join_failed(_thing, error):
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")
	if str(error) == "1":
		join_error = "Lobby closed"
	else:
		join_error = "Lobby full"
		
	if not in_game:
		var status_node = get_node_or_null("/root/main_menu/menu_UI/status")
		if status_node: status_node.text = "Unable to join lobby :("

func generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"
	var code = "KC_"
	for i in range(4):
		code += CHARS[randi() % CHARS.length()]
	return code
