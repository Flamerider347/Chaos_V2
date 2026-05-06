extends StaticBody3D

var is_open: bool = false

func _ready() -> void:
	GDSync.expose_func(open_door)

func open_door() -> void:
	if is_open:
		return
	is_open = true
	$"../../../../SynchronizedAnimationPlayer".play("door_open")
	if GDSync.is_host():
		GDSync.lobby_close()
