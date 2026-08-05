extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GameData.using_computer = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Prefabs/main_menu.tscn")
