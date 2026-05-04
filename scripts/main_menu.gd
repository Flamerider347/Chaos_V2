extends Node
func _on_play_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	GameData.username = username if username != "" else "Player"
	
	if GameData.connected:
		var code = GameData.generate_room_code()
		GameData.room_code = code
		GDSync.lobby_create(code)
	
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	var username = $menu_UI/username.text.strip_edges()
	var code = $menu_UI/join_code.text.strip_edges()
	if code == "":
		return
	GameData.username = username if username != "" else "Player"
	GameData.room_code = code
	GameData.is_joining = true
	
	if GameData.connected:
		GDSync.lobby_join(code)
	
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")


func _on_host_pressed() -> void:
	pass # Replace with function body.
