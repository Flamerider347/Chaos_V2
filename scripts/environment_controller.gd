extends Node3D

@export var day_length_seconds: float = 180.0

@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var night_light : OmniLight3D = $nightlight
@onready var ingredients = {
	"tomato_chopped" : preload("res://Prefabs/tomato_chopped.tscn"),
	"cheese_chopped" : preload("res://Prefabs/cheese_chopped.tscn"),
	"bun_top_chopped" : preload("res://Prefabs/bun_top_chopped.tscn"),
	"bun_bottom_chopped" : preload("res://Prefabs/bun_bottom_chopped.tscn"),
	"meat_cooked" : preload("res://Prefabs/meat_cooked.tscn"),
	"plate" : preload("res://Prefabs/plate.tscn")
}

var ui_time_label: Label = null
var current_time: float = 0.25
var is_cycle_started: bool = false 
var current_day = 0
var changed_day = false
signal new_day


func _ready() -> void:
	if has_node("/root/main/UI/day_timer"):
		ui_time_label = get_node("/root/main/UI/day_timer") as Label
	else:
		ui_time_label = get_tree().current_scene.find_child("day_timer", true, false) as Label

	update_sky_and_lighting()


func _process(delta: float) -> void:
	if not is_cycle_started:
		return

	if GameData.paused and not GameData.connected:
		return
		
	if not GameData.connected:
		current_time += delta / day_length_seconds
		
		GameData.is_night = (current_time >= 0.8333333 or current_time < 0.25)
			
		if current_time > 0.25 and not changed_day:
			create_daily_special()
			changed_day = true
			current_day += 1
			new_day.emit(current_day)
			$"../../UI/current_day".text = "Day: " + str(current_day)
			
		if current_time > 1.0 and changed_day:
			current_time = 0.0
			changed_day = false

			
	if is_instance_valid(sun_light) and is_instance_valid(world_env):
		update_sky_and_lighting()
		
	if is_instance_valid(ui_time_label):
		update_ui_clock()


func start_day_cycle() -> void:
	is_cycle_started = true


func sync_time_from_host(args) -> void:
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		current_time = float(args[0])
	elif typeof(args) == TYPE_FLOAT or typeof(args) == TYPE_INT:
		current_time = float(args)


func sync_start_trigger(_dummy = null) -> void:
	is_cycle_started = true


func create_daily_special():
	var recipe_size = RecipeManager.recipes.size()
	if recipe_size == 0:
		return

	var keys = RecipeManager.recipes.keys()
	var random_recipe_1 = keys[randi_range(0, recipe_size - 1)]
	var random_recipe_2 = random_recipe_1
	
	if recipe_size > 1:
		while random_recipe_2 == random_recipe_1:
			random_recipe_2 = keys[randi_range(0, recipe_size - 1)]

	else:
		sync_daily_specials_to_all([random_recipe_1, random_recipe_2])


func sync_daily_specials_to_all(args) -> void:
	if typeof(args) != TYPE_ARRAY or args.size() < 2:
		return

	var recipe_1_key = args[0]
	var recipe_2_key = args[1]

	RecipeManager.recipe_of_the_day = recipe_1_key
	RecipeManager.recipe_of_the_day2 = recipe_2_key

	var setups = [
		{
			"display_node": $"../world/kitchen/thing_placement/daily_recipe",
			"label_node": $"../world/kitchen/thing_placement/recipe_of_the_day",
			"data": RecipeManager.recipes.get(recipe_1_key)
		},
		{
			"display_node": $"../world/kitchen/thing_placement/daily_recipe2",
			"label_node": $"../world/kitchen/thing_placement/recipe_of_the_day2",
			"data": RecipeManager.recipes.get(recipe_2_key)
		}
	]

	for setup in setups:
		var display_node = setup["display_node"]
		var recipe_label = setup["label_node"]
		var chosen_recipe_data = setup["data"]
		
		if not is_instance_valid(display_node) or chosen_recipe_data == null:
			continue

		for child in display_node.get_children():
			child.queue_free()
			
		var stack_height: float = 0.0
		var ingredient_gap: float = 0.1 
		
		var spawned_plate = ingredients["plate"].instantiate()
		if "freeze" in spawned_plate:
			spawned_plate.freeze = true
			spawned_plate.remove_from_group("plate")

		display_node.add_child(spawned_plate)
		spawned_plate.global_position = display_node.global_position 
		stack_height += get_node_height(spawned_plate) + ingredient_gap
		
		var components_list: Array = chosen_recipe_data.components if chosen_recipe_data is Resource else chosen_recipe_data["components"]
		
		for item_key in components_list:
			if not ingredients.has(item_key):
				continue
				
			var spawned_item = ingredients[item_key].instantiate()
			spawned_item.type = item_key
			if "freeze" in spawned_item:
				spawned_item.freeze = true
				
			display_node.add_child(spawned_item)
			spawned_item.global_position = display_node.global_position + Vector3(0, stack_height, 0)
			stack_height += get_node_height(spawned_item) + ingredient_gap

		if is_instance_valid(recipe_label):
			recipe_label.text = "RECIPE OF THE DAY:\n%s ($%d)" % [
				chosen_recipe_data.get("display_name", "Unknown"), 
				int(chosen_recipe_data.get("value", 0)) * 1.5
			]
			recipe_label.global_position = display_node.global_position + Vector3(0, stack_height + 0.6, 0)


func get_node_height(node: Node) -> float:
	if not is_instance_valid(node): 
		return 0.1
	var col = node.find_child("CollisionShape3D", true, false)
	if col and col.shape:
		if col.shape is BoxShape3D: return col.shape.size.y
		elif col.shape is CylinderShape3D or col.shape is CapsuleShape3D: return col.shape.height
		elif col.shape is SphereShape3D: return col.shape.radius * 2.0
	return 0.1


func update_sky_and_lighting() -> void:
	var sun_angle = current_time * TAU - (TAU / 4.0) + (TAU / 2.0)
	sun_light.rotation.x = sun_angle
	sun_light.rotation.y = deg_to_rad(25.0) 
	
	var sun_fade: float = 0.0
	var sunset_blend: float = 0.0
	
	if current_time >= 0.25 and current_time < 0.3333:
		sun_fade = smoothstep(0.25, 0.3333, current_time) * 0.4
		sunset_blend = 1.0
	elif current_time >= 0.3333 and current_time < 0.4167:
		sun_fade = lerp(0.4, 1.2, smoothstep(0.3333, 0.4167, current_time))
		sunset_blend = smoothstep(0.4167, 0.3333, current_time)
	elif current_time >= 0.4167 and current_time < 0.6667:
		sun_fade = 1.2
		sunset_blend = 0.0
	elif current_time >= 0.6667 and current_time < 0.75:
		sun_fade = 1.2
		sunset_blend = smoothstep(0.6667, 0.75, current_time)
	elif current_time >= 0.75 and current_time < 0.9167:
		sun_fade = smoothstep(0.9167, 0.75, current_time) * 0.3
		sunset_blend = smoothstep(0.9167, 0.75, current_time)

	sun_light.light_energy = sun_fade
	
	var day_color = Color(1.0, 0.95, 0.85)
	var sunset_color = Color(0.95, 0.45, 0.15)
	
	sun_light.light_color = Color(0.05, 0.05, 0.15) if GameData.is_night else day_color.lerp(sunset_color, sunset_blend)

	var env = world_env.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var night_weight = 1.0 - (sun_fade / 1.2)
		env.ambient_light_color = Color(0.6, 0.7, 0.8).lerp(Color(0.2, 0.25, 0.35), night_weight)
		env.ambient_light_energy = lerp(1.0, 0.6, night_weight)

	# --- FADE NIGHTLIGHT IN AND OUT ---
	if is_instance_valid(night_light):
		var night_weight = 1.0 - (sun_fade / 1.2)
		# Multiplied by 2.0 for max brightness at midnight. Adjust this value as needed.
		night_light.light_energy = night_weight * 2.0
func update_ui_clock() -> void:
	var total_minutes = int(current_time * 24.0 * 60.0)
	var hours = int(total_minutes / 60.0) % 24
	var minutes = total_minutes % 60
	
	var am_pm = "PM" if hours >= 12 else "AM"
	var display_hour = hours % 12
	if display_hour == 0:
		display_hour = 12
		
	ui_time_label.text = "%02d:%02d %s" % [display_hour, minutes, am_pm]
	$"../../UI/current_day".text = "Day: " +str(current_day)
