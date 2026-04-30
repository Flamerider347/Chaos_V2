extends RigidBody3D

var held_by: int = -1  # peer ID of whoever is holding it, -1 = nobody
@export var hit_force_multiplier: float = 2

func _ready():
	contact_monitor = true
	max_contacts_reported = 1
	set_multiplayer_authority(1)  # server owns all holdables


func _on_body_entered(body: Node):
	if body is CharacterBody3D and held_by == -1:
		var vel = linear_velocity
		# Apply XZ and Y separately
		body.velocity.x += vel.x * hit_force_multiplier
		body.velocity.z += vel.z * hit_force_multiplier
		body.velocity.y += vel.y * hit_force_multiplier * 0.3  # dampen vertical a lot
	
@rpc("any_peer", "reliable", "call_local")
func set_held_by(peer_id: int):
	held_by = peer_id
	freeze = peer_id != -1
	# Disable collision while held, re-enable on drop
	if peer_id == -1:
		collision_layer = 1
		collision_mask = 1
		await get_tree().create_timer(0.1).timeout
		set_multiplayer_authority(1)
	else:
		collision_layer = 0
		collision_mask = 0
		await get_tree().create_timer(0.1).timeout
		set_multiplayer_authority(peer_id)
