extends Node3D
var cheese = load("res://prefabs/cheese.tscn")
var cheese_left = 5
@onready var Cheeseinstantiator = $Cheeseinstantiator
func _on_punched():
	print("Hello")
	if multiplayer.is_server():
		request_cheese_spawn(global_position)  # call directly if server
	else:
		request_cheese_spawn.rpc_id(1, global_position)  # send to server if client

@rpc("any_peer", "reliable")
func request_cheese_spawn(pos: Vector3):
	if cheese_left > 0:
		cheese_left -= 1
		$Label3D.text = str(cheese_left)
		var spawned_cheese = Cheeseinstantiator.instantiate_node()
		spawned_cheese.position = pos + Vector3(randf_range(-1, 1), 3, randf_range(-1, 1))
		GDSync.set_gdsync_owner(spawned_cheese, GDSync.get_client_id())
		$cheese_timer.start(10)


func _on_cheese_timer_timeout() -> void:
	cheese_left += 1
	$Label3D.text = str(cheese_left)
