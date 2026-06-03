extends Node3D

@export var spawn_points: Array[Marker3D] = []
var active_enemies: Array = []

# Dynamically grabs your custom MultiplayerSpawner child node
@onready var enemy_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/enemy_spawner")

func _ready() -> void:
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_time_check)
	add_child(timer)

func _on_time_check() -> void:
	if not multiplayer.is_server(): return
	
	var is_night = GameData.get("is_night") if "is_night" in GameData else false
	
	if is_night and active_enemies.size() == 0:
		_spawn_night_wave()
	elif not is_night and active_enemies.size() > 0:
		_despawn_clear_daytime()

func _spawn_night_wave() -> void:
	if spawn_points.size() == 0: return
	var map = get_world_3d().navigation_map
	
	for marker in spawn_points:
		if not is_instance_valid(marker): continue
		
		var spawn_pos = marker.global_position
		var closest_point = NavigationServer3D.map_get_closest_point(map, spawn_pos)
		if closest_point != Vector3.ZERO: spawn_pos = closest_point

		# Use the MultiplayerSpawner to spawn the goblin. 
		# Passing custom arguments array ensures the server tracks it.
		var enemy_instance = enemy_spawner.spawn(["goblin", 1])
		enemy_instance.global_position = spawn_pos
		active_enemies.append(enemy_instance)

func _despawn_clear_daytime() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("start_despawn_sequence"):
				enemy.start_despawn_sequence()
			else:
				# Native fallback: Server handles removal automatically across clients
				enemy.queue_free()
					
	active_enemies.clear()
