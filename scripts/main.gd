extends Node3D

var paused: bool = false

func _ready() -> void:
	$UI/roomcode.visible = false
	$UI/status.text = "Connecting..."
	$pause_UI/roomcode.text = ""
	$pause_UI.visible = false
	
	GDSync.connected.connect(_on_connected)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_creation_failed.connect(_on_lobby_creation_failed)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.start_multiplayer()

func _on_connected() -> void:
	if GameData.is_joining:
		GDSync.lobby_join(GameData.room_code)
	else:
		var code = _generate_room_code()
		GameData.room_code = code
		GDSync.lobby_create(code)

func _on_connection_failed(error: int) -> void:
	$UI/status.text = "Multiplayer unavailable"

func _on_lobby_created(lobby_name: String) -> void:
	GDSync.lobby_join(lobby_name)

func _on_lobby_creation_failed(lobby_name: String, error: int) -> void:
	if error == ENUMS.LOBBY_CREATION_ERROR.LOBBY_ALREADY_EXISTS:
		GDSync.lobby_join(lobby_name)

func _on_lobby_joined(lobby_name: String) -> void:
	GameData.connected = true
	GameData.room_code = lobby_name
	$UI/status.text = "Room: " + lobby_name
	$UI/roomcode.visible = true
	$Pause_UI/roomcode.text = "Room: " + lobby_name

func _generate_room_code() -> String:
	const CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code = "KC_"
	for i in range(4):
		code += CHARS[randi() % CHARS.length()]
	return code

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			paused = !paused
			GameData.paused = paused
			$pause_UI.visible = paused
			if paused:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_copy_button_pressed() -> void:
	DisplayServer.clipboard_set(GameData.room_code)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if not GameData.paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
