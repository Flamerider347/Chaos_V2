extends Node3D

var cheese_left = 5

@onready var Cheeseinstantiator = $Cheeseinstantiator

func _ready() -> void:
	GDSync.expose_func(_on_punched)
	GDSync.expose_var(self, "cheese_left")

var _last_cheese_left = 5

func _process(_delta: float) -> void:
	if cheese_left != _last_cheese_left:
		_last_cheese_left = cheese_left
		$Label3D.text = str(cheese_left)

func _on_punched():
	if not GDSync.is_host():
		GDSync.call_func_on(GDSync.get_host(), _on_punched)
		return
	if cheese_left > 0:
		cheese_left -= 1
		GDSync.sync_var(self, "cheese_left")
		$Label3D.text = str(cheese_left)
		var spawned_cheese = Cheeseinstantiator.instantiate_node()
		spawned_cheese.type = "cheese"
		spawned_cheese.position = global_position + Vector3(randf_range(-1, 1), 3, randf_range(-1, 1))
		GDSync.set_gdsync_owner(spawned_cheese, GDSync.get_client_id())
		$cheese_timer.start(10)

func _on_cheese_timer_timeout() -> void:
	cheese_left += 1
	GDSync.sync_var(self, "cheese_left")
	$Label3D.text = str(cheese_left)
