@tool
extends StaticBody3D

@export var stored: int:
	set(value):
		stored = value
		if is_inside_tree():
			_update_stored()
@export var display_mesh: Mesh: 
	set(value): 
		display_mesh = value
		if is_inside_tree():
			_update_mesh()
@export var y_offset: float:
	set(value):
		y_offset = value
		if is_inside_tree():
			_update_mesh_pos()

@warning_ignore("unused_signal") signal spawn_item(type: String)


func _ready():
	_update_mesh()
	_update_mesh_pos()
	_update_stored()

func _update_mesh():
	var item_mesh = $item_mesh
	if is_inside_tree() and item_mesh:
		item_mesh.mesh = display_mesh

func _update_mesh_pos():
	var item_mesh = $item_mesh
	if is_inside_tree() and item_mesh:
		item_mesh.position.y = -0.4 + y_offset 

func _update_stored():
	var stored_label = $stored
	if is_inside_tree() and stored_label:
		stored_label.text = str(stored)
