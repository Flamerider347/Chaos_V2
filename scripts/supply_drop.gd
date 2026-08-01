extends CharacterBody3D

var contents: Array = []

@onready var item_spawner: MultiplayerSpawner = get_node_or_null("/root/main/game/spawners/item_spawner")

# Tracks whether the crate has already landed so land() only runs once
var has_landed: bool = false

func _ready() -> void:
	# Position is managed by MultiplayerSpawner / custom spawn handler
	$CSGBakedMeshInstance3D2.hide()
	$CSGBakedMeshInstance3D.show()
	$Label3D2.show()
	$Label3D.show()
	$CollisionShape3D2.disabled = false
	$CollisionShape3D.disabled = true

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	elif not has_landed:
		land()

	move_and_slide()

func land() -> void:
	has_landed = true
	
	# Swap visual meshes and collision shapes
	$CSGBakedMeshInstance3D2.show()
	$CSGBakedMeshInstance3D.hide()
	$Label3D2.hide()
	$Label3D.hide()
	$CollisionShape3D2.disabled = true
	$CollisionShape3D.disabled = false
	
	# Spawning network objects must only happen on the server
	if not multiplayer.is_server():
		return
		
	# Spawn all items contained in the supply crate
	for raw_item in contents:
		var item_name: String = str(raw_item)
		
		# If a full path was passed, extract just the item name (e.g., "res://Prefabs/carrot.tscn" -> "carrot")
		if item_name.contains("/"):
			item_name = item_name.get_file().get_basename()
			
		item_name = item_name.to_lower()

		# Scatter within +/- 1 unit offset on X and Z
		var offset: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
		var spawn_pos: Vector3 = global_position + offset
		
		var unique_name: String = item_name + "_" + str(randi() % 100000)
		
		# Build the exact same package structure used by your tree script
		# [item_name_prefix, sender_id, spawn_pos, unique_name]
		var package: Array = [item_name, multiplayer.get_unique_id(), spawn_pos, unique_name]
		
		if is_instance_valid(item_spawner):
			item_spawner.spawn(package)
