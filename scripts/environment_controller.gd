extends Node3D

# Day length updated to 24.0 for quick testing (change to 240.0 for production)
@export var day_length_seconds: float = 240.0

@onready var ui_time_label = get_node_or_null("/root/main/UI/day_timer")
@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var night_light = $nightlight
@onready var ingredients = {
	"tomato_chopped" : preload("res://Prefabs/tomato_chopped.tscn"),
	"cheese_chopped" : preload("res://Prefabs/cheese_chopped.tscn"),
	"bun_top_chopped" : preload("res://Prefabs/bun_top_chopped.tscn"),
	"lettuce_chopped" : preload("res://Prefabs/lettuce_chopped.tscn"),
	"carrot_chopped" : preload("res://Prefabs/carrot_chopped.tscn"),
	"bun_bottom_chopped" : preload("res://Prefabs/bun_bottom_chopped.tscn"),
	"meat_cooked" : preload("res://Prefabs/meat_cooked.tscn"),
	"plate" : preload("res://Prefabs/plate.tscn")
}

# Day starts at 6:00 AM (0.25)
var current_time: float = 0.25
var is_cycle_started: bool = false 
var current_day = 0
var changed_day = false
signal new_day

func _ready() -> void:
	ui_time_label = get_node_or_null("/root/main/UI/day_timer")
	update_sky_and_lighting()

func _process(delta: float) -> void:
	# 1. Stop immediately if the cycle isn't running or if the game has been lost
	if not is_cycle_started or GameData.lost or (GameData.paused and not GameData.connected): return
	
	# 2. Safety Check: If the multiplayer API wrapper instance itself is broken or freeing, skip calculation
	if not is_instance_valid(multiplayer): return
		
	# Check if we are running the simulation host authority role
	var is_host_authority = true
	if multiplayer.multiplayer_peer and not multiplayer.is_server():
		is_host_authority = false
		
	if is_host_authority:
		current_time += delta / day_length_seconds
		
		# Only send RPC updates if a network match is running
		if multiplayer.multiplayer_peer:
			rpc_id(0, "sync_time_from_host", current_time)
		else:
			# Singleplayer manual assignment loop
			# STRICT GOBLIN WINDOW: True only between Midnight (0.0) and 6:00 AM (0.25)
			GameData.is_night = (current_time < 0.25)
		
		# Day increments at 6:00 AM when the light returns
		if current_time > 0.25 and not changed_day:
			changed_day = true
			current_day += 1
			
			if multiplayer.multiplayer_peer:
				rpc("sync_day_increment", current_day)
			else:
				sync_day_increment(current_day)
				
			create_daily_special()
			
		if current_time > 1.0:
			current_time -= 1.0  # Keep smooth remainder loop
			changed_day = false

	update_sky_and_lighting()
	if ui_time_label: update_ui_clock()

@rpc("any_peer", "call_local", "reliable")
func start_day_cycle() -> void:
	is_cycle_started = true
	
func _is_host_or_singleplayer() -> bool:
	if not is_instance_valid(multiplayer) or multiplayer.multiplayer_peer == null:
		return true
	return multiplayer.is_server()

func create_daily_special():
	if not _is_host_or_singleplayer(): return
	
	var keys = RecipeManager.recipes.keys()
	if keys.size() == 0: return

	var r1 = keys[randi_range(0, keys.size() - 1)]
	var r2 = r1
	if keys.size() > 1:
		while r2 == r1:
			r2 = keys[randi_range(0, keys.size() - 1)]
			
	if is_instance_valid(multiplayer) and multiplayer.multiplayer_peer:
		rpc("sync_daily_specials_to_all", [r1, r2])
	else:
		sync_daily_specials_to_all([r1, r2])

@rpc("authority", "unreliable", "call_local")
func sync_time_from_host(new_time: float) -> void:
	current_time = new_time
	# STRICT GOBLIN WINDOW: Midnight to 6 AM
	GameData.is_night = (current_time < 0.25)

@rpc("authority", "call_local", "reliable")
func sync_day_increment(day_num: int) -> void:
	current_day = day_num
	new_day.emit(current_day)
	
	if not is_inside_tree(): return
	
	var day_lbl = get_node_or_null("/root/main/UI/current_day")
	if day_lbl: day_lbl.text = "Day: " + str(current_day)

@rpc("authority", "call_local", "reliable")
func sync_daily_specials_to_all(args: Array) -> void:
	RecipeManager.recipe_of_the_day = args[0]
	RecipeManager.recipe_of_the_day2 = args[1]

	if not is_inside_tree(): return

	var setups = [
		{"disp": get_node_or_null("../world/kitchen/thing_placement/daily_recipe"), "lbl": get_node_or_null("../world/kitchen/thing_placement/recipe_of_the_day"), "data": RecipeManager.recipes.get(args[0])},
		{"disp": get_node_or_null("../world/kitchen/thing_placement/daily_recipe2"), "lbl": get_node_or_null("../world/kitchen/thing_placement/recipe_of_the_day2"), "data": RecipeManager.recipes.get(args[1])}
	]

	for setup in setups:
		var display_node = setup["disp"]
		var recipe_label = setup["lbl"]
		var data = setup["data"]
		if not is_instance_valid(display_node) or data == null: continue

		for child in display_node.get_children(): child.queue_free()
			
		var stack_height: float = 0.0
		var gap: float = 0.1 
		
		var plate = ingredients["plate"].instantiate()
		_strip_item_interactivity(plate, "plate")
		
		display_node.add_child(plate)
		plate.global_position = display_node.global_position 
		stack_height += get_node_height(plate) + gap
		
		var components_list: Array = data.components if data is Resource else data["components"]
		for item_key in components_list:
			if not ingredients.has(item_key): continue
			var item = ingredients[item_key].instantiate()
			item.type = item_key
			
			_strip_item_interactivity(item, "pickupable")
			
			display_node.add_child(item)
			item.global_position = display_node.global_position + Vector3(0, stack_height, 0)
			stack_height += get_node_height(item) + gap

		if is_instance_valid(recipe_label):
			recipe_label.text = "RECIPE OF THE DAY:\n%s ($%d)" % [data.get("display_name", "Unknown"), int(data.get("value", 0)) * 1.5]
			recipe_label.global_position = display_node.global_position + Vector3(0, stack_height + 0.6, 0)

func _strip_item_interactivity(node: Node, group_to_remove: String) -> void:
	if not is_instance_valid(node): return
	if node.is_in_group(group_to_remove):
		node.remove_from_group(group_to_remove)
	if node.is_in_group("pickupable"):
		node.remove_from_group("pickupable")
		
	if "freeze" in node:
		node.freeze = true
		
	node.set_process(false)
	node.set_physics_process(false)
	node.set_script(null) 
	
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.process_mode = Node.PROCESS_MODE_DISABLED

func get_node_height(node: Node) -> float:
	if not is_instance_valid(node): return 0.1
	var col = node.find_child("CollisionShape3D", true, false)
	if col and col.shape:
		if col.shape is BoxShape3D: return col.shape.size.y
		elif col.shape is CylinderShape3D or col.shape is CapsuleShape3D: return col.shape.height
		elif col.shape is SphereShape3D: return col.shape.radius * 2.0
	return 0.1

func update_sky_and_lighting() -> void:
	var sun_angle = (current_time * TAU) + (TAU / 4.0)
	sun_light.rotation.x = sun_angle
	sun_light.rotation.y = deg_to_rad(25.0) 
	
	var sun_fade: float = 0.0
	var sunset_blend: float = 0.0
	
	# LONG TWILIGHT BUFFER:
	# 0.25 to 0.30 -> Sunrise (6:00 AM to 7:12 AM)
	# 0.30 to 0.75 -> Full Day (7:12 AM to 6:00 PM)
	# 0.75 to 1.00 -> SLOW Sunset Fade (6:00 PM down to Midnight)
	# 0.00 to 0.25 -> Pitch Black Goblin Hours (Midnight to 6:00 AM)
	
	if current_time >= 0.25 and current_time < 0.30:
		# Sunrise
		sun_fade = smoothstep(0.25, 0.30, current_time) * 1.2
		sunset_blend = smoothstep(0.30, 0.25, current_time)
	elif current_time >= 0.30 and current_time < 0.75:
		# Full Day
		sun_fade = 1.2
		sunset_blend = 0.0
	elif current_time >= 0.75 and current_time <= 1.0:
		# Slow Evening Transition (6 hours long)
		sun_fade = smoothstep(1.0, 0.75, current_time) * 1.2
		sunset_blend = smoothstep(0.75, 1.0, current_time)
	else:
		# Deep night (0.0 to 0.25)
		sun_fade = 0.0
		sunset_blend = 0.0

	sun_light.light_energy = sun_fade
	sun_light.light_color = Color(0.02, 0.02, 0.08) if GameData.is_night else Color(1.0, 0.95, 0.85).lerp(Color(0.95, 0.45, 0.15), sunset_blend)

	var env = world_env.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var night_weight = 1.0 - (sun_fade / 1.2)
		env.ambient_light_color = Color(0.6, 0.7, 0.8).lerp(Color(0.15, 0.18, 0.25), night_weight)
		env.ambient_light_energy = lerp(1.0, 0.3, night_weight)

	if is_instance_valid(night_light):
		night_light.light_energy = (1.0 - (sun_fade / 1.2)) * 2.0

func update_ui_clock() -> void:
	var total_minutes = int(current_time * 24.0 * 60.0)
	var hours = int(total_minutes / 60.0) % 24
	var minutes = total_minutes % 60
	
	var am_pm = "AM" if hours < 12 else "PM"
	var display_hour = hours % 12
	if display_hour == 0: display_hour = 12
		
	ui_time_label.text = "%02d:%02d %s" % [display_hour, minutes, am_pm]
