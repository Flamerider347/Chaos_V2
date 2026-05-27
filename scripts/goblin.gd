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

# --- State & AI Wander variables ---
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
	GDSync.expose_node(self)
	
	spawn_position = global_position
	_pick_random_wander_target()
	
	# Lock states and play GetUp safely
	is_busy = true
	_play_animation_networked("GetUp")
	
	if GameData.connected:
		await get_tree().process_frame
		if not (GDSync.is_host() or GDSync.is_gdsync_owner(self)):
			set_physics_process(false)
			return

	# Keep them locked until the wakeup frames finish
	await get_tree().create_timer(1.5).timeout
	is_busy = false

func _physics_process(delta: float) -> void:
	# If dying, freeze entirely. Do not run gravity or move_and_slide.
	if is_dying:
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	# While getting up or attacking, process gravity/sliding but skip AI pathfinding
	if is_busy:
		move_and_slide()
		return

	if GameData.connected and not (GDSync.is_host() or GDSync.is_gdsync_owner(self)):
		if not is_on_floor():
			move_and_slide()
		return
		
	if nav_agent.get_navigation_map() == RID():
		move_and_slide()
		return

	_find_closest_player_in_range()
	
	var current_speed = SPEED
	
	if is_instance_valid(target_player):
		nav_agent.target_position = target_player.global_position
		current_speed = SPEED
	else:
		current_speed = WANDER_SPEED
		wander_timer += delta
		if wander_timer >= wander_interval:
			wander_timer = 0.0
			_pick_random_wander_target()
		nav_agent.target_position = wander_target
		
	# --- Movement & Execution Loop ---
	if not nav_agent.is_target_reached():
		var next_path_position = nav_agent.get_next_path_position()
		var current_position = global_position
		
		if current_position.distance_to(next_path_position) > 0.05:
			var horizontal_direction = (next_path_position - current_position).normalized() * current_speed
			velocity.x = horizontal_direction.x
			velocity.z = horizontal_direction.z
			_play_animation_networked("Run") 
		else:
			velocity.x = 0.0
			velocity.z = 0.0
			_play_animation_networked("Idle")
		
		move_and_slide()
		
		# Safe rotation check while moving
		if Vector2(velocity.x, velocity.z).length() > 0.1:
			var look_pos = target_player.global_position if is_instance_valid(target_player) else next_path_position
			_safe_look_at(look_pos)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_play_animation_networked("Idle")
		
		# Safe rotation check while idling near target
		if is_instance_valid(target_player):
			_safe_look_at(target_player.global_position)
				
	if is_instance_valid(target_player):
		_check_attack_zone()

# --- Fixed Safe Rotation Logic ---
func _safe_look_at(target_pos: Vector3) -> void:
	# Flat target vector to prevent weird tilting up or down
	var look_target = Vector3(target_pos.x, global_position.y, target_pos.z)
	
	# Only look if the target point is far enough away to calculate proper geometry vectors
	if global_position.distance_to(look_target) > 0.2:
		look_at(look_target, Vector3.UP)

# --- Networked Animation Helper ---
func _play_animation_networked(anim_name: String) -> void:
	if current_anim == anim_name: return
	
	current_anim = anim_name
	if GameData.connected:
		GDSync.call_func_all(sync_play_animation, [anim_name])
	else:
		if anim_player.has_animation(anim_name):
			anim_player.play(anim_name)

func sync_play_animation(params: Array) -> void:
	var anim_name = params[0]
	if is_instance_valid(anim_player) and anim_player.has_animation(anim_name):
		anim_player.play(anim_name)

# --- Daytime Despawn Trigger ---
func start_despawn_sequence() -> void:
	if is_dying: return
	is_dying = true
	is_busy = true
	
	velocity = Vector3.ZERO
	current_anim = "FallOver"
	
	if GameData.connected:
		GDSync.call_func_all(sync_play_animation, ["FallOver"])
	else:
		if anim_player.has_animation("FallOver"):
			anim_player.play("FallOver")
	
	# Match this timer exactly to the length of your FallOver animation clip!
	await get_tree().create_timer(2.0).timeout
	
	if GameData.connected:
		# Only the owner or host should execute the absolute scene destruction
		if GDSync.is_host() or GDSync.is_gdsync_owner(self):
			GDSync.multiplayer_queue_free(self)
	else:
		queue_free()

func _find_closest_player_in_range() -> void:
	var players = get_tree().get_nodes_in_group("player")
	var closest_dist = DETECTION_RADIUS 
	var closest_player = null
	
	for player in players:
		if is_instance_valid(player) and player.get("is_dead") == false:
			# FIX: If the player is in the kitchen, skip them entirely
			if player.get("is_in_kitchen") == true:
				continue
				
			var dist = global_position.distance_to(player.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_player = player
				
	target_player = closest_player
	
func _pick_random_wander_target() -> void:
	var random_angle = randf() * TAU
	var random_dist = randf() * WANDER_RADIUS
	var offset = Vector3(cos(random_angle) * random_dist, 0.0, sin(random_angle) * random_dist)
	var unverified_target = spawn_position + offset
	
	var map = get_world_3d().navigation_map
	var closest_point = NavigationServer3D.map_get_closest_point(map, unverified_target)
	wander_target = closest_point if closest_point != Vector3.ZERO else spawn_position

func _check_attack_zone() -> void:
	if not can_attack or not is_instance_valid(target_player) or is_busy or is_dying: return
	
	if attack_zone.overlaps_body(target_player):
		can_attack = false
		is_busy = true 
		_play_animation_networked("Attack1")
		
		if GameData.connected:
			GDSync.call_func_all(sync_attack_player, [target_player.get_path(), DAMAGE])
		else:
			target_player.take_damage(DAMAGE)
			
		await get_tree().create_timer(0.8).timeout
		is_busy = false
		
		await get_tree().create_timer(ATTACK_COOLDOWN - 0.8).timeout
		can_attack = true

func sync_attack_player(params: Array) -> void:
	var player_node = get_node_or_null(params[0])
	var damage_amount = params[1]
	if is_instance_valid(player_node) and player_node.has_method("take_damage"):
		player_node.take_damage(damage_amount)
