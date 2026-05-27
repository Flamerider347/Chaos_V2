extends CharacterBody3D

const WALK_SPEED = 1.5
const GRAVITY = 9.8

@export var wander_radius: float = 10.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var wander_timer: Timer = $WanderTimer

var home_position: Vector3

func _ready() -> void:
	# Save where the cow started so it wanders around this general area
	home_position = global_position
	
	
	# Pick the first spot after a tiny delay to let the map initialize
	await get_tree().create_timer(0.5).timeout
	pick_random_destination()

func _physics_process(delta: float) -> void:
	# Apply standard physics gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# If we haven't reached our destination, move towards it
	if not nav_agent.is_navigation_finished():
		var next_path_position: Vector3 = nav_agent.get_next_path_position()
		var current_position: Vector3 = global_position
		
		# Calculate horizontal direction vector
		var direction: Vector3 = (next_path_position - current_position)
		direction.y = 0 # Keep movement purely strictly horizontal
		direction = direction.normalized()
		
		# Rotate smoothly towards the walking direction
		if direction != Vector3.ZERO:
			var target_rotation = atan2(-direction.x, -direction.z)
			rotation.y = rotate_toward(rotation.y, target_rotation, delta * 4.0)
		
		# Set movement velocity
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
	else:
		# Slow down smoothly when destination is reached
		velocity.x = move_toward(velocity.x, 0, WALK_SPEED * delta * 5.0)
		velocity.z = move_toward(velocity.z, 0, WALK_SPEED * delta * 5.0)

	move_and_slide()

func pick_random_destination() -> void:
	# Generate a random offset offset inside our designated wander zone
	var random_offset = Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	
	var target_pos = home_position + random_offset
	
	# Ask Godot's navigation system to find the closest valid point on your NavMesh
	var map = get_world_3d().navigation_map
	var closest_point = NavigationServer3D.map_get_closest_point(map, target_pos)
	
	# Assign it to the agent
	nav_agent.target_position = closest_point

func _on_wander_timer_timeout() -> void:
	print("Hello")
	# Only pick a new spot if the cow is idle or sitting still
	if nav_agent.is_navigation_finished() or randf() > 0.3:
		pick_random_destination()
		print("Hello 2")


func _on_navigation_agent_3d_waypoint_reached(_details: Dictionary) -> void:
	$WanderTimer.start(1)
