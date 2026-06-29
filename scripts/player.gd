extends CharacterBody3D

var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = false
var is_owned: bool = false

# Movement & Settings
const SPEED: float = 5.0
const JUMP_VELOCITY: float = 3.5
const GRAVITY: float = 9.8
var mouse_sensitivity: float = 0.003
var speed_multiplier: float = 1.0

# Inventory State
var held_item = null
var held_object_amount: int = 0
var can_pickup: bool = true
var current_slot: String = "1" # "0" is now used for empty hands
var holding_two_handed: bool = false

# Format: "Slot": [UI_Label, Count, Type_String, [Array_Of_World_Nodes]]
var inventory: Dictionary = {
	"1": [null, 0, null, []],
	"2": [null, 0, null, []],
	"3": [null, 0, null, []],
	"4": [null, 0, null, []]
}

# Nodes
var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

# UI Nodes
@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/loading")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider: Slider = get_node_or_null("/root/main/Pause_UI/sensitivity")
@onready var main_game_ui = get_node_or_null("/root/main/UI")
@onready var pause_menu_ui = get_node_or_null("/root/main/Pause_UI")

# ---------------------------------------------------------
# INITIALIZATION
# ---------------------------------------------------------

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("player")
	is_owned = (name.to_int() == multiplayer.get_unique_id())

	if is_owned:
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_setup_ui_slots()
		var chosen_name: String = GameData.username if GameData.username != "" else "Player"
		rpc.call_deferred("sync_username", chosen_name)
	else:
		if is_instance_valid($head/camera): $head/camera.queue_free()
		rpc_id.call_deferred(name.to_int(), "request_username_from_owner")

	update_inventory_ui()

func _setup_ui_slots() -> void:
	for slot_key in inventory:
		var ui_slot: Label = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key))
		if ui_slot: inventory[slot_key][0] = ui_slot

# ---------------------------------------------------------
# INPUT & PROCESS
# ---------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_owned: return

	if Input.is_action_just_pressed("ui_cancel"):
		GameData.paused = not GameData.paused
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if GameData.paused else Input.MOUSE_MODE_CAPTURED)
		if main_game_ui: main_game_ui.visible = not GameData.paused
		if pause_menu_ui: pause_menu_ui.visible = GameData.paused

	if GameData.paused: return

	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x - event.relative.y * mouse_sensitivity * 5, -90, 90)

func _physics_process(delta: float) -> void:
	if not is_owned: return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		if position.y < -5: position = Vector3(0, 2, 0)
	if GameData.paused:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return

	_update_states(delta)
	_handle_slot_switching()
	
	var target = interact_cast.get_collider() if interact_cast.is_colliding() else null
	_update_outline(target)
	
	_handle_interactions(target)
	_handle_snapping(target)
	_handle_movement()
# ---------------------------------------------------------
# CORE LOGIC HANDLERS
# ---------------------------------------------------------

func _update_states(delta: float) -> void:
	if Input.is_action_just_pressed("debug_toggle"): GameData.is_night = true
	if ui_sensitivity_slider: mouse_sensitivity = ui_sensitivity_slider.value

	if is_in_kitchen:
		health = minf(health + (10.0 * delta), max_health)
		if ui_healthbar: ui_healthbar.value = int(health)

	holding_two_handed = false
	if is_instance_valid(held_item):
		if ("is_two_handed" in held_item and held_item.is_two_handed) or (held_item.is_in_group("plate") and held_item.get("stacked_items").size() > 0):
			holding_two_handed = true
func _handle_movement() -> void:
	if Input.is_action_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var vec: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	speed_multiplier = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var weighted_speed: float = clampf(SPEED - (held_object_amount * 0.1), 3.0, 5.0) * speed_multiplier
	if holding_two_handed: weighted_speed = 3.0

	var dir: Vector3 = (transform.basis * Vector3(vec.x, 0, vec.y)).normalized()
	if dir:
		velocity.x = dir.x * weighted_speed
		velocity.z = dir.z * weighted_speed
	else:
		velocity.x = move_toward(velocity.x, 0, weighted_speed)
		velocity.z = move_toward(velocity.z, 0, weighted_speed)

	move_and_slide()

func _handle_interactions(target: Node3D) -> void:
	if holding_two_handed and Input.is_action_just_pressed("right_click"):
		drop_object()
		return

	if not is_instance_valid(target):
		if Input.is_action_just_pressed("right_click") and current_slot != "0" and inventory[current_slot][2] != null and can_pickup:
			drop_object()
		return

	if Input.is_action_just_pressed("left_click") and not holding_two_handed:
		if target.is_in_group("punchable"): target._on_punched()
		elif target.is_in_group("storage_button"): target.spawn_item.emit(target.name)
		elif target.is_in_group("pickupable") and can_pickup: pickup_object(target)
		elif target.is_in_group("door"): target.open_door()

	elif Input.is_action_just_pressed("right_click"):
		if target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable") and not held_item.is_in_group("plate") and can_pickup:
			stack_object(target)
		elif current_slot != "0" and inventory[current_slot][2] != null and can_pickup:
			drop_object()

func _handle_snapping(target: Node3D) -> void:
	if current_slot == "0" or not is_instance_valid(held_item): 
		return

	var visual_slot = hand.find_child("slot" + current_slot)
	if not is_instance_valid(visual_slot): return

	var visual_item = visual_slot.get_child(0) if visual_slot.get_child_count() > 0 else null
	var is_snapping = false

	if is_instance_valid(visual_item) and is_instance_valid(target):
		var snap_offset = Vector3.ZERO
		
		if target.is_in_group("placeable"):
			if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"): snap_offset = Vector3(0, 1.2, 0)
			elif target.is_in_group("THE_THING") or target.is_in_group("delivery_area"): snap_offset = Vector3(0, 0.2, 0)
			elif not target.is_in_group("chopping_board") and held_item.is_in_group("meat"): snap_offset = Vector3(0, 0.4, 0)
		elif target.is_in_group("plate") and held_item.is_in_group("plate_stackable"):
			snap_offset = Vector3(0, target.calculate_stack_height() + 0.1, 0)

		if snap_offset != Vector3.ZERO:
			visual_item.global_position = target.global_position + snap_offset
			visual_item.global_rotation = target.global_rotation
			is_snapping = true

	if is_instance_valid(visual_item) and not is_snapping:
		# Snap back to the hand locally
		visual_item.position = Vector3.ZERO
		visual_item.rotation = Vector3.ZERO

func _handle_slot_switching() -> void:
	if holding_two_handed: return
	
	var pressed_slot = current_slot
	if Input.is_action_just_pressed("1"): pressed_slot = "1"
	elif Input.is_action_just_pressed("2"): pressed_slot = "2"
	elif Input.is_action_just_pressed("3"): pressed_slot = "3"
	elif Input.is_action_just_pressed("4"): pressed_slot = "4"

	if pressed_slot != current_slot:
		current_slot = pressed_slot
	elif pressed_slot != "0" and Input.is_action_just_pressed(pressed_slot):
		# Pressing the active slot again unequips it
		current_slot = "0"

	# Update held item data
	if current_slot != "0":
		held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	else:
		held_item = null

	if Input.is_action_just_pressed("1") or Input.is_action_just_pressed("2") or Input.is_action_just_pressed("3") or Input.is_action_just_pressed("4"):
		rpc("sync_active_slot", current_slot)
		update_inventory_ui()

# ---------------------------------------------------------
# INVENTORY ACTIONS
# ---------------------------------------------------------

func pickup_object(object: Node3D) -> void:
	var picked_up = "0"
	for i in inventory.keys():
		if inventory[i][2] == null or inventory[i][2] == object.type:
			inventory[i][1] += 1
			inventory[i][2] = object.type
			inventory[i][3].append(object)
			picked_up = i
			break

	if picked_up != "0":
		held_object_amount += 1
		
		# FIX: Pass the current stable global transform of the object into the hand sync
		if inventory[picked_up][1] <= 1:
			rpc("sync_hand_item_added", picked_up, str(object.get_path()), object.global_transform)
			
		rpc("sync_world_item_pickup", str(object.get_path())) 
		
		current_slot = picked_up
		held_item = inventory[picked_up][3][-1]
		
		rpc("sync_active_slot", current_slot)
		update_inventory_ui()
		
func drop_object() -> void:
	if current_slot == "0" or inventory[current_slot][2] == null or inventory[current_slot][3].is_empty(): return

	inventory[current_slot][1] -= 1
	held_object_amount -= 1
	var dropped = inventory[current_slot][3].pop_back()
	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null

	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
		rpc("sync_hand_item_removed", current_slot)

	update_inventory_ui()

	var drop_pos: Vector3 = hand.global_position
	var col = interact_cast.get_collider() if interact_cast.is_colliding() else null
	
	if is_instance_valid(col) and col.is_in_group("placeable"):
		if col.is_in_group("chopping_board") and dropped.is_in_group("choppable"): drop_pos = col.global_position + Vector3(0, 1.2, 0)
		elif col.is_in_group("THE_THING"): 
			drop_pos = col.global_position + Vector3(0, 0.2, 0)
			if dropped.is_in_group("storable"): dropped.set_collision_layer_value(3, false)
		elif col.is_in_group("delivery_area"): drop_pos = col.global_position + Vector3(0, 0.2, 0)
		elif not col.is_in_group("chopping_board") and dropped.is_in_group("meat"): drop_pos = col.global_position + Vector3(0, 0.4, 0)

	if multiplayer.is_server(): notify_item_dropped(str(dropped.get_path()), drop_pos, multiplayer.get_unique_id())
	else: rpc_id(1, "notify_item_dropped", str(dropped.get_path()), drop_pos, multiplayer.get_unique_id())

func stack_object(plate: Node3D) -> void:
	if not is_instance_valid(held_item): return

	if held_item.is_in_group("pickupable"): held_item.remove_from_group("pickupable")
	
	plate.stack_item(held_item)
	can_pickup = false
	pickup_timer.start()
	
	inventory[current_slot][3].erase(held_item)
	inventory[current_slot][1] -= 1
	held_object_amount -= 1
	
	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
		rpc("sync_hand_item_removed", current_slot)

	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	update_inventory_ui()

# ---------------------------------------------------------
# NETWORKING & VISUAL SYNC
# ---------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func sync_world_item_pickup(item_path: String) -> void:
	var item = get_node_or_null(item_path)
	if is_instance_valid(item):
		_set_physical_item_state(item, true)
		# Banish item to prevent teleport flash when dropped
		item.global_position = Vector3(0, -50, 0)

@rpc("any_peer", "call_local", "reliable")
func sync_active_slot(slot_key: String) -> void:
	current_slot = slot_key
	for i in hand.get_children(): i.hide()
	
	if current_slot != "0":
		var slot_node = hand.find_child("slot" + current_slot)
		if is_instance_valid(slot_node): slot_node.show()

@rpc("any_peer", "call_local", "reliable")
func sync_hand_item_added(slot_key: String, item_path: String, base_transform: Transform3D) -> void:
	var world_object = get_node_or_null(item_path)
	var slot_node = hand.find_child("slot" + slot_key)
	
	if is_instance_valid(world_object) and is_instance_valid(slot_node):
		for child in slot_node.get_children(): child.queue_free()
			
		var duplicate_mesh = world_object.duplicate()
		_strip_network_nodes(duplicate_mesh)
		
		slot_node.add_child(duplicate_mesh)
		duplicate_mesh.position = Vector3.ZERO
		duplicate_mesh.rotation = Vector3.ZERO
		
		if "visible" in duplicate_mesh: duplicate_mesh.visible = true
		duplicate_mesh.show()
		
		if "stacked_items" in world_object:
			for item_node in world_object.stacked_items:
				if is_instance_valid(item_node):
					var item_copy = item_node.duplicate()
					_strip_network_nodes(item_copy)
					
					# FIX: Use the stable snapshot transform we passed in, 
					# NOT the world_object's current live (and potentially banished) position!
					var local_offset_transform = base_transform.affine_inverse() * item_node.global_transform
					
					duplicate_mesh.add_child(item_copy)
					item_copy.transform = local_offset_transform
					
					if "visible" in item_copy: item_copy.visible = true
					item_copy.show()

@rpc("any_peer", "call_local", "reliable")
func sync_hand_item_removed(slot_key: String) -> void:
	var slot_node = hand.find_child("slot" + slot_key)
	if is_instance_valid(slot_node):
		for child in slot_node.get_children(): child.queue_free()

@rpc("any_peer", "reliable")
func notify_item_dropped(item_path: String, drop_pos: Vector3, sender_id: int) -> void:
	if not multiplayer.is_server(): return
	rpc("sync_item_dropped", item_path, drop_pos, sender_id)

@rpc("any_peer", "call_local", "reliable")
func sync_item_dropped(item_path: String, drop_pos: Vector3, _sender_id: int) -> void:
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item): return
		
	var relative_transforms = []
	if "stacked_items" in item:
		for stacked_item in item.stacked_items:
			if is_instance_valid(stacked_item):
				relative_transforms.append(item.global_transform.affine_inverse() * stacked_item.global_transform)

	# Set position first to avoid flash, then unhide
	item.global_position = drop_pos
	var mesh_item = $hand.find_child("slot" + str(current_slot))
	item.global_rotation = mesh_item.get_child(0).global_rotation
	_set_physical_item_state(item, false) 

	if "stacked_items" in item:
		for idx in range(item.stacked_items.size()):
			var stacked_item = item.stacked_items[idx]
			if is_instance_valid(stacked_item) and idx < relative_transforms.size():
				if stacked_item.is_in_group("pickupable"): stacked_item.remove_from_group("pickupable")
				
				stacked_item.global_transform = item.global_transform * relative_transforms[idx]
				_set_physical_item_state(stacked_item, false)
				stacked_item.freeze = true 
				
				var s_shape: CollisionShape3D = stacked_item.find_child("CollisionShape3D")
				if s_shape: s_shape.disabled = true 

# ---------------------------------------------------------
# UTILITY FUNCTIONS
# ---------------------------------------------------------

func update_inventory_ui() -> void:
	if not is_owned: return
	for s in inventory:
		var lbl: Label = inventory[s][0]
		if not is_instance_valid(lbl): continue

		var count: int = inventory[s][1]
		if inventory[s][2] != null and count > 0:
			var last_item = inventory[s][3][-1] if inventory[s][3].size() > 0 else null
			
			# Check if this is a plate with items stacked on it
			if str(inventory[s][2]) == "plate" and is_instance_valid(last_item) and "stacked_items" in last_item and last_item.stacked_items.size() > 0:
				
				# Dictionary to store item name -> total count
				var item_counts: Dictionary = {}
				for item in last_item.stacked_items:
					if is_instance_valid(item):
						var item_name = item.type.capitalize()
						if item_counts.has(item_name):
							item_counts[item_name] += 1
						else:
							item_counts[item_name] = 1
				
				# Format counts into strings (e.g., "Lettuce x5" or "Tomato")
				var formatted_contents = []
				for item_name in item_counts:
					var item_total = item_counts[item_name]
					if item_total > 1:
						formatted_contents.append("%s x%d" % [item_name, item_total])
					else:
						formatted_contents.append(item_name)
				
				lbl.text = "%s\nPlate with %s" % [s, ", ".join(formatted_contents)]
			else:
				lbl.text = "%s\n%s%s" % [s, str(inventory[s][2]).capitalize(), " x" + str(count) if count > 1 else ""]
		else:
			lbl.text = "%s\nEmpty" % s

		lbl.pivot_offset = lbl.size / 2.0
		lbl.scale = Vector2(1.15, 1.15) if str(s) == current_slot else Vector2.ONE
		
func _set_physical_item_state(item: Node3D, is_hidden: bool) -> void:
	item.visible = not is_hidden
	if item is RigidBody3D: item.freeze = is_hidden
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape: shape.disabled = is_hidden
	if "stacked_items" in item:
		for s_item in item.stacked_items:
			if is_instance_valid(s_item): _set_physical_item_state(s_item, is_hidden)

func _strip_network_nodes(node: Node) -> void:
	if not is_instance_valid(node): return
	
	# Check children first to delete synchronizers safely from the bottom up
	for child in node.get_children():
		_strip_network_nodes(child)
		
	if node is MultiplayerSynchronizer or node is MultiplayerSpawner or node is RemoteTransform3D:
		node.name = "DELETED_NET_NODE" # Avoid path collisions
		node.queue_free()
		if node.get_parent():
			node.get_parent().remove_child(node) # Force instant removal from hierarchy
		return
		
	if node is RigidBody3D:
		node.freeze = true
		node.gravity_scale = 0.0
		node.collision_layer = 0
		node.collision_mask = 0
		node.process_mode = Node.PROCESS_MODE_DISABLED 
	if node is CollisionShape3D: 
		node.disabled = true
		
func _update_outline(target: Node3D) -> void:
	if target != last_highlighted_target:
		if is_instance_valid(last_highlighted_target): _set_mesh_outline(last_highlighted_target, false)
		if is_instance_valid(target): _set_mesh_outline(target, true)
		last_highlighted_target = target

func _set_mesh_outline(node: Node, active: bool) -> void:
	if node is MeshInstance3D: node.material_overlay = outline_material if active else null
	for child in node.get_children(): _set_mesh_outline(child, active)

func take_damage(amount: float) -> void:
	if not is_owned or is_dead: return
	health -= amount
	if ui_healthbar: ui_healthbar.value = int(health)
	if health <= 0: die()

func die() -> void:
	is_dead = true; health = 0
	var origin: Vector3 = global_position
	for s in inventory:
		while inventory[s][3].size() > 0:
			var angle = randf() * TAU
			current_slot = s
			drop_object()
			var dropped_item = inventory[s][3][-1] if inventory[s][3].size() > 0 else null
			if is_instance_valid(dropped_item):
				dropped_item.global_position = origin + Vector3(cos(angle) * (randf() * 1.5), 0.5, sin(angle) * (randf() * 1.5))
	
	global_position = origin
	for s in inventory: inventory[s] = [inventory[s][0], 0, null, []]
	held_item = null
	current_slot = "0"
	update_inventory_ui()
	rpc("sync_player_death")

@rpc("any_peer", "call_local", "reliable")
func sync_player_death() -> void:
	if is_owned:
		global_position = Vector3(5, 5, 0)
		health = max_health; is_dead = false
		if ui_healthbar: ui_healthbar.value = int(health)

func _on_pickup_timer_timeout() -> void: can_pickup = true

@rpc("any_peer", "call_local", "reliable")
func sync_username(target_name: String) -> void:
	if not is_inside_tree(): await get_tree().process_frame
	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned: username_label.show()

@rpc("any_peer", "reliable")
func request_username_from_owner() -> void:
	if not is_inside_tree(): await get_tree().process_frame
	if is_owned: rpc("sync_username", GameData.username if GameData.username != "" else "Player")
