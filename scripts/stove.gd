extends StaticBody3D

@export var cooked_meat_scene: PackedScene
@export var burnt_meat_scene: PackedScene

var current_cooking_item: RigidBody3D = null
var cookedness: float = 0.0

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_in_group("pickupable") and "state" in body:
		current_cooking_item = body

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == current_cooking_item:
		current_cooking_item = null
		cookedness = 0.0

func _physics_process(delta: float) -> void:
	# Only the host should handle tracking cooking timers and swapping network items
	if not GDSync.is_host(): 
		return

	if is_instance_valid(current_cooking_item):
		var state = current_cooking_item.state
		
		if state != "burnt":
			cookedness += 1.0 * delta
			
			if state == "raw" and cookedness > 5.0:
				cook_swap(cooked_meat_scene, "cooked")
			elif state == "cooked" and cookedness > 10.0:
				cook_swap(burnt_meat_scene, "burnt")

func cook_swap(new_scene: PackedScene, new_state_string: String) -> void:
	var old_pos = current_cooking_item.global_position
	var old_rot = current_cooking_item.global_rotation
	
	# FIX: Use GD-Sync's network wide deletion so it disappears for non-hosts instantly!
	GDSync.multiplayer_queue_free(current_cooking_item)
	current_cooking_item = null
	
	if new_scene:
		# Use GDSync's multiplayer instantiation to spawn it globally 
		var new_item = GDSync.multiplayer_instantiate(new_scene, get_node("/root/main/game/items"), true, [], true)
		new_item.global_position = old_pos
		new_item.global_rotation = old_rot
		new_item.state = new_state_string
		
		# Relock the loop tracking pointer for the host
		current_cooking_item = new_item
