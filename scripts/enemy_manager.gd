extends Node3D

@export var enemy_scene: PackedScene = preload("res://Prefabs/goblin.tscn")
@export var spawn_points: Array[Marker3D] = []

var active_enemies: Array = []

func _ready() -> void:
	# Poll time state changes every second
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_time_check)
	add_child(timer)

func _on_time_check() -> void:
	if GameData.connected and not GDSync.is_host(): return
	
	var is_night = GameData.get("is_night") if "is_night" in GameData else false
	
	if is_night and active_enemies.size() == 0:
		_spawn_night_wave()
	elif not is_night and active_enemies.size() > 0:
		_despawn_clear_daytime()

func _spawn_night_wave() -> void:
	if spawn_points.size() == 0: return
	
	for marker in spawn_points:
		if not is_instance_valid(marker): 
			continue
			
		var spawn_pos = marker.global_position
		
		# Optional: Use NavigationServer to snap the spawn position perfectly onto the navmesh floor
		var map = get_world_3d().navigation_map
		var closest_point = NavigationServer3D.map_get_closest_point(map, spawn_pos)
		if closest_point != Vector3.ZERO:
			spawn_pos = closest_point

		if GameData.connected:
			var enemy_instance = GDSync.multiplayer_instantiate(enemy_scene, self, true, [])
			# Always set global_position AFTER adding to or instantiating in the tree
			enemy_instance.global_position = spawn_pos
			active_enemies.append(enemy_instance)
		else:
			var enemy_instance = enemy_scene.instantiate()
			add_child(enemy_instance)
			# Always set global_position AFTER adding to or instantiating in the tree
			enemy_instance.global_position = spawn_pos
			active_enemies.append(enemy_instance)

func _despawn_clear_daytime() -> void:
	print("Day breaks... Despawning remaining monsters.")
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			# If the enemy has our script, tell it to handle its own death sequence
			if enemy.has_method("start_despawn_sequence"):
				enemy.start_despawn_sequence()
			else:
				# Fallback for generic nodes without the script
				if GameData.connected:
					GDSync.multiplayer_queue_free(enemy)
				else:
					enemy.queue_free()
					
	# Clear our tracking list immediately so no new logic runs on them
	active_enemies.clear()
