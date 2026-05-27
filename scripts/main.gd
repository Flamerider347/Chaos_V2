extends Node3D

@export var score: int = 0
@export var power: float = 100
@export var total_power_cost = 0
var current_day = 0
var paused: bool = false

func _ready() -> void:
	GDSync.expose_func(burn_it_all_down)
	GameData.in_game = true
	GameData.lost = false
	$Pause_UI.visible = false
	
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
			$UI.visible = !paused
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


func _on_environment_controller_new_day(day) -> void:
	current_day = day
	if day != 1:
		total_power_cost += 10 * day 
	thing_ui_update()
	if power <0:
		if not GameData.connected:
			burn_it_all_down()
		if GameData.connected:
			GDSync.call_func_all(burn_it_all_down)


func thing_ui_update():
	var next_night_cost = 10 * (current_day+1)
	power = 100 + score - total_power_cost
	var power_req = power - next_night_cost
	if power_req < 0:
		power_req = abs(power_req)
	else:
		power_req = 0
	$game/world/kitchen/thing_placement/thing_UI.text = "
	Score:" + str(score) + "
	Power left: " +str(power) + "
	Power needed to survive next night: " +str(next_night_cost) + "
	You need " +str(power_req) + " more Power to survive tonight"
func burn_it_all_down():
	GameData.lost = true
	GameData.in_game = false
	GDSync.lobby_leave()
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")
	
