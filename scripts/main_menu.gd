extends Node

func _ready() -> void:
	$menu_UI/join_button.pressed.connect(_on_join_pressed)
	$menu_UI/play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	if username == "":
		username = "Player"
	GameData.username = username
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	var code = $menu_UI/join_code.text.strip_edges()
	if username == "":
		username = "Player"
	if code == "":
		return
	GameData.username = username
	GameData.room_code = code
	GameData.is_joining = true
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")
