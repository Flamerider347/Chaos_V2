@tool
extends StaticBody3D

@export var stored: int:
	set(value):
		stored = value
		if is_inside_tree():
			_update_stored()

@warning_ignore("unused_signal") signal spawn_item(type: String)


func _ready():
	_update_stored()


func _update_stored():
	var stored_label = $stored
	if is_inside_tree() and stored_label:
		stored_label.text = str(stored)
