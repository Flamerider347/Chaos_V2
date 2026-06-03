extends CharacterBody3D

# ==========================================
# STATES & INVENTORY SYSTEM
# ==========================================

var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = false
var is_owned: bool = false
var speed_multiplier: float = 1.0

var held_item: Node3D = null          # References the REAL physical item on the floor
var client_dummy_mesh: Node3D = null  # Legacy reference variable (kept for structural safety)
var can_pickup: bool = true
var current_slot: String = "1"
var holding_two_handed: bool = false

# Expanded inventory layout tracks: [UI_Slot_Label, Stack_Count, Item_Type_String, Array_Of_Physical_Nodes]
var inventory: Dictionary = {
	"1": [null, 0, null, []], 
	"2": [null, 0, null, []], 
	"3": [null, 0, null, []], 
	"4": [null, 0, null, []]
}

# ==========================================
# SETTINGS & VISUAL CONFIGURATIONS
# ==========================================

var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 3.0
const GRAVITY: float = 9.8
var mouse_sensitivity: float = 0.003

@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

# Fully Expanded UI Canvas References
@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/loading")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider: Slider = get_node_or_null("/root/main/Pause_UI/sensitivity")
@onready var main_game_ui  = get_node_or_null("/root/main/UI")
@onready var pause_menu_ui  = get_node_or_null("/root/main/Pause_UI")

# ==========================================
# LIFE CYCLE ENGINE INTERACTIONS
# ==========================================

func _enter_tree() -> void:
	var peer_id: int = name.to_int()
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	add_to_group("player")
	var peer_id: int = name.to_int()
	is_owned = (peer_id == multiplayer.get_unique_id())
	
	if is_owned:
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

		for slot_key in inventory: 
			var ui_slot: Label = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key))
			if ui_slot:
				inventory[slot_key][0] = ui_slot
		
		var chosen_name: String = GameData.username if GameData.username != "" else "Player"
		rpc.call_deferred("sync_username", chosen_name)
	else:
		if is_instance_valid($head/camera):
			$head/camera.queue_free()
			
		rpc_id.call_deferred(peer_id, "request_username_from_owner")
		
	update_inventory_ui()


func _input(event: InputEvent) -> void:
	if not is_owned:
		return
	
	if Input.is_action_just_pressed("ui_cancel"):
		GameData.paused = not GameData.paused
		if GameData.paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			if main_game_ui:
				main_game_ui.hide()
			if pause_menu_ui:
				pause_menu_ui.show()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			if main_game_ui:
				main_game_ui.show()
			if pause_menu_ui:
				pause_menu_ui.hide()
			
	if GameData.paused:
		return

	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x - event.relative.y * mouse_sensitivity * 5, -90, 90)


func _physics_process(delta: float) -> void:
	if not is_owned: 
		return
		
	if Input.is_action_just_pressed("debug_toggle"):
		GameData.is_night = true
		
	if ui_sensitivity_slider:
		mouse_sensitivity = ui_sensitivity_slider.value
	
	if is_in_kitchen:
		health = minf(health + (10.0 * delta), max_health)
		if ui_healthbar:
			ui_healthbar.value = int(health)
			
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if GameData.paused:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
		
	var target: Node3D = null
	if interact_cast.is_colliding():
		target = interact_cast.get_collider()
	
	if not is_instance_valid(target):
		target = null

	if target != last_highlighted_target:
		if is_instance_valid(last_highlighted_target):
			_set_mesh_outline(last_highlighted_target, false)
		if is_instance_valid(target):
			_set_mesh_outline(target, true)
		last_highlighted_target = target
		
	if Input.is_action_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		
	if holding_two_handed:
		if Input.is_action_just_pressed("right_click"):
			drop_object()
		return

	if is_instance_valid(target):
		if Input.is_action_just_pressed("left_click"):
			if target.is_in_group("punchable"):
				target._on_punched()
			elif target.is_in_group("storage_button"):
				target.spawn_item.emit(target.name)
			elif target.is_in_group("pickupable") and can_pickup: 
				pickup_object(target)
			elif target.is_in_group("door"):
				target.open_door()
				
		if Input.is_action_just_pressed("right_click") and target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
			stack_object(target)
			return
				
	if Input.is_action_just_pressed("right_click") and inventory[current_slot][2] != null and can_pickup: 
		drop_object()


	#_process_ui_context_labels(raycast_target)
	handle_inventory_slots() 
	handle_movement()
	move_and_slide()

# ==========================================
# MASTER LOGIC BLOCK: PICKUP, DROP, STACK & NET
# ==========================================

func pickup_object(object: Node3D) -> void:
	var actual_target: Node3D = object
	if not "type" in object and object.get_parent() and "type" in object.get_parent():
		actual_target = object.get_parent()
		
	rpc_id(1, "server_pickup", actual_target.get_path(), current_slot)


@rpc("any_peer", "call_local", "reliable")
func server_pickup(item_path: NodePath, target_slot: String) -> void:
	if not multiplayer.is_server():
		return
		
	var item: Node3D = get_node_or_null(item_path)
	if not is_instance_valid(item):
		return
	
	var target_type: String = ""
	if "type" in item and item.type != null:
		target_type = str(item.type)
	else:
		target_type = item.name
	
	if item is RigidBody3D:
		item.freeze = true
		
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape:
		shape.disabled = true
	
	rpc("sync_inventory_pickup", target_slot, target_type, item_path)


func drop_object() -> void:
	if inventory[current_slot][3].size() == 0:
		return
	
	var drop_pos: Vector3 = hand.global_position
	var drop_rot: Vector3 = hand.global_rotation
	
	if interact_cast.is_colliding():
		var col: Node3D = interact_cast.get_collider()
		if col.is_in_group("placeable"):
			var item: Node3D = inventory[current_slot][3][-1]
			if is_instance_valid(item):
				if col.is_in_group("chopping_board") and item.is_in_group("choppable"):
					drop_pos = col.global_position + Vector3(0, 1.2, 0)
				elif col.is_in_group("THE_THING"):
					drop_pos = col.global_position + Vector3(0, 0.2, 0)
				elif not col.is_in_group("chopping_board") and item.is_in_group("meat"):
					drop_pos = col.global_position + Vector3(0, 0.4, 0)

	rpc_id(1, "server_drop", current_slot, drop_pos, drop_rot)


@rpc("any_peer", "call_local", "reliable")
func server_drop(slot: String, drop_pos: Vector3, drop_rot: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if inventory[slot][3].size() == 0:
		return
	
	var item: Node3D = inventory[slot][3][-1]
	if is_instance_valid(item):
		item.global_position = drop_pos
		item.global_rotation = drop_rot
		if item is RigidBody3D:
			item.freeze = false
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
		var shape: CollisionShape3D = item.find_child("CollisionShape3D")
		if shape:
			shape.disabled = false
		
	rpc("sync_inventory_drop", slot, drop_pos, drop_rot)


func stack_object(plate: Node3D) -> void:
	if not is_instance_valid(held_item):
		return
		
	plate.stack_item(held_item)
	inventory[current_slot][3].erase(held_item)
	inventory[current_slot][1] -= 1
	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
	
	var active_slot: Node3D = hand.get_node("slot" + current_slot)
	for child in active_slot.get_children():
		if child.is_in_group("cosmetic_dummy"):
			child.queue_free()
		
	_refresh_held_references()
	update_inventory_ui()


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_pickup(slot: String, type_str: String, item_path: NodePath) -> void:
	if not is_inside_tree():
		await get_tree().process_frame
		if not is_inside_tree():
			return

	if not has_node(item_path):
		await get_tree().process_frame
		if not has_node(item_path):
			return
			
	var item_node: Node3D = get_node_or_null(item_path)
	if not is_instance_valid(item_node):
		return
	
	# SET COLLIDING TO FALSE (Turn off physics tracking)
	if item_node is RigidBody3D:
		item_node.freeze = true
		item_node.sleeping = true
		
	# Find all collision shapes recursively and disable them
	for child in item_node.get_children():
		if child is CollisionShape3D:
			child.disabled = true
	
	# Hide the real physical floor item completely
	item_node.hide() 
	
	inventory[slot][2] = type_str
	inventory[slot][1] += 1
	inventory[slot][3].append(item_node)
	
	var active_slot: Node3D = hand.get_node("slot" + slot)
	for child in active_slot.get_children():
		if child.is_in_group("cosmetic_dummy"):
			child.queue_free()
	
	var original_mesh: MeshInstance3D = item_node.find_child("MeshInstance3D")
	if original_mesh:
		var dummy: MeshInstance3D = original_mesh.duplicate()
		dummy.add_to_group("cosmetic_dummy")
		active_slot.add_child(dummy)
		dummy.position = Vector3.ZERO
		dummy.rotation = Vector3.ZERO
		
		if current_slot == slot:
			dummy.show()
		else:
			dummy.hide()

	if is_owned:
		current_slot = slot
		can_pickup = false
		pickup_timer.start()
		
	_refresh_held_references()
	update_inventory_ui()
	_refresh_hand_visibility_filters()


@rpc("any_peer", "call_local", "reliable")
func sync_inventory_drop(slot: String, drop_pos: Vector3, drop_rot: Vector3) -> void:
	if inventory[slot][3].size() == 0:
		return
	var item: Node3D = inventory[slot][3].pop_back()
	
	inventory[slot][1] -= 1
	if inventory[slot][1] <= 0:
		inventory[slot][2] = null
	
	var active_slot: Node3D = hand.get_node("slot" + slot)
	for child in active_slot.get_children():
		if child.is_in_group("cosmetic_dummy"):
			child.queue_free()
	
	if is_instance_valid(item):
		item.global_position = drop_pos
		item.global_rotation = drop_rot
		item.show()
		
		# SET COLLIDING TO TRUE (Restore physics tracking on drop)
		if item is RigidBody3D:
			item.freeze = false
			item.sleeping = false
			item.linear_velocity = Vector3.ZERO
			item.angular_velocity = Vector3.ZERO
			
		# Re-enable all collision shapes so it hits the floor normally
		for child in item.get_children():
			if child is CollisionShape3D:
				child.disabled = false
		
	if is_owned:
		can_pickup = false
		pickup_timer.start()
		
	_refresh_held_references()
	update_inventory_ui()
	_refresh_hand_visibility_filters()
# ==========================================
# INTERACTION HANDLING & UI PROCESSES
# ==========================================

func _process_ui_context_labels(target: Node3D) -> void:
	var is_interactive: bool = false
	var context_text: String = ""

	if is_owned and is_instance_valid(target):
		if target.is_in_group("pickupable") or target.is_in_group("punchable") or target.is_in_group("door") or target.is_in_group("placeable") or target.is_in_group("plate") or target.is_in_group("storage_button"):
			is_interactive = true
			if "type" in target and target.type != null:
				context_text = str(target.type).capitalize()
			else:
				context_text = str(target.name).replace("_", " ").capitalize()

	if is_owned and ui_colliding_label:
		ui_colliding_label.visible = is_interactive
		if ui_colliding_label.visible:
			ui_colliding_label.text = context_text


func _can_interact_with(target: Node3D) -> bool:
	if not is_instance_valid(target):
		return false
	if target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
		return true
	if target.is_in_group("door") or target.is_in_group("punchable") or target.is_in_group("storage_button"):
		return true
	if target.is_in_group("placeable"):
		if is_instance_valid(held_item):
			if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"):
				return true
			if target.is_in_group("THE_THING") or target.is_in_group("stove"):
				return true
			if not target.is_in_group("chopping_board") and held_item.is_in_group("meat"):
				return true
		return false
	if holding_two_handed or not can_pickup or not target.is_in_group("pickupable"):
		return false
	
	var target_type: String = ""
	if "type" in target and target.type != null:
		target_type = str(target.type)
	else:
		target_type = target.name
		
	for s in inventory:
		if (inventory[s][2] == target_type and inventory[s][1] > 0) or inventory[s][2] == null or inventory[s][1] == 0:
			return true
	return false


func handle_inventory_slots() -> void:
	if holding_two_handed:
		return 
	var prev: String = current_slot
	if Input.is_action_just_pressed("1"):
		current_slot = "1"
	elif Input.is_action_just_pressed("2"):
		current_slot = "2"
	elif Input.is_action_just_pressed("3"):
		current_slot = "3"
	elif Input.is_action_just_pressed("4"):
		current_slot = "4"
	
	if prev != current_slot:
		_refresh_held_references()
		update_inventory_ui()
		_refresh_hand_visibility_filters()


func update_inventory_ui() -> void:
	if not is_owned:
		return
	
	for s in inventory:
		var lbl: Label = inventory[s][0]
		if not is_instance_valid(lbl):
			continue
		
		var item_type = inventory[s][2]
		var count: int = inventory[s][1]
		
		if item_type != null and count > 0:
			var last_item: Node3D = null
			if inventory[s][3].size() > 0:
				last_item = inventory[s][3][-1]
			
			var item_type_string: String = str(item_type)
			
			if item_type_string == "plate" and is_instance_valid(last_item) and "stacked_items" in last_item and last_item.stacked_items.size() > 0:
				var contents: Array = []
				for item in last_item.stacked_items:
					if is_instance_valid(item):
						contents.append(item.type.capitalize())
				lbl.text = "%s\nPlate with %s" % [s, ", ".join(contents)]
			else:
				var multiplier_text: String = ""
				if count > 1:
					multiplier_text = " x" + str(count)
				lbl.text = "%s\n%s%s" % [s, item_type_string.capitalize(), multiplier_text]
		else:
			lbl.text = "%s\nEmpty" % s
			
		if str(s) == current_slot:
			lbl.scale = Vector2(1.15, 1.15)
		else:
			lbl.scale = Vector2(1.0, 1.0)


func _refresh_held_references() -> void:
	var stack: Array = inventory[current_slot][3]
	if stack.size() > 0 and is_instance_valid(stack[-1]):
		held_item = stack[-1]
	else:
		held_item = null
	check_two_handed_status()


func check_two_handed_status() -> void:
	var conditions_met: bool = is_instance_valid(held_item) and "is_two_handed" in held_item and held_item.is_two_handed
	holding_two_handed = conditions_met


func _refresh_hand_visibility_filters() -> void:
	# Show/hide specific slot container nodes and control internal cosmetic clones
	for slot_node in hand.get_children():
		var is_active_slot: bool = (slot_node.name == "slot" + current_slot)
		
		if is_active_slot:
			slot_node.show()
			for child in slot_node.get_children():
				if child.is_in_group("cosmetic_dummy"):
					child.show()
		else:
			slot_node.hide()
			for child in slot_node.get_children():
				if child.is_in_group("cosmetic_dummy"):
					child.hide()

# ==========================================
# MOVEMENT, UTILITIES, HEALTH & RE-SPAWN
# ==========================================

func handle_movement() -> void:
	var vec: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_action_pressed("sprint"):
		speed_multiplier = 1.5
	else:
		speed_multiplier = 1.0
		
	var dir: Vector3 = (transform.basis * Vector3(vec.x, 0, vec.y)).normalized()
	if dir:
		velocity.x = dir.x * SPEED * speed_multiplier
		velocity.z = dir.z * SPEED * speed_multiplier
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)


func _set_mesh_outline(node: Node, active: bool) -> void:
	if node is MeshInstance3D:
		if active:
			node.material_overlay = outline_material
		else:
			node.material_overlay = null
	for child in node.get_children():
		_set_mesh_outline(child, active)


func wake_up_stacked_items(target: Node3D) -> void:
	var state: PhysicsDirectSpaceState3D = target.get_world_3d().direct_space_state
	var q: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	q.shape = box
	q.transform = target.global_transform
	q.transform.origin += Vector3(0, 0.4, 0) 
	q.exclude = [target, self]
	
	for res in state.intersect_shape(q):
		var col: Object = res.get("collider")
		if is_instance_valid(col) and col is RigidBody3D and not col.freeze:
			col.sleeping = false


func take_damage(amount: float) -> void:
	if not is_owned or is_dead:
		return
	health -= amount
	if ui_healthbar:
		ui_healthbar.value = int(health)
	if health <= 0:
		die()


func get_inventory_items_for_score() -> Array:
	var items: Array = []
	for s in inventory:
		for i in inventory[s][3]:
			if i and "type" in i:
				items.append(i.type)
	return items


func clear_inventory_safely() -> void:
	for s in inventory:
		inventory[s] = [inventory[s][0], 0, null, []]
	_refresh_held_references()
	update_inventory_ui()
	_refresh_hand_visibility_filters()


func die() -> void:
	is_dead = true
	health = 0
	var origin: Vector3 = global_position
	for s in inventory:
		while inventory[s][3].size() > 0:
			var angle: float = randf() * TAU
			var dist: float = randf() * 1.5
			current_slot = s
			drop_object()
			if inventory[s][3].size() > 0:
				var dropped_item: Node3D = inventory[s][3][-1]
				if is_instance_valid(dropped_item):
					dropped_item.global_position = origin + Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
	global_position = origin
	clear_inventory_safely()
	rpc("sync_player_death")


func _execute_local_respawn() -> void:
	global_position = Vector3(5, 5, 0)
	health = max_health
	is_dead = false
	if ui_healthbar:
		ui_healthbar.value = int(health)


func _on_pickup_timer_timeout() -> void:
	can_pickup = true


@rpc("any_peer", "call_local", "reliable")
func sync_username(target_name: String) -> void:
	if not is_inside_tree():
		await get_tree().process_frame
		if not is_inside_tree():
			return

	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned: 
			username_label.show()


@rpc("any_peer", "reliable")
func request_username_from_owner() -> void:
	if not is_inside_tree():
		await get_tree().process_frame
		if not is_inside_tree():
			return

	if is_owned: 
		var chosen_name: String = GameData.username if GameData.username != "" else "Player"
		rpc("sync_username", chosen_name)


@rpc("any_peer", "call_local", "reliable")
func sync_player_death() -> void:
	if is_owned: 
		_execute_local_respawn()
