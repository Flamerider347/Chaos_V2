extends Area3D

@onready var smoke_particle: PackedScene = preload("res://Prefabs/smoke_particle.tscn")
@onready var game: Node = $"../../.."

var scores: Dictionary = {
	"cheese": 5,
	"cheese_chopped": 10,
	"tomato": 6,
	"tomato_chopped": 12,
	"bun": 50,
	"bun_bottom_chopped": 40,
	"bun_top_chopped": 30,
	"meat_raw" : 10,
	"meat_cooked" : 50,
	"meat_burnt" : 25,
}

func _ready() -> void:
	GDSync.expose_func(_spawn_smoke)
	GDSync.expose_func(sync_score_to_all)
	GDSync.expose_func(sync_despawn_to_all)


func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return

	# --- 1. IF IT'S A PLAYER: KILL THEM AND EXIT ---
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(1000)
		return

	# --- 2. PROCESS LOOSE ITEMS DROP ---
	if not GameData.connected or GDSync.is_host():
		var score_to_add = 0
		var is_valid_delivery = false
		
		if body.is_in_group("plate"):
			score_to_add = _calculate_plate_score(body)
			is_valid_delivery = true
		elif body.is_in_group("pickupable") and scores.has(body.type):
			score_to_add = scores[body.type]
			is_valid_delivery = true
			
		if is_valid_delivery:
			if score_to_add > 0:
				game.score += score_to_add
				game.power += score_to_add
				if GameData.connected:
					GDSync.call_func_all(sync_score_to_all, [game.score])
					GDSync.call_func_all(_spawn_smoke, [body.global_position])
				else:
					_spawn_smoke(body.global_position)
					
			if GameData.connected:
				# Host explicitly commands everyone (including itself) to clear this asset path
				GDSync.call_func_all(sync_despawn_to_all, [body.get_path()])
			else:
				# Singleplayer fallback safely deferred
				body.call_deferred("queue_free")


func sync_score_to_all(args) -> void:
	if GDSync.is_host():
		return
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		game.score = int(args[0])
	elif typeof(args) == TYPE_INT or typeof(args) == TYPE_FLOAT:
		game.score = int(args)


func sync_despawn_to_all(args) -> void:
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		var target_path = args[0]
		var target_node = get_node_or_null(target_path)
		if is_instance_valid(target_node):
			# Clears the Jolt engine buffer uniformly across the network
			target_node.call_deferred("queue_free")


func _calculate_plate_score(plate_node: Node) -> int:
	if not is_instance_valid(plate_node) or not "stacked_items" in plate_node:
		return 0
		
	var item_nodes: Array = plate_node.stacked_items
	var items: Array = []
	for item in item_nodes:
		if is_instance_valid(item) and "type" in item:
			items.append(item.type)
		
	# --- ORDER INDEPENDENT VALIDATION ---
	# Checks if the plate contains at least one bottom bun and one top bun anywhere in the pile
	var valid_burger := false
	if items.has("bun_bottom_chopped") and items.has("bun_top_chopped"):
		valid_burger = true
	
	items.sort()
	var parsed_key := ""
	for item in items:
		parsed_key += item + ","
	parsed_key = parsed_key.rstrip(" ,")
	
	if parsed_key in RecipeManager.recipe_key_lookup:
		var key_name = RecipeManager.recipe_key_lookup[parsed_key]
		var recipe_data = RecipeManager.recipes[key_name]
		
		if not recipe_data["is_burger"] or valid_burger:
			var base_value = recipe_data["value"]
			
			var is_special = false
			if "recipe_of_the_day" in RecipeManager and RecipeManager.recipe_of_the_day == key_name:
				is_special = true
			elif "recipe_of_the_day2" in RecipeManager and RecipeManager.recipe_of_the_day2 == key_name:
				is_special = true
				
			if is_special:
				return int(base_value * 1.5)
				
			return base_value

	var fallback_score = 0
	for item_name in items:
		if scores.has(item_name):
			fallback_score += scores[item_name]
	return fallback_score


func _spawn_smoke(args) -> void:
	var spawn_pos: Vector3 = Vector3.ZERO
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		spawn_pos = args[0]
	elif typeof(args) == TYPE_VECTOR3:
		spawn_pos = args
	else:
		return
		
	var p = smoke_particle.instantiate()
	var items_container = get_node_or_null("/root/main/game/items")
	if items_container:
		items_container.add_child(p)
	else:
		add_child(p)
		
	p.global_position = spawn_pos
	p.emitting = true
	
	await get_tree().create_timer(p.lifetime + 0.5).timeout
	if is_instance_valid(p):
		p.queue_free()
