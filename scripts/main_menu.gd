extends Node
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if GameData.connected:
		$menu_UI/join_button.disabled = false
		$menu_UI/status.text = "Connected!"
		if GameData.join_error:
			$"menu_UI/lobby error".text = GameData.join_error
	if GameData.lost:
		$menu_UI/status.text = "Game lost, sorry you can't rejoin lobbies yet. To play again, relauch the game."

func _on_play_pressed() -> void:
	GameData.username = $menu_UI/username.text.strip_edges()
	if GameData.username == "":
		GameData.username = "Player"
	
	$LAN_starter.start_server()
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")

func _on_join_pressed() -> void:
	GameData.username = $menu_UI/username.text.strip_edges()
	if GameData.username == "":
		GameData.username = "Player"
	
	$LAN_starter.start_client()
	get_tree().change_scene_to_file("res://Prefabs/main.tscn")
