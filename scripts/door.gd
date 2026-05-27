extends StaticBody3D

var is_open: bool = false

func _ready() -> void:
	GDSync.expose_func(open_door)

func open_door() -> void:
	if is_open:
		return
	is_open = true
	$"../../../../door_animation_player".play("door_open")
	GDSync.call_func_all(open_door)
	if GameData.connected and GDSync.is_host():
		GDSync.lobby_close()
	GameData.closed_lobby = true
	var env_controller = $"../../../environment_controller" # Change path to match your scene layout

	if env_controller and env_controller.has_method("start_day_cycle"):
		# If utilizing GDSync RPCs, ensure this triggers across the network or is called by the Host
		env_controller.start_day_cycle()
