extends Node3D

@onready var spawn_points: Array[Marker3D] = []
var active_enemies: Array = []

# 1. OPTIMIZATION: Preload the scene so it lives in RAM, avoiding disk reads mid-game
const GOBLIN_PREFAB = preload("res://Prefabs/goblin.tscn")

@onready var enemy_spawner: MultiplayerSpawner = get_node("/root/main/game/spawners/enemy_spawner")
func _ready() -> void:
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_on_time_check)
	add_child(timer)
	
	for i in $"../navigation_nodes".get_children():
		if i is Marker3D:
			spawn_points.append(i)
			
	# Every peer binds the spawning template rules on load
	if is_instance_valid(enemy_spawner):
		enemy_spawner.spawn_function = _on_goblin_spawn_custom

func _on_time_check() -> void:
	if not multiplayer.is_server(): return
	
	if GameData.is_night and active_enemies.size() == 0:
		_spawn_night_wave()
	elif not GameData.is_night and active_enemies.size() > 0:
		_despawn_clear_daytime()

func _spawn_night_wave() -> void:
	if spawn_points.size() == 0: return
	if not is_instance_valid(enemy_spawner): return
	
	var map = get_world_3d().navigation_map
	var spawn_parent = get_node_or_null("/root/main/game/enemies")
	
	for marker in spawn_points:
		if not is_instance_valid(marker): continue
		
		var global_spawn_pos = marker.global_position
		var closest_point = NavigationServer3D.map_get_closest_point(map, global_spawn_pos)
		if closest_point != Vector3.ZERO: 
			global_spawn_pos = closest_point
		
		var local_spawn_pos: Vector3 = Vector3.ZERO
		if is_instance_valid(spawn_parent):
			local_spawn_pos = spawn_parent.to_local(global_spawn_pos)
		else:
			local_spawn_pos = self.to_local(global_spawn_pos)
		
		var enemy_id = "Goblin_" + str(randi() % 100000)
		var package = [local_spawn_pos, enemy_id]
		
		enemy_spawner.spawn(package)
		
		# 3. OPTIMIZATION: Wait 1 frame before spawning the next goblin. 
		# This spreads the performance load smoothly instead of hitting the CPU all at once!
		await get_tree().process_frame

func _on_goblin_spawn_custom(data: Array) -> Node:
	var target_pos = data[0]
	var unique_name = data[1]
	
	# 2. OPTIMIZATION: Instantiate directly from RAM. No more ResourceLoader checks!
	var goblin_instance = GOBLIN_PREFAB.instantiate()
	goblin_instance.name = unique_name
	goblin_instance.position = target_pos
	
	if not active_enemies.has(goblin_instance):
		active_enemies.append(goblin_instance)
		
	return goblin_instance

func _despawn_clear_daytime() -> void:
	for enemy in active_enemies:
		if is_instance_valid(enemy):
			if enemy.has_method("start_despawn_sequence"):
				enemy.start_despawn_sequence()
			else:
				enemy.queue_free()
	
	active_enemies.clear()
