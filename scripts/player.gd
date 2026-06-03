extends CharacterBody3D

# --- States & Inventory ---
var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = false
var is_owned: bool = false
var speed_multiplier: float = 1.0

var held_item: Node3D = null          # References the REAL physical item on the floor
var client_dummy_mesh: Node3D = null  # References the local cosmetic fake item in your hand
var can_pickup: bool = true
var current_slot: String = "1"
var holding_two_handed: bool = false

# Your inventory layout tracks: [UI_Slot_Label, Stack_Count, Item_Type_String, Array_Of_Physical_Nodes]
var inventory = {
	"1": [null, 0, null, []], 
	"2": [null, 0, null, []], 
	"3": [null, 0, null, []], 
	"4": [null, 0, null, []]
}

# --- Settings & Visuals ---
var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")
const SPEED = 5.0
const JUMP_VELOCITY = 3.0
const GRAVITY = 9.8
var mouse_sensitivity: float = 0.003

@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

# UI Canvas References
@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/colliding")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider = get_node_or_null("/root/main/Pause_UI/sensitivity")
@onready var main_game_ui = get_node_or_null("/root/main/UI")
@onready var pause_menu_ui = get_node_or_null("/root/main/Pause_UI")

# ==========================================
# LIFE CYCLE & INPUT
# ==========================================

func _enter_tree() -> void:
	var peer_id = name.to_int()
	set_multiplayer_authority(peer_id)

func _ready() -> void:
	add_to_group("player")
	var peer_id = name.to_int()
	is_owned = (peer_id == multiplayer.get_unique_id())
	
	if is_owned:
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if is_instance_valid(username_label): username_label.hide()
		
		for slot_key in inventory: 
			var ui_slot = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key))
			if ui_slot: inventory[slot_key][0] = ui_slot
			
		rpc("sync_username", GameData.username if GameData.username != "" else "Player")
	else:
		if is_instance_valid($head/camera): $head/camera.queue_free()
		rpc_id(peer_id, "request_username_from_owner")
		
	update_inventory_ui()

func _input(event: InputEvent) -> void:
	if not is_owned: return
	
	if Input.is_action_just_pressed("ui_cancel"):
		GameData.paused = not GameData.paused
		if GameData.paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			if main_game_ui: main_game_ui.hide()
			if pause_menu_ui: pause_menu_ui.show()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			if main_game_ui: main_game_ui.show()
			if pause_menu_ui: pause_menu_ui.hide()
			
	if GameData.paused: return

	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x - event.relative.y * mouse_sensitivity * 5, -90, 90)

func _physics_process(delta: float) -> void:
	if not is_owned: return
	if Input.is_action_just_pressed("debug_toggle"): GameData.is_night = true
	if ui_sensitivity_slider: mouse_sensitivity = ui_sensitivity_slider.value
	
	if is_in_kitchen:
		health = minf(health + (10.0 * delta), max_health)
		if ui_healthbar: ui_healthbar.value = int(health)
			
	if not is_on_floor(): velocity.y -= GRAVITY * delta
	
	if GameData.paused:
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return
		
	var raycast_target: Node3D = interact_cast.get_collider() if interact_cast.is_colliding() else null
	_process_ui_context_labels(raycast_target)
	handle_inventory_slots() 
	handle_interactions(raycast_target)
	handle_movement()
	move_and_slide()

# ==========================================
# INTERACTION LOOKUPS & HUD UI
# ==========================================

func _process_ui_context_labels(target: Node3D) -> void:
	var is_interactive: bool = false
	var context_text: String = ""

	if is_owned and is_instance_valid(target):
		if target.is_in_group("pickupable") or target.is_in_group("punchable") or target.is_in_group("door") or target.is_in_group("placeable") or target.is_in_group("plate") or target.is_in_group("storage_button"):
			is_interactive = true
			context_text = str(target.type).capitalize() if "type" in target else str(target.name).replace("_", " ").capitalize()

	if is_owned and ui_colliding_label:
		ui_colliding_label.visible = is_interactive
		if ui_colliding_label.visible: ui_colliding_label.text = context_text

func handle_interactions(target: Node3D):
	var current_target: Node3D = target if (is_instance_valid(target) and _can_interact_with(target)) else null

	if current_target != last_highlighted_target:
		if is_instance_valid(last_highlighted_target): _set_mesh_outline(last_highlighted_target, false)
		if is_instance_valid(current_target): _set_mesh_outline(current_target, true)
		last_highlighted_target = current_target
		
	if Input.is_action_pressed("ui_accept") and is_on_floor(): velocity.y = JUMP_VELOCITY
	if holding_two_handed:
		if Input.is_action_just_pressed("right_click"): drop_object()
		return

	if is_instance_valid(current_target):
		if Input.is_action_just_pressed("left_click"):
			if current_target.is_in_group("punchable"): current_target._on_punched()
			elif current_target.is_in_group("storage_button"): current_target.spawn_item.emit(current_target.name)
			elif current_target.is_in_group("pickupable") and can_pickup: 
				pickup_object(current_target)
			elif current_target.is_in_group("door"): current_target.open_door()
				
		if Input.is_action_just_pressed("right_click") and current_target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
			stack_object(current_target)
			return
				
	if Input.is_action_just_pressed("right_click") and inventory[current_slot][2] != null and can_pickup: 
		drop_object()

func _can_interact_with(target: Node3D) -> bool:
	if not is_instance_valid(target): return false
	if target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"): return true
	if target.is_in_group("door") or target.is_in_group("punchable") or target.is_in_group("storage_button"): return true
	if target.is_in_group("placeable"):
		if is_instance_valid(held_item):
			if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"): return true
			if target.is_in_group("THE_THING") or target.is_in_group("stove"): return true
			if not target.is_in_group("chopping_board") and held_item.is_in_group("meat"): return true
		return false
	if holding_two_handed or not can_pickup or not target.is_in_group("pickupable"): return false
	
	var target_type = target.type if "type" in target else target.name
	for s in inventory:
		if (inventory[s][2] == target_type and inventory[s][1] > 0) or inventory[s][2] == null or inventory[s][1] == 0: return true
	return false

# ==========================================
# RE-OPTIMIZED DUPLICATION PICKUP / DROP
# ==========================================

func pickup_object(object: Node3D):
	var actual_target = object.get_parent() if (not "type" in object and object.get_parent() and "type" in object.get_parent()) else object
	rpc_id(1, "server_pickup", actual_target.get_path(), current_slot)

@rpc("any_peer", "reliable")
func server_pickup(item_path: NodePath, target_slot: String) -> void:
	if not multiplayer.is_server(): return
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item): return
	
	var target_type = item.type if "type" in item else item.name
	
	# Freeze the physical body on the floor immediately
	if item is RigidBody3D: item.freeze = true
	var shape = item.find_child("CollisionShape3D")
	if shape: shape.disabled = true
	
	rpc("sync_inventory_pickup", target_slot, target_type, item_path)

func drop_object():
	if inventory[current_slot][3].size() == 0: return
	
	var drop_pos = hand.global_position
	var drop_rot = hand.global_rotation
	
	if interact_cast.is_colliding():
		var col = interact_cast.get_collider()
		if col.is_in_group("placeable"):
			var item = inventory[current_slot][3][-1]
			if is_instance_valid(item):
				if col.is_in_group("chopping_board") and item.is_in_group("choppable"): drop_pos = col.global_position + Vector3(0, 1.2, 0)
				elif col.is_in_group("THE_THING"): drop_pos = col.global_position + Vector3(0, 0.2, 0)
				elif not col.is_in_group("chopping_board") and item.is_in_group("meat"): drop_pos = col.global_position + Vector3(0, 0.4, 0)

	rpc_id(1, "server_drop", current_slot, drop_pos, drop_rot)

@rpc("any_peer", "reliable")
func server_drop(slot: String, drop_pos: Vector3, drop_rot: Vector3) -> void:
	if not multiplayer.is_server() or inventory[slot][3].size() == 0: return
	
	var item = inventory[slot][3][-1]
	if is_instance_valid(item):
		item.global_position = drop_pos
		item.global_rotation = drop_rot
		if item is RigidBody3D:
			item.freeze = false
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
		var shape = item.find_child("CollisionShape3D")
		if shape: shape.disabled = false
		
	rpc("sync_inventory_drop", slot, drop_pos, drop_rot)

func stack_object(plate: Node3D):
	if not is_instance_valid(held_item): return
	plate.stack_item(held_item)
	inventory[current_slot][3].erase(held_item)
	inventory[current_slot][1] -= 1
	if inventory[current_slot][1] <= 0: inventory[current_slot][2] = null
	
	# Wipe out visual duplicate upon stacking
	if is_instance_valid(client_dummy_mesh):
		client_dummy_mesh.queue_free()
		client_dummy_mesh = null
		
	_refresh_held_references()
	update_inventory_ui()

# ==========================================
# NETWORKING DUPLICATION INTERFACES
# ==========================================

@rpc("any_peer", "call_local", "reliable")
func sync_inventory_pickup(slot: String, type_str: String, item_path: NodePath) -> void:
	if not has_node(item_path):
		await get_tree().process_frame
		if not has_node(item_path): return
			
	var item_node = get_node_or_null(item_path)
	if not is_instance_valid(item_node): return
	
	# 1. Freeze the item completely on the ground across all window viewports
	if item_node is RigidBody3D: item_node.freeze = true
	var shape = item_node.find_child("CollisionShape3D")
	if shape: shape.disabled = true
	item_node.hide() # Conceal the physical one sitting on the kitchen floor
	
	inventory[slot][2] = type_str
	inventory[slot][1] += 1
	inventory[slot][3].append(item_node)
	current_slot = slot
	
	# 2. Build the visual fake model directly inside the hand slot container node
	if is_owned:
		if is_instance_valid(client_dummy_mesh): client_dummy_mesh.queue_free()
		
		# Find the visual mesh child inside the original item and duplicate only that aspect
		var original_mesh = item_node.find_child("MeshInstance3D")
		if original_mesh:
			client_dummy_mesh = original_mesh.duplicate()
			var active_slot = hand.get_node("slot" + slot)
			active_slot.add_child(client_dummy_mesh)
			client_dummy_mesh.position = Vector3.ZERO
			client_dummy_mesh.rotation = Vector3.ZERO
			client_dummy_mesh.show()

	can_pickup = false
	pickup_timer.start()
	_refresh_held_references()
	update_inventory_ui()

@rpc("any_peer", "call_local", "reliable")
func sync_inventory_drop(slot: String, drop_pos: Vector3, drop_rot: Vector3) -> void:
	if inventory[slot][3].size() == 0: return
	var item = inventory[slot][3].pop_back()
	
	inventory[slot][1] -= 1
	if inventory[slot][1] <= 0: inventory[slot][2] = null
	
	# Clean up the visual hand copy on the client holding it
	if is_owned and is_instance_valid(client_dummy_mesh):
		client_dummy_mesh.queue_free()
		client_dummy_mesh = null
	
	# Unhide and restore physics processing loops to the real item dropped onto the map floor
	if is_instance_valid(item):
		item.global_position = drop_pos
		item.global_rotation = drop_rot
		item.show()
		if item is RigidBody3D:
			item.freeze = false
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
		var shape = item.find_child("CollisionShape3D")
		if shape: shape.disabled = false
		
	can_pickup = false
	pickup_timer.start()
	_refresh_held_references()
	update_inventory_ui()

func _refresh_held_references():
	var stack = inventory[current_slot][3]
	if stack.size() > 0 and is_instance_valid(stack[-1]):
		held_item = stack[-1]
	else:
		held_item = null
	check_two_handed_status()

func handle_inventory_slots():
	if holding_two_handed: return 
	var prev = current_slot
	if Input.is_action_just_pressed("1"): current_slot = "1"
	elif Input.is_action_just_pressed("2"): current_slot = "2"
	elif Input.is_action_just_pressed("3"): current_slot = "3"
	elif Input.is_action_just_pressed("4"): current_slot = "4"
	
	if prev != current_slot:
		for slot in hand.get_children(): slot.hide()
		var slot_node = hand.get_node_or_null("slot" + current_slot)
		if slot_node: slot_node.show()
		
		# If hot-swapping slots, move our local fake mesh to the active hand socket
		if is_owned and is_instance_valid(client_dummy_mesh):
			client_dummy_mesh.get_parent().remove_child(client_dummy_mesh)
			slot_node.add_child(client_dummy_mesh)
			client_dummy_mesh.position = Vector3.ZERO
			client_dummy_mesh.rotation = Vector3.ZERO
			
		_refresh_held_references()
		update_inventory_ui()

func update_inventory_ui():
	for s in inventory:
		var lbl = inventory[s][0]
		if not is_instance_valid(lbl): continue
		if inventory[s][2] != null and inventory[s][1] > 0:
			if inventory[s][2] == "plate" and inventory[s][3].size() > 0 and is_instance_valid(inventory[s][3][-1]) and "stacked_items" in inventory[s][3][-1] and inventory[s][3][-1].stacked_items.size() > 0:
				var names = []
				for i in inventory[s][3][-1].stacked_items: 
					if is_instance_valid(i): names.append(i.type)
				lbl.text = "%s\n%s (%s) (%d)" % [s, inventory[s][2], ", ".join(names), inventory[s][1]]
			else: 
				lbl.text = "%s\n%s (%d)" % [s, inventory[s][2], inventory[s][1]]
		else: 
			lbl.text = str(s) + "\nempty"
		lbl.scale = Vector2(1.2, 1.2) if str(s) == current_slot else Vector2(1.0, 1.0)

func check_two_handed_status() -> void:
	holding_two_handed = is_instance_valid(held_item) and "is_two_handed" in held_item and held_item.is_two_handed

# ==========================================
# UTILITIES, DEATH & HEALTH
# ==========================================

func handle_movement():
	var vec = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	speed_multiplier = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var dir = (transform.basis * Vector3(vec.x, 0, vec.y)).normalized()
	velocity.x = dir.x * SPEED * speed_multiplier if dir else move_toward(velocity.x, 0, SPEED)
	velocity.z = dir.z * SPEED * speed_multiplier if dir else move_toward(velocity.z, 0, SPEED)

func _set_mesh_outline(node: Node, active: bool) -> void:
	if node is MeshInstance3D: node.material_overlay = outline_material if active else null
	for child in node.get_children(): _set_mesh_outline(child, active)

func wake_up_stacked_items(target: Node3D) -> void:
	var state = target.get_world_3d().direct_space_state
	var q = PhysicsShapeQueryParameters3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	q.shape = box; q.transform = target.global_transform; q.transform.origin += Vector3(0, 0.4, 0) 
	q.exclude = [target, self]
	for res in state.intersect_shape(q):
		var col = res.get("collider")
		if is_instance_valid(col) and col is RigidBody3D and not col.freeze: col.sleeping = false

func take_damage(amount: float) -> void:
	if not is_owned or is_dead: return
	health -= amount
	if ui_healthbar: ui_healthbar.value = int(health)
	if health <= 0: die()

func get_inventory_items_for_score() -> Array:
	var items: Array = []
	for s in inventory:
		for i in inventory[s][3]:
			if i and "type" in i: items.append(i.type)
	return items

func clear_inventory_safely() -> void:
	for s in inventory: inventory[s] = [inventory[s][0], 0, null, []]
	_refresh_held_references()
	update_inventory_ui()

func die() -> void:
	is_dead = true; health = 0
	var origin = global_position
	for s in inventory:
		while inventory[s][3].size() > 0:
			var angle = randf() * TAU
			var dist = randf() * 1.5
			current_slot = s
			drop_object()
			if inventory[s][3].size() > 0:
				var dropped_item = inventory[s][3][-1]
				if is_instance_valid(dropped_item):
					dropped_item.global_position = origin + Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
	global_position = origin
	clear_inventory_safely()
	rpc("sync_player_death")

func _execute_local_respawn() -> void:
	global_position = Vector3(5, 5, 0); health = max_health; is_dead = false
	if ui_healthbar: ui_healthbar.value = int(health)

func _on_pickup_timer_timeout() -> void: can_pickup = true

@rpc("any_peer", "call_local", "reliable")
func sync_username(target_name: String) -> void:
	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned: username_label.show()

@rpc("any_peer", "reliable")
func request_username_from_owner() -> void:
	if is_owned: rpc("sync_username", GameData.username if GameData.username != "" else "Player")

@rpc("any_peer", "call_local", "reliable")
func sync_player_death() -> void:
	if is_owned: _execute_local_respawn()
