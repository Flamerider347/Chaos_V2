extends Node3D

var valid_food_types : Array[String] = ["cheese", "tomato", "bun", "meat_raw"]
var stocks : Dictionary[String, Array] = {}
var item_spawn_pos : Vector3

func _ready():
	for food_type in valid_food_types:
		stocks[food_type] = []
	item_spawn_pos = $output/spawn_point.global_position
	$main_display/cheese.spawn_item.connect(spawn_item)
	$main_display/tomato.spawn_item.connect(spawn_item)
	$main_display/bun.spawn_item.connect(spawn_item)
	$main_display/meat_raw.spawn_item.connect(spawn_item)
	


func _process(_delta):
	pass


func _on_input_body_entered(body):
	var type = body.get("type")
	if type != null:
		if body.is_class("RigidBody3D"):
			if type in valid_food_types:
				stocks[type].append(body)
				body.position = Vector3(0, -50 , 0)
				body.freeze = true
				body.visible = false
				get_node("main_display/" + type).stored = len(stocks[type])
			else:
				body.linear_velocity.y = 4
				body.linear_velocity.x = randf_range(-3, 3)
				body.linear_velocity.z = randf_range(-3, 3)
		else:
			print("static")


func spawn_item(item_type):
	print(item_type)
	if len(stocks[item_type]) > 0:
		var item_to_spawn = stocks[item_type].pop_back()
		item_to_spawn.freeze = false
		item_to_spawn.visible = true
		item_to_spawn.position = item_spawn_pos
		get_node("main_display/" + item_type).stored = len(stocks[item_type])
		
