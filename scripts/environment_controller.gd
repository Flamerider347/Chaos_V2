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
	ui_time_label = get_node_or_null("/root/main/UI/day_timer")
	if not ui_time_label:
		ui_time_label = get_tree().current_scene.find_child("day_timer", true, false) as Label
	update_sky_and_lighting()


func _process(delta: float) -> void:
	if not is_cycle_started or (GameData.paused and not GameData.connected): return
		
	if multiplayer.is_server():
		current_time += delta / day_length_seconds
		rpc_id(0, "sync_time_from_host", current_time)
		
		if current_time > 0.25 and not changed_day:
			changed_day = true
			current_day += 1
			rpc("sync_day_increment", current_day)
			create_daily_special()
			
		if current_time > 1.0 and changed_day:
			current_time = 0.0
			changed_day = false

	update_sky_and_lighting()
	if is_instance_valid(ui_time_label): update_ui_clock()


func start_day_cycle() -> void:
	is_cycle_started = true


@rpc("any_peer", "unreliable")
func sync_time_from_host(new_time: float) -> void:
	current_time = new_time
	GameData.is_night = (current_time >= 0.8333333 or current_time < 0.25)


@rpc("any_peer", "call_local", "reliable")
func sync_day_increment(day_num: int) -> void:
	current_day = day_num
	new_day.emit(current_day)
	var day_lbl = get_node_or_null("/root/main/UI/current_day")
	if day_lbl: day_lbl.text = "Day: " + str(current_day)


func create_daily_special():
	if not multiplayer.is_server(): return
	var keys = RecipeManager.recipes.keys()
	if keys.size() == 0: return

	var r1 = keys[randi_range(0, keys.size() - 1)]
	var r2 = r1
	if keys.size() > 1:
		while r2 == r1:
			r2 = keys[randi_range(0, keys.size() - 1)]
			
	rpc("sync_daily_specials_to_all", [r1, r2])


@rpc("any_peer", "call_local", "reliable")
func sync_daily_specials_to_all(args: Array) -> void:
	RecipeManager.recipe_of_the_day = args[0]
	RecipeManager.recipe_of_the_day2 = args[1]

	var setups = [
		{"disp": $"../world/kitchen/thing_placement/daily_recipe", "lbl": $"../world/kitchen/thing_placement/recipe_of_the_day", "data": RecipeManager.recipes.get(args[0])},
		{"disp": $"../world/kitchen/thing_placement/daily_recipe2", "lbl": $"../world/kitchen/thing_placement/recipe_of_the_day2", "data": RecipeManager.recipes.get(args[1])}
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
		if "freeze" in plate:
			plate.freeze = true
			plate.remove_from_group("plate")
		display_node.add_child(plate)
		plate.global_position = display_node.global_position 
		stack_height += get_node_height(plate) + gap
		
		var components_list: Array = data.components if data is Resource else data["components"]
		for item_key in components_list:
			if not ingredients.has(item_key): continue
			var item = ingredients[item_key].instantiate()
			item.type = item_key
			if "freeze" in item: item.freeze = true
			display_node.add_child(item)
			item.global_position = display_node.global_position + Vector3(0, stack_height, 0)
			stack_height += get_node_height(item) + gap

		if is_instance_valid(recipe_label):
			recipe_label.text = "RECIPE OF THE DAY:\n%s ($%d)" % [data.get("display_name", "Unknown"), int(data.get("value", 0)) * 1.5]
			recipe_label.global_position = display_node.global_position + Vector3(0, stack_height + 0.6, 0)


func get_node_height(node: Node) -> float:
	if not is_instance_valid(node): return 0.1
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
	sun_light.light_color = Color(0.05, 0.05, 0.15) if GameData.is_night else Color(1.0, 0.95, 0.85).lerp(Color(0.95, 0.45, 0.15), sunset_blend)

	var env = world_env.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var night_weight = 1.0 - (sun_fade / 1.2)
		env.ambient_light_color = Color(0.6, 0.7, 0.8).lerp(Color(0.2, 0.25, 0.35), night_weight)
		env.ambient_light_energy = lerp(1.0, 0.6, night_weight)

	if is_instance_valid(night_light):
		night_light.light_energy = (1.0 - (sun_fade / 1.2)) * 2.0


func update_ui_clock() -> void:
	var total_minutes = int(current_time * 24.0 * 60.0)
	var hours = int(total_minutes / 60.0) % 24
	var minutes = total_minutes % 60
	var am_pm = "PM" if hours >= 12 else "AM"
	var display_hour = hours % 12
	if display_hour == 0: display_hour = 12
		
	ui_time_label.text = "%02d:%02d %s" % [display_hour, minutes, am_pm]
