extends CharacterBody3D

const SPEED = 5.0
const GRAVITY = -9.8

func _ready():
	# Disable camera for everyone except the local player
	$Camera3D.current = is_multiplayer_authority()

func _physics_process(delta):
	if not is_multiplayer_authority():
		return  # Only process input for YOUR player

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Movement
	var input = Vector3(
		Input.get_axis("ui_left", "ui_right"),
		0,
		Input.get_axis("ui_up", "ui_down")
	)
	velocity.x = input.x * SPEED
	velocity.z = input.z * SPEED
	move_and_slide()

	# Sync position to other players
	_sync_position.rpc(global_position, global_rotation)

@rpc("any_peer", "unreliable")
func _sync_position(pos: Vector3, rot: Vector3):
	if not is_multiplayer_authority():
		global_position = pos
		global_rotation = rot
