extends StaticBody3D
const CHOPPED_SCENES = {
	"cheese": preload("res://Prefabs/cheese_chopped.tscn"),
	"tomato": preload("res://Prefabs/cheese_chopped.tscn")
}


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("choppable"):
		chop(body)

func chop(body: Node3D) -> void:
	body.queue_free()
	if not GDSync.is_host():
		return
	if CHOPPED_SCENES.has(body.type):
		var chopped = GDSync.multiplayer_instantiate(CHOPPED_SCENES[body.type], get_node("/root/main/game/items"), true, [], true)
		chopped.global_position = global_position + Vector3(0, 0.5, 0)
		chopped.add_to_group("plate_stackable")
