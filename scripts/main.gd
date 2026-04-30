extends Node3D

var paused: bool = false

func _ready() -> void:
	$UI/roomcode.text = "Room: " + GameData.room_code
	$pause_UI/roomcode.text = "Room: " + GameData.room_code
	$pause_UI.visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			paused = !paused
			$pause_UI.visible = paused
			GameData.paused = paused
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
