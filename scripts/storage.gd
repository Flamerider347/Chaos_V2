extends Node3D

var valid_food_types : Array[String] = ["cheese", "tomato", "bun", "meat_raw"]
@export var stocks : Dictionary[String, Array] = {}
var item_spawn_pos : Vector3

func _ready():
	for food_type in valid_food_types:
		stocks[food_type] = []
	item_spawn_pos = $output/spawn_point.global_position
	$main_display/cheese.spawn_item.connect(spawn_item)
	$main_display/tomato.spawn_item.connect(spawn_item)
	$main_display/bun.spawn_item.connect(spawn_item)
	$main_display/meat_raw.spawn_item.connect(spawn_item)
	$main_display/plate.spawn_item.connect(spawn_item)
	
	GDSync.expose_func(spawn_item)


func _on_input_body_entered(body):
	if (GameData.connected and GDSync.is_host()) or not GameData.connected:
		var type = body.get("type")
		if type != null:
			if body.is_class("RigidBody3D"):
				if type in valid_food_types:
					stocks[type].append(body)
					body.position = Vector3(0, -50 , 0)
					body.freeze = true
					body.visible = false
					get_node("main_display/" + type).stored = len(stocks[type])
				elif type == "plate" and len(body.stacked_items) == 0:
					body.position = Vector3(0,0,0)
				else:
					body.linear_velocity.y = 4
					body.linear_velocity.x = randf_range(-3, 3)
					body.linear_velocity.z = randf_range(-3, 3)
			else:
				print("static")

func spawn_item(item_type):
	if not GameData.closed_lobby:
		return
	if (GameData.connected and not GDSync.is_host()):
		GDSync.call_func_on(GDSync.get_host(), spawn_item, item_type)
		return
	
	if item_type == "plate":
		if GameData.current_plates < 20:
			var spawned_item = $plate_instantiator.instantiate_node()
			if GameData.connected:
				GDSync.set_gdsync_owner(spawned_item, GDSync.get_client_id())
			spawned_item.position = item_spawn_pos
			GameData.current_plates += 1
			get_node("main_display/" + item_type).stored = 20 - GameData.current_plates
		else:
			$main_display/plate_warning.show()
			$warning_timer.start(1.5)
			return

	elif len(stocks[item_type]) > 0:
		var item_to_spawn = stocks[item_type].pop_back()
		item_to_spawn.freeze = false
		item_to_spawn.visible = true
		item_to_spawn.position = item_spawn_pos
		get_node("main_display/" + item_type).stored = len(stocks[item_type])


func _on_warning_timer_timeout() -> void:
	$main_display/plate_warning.hide()
