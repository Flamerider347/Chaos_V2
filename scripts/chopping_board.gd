extends StaticBody3D
const CHOPPED_SCENES = {
	"cheese": [[preload("res://Prefabs/cheese_chopped.tscn"), "cheese_chopped"]],
	"tomato": [[preload("res://Prefabs/tomato_chopped.tscn"), "tomato_chopped"]],
	"bun": [
		[preload("res://Prefabs/bun_bottom_chopped.tscn"), "bun_bottom_chopped"], 
		[preload("res://Prefabs/bun_top_chopped.tscn"), "bun_top_chopped"]
	]
}


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("choppable"):
		chop(body)

func chop(body: Node3D) -> void:
	body.queue_free()
	if not GDSync.is_host():
		return
	if CHOPPED_SCENES.has(body.type):
		var things_to_spawn = CHOPPED_SCENES[body.type]
		for item_collection in things_to_spawn:
			var chopped = GDSync.multiplayer_instantiate(item_collection[0], get_node("/root/main/game/items"), true, [], true)
			chopped.global_position = global_position + Vector3(0, 0.5, 0)
			chopped.add_to_group("plate_stackable")
			chopped.type = item_collection[1]
