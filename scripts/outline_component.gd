extends Node
class_name OutlineComponent

# Load your local_outline_mat.tres here in the Inspector
@export var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

func set_outline(active: bool) -> void:
	var parent = get_parent()
	_apply_outline(parent, active)

func _apply_outline(node: Node, active: bool) -> void:
	# If this child is a mesh, overlay or clear the shader shell
	if node is MeshInstance3D:
		node.material_overlay = outline_material if active else null
		
	# Recurse down inside complex nodes (like stoves, chopping boards with sub-meshes)
	for child in node.get_children():
		_apply_outline(child, active)
