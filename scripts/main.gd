extends Node3D

var paused: bool = false

func _ready() -> void:
	$Pause_UI.visible = false
	$Pause_UI/roomcode.text = ""
	
	if GameData.room_code == "":
		GameData.room_code = GameData.generate_room_code()
		if GameData.connected:
			GDSync.lobby_create(GameData.room_code)
	
	if GameData.connected and GameData.room_code != "":
		$UI/status.text = "Room: " + GameData.room_code
		$Pause_UI/roomcode.text = "Room: " + GameData.room_code
	else:
		$UI/status.text = "Connecting..."
		GDSync.lobby_joined.connect(_on_lobby_joined)
		GDSync.connection_failed.connect(_on_connection_failed)
		
func _on_lobby_joined(_lobby_name: String) -> void:
	$UI/status.text = "Room: " + GameData.room_code
	$Pause_UI/roomcode.text = "Room: " + GameData.room_code

func _on_connection_failed(_error: int) -> void:
	$UI/status.text = "Multiplayer unavailable"

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			paused = !paused
			GameData.paused = paused
			$Pause_UI.visible = paused
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
