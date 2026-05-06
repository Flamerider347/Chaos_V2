extends Node

func _on_play_pressed() -> void:
	GameData.username = $menu_UI/username.text.strip_edges()
	if GameData.username == "":
		GameData.username = "Player"
	if GameData.connected:
		GDSync.lobby_create(GameData.generate_room_code())
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	var code = $menu_UI/join_code.text.strip_edges()
	if code == "":
		return
	GameData.username = $menu_UI/username.text.strip_edges()
	if GameData.username == "":
		GameData.username = "Player"
	GameData.room_code = code
	GameData.is_joining = true
	if GameData.connected:
		GDSync.lobby_join(code)
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")
