extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $nav_agent
@onready var attack_zone: Area3D = $attack_zone
@onready var anim_player: AnimationPlayer = $goblin/AnimationPlayer

const SPEED = 4.0
const WANDER_SPEED = 3.0
const DAMAGE = 20.0
const ATTACK_COOLDOWN = 1.5
const DETECTION_RADIUS = 7.5

enum State { WANDER, CHASE, ATTACKING }
var current_state: State = State.WANDER

var target_player: CharacterBody3D = null
var cooldown_timer: float = 0.0
var state_timer: float = 0.0
var damage_dealt_this_attack: bool = false
var spawn_position: Vector3
var current_anim: String = ""

func _ready() -> void:
	add_to_group("enemy")
	spawn_position = global_position
	
	_play_anim("GetUp")
	if not multiplayer.is_server():
		set_physics_process(false)
		return
		
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(nav_agent):
		nav_agent.target_reached.connect(_on_target_reached)
	_pick_new_wander_target()

func _physics_process(delta: float) -> void:
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
			_handle_movement(WANDER_SPEED)

		State.CHASE:
			if not is_instance_valid(target_player):
				current_state = State.WANDER
				_pick_new_wander_target()
			elif cooldown_timer <= 0.0 and attack_zone.overlaps_body(target_player):
				current_state = State.ATTACKING
				state_timer = 0.666 # Total duration of Attack2 animation
				damage_dealt_this_attack = false
				cooldown_timer = ATTACK_COOLDOWN
				_play_anim("Attack2")
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				nav_agent.target_position = target_player.global_position
				_play_anim("Run")
				_handle_movement(SPEED)

		State.ATTACKING:
			state_timer -= delta
			velocity.x = 0.0
			velocity.z = 0.0
			
			# Check for the strike frame at precisely 0.45 seconds into the animation
			# (0.666 total - 0.45 strike time = 0.216 remaining on clock)
			if state_timer <= 0.216 and not damage_dealt_this_attack:
				damage_dealt_this_attack = true
				if is_instance_valid(target_player) and attack_zone.overlaps_body(target_player):
					if not target_player.get("is_dead") and not target_player.get("is_in_kitchen"):
						rpc("sync_attack_player", target_player.get_path(), DAMAGE)
			
			if state_timer <= 0.0:
				current_anim = "" 
				current_state = State.CHASE if is_instance_valid(target_player) else State.WANDER
				if current_state == State.WANDER:
					_pick_new_wander_target()

	# Handle smooth spatial rotation
	var look_target = target_player.global_position if is_instance_valid(target_player) else nav_agent.get_next_path_position()
	var look_vector = Vector3(look_target.x, global_position.y, look_target.z)
	if global_position.distance_to(look_vector) > 0.2:
		look_at(look_vector, Vector3.UP)

	move_and_slide()

func _handle_movement(move_speed: float) -> void:
	if not nav_agent.is_navigation_finished():
		var next_path = nav_agent.get_next_path_position()
		var dir = (next_path - global_position).normalized() * move_speed
		velocity.x = dir.x
		velocity.z = dir.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0

func _pick_new_wander_target() -> void:
	if current_anim == "FallOver": return
	var offset = Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var target = spawn_position + offset
	var closest_point = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, target)
	
	nav_agent.target_position = closest_point if closest_point != Vector3.ZERO else spawn_position
	if current_state == State.WANDER:
		_play_anim("Run")

func _on_target_reached() -> void:
	if current_state == State.CHASE or is_instance_valid(target_player): return
	_play_anim("Idle1")
	await get_tree().create_timer(5.0).timeout
	if not is_instance_valid(target_player) and current_state == State.WANDER:
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

func start_despawn_sequence() -> void:
	if current_anim == "FallOver": return
	_play_anim("FallOver")
	current_state = State.WANDER
	velocity = Vector3.ZERO
	await get_tree().create_timer(2.0).timeout
	if multiplayer.is_server():
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
