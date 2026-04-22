extends CharacterBody3D

const SPEED = 5.0
const GRAVITY = -9.8

var room_peers: Array = []

func _ready():
	await get_tree().process_frame
	$Camera3D.current = is_multiplayer_authority()

func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	var input = Vector3(
		Input.get_axis("ui_left", "ui_right"),
		0,
		Input.get_axis("ui_up", "ui_down")
	)
	velocity.x = input.x * SPEED
	velocity.z = input.z * SPEED
	move_and_slide()
	for peer in room_peers:
		if peer != multiplayer.get_unique_id():
			_sync_position.rpc_id(peer, global_position, global_rotation)

@rpc("any_peer", "unreliable_ordered")
func _sync_position(pos: Vector3, rot: Vector3):
	if is_multiplayer_authority():
		return
	global_position = pos
	global_rotation = rot
