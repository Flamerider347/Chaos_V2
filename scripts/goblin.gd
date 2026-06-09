extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $nav_agent
@onready var attack_zone: Area3D = $attack_zone
@onready var anim_player: AnimationPlayer = $goblin/AnimationPlayer

const SPEED = 4.0
const WANDER_SPEED = 1.5 
const DAMAGE = 20.0
const ATTACK_COOLDOWN = 1.5
const DETECTION_RADIUS = 10.0 
const WANDER_RADIUS = 15.0 

var target_player: CharacterBody3D = null
var can_attack: bool = true

# --- State & AI Wander ---
var spawn_position: Vector3
var wander_target: Vector3
var wander_timer: float = 0.0
var wander_interval: float = 5.0 

# --- Animation Control States ---
var is_busy: bool = false
var is_dying: bool = false
var current_anim: String = ""

func _ready() -> void:
	add_to_group("enemy")
	spawn_position = global_position
	_pick_random_wander_target()
	
	# Wakeup Sequence
	is_busy = true
	if multiplayer.is_server():
		await get_tree().process_frame
	_play_animation_networked("GetUp")
	
	# If this is a client machine, entirely turn off AI math processing loops
	if not multiplayer.is_server():
		set_physics_process(false)
		return

	await get_tree().create_timer(1.5).timeout
	is_busy = false

func _physics_process(delta: float) -> void:
	if is_dying: return

	# Gravity calculation
	velocity += Vector3.ZERO if is_on_floor() else get_gravity() * delta
	if is_on_floor(): velocity.y = 0.0

	if is_busy or nav_agent.get_navigation_map() == RID():
		move_and_slide()
		return

	_find_closest_player_in_range()
	
	var current_speed = SPEED
	if is_instance_valid(target_player):
		nav_agent.target_position = target_player.global_position
	else:
		current_speed = WANDER_SPEED
		wander_timer += delta
		if wander_timer >= wander_interval:
			wander_timer = 0.0
			_pick_random_wander_target()
		nav_agent.target_position = wander_target
		
	# Path execution loop (Host Only)
	if not nav_agent.is_target_reached():
		var next_path = nav_agent.get_next_path_position()
		if global_position.distance_to(next_path) > 0.05:
			var dir = (next_path - global_position).normalized() * current_speed
			velocity.x = dir.x; velocity.z = dir.z
			_play_animation_networked("Run") 
		else:
			velocity.x = 0.0; velocity.z = 0.0
			_play_animation_networked("Idle")
		
		move_and_slide()
		if Vector2(velocity.x, velocity.z).length() > 0.1:
			_safe_look_at(target_player.global_position if is_instance_valid(target_player) else next_path)
	else:
		velocity.x = 0.0; velocity.z = 0.0
		move_and_slide()
		_play_animation_networked("Idle")
		if is_instance_valid(target_player): _safe_look_at(target_player.global_position)
				
	if is_instance_valid(target_player): _check_attack_zone()

func _safe_look_at(target_pos: Vector3) -> void:
	var look_target = Vector3(target_pos.x, global_position.y, target_pos.z)
	if global_position.distance_to(look_target) > 0.2:
		look_at(look_target, Vector3.UP)

func _play_animation_networked(anim_name: String) -> void:
	if current_anim == anim_name: return
	current_anim = anim_name
	rpc("sync_play_animation", anim_name)

@rpc("any_peer", "call_local", "reliable")
func sync_play_animation(anim_name: String) -> void:
	if is_instance_valid(anim_player) and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

func start_despawn_sequence() -> void:
	if is_dying: return
	is_dying = true; is_busy = true
	velocity = Vector3.ZERO
	_play_animation_networked("FallOver")
	
	await get_tree().create_timer(2.0).timeout
	if multiplayer.is_server():
		queue_free() # Native MultiplayerSpawner cleans up automatically across clients on deletion

func _find_closest_player_in_range() -> void:
	var closest_dist = DETECTION_RADIUS 
	var closest_player = null
	
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_with_properties(player):
			var dist = global_position.distance_to(player.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_player = player
				
	target_player = closest_player

func is_instance_with_properties(player: Node) -> bool:
	return is_instance_valid(player) and not player.get("is_dead") and not player.get("is_in_kitchen")
	
func _pick_random_wander_target() -> void:
	var random_angle = randf() * TAU
	var random_dist = randf() * WANDER_RADIUS
	var unverified_target = spawn_position + Vector3(cos(random_angle) * random_dist, 0.0, sin(random_angle) * random_dist)
	var closest_point = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, unverified_target)
	wander_target = closest_point if closest_point != Vector3.ZERO else spawn_position

func _check_attack_zone() -> void:
	if not can_attack or not is_instance_valid(target_player) or is_busy or is_dying: return
	
	if attack_zone.overlaps_body(target_player):
		can_attack = false; is_busy = true 
		_play_animation_networked("Attack1")
		
		rpc("sync_attack_player", target_player.get_path(), DAMAGE)
			
		await get_tree().create_timer(0.8).timeout
		is_busy = false
		await get_tree().create_timer(ATTACK_COOLDOWN - 0.8).timeout
		can_attack = true

@rpc("any_peer", "call_local", "reliable")
func sync_attack_player(player_path: NodePath, damage_amount: float) -> void:
	var player_node = get_node_or_null(player_path)
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(damage_amount)
