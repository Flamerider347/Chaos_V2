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
	
func _on_body_entered(body: Node) -> void:
	if GameData.connected:
		GDSync.call_func_all(_spawn_smoke, [body.global_position])
	else:
		_spawn_smoke(body.global_position)

	# --- OPTIMIZED PLAYER INVENTORY DELIVERY ---
	if body.is_in_group("player"):
		# Check if the player actually has items to prevent useless loops
		if body.has_method("get_inventory_items_for_score"):
			var player_items: Array = body.get_inventory_items_for_score()
			
			if player_items.size() > 0:
				var local_added_score = 0
				for item_name in player_items:
					if scores.has(item_name):
						local_added_score += scores[item_name]
				
				# Apply score directly to the match state
				game.score += local_added_score
				print("Player sacrificed inventory directly! Scored: +", local_added_score)
			
			# Wipe inventory data safely inside the player instance without spawning loose entities
			if body.has_method("clear_inventory_safely"):
				body.clear_inventory_safely()
		
		# Execute a standard damage/respawn loop without littering the arena floor
		body.take_damage(1000)
		return

	# --- STANDARD SINGLE-PLATE DELIVERY ---
	elif body.is_in_group("plate"):
		var item_nodes: Array = body.stacked_items
		var items: Array = []
		for item in item_nodes:
			items.append(item.type)
		
		var valid_burger := false
		if items:
			if items[0] == "bun_bottom_chopped" and items[-1] == "bun_top_chopped":
				valid_burger = true
		
		items.sort()
		var parsed_key := ""
		for item in items:
			parsed_key += item + ","
		parsed_key = parsed_key.rstrip(" ,")
		
		if parsed_key in RecipeManager.recipe_key_lookup:
			var name = RecipeManager.recipe_key_lookup[parsed_key]
			if RecipeManager.recipes[name]["is_burger"]:
				if valid_burger:
					game.score += RecipeManager.recipes[name]["value"]
					body.queue_free()
					print(name)
					return
			else:
				game.score += RecipeManager.recipes[name]["value"]
				body.queue_free()
				print(name)
				return
		
		for item_name in items:
			if scores.has(item_name):
				game.score += scores[item_name]
		print(items)
		body.queue_free()
		
	elif body.is_in_group("pickupable"):
		if scores.has(body.type):
			game.score += scores[body.type]
		print(body.type)
		body.queue_free()

func _spawn_smoke(args) -> void:
	var spawn_pos: Vector3 = Vector3.ZERO
	
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		spawn_pos = args[0]
	elif typeof(args) == TYPE_VECTOR3:
		spawn_pos = args
	else:
		return
		
	var p = smoke_particle.instantiate()
	get_node("/root/main/game/items").add_child(p)
	p.global_position = spawn_pos
	p.emitting = true
	
	await get_tree().create_timer(p.lifetime + 0.5).timeout
	if is_instance_valid(p):
		p.queue_free()
