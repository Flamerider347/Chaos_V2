extends Area3D

@onready var smoke_particle: PackedScene = preload("res://Prefabs/smoke_particle.tscn")
@onready var game: Node = $"../../.."

var scores: Dictionary = {
	"cheese": 5, "cheese_chopped": 10, "tomato": 6, "tomato_chopped": 12, "bun": 50,
	"bun_bottom_chopped": 40, "bun_top_chopped": 30, "meat": 10, "meat_cooked": 50, "meat_burnt": 25
}

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body): return

	if body.is_in_group("player"):
		if body.has_method("take_damage"): body.take_damage(1000)
		return

	# Offline Check: Ensure non-server players are caught and blocked in multiplayer, 
	# but allowed through if playing entirely alone.
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server(): return
	
	var score_to_add = 0
	var is_valid_delivery = false
	
	if body.is_in_group("plate"):
		score_to_add = _calculate_plate_score(body)
		is_valid_delivery = true
		GameData.current_plates = max(0, GameData.current_plates - 1)
		
		if multiplayer.multiplayer_peer:
			rpc("sync_plate_ui", GameData.current_plates)
		else:
			sync_plate_ui(GameData.current_plates)
			
	elif body.is_in_group("pickupable") and scores.has(body.type):
		score_to_add = scores[body.type]
		is_valid_delivery = true
		
	if is_valid_delivery:
		game.score += score_to_add
		game.power += score_to_add
		
		if multiplayer.multiplayer_peer:
			rpc("sync_delivery_effects", body.global_position, game.score)
		else:
			sync_delivery_effects(body.global_position, game.score)
		
		if "stacked_items" in body:
			for item in body.stacked_items:
				_safe_jolt_delete(item)
				
		_safe_jolt_delete(body)

# Helper function to strip collisions before freeing to prevent Jolt ref_count errors
func _safe_jolt_delete(node) -> void:
	if not is_instance_valid(node): return
	node.freeze = true

	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.process_mode = Node.PROCESS_MODE_DISABLED
	
	node.call_deferred("queue_free")

@rpc("any_peer", "call_local", "reliable")
func sync_plate_ui(current_plates: int) -> void:
	var ui_node = get_node_or_null("../kitchen/storage_unit/main_display/plate")
	if ui_node: ui_node.stored = 20 - current_plates

@rpc("any_peer", "call_local", "reliable")
func sync_delivery_effects(spawn_pos: Vector3, new_score: int) -> void:
	game.score = new_score
	if game.has_method("thing_ui_update"): game.thing_ui_update()
	_spawn_smoke(spawn_pos)

func _calculate_plate_score(plate_node: Node) -> int:
	if not is_instance_valid(plate_node) or not "stacked_items" in plate_node: return 0
		
	var items: Array = []
	for item in plate_node.stacked_items:
		if is_instance_valid(item) and "type" in item: items.append(item.type)
		
	var valid_burger = items.has("bun_bottom_chopped") and items.has("bun_top_chopped")
	items.sort()
	
	var parsed_key = ",".join(items)
	if parsed_key in RecipeManager.recipe_key_lookup:
		var key_name = RecipeManager.recipe_key_lookup[parsed_key]
		var recipe_data = RecipeManager.recipes[key_name]
		
		if not recipe_data["is_burger"] or valid_burger:
			var base_value = recipe_data["value"]
			var is_special = ("recipe_of_the_day" in RecipeManager and RecipeManager.recipe_of_the_day == key_name) or \
							 ("recipe_of_the_day2" in RecipeManager and RecipeManager.recipe_of_the_day2 == key_name)
			return int(base_value * 1.5) if is_special else base_value

	var fallback_score = 0
	for item_name in items:
		if scores.has(item_name): fallback_score += scores[item_name]
	return fallback_score

func _spawn_smoke(spawn_pos: Vector3) -> void:
	var p = smoke_particle.instantiate()
	var items_container = get_node_or_null("/root/main/game/items")
	if items_container: items_container.add_child(p)
	else: add_child(p)
		
	p.global_position = spawn_pos
	p.emitting = true
	await p.finished
	if is_instance_valid(p): p.queue_free()
