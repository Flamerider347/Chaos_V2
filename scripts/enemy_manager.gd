extends Node3D

@onready var spawn_points: Array[Marker3D] = []
var active_enemies: Array = []

# Dynamically grabs your custom MultiplayerSpawner child node
@onready var enemy_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/enemy_spawner")
@onready var goblin := preload("res://Prefabs/goblin.tscn")

func _ready() -> void:
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_time_check)
	add_child(timer)
	for i in $"../navigation_nodes".get_children():
		if i is Marker3D:
			spawn_points.append(i)

func _on_time_check() -> void:
	if not multiplayer.is_server(): return
	
	if GameData.is_night and active_enemies.size() == 0:
		_spawn_night_wave()
	elif not GameData.is_night and active_enemies.size() > 0:
		_despawn_clear_daytime()

func _spawn_night_wave() -> void:
	if spawn_points.size() == 0: return
	var map = get_world_3d().navigation_map
	print(spawn_points)
	
	for marker in spawn_points:
		if not is_instance_valid(marker): continue
		
		var spawn_pos = marker.global_position
		var closest_point = NavigationServer3D.map_get_closest_point(map, spawn_pos)
		if closest_point != Vector3.ZERO: spawn_pos = closest_point
		
		var goblin_instance = goblin.instantiate()
		$"/root/main/game/enemies".add_child(goblin_instance, true)
		goblin_instance.global_position = spawn_pos
		active_enemies.append(goblin_instance)

func _despawn_clear_daytime() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("start_despawn_sequence"):
				enemy.start_despawn_sequence()
			else:
				# Native fallback: Server handles removal automatically across clients
				enemy.queue_free()
	
	active_enemies.clear()
