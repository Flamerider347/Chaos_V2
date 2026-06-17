extends Node

func _ready():
	if OS.has_feature("server_spooler"): # Multiinstancer
		get_tree().change_scene_to_file.call_deferred("res://Prefabs/server_spooler_gui.tscn")
	elif OS.has_feature("dedicated_server"): # Server Instance
		if OS.has_feature("dedicated_server"):
			GameData.host_game()
		get_tree().change_scene_to_file.call_deferred("res://Prefabs/main.tscn")
	else: # Average Client
		get_tree().change_scene_to_file.call_deferred("res://Prefabs/main_menu.tscn")
