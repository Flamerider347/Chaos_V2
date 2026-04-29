extends Node

func _ready() -> void:
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	
	$menu_UI/host_button.pressed.connect(_on_host_pressed)
	$menu_UI/join_button.pressed.connect(_on_join_pressed)
	
	GDSync.start_multiplayer()

func _on_host_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	if username == "":
		push_error("No username entered")
		return
	# Remove: GDSync.set_client_name(username)
	var room_code = _generate_room_code()
	$menu_UI/join_code.text = room_code
	GDSync.player_set_username(username)
	GDSync.lobby_create(room_code)

func _on_join_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	var code = $menu_UI/join_code.text.strip_edges()
	if username == "":
		push_error("No username entered")
		return
	if code == "":
		push_error("No room code entered")
		return
	GameData.room_code = code
	GDSync.player_set_username(username)
	GDSync.lobby_join(code)
	

func _generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code = "KC_"
	for i in range(4):
		code += CHARS[randi() % CHARS.length()]
	return code

func _on_connected() -> void:
	print("Connected to GDSync")
	$menu_UI/status.text = "Connected!"
	$menu_UI/host_button.disabled = false
	$menu_UI/join_button.disabled = false

func _on_connection_failed(error: int) -> void:
	match error:
		ENUMS.CONNECTION_FAILED.INVALID_PUBLIC_KEY:
			push_error("Invalid key")
		ENUMS.CONNECTION_FAILED.TIMEOUT:
			push_error("Connection timed out")

func _on_lobby_created(lobby_name: String) -> void:
	GameData.room_code = lobby_name
	GDSync.lobby_join(lobby_name)

func _on_lobby_creation_failed(lobby_name: String, error: int) -> void:
	push_error("Failed to create lobby: " + lobby_name + str(error))

func _on_lobby_joined(lobby_name: String) -> void:
	print("Joined lobby: ", lobby_name)
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")
