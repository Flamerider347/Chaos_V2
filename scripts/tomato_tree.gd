extends Node3D

var tomato_left = 5

@onready var Tomatoinstantiator = $TomatoInstantiator

func _ready() -> void:
	GDSync.expose_func(_on_punched)
	GDSync.expose_var(self, "tomato_left")

var _last_tomato_left = 5

func _process(_delta: float) -> void:
	if tomato_left != _last_tomato_left:
		_last_tomato_left = tomato_left
		$Label3D.text = str(tomato_left)

func _on_punched():
	if not GDSync.is_host():
		GDSync.call_func_on(GDSync.get_host(), _on_punched)
		return
	if tomato_left > 0:
		tomato_left -= 1
		GDSync.sync_var(self, "tomato_left")
		$Label3D.text = str(tomato_left)
		var spawned_tomato = Tomatoinstantiator.instantiate_node()
		spawned_tomato.type = "tomato"
		spawned_tomato.position = global_position + Vector3(randf_range(-1, 1), 3, randf_range(-1, 1))
		GDSync.set_gdsync_owner(spawned_tomato, GDSync.get_client_id())
		$tomato_timer.start(10)

func _on_tomato_timer_timeout() -> void:
	tomato_left += 1
	GDSync.sync_var(self, "tomato_left")
	$Label3D.text = str(tomato_left)
