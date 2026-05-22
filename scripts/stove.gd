extends StaticBody3D
const COOKED_SCENES = {
	"cheese": preload("res://Prefabs/cheese_chopped.tscn"),
	"tomato": preload("res://Prefabs/tomato_chopped.tscn")
}


func _on_area_3d_body_entered(body: Node3D) -> void:
	print(body.get_groups())
	if body.is_in_group("meat"):
		body.cooking = true




func _on_area_3d_body_exited(body: Node3D) -> void:
	if body.is_in_group("meat"):
		body.cooking = false
