extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $nav_agent
@onready var attack_zone: Area3D = $attack_zone
@onready var anim_player: AnimationPlayer = $goblin/AnimationPlayer

# UI Reference
@onready var health_bar = get_node_or_null("SubViewport/ProgressBar")

# Spawner Reference
@onready var item_spawner: MultiplayerSpawner = get_node_or_null("/root/main/game/spawners/item_spawner")

# Baseline speeds (Hard / Baseline difficulty values)
const BASE_SPEED = 3.25        # Normal chase speed
const BASE_ATTACK_SPEED = 3.5   # Lunge attack speed
const BASE_WANDER_SPEED = 3.0   # Wandering speed

# Health Settings
const MAX_HEALTH: float = 100.0
var current_health: float = MAX_HEALTH
var is_dead: bool = false

# Actual speeds applied after difficulty multiplier calculation
var move_speed: float = BASE_SPEED
var attack_speed: float = BASE_ATTACK_SPEED
var wander_speed: float = BASE_WANDER_SPEED

const DAMAGE = 20.0
const ATTACK_COOLDOWN = 1.5
const DETECTION_RADIUS = 10.0
const DAMAGE_RADIUS = 3.5

enum State { WANDER, CHASE, ATTACKING }
var current_state: State = State.WANDER

var target_player: CharacterBody3D = null
var cooldown_timer: float = 0.0
var state_timer: float = 0.0
var damage_dealt_this_attack: bool = false
var spawn_position: Vector3
var current_anim: String = ""

func _ready() -> void:
	set_physics_process(false)
	
	# Fetch difficulty multiplier from global game data singleton
	var diff_mult: float = 1.0
	if Engine.has_singleton("GameData") or get_node_or_null("/root/GameData"):
		var game_data = get_node("/root/GameData")
		if game_data.has_method("get_difficulty_multiplier"):
			diff_mult = game_data.get_difficulty_multiplier()
	
	# Apply difficulty scaling to goblin movement speeds
	move_speed = BASE_SPEED * diff_mult
	attack_speed = BASE_ATTACK_SPEED * diff_mult
	wander_speed = BASE_WANDER_SPEED * diff_mult

	await get_tree().create_timer(0.2).timeout
	set_physics_process(true)
	
	add_to_group("enemy")
	spawn_position = global_position
	
	_update_health_bar()
	_play_anim("GetUp")
	
	if not multiplayer.is_server():
		set_physics_process(false)
		return
		
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(nav_agent):
		nav_agent.target_reached.connect(_on_target_reached)
	_pick_new_wander_target()

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	if cooldown_timer > 0.0:
		cooldown_timer -= delta

	if not is_on_floor():
		velocity.y -= 9.81 * delta
	else:
		velocity.y = 0.0

	if current_anim == "FallOver" or current_anim == "GetUp":
		move_and_slide()
		return

	_find_closest_player()

	match current_state:
		State.WANDER:
			if is_instance_valid(target_player):
				current_state = State.CHASE
			elif nav_agent.is_navigation_finished():
				_play_anim("Idle1")
			_handle_movement(wander_speed)

		State.CHASE:
			if not is_instance_valid(target_player):
				current_state = State.WANDER
				_pick_new_wander_target()
			elif cooldown_timer <= 0.0 and attack_zone.overlaps_body(target_player):
				current_state = State.ATTACKING
				state_timer = 0.666 # Duration of Attack2 animation
				damage_dealt_this_attack = false
				cooldown_timer = ATTACK_COOLDOWN
				_play_anim("Attack2")
			else:
				nav_agent.target_position = target_player.global_position
				_play_anim("Run")
				_handle_movement(move_speed)

		State.ATTACKING:
			state_timer -= delta
			
			# Lunge directly toward player using difficulty-adjusted attack_speed
			if is_instance_valid(target_player):
				var dir = (target_player.global_position - global_position)
				dir.y = 0.0
				dir = dir.normalized() * attack_speed
				velocity.x = dir.x
				velocity.z = dir.z
			else:
				velocity.x = 0.0
				velocity.z = 0.0
			
			# Check strike frame timing
			if state_timer <= 0.216 and not damage_dealt_this_attack:
				damage_dealt_this_attack = true
				if is_instance_valid(target_player):
					var dist_to_player = global_position.distance_to(target_player.global_position)
					if dist_to_player <= DAMAGE_RADIUS:
						if not target_player.get("is_dead") and not target_player.get("is_in_kitchen"):
							rpc("sync_attack_player", target_player.get_path(), DAMAGE)
			
			if state_timer <= 0.0:
				current_anim = "" 
				current_state = State.CHASE if is_instance_valid(target_player) else State.WANDER
				if current_state == State.WANDER:
					_pick_new_wander_target()

	# Handle smooth rotation
	var look_target = target_player.global_position if is_instance_valid(target_player) else nav_agent.get_next_path_position()
	var look_vector = Vector3(look_target.x, global_position.y, look_target.z)
	if global_position.distance_to(look_vector) > 0.2:
		look_at(look_vector, Vector3.UP)

	move_and_slide()

# --- DAMAGE & HEALTH SYSTEM ---
func take_damage(amount: float) -> void:
	if is_dead:
		return
		
	# Request server to process damage if client is calling this
	if not multiplayer.is_server():
		rpc_id(1, "server_handle_damage", amount)
		return
		
	server_handle_damage(amount)

@rpc("any_peer", "call_local", "reliable")
func server_handle_damage(amount: float) -> void:
	if not multiplayer.is_server() or is_dead:
		return
		
	rpc("sync_take_damage", amount)

@rpc("any_peer", "call_local", "reliable")
func sync_take_damage(amount: float) -> void:
	if is_dead:
		return

	current_health = clamp(current_health - amount, 0.0, MAX_HEALTH)
	_update_health_bar()

	if current_health <= 0.0:
		die()

func _spawn_meat_drops() -> void:
	if not multiplayer.is_server():
		return
		
	var drop_count: int = randi_range(1, 3)
	for i in range(drop_count):
		var angle: float = randf_range(0, 2 * PI)
		var spawn_pos: Vector3 = global_position + Vector3(sin(angle), 0.2, cos(angle)) * randf_range(0.5, 1.5)
		var unique_name: String = "meat_" + str(randi() % 100000)
		
		# Spawns meat using item_spawner matching your tree item structure
		# package array format: [item_type, sender_id, position, unique_name]
		var package: Array = ["meat", 1, spawn_pos, unique_name]
		
		if is_instance_valid(item_spawner):
			item_spawner.spawn(package)

func _update_health_bar() -> void:
	if is_instance_valid(health_bar):
		health_bar.value = (current_health / MAX_HEALTH) * 100.0

# --- NAVIGATION & UTILITY ---
func _handle_movement(speed_to_use: float) -> void:
	if not nav_agent.is_navigation_finished():
		var next_path = nav_agent.get_next_path_position()
		var dir = (next_path - global_position).normalized() * speed_to_use
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _pick_new_wander_target() -> void:
	if current_anim == "FallOver" or is_dead: return
	var offset = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var target = spawn_position + offset
	var closest_point = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, target)
	
	nav_agent.target_position = closest_point if closest_point != Vector3.ZERO else spawn_position
	if current_state == State.WANDER:
		_play_anim("Run")

func _on_target_reached() -> void:
	if current_state == State.CHASE or is_instance_valid(target_player) or is_dead: return
	_play_anim("Idle1")
	await get_tree().create_timer(5.0).timeout
	if not is_instance_valid(target_player) and current_state == State.WANDER and not is_dead:
		_pick_new_wander_target()

func _find_closest_player() -> void:
	var closest_dist = DETECTION_RADIUS 
	var closest_player = null
	
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and not player.get("is_dead") and not player.get("is_in_kitchen"):
			var dist = global_position.distance_to(player.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_player = player
				
	target_player = closest_player

func die() -> void:
	if is_dead:
		return
	is_dead = true
	set_physics_process(false)
	
	# Turn off collisions so it doesn't trigger extra hits while dying
	$CollisionShape3D.set_deferred("disabled", true)
	if is_instance_valid(attack_zone):
		attack_zone.set_deferred("monitoring", false)
		attack_zone.set_deferred("monitorable", false)
		
	_spawn_meat_drops()
	start_despawn_sequence()

func start_despawn_sequence() -> void:
	# Avoid repeating the animation if already falling over
	if current_anim != "FallOver":
		_play_anim("FallOver")
		
	current_state = State.WANDER
	velocity = Vector3.ZERO
	
	# Safe timer check using the scene tree directly
	var tree = get_tree()
	if not tree:
		return
		
	await tree.create_timer(2.0).timeout
	
	# Verify node and multiplayer peer are still valid before freeing
	if is_instance_valid(self) and is_inside_tree():
		if multiplayer and multiplayer.is_server():
			queue_free()

func _play_anim(anim_name: String) -> void:
	if current_anim == anim_name: return
	current_anim = anim_name
	rpc("sync_play_animation", anim_name)

@rpc("any_peer", "call_local", "reliable")
func sync_play_animation(anim_name: String) -> void:
	if is_instance_valid(anim_player) and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

@rpc("any_peer", "call_local", "reliable")
func sync_attack_player(player_path: NodePath, damage_amount: float) -> void:
	var player_node = get_node_or_null(player_path)
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(damage_amount)
