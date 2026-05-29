extends CharacterBody3D

# --- Health & Vital States ---
var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = true

# --- Networking & Possession ---
var is_owned: bool = false
var speed_multiplier: float = 1.0

# --- Inventory & Holding States ---
var held_item: RigidBody3D = null  
var hand_item: Node3D = null 
var can_pickup: bool = true
var current_slot: String = "1"
var holding_two_handed: bool = false

var inventory = {
	"1": ["triangle", 0, null, []], 
	"2": ["triangle", 0, null, []], 
	"3": ["triangle", 0, null, []], 
	"4": ["triangle", 0, null, []]
}

# --- Interaction & Visual Outlines ---
var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

# --- Constants ---
const SPEED = 5.0
const JUMP_VELOCITY = 3.0
const GRAVITY = 9.8
var mouse_sensitivity: float = 0.003

# --- Onready Nodes ---
@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

# --- Cached UI References ---
@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/colliding")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider = get_node_or_null("/root/main/Pause_UI/sensitivity")


# ==========================================
# LIFE CYCLE METHODS
# ==========================================

func _ready() -> void:
	add_to_group("player")
	
	# Link UI elements to inventory slots
	for slot_key in inventory: 
		inventory[slot_key][0] = get_node("/root/main/UI/item_slots/slot" + str(slot_key))
	
	# GDSync Setup
	GDSync.expose_node(self)
	GDSync.expose_func(sync_drop)
	GDSync.expose_func(sync_wake_up_stacked)
	GDSync.expose_func(sync_username)
	GDSync.expose_func(request_username_from_owner) 
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	
	_initialize_ownership()
	update_inventory_ui()


func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused: 
		return
		
	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x += -event.relative.y * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)


func _physics_process(delta: float) -> void:
	if not is_owned: return
	
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
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return
		
	# Gather the raycast context once per frame to share across methods
	var raycast_target: Node3D = null
	if interact_cast.is_colliding():
		var col = interact_cast.get_collider()
		if is_instance_valid(col):
			raycast_target = col
			
	# Update active pipelines using the cached target
	_process_item_carrying_logic(raycast_target)
	handle_inventory_slots() 
	handle_interactions(raycast_target)
	handle_movement()
	move_and_slide()


# ==========================================
# PROCESSING PIPELINES
# ==========================================

func _process_item_carrying_logic(target: Node3D) -> void:
	var active_slot_node = hand.find_child("slot" + current_slot)
	var target_transform: Transform3D
	var is_colliding_with_placeable: bool = false
	var is_looking_at_interactive: bool = false
	var context_text: String = ""
	
	if is_instance_valid(active_slot_node):
		target_transform = active_slot_node.global_transform

	# Only compute raycast placement logic for the local player who owns this controller character
	if is_owned and is_instance_valid(target):
		if target.is_in_group("pickupable") or target.is_in_group("punchable") or target.is_in_group("door") or target.is_in_group("placeable") or target.is_in_group("plate"):
			is_looking_at_interactive = true
			
			if "type" in target:
				context_text = str(target.type).capitalize()
			else:
				context_text = str(target.name).replace("_", " ").capitalize()

		if is_instance_valid(held_item) and held_item.is_inside_tree() and _can_interact_with(target):
			if target.is_in_group("placeable"):
				is_colliding_with_placeable = true
				target_transform.basis = Basis.IDENTITY
				if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"):
					target_transform.origin = target.global_position + Vector3(0, 1.2, 0)
				elif target.is_in_group("THE_THING"):
					target_transform.origin = target.global_position + Vector3(0, 0, 0)
				elif not target.is_in_group("chopping_board") and held_item.is_in_group("meat"):
					target_transform.origin = target.global_position + Vector3(0, 0.4, 0)
				else:
					is_colliding_with_placeable = false
					
			elif target.is_in_group("plate") and held_item.is_in_group("plate_stackable") and target.has_method("calculate_stack_height"):
				target_transform.origin = target.global_position + Vector3(0, target.calculate_stack_height(), 0)
				target_transform.basis = Basis.IDENTITY
				is_colliding_with_placeable = true

	if is_owned and ui_colliding_label:
		var interactive = is_looking_at_interactive or is_colliding_with_placeable
		ui_colliding_label.visible = interactive
		if interactive:
			ui_colliding_label.text = context_text
	
	# --- NET-READY ITEM VISIBILITY FIX ---
	for slot_key in inventory:
		var stack = inventory[slot_key][3]
		if stack.size() > 0:
			if slot_key == current_slot and is_instance_valid(active_slot_node):
				for item in stack:
					if is_instance_valid(item):
						item.global_transform = target_transform
						if is_owned:
							item.visible = is_colliding_with_placeable
						else:
							item.visible = true
			else:
				for item in stack:
					if is_instance_valid(item):
						item.global_position = Vector3(0, -20, 0)
						item.show()
						
	# Update the actual visual item node sitting in your hands
	if is_instance_valid(hand_item):
		if is_owned and is_colliding_with_placeable:
			hand_item.hide() # Hide visual hand representation if placing/stacking preview is active
		else:
			hand_item.show()
			hand_item.position = Vector3.ZERO
			hand_item.rotation = Vector3.ZERO


# ==========================================
# INTERACTION CORE
# ==========================================

func handle_interactions(target: Node3D):
	var current_target: Node3D = target if (is_instance_valid(target) and _can_interact_with(target)) else null

	# Manage visual overlay swaps efficiently
	if current_target != last_highlighted_target:
		if is_instance_valid(last_highlighted_target):
			_set_mesh_outline(last_highlighted_target, false)
		if is_instance_valid(current_target):
			_set_mesh_outline(current_target, true)
		last_highlighted_target = current_target

	# Clean up ghost references safely 
	if inventory[current_slot][1] > 0 and not is_instance_valid(held_item):
		inventory[current_slot][3].clear()
		inventory[current_slot][1] = 0
		inventory[current_slot][2] = null
		if is_instance_valid(hand_item): hand_item.queue_free()
		update_hand_visuals()
		update_inventory_ui()
		
	if Input.is_action_pressed("ui_accept") and is_on_floor(): 
		velocity.y = JUMP_VELOCITY
		
	if holding_two_handed:
		if Input.is_action_just_pressed("right_click"): drop_object()
		return

	# Action Executions
	if is_instance_valid(current_target):
		if Input.is_action_just_pressed("left_click"):
			if current_target.is_in_group("punchable"): 
				current_target._on_punched()
			elif current_target.is_in_group("pickupable") and can_pickup: 
				if "freeze" in current_target and current_target.freeze: return 
				pickup_object(current_target)
			elif current_target.is_in_group("door"): 
				current_target.open_door()
				
		if Input.is_action_just_pressed("right_click"):
			if current_target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
				stack_object(current_target)
				return
				
	if Input.is_action_just_pressed("right_click") and inventory[current_slot][2] != null and can_pickup and not holding_two_handed: 
		drop_object()


func _can_interact_with(target: Node3D) -> bool:
	if not is_instance_valid(target): return false
	
	if target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
		return true

	if target.is_in_group("door") or target.is_in_group("punchable"): return true

	if target.is_in_group("placeable"):
		if is_instance_valid(held_item):
			if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"): return true
			if target.is_in_group("THE_THING") or target.is_in_group("stove"): return true
			if not target.is_in_group("chopping_board") and held_item.is_in_group("meat"): return true
		return false

	if holding_two_handed: return false

	if target.is_in_group("pickupable"):
		if not can_pickup: return false
		
		var target_type = target.type if "type" in target else target.name
		
		for slot_key in inventory:
			if inventory[slot_key][2] == target_type and inventory[slot_key][1] > 0:
				return true
				
		for slot_key in inventory:
			if inventory[slot_key][2] == null or inventory[slot_key][1] == 0:
				return true
		return false

	return false


func pickup_object(object: Node3D):
	var actual_target = object
	if not "type" in actual_target and actual_target.get_parent() and "type" in actual_target.get_parent():
		actual_target = actual_target.get_parent()

	var target_type = actual_target.type if "type" in actual_target else actual_target.name
	var object_is_two_handed = actual_target.is_two_handed if "is_two_handed" in actual_target else actual_target.is_in_group("two_handed")
	
	if object_is_two_handed:
		var has_empty_slot = false
		for slot_key in inventory:
			if inventory[slot_key][2] == null or inventory[slot_key][1] == 0:
				has_empty_slot = true; break
		if not has_empty_slot: return

	var destination_slot: String = ""
	for slot_key in inventory:
		if inventory[slot_key][2] == target_type and inventory[slot_key][1] > 0:
			destination_slot = slot_key
			break
			
	if destination_slot == "":
		for slot_key in inventory:
			if inventory[slot_key][2] == null or inventory[slot_key][1] == 0:
				destination_slot = slot_key
				break

	if destination_slot != "":
		if GameData.connected:
			GDSync.call_func_all(sync_wake_up_stacked, [actual_target.get_path()])
		else:
			wake_up_stacked_items(actual_target)
			
		inventory[destination_slot][2] = target_type
		inventory[destination_slot][1] += 1
		inventory[destination_slot][3].append(actual_target)
		current_slot = destination_slot
		can_pickup = false
		pickup_timer.start()
		
		if GameData.connected: 
			GDSync.set_gdsync_owner(actual_target, GDSync.get_client_id())
			
		actual_target.freeze = true
		var collision_shape = actual_target.find_child("CollisionShape3D")
		if collision_shape: collision_shape.disabled = true
			
		if actual_target == last_highlighted_target:
			_set_mesh_outline(actual_target, false)
			last_highlighted_target = null
			
		update_hand_visuals()
		update_inventory_ui()


func drop_object(forced_position: Vector3 = Vector3.ZERO, forced_rotation: Vector3 = Vector3.ZERO):
	if inventory[current_slot][3].size() == 0: return
	
	var item = inventory[current_slot][3].pop_back()
	inventory[current_slot][1] -= 1
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: inventory[current_slot][2] = null
	
	can_pickup = false
	pickup_timer.start()
	if slot_is_empty and is_instance_valid(hand_item): hand_item.queue_free()
		
	var drop_position = hand.global_position if forced_position == Vector3.ZERO else forced_position
	var drop_rotation = hand.global_rotation if forced_rotation == Vector3.ZERO else forced_rotation
	
	if forced_position == Vector3.ZERO and interact_cast.is_colliding():
		var target_collider = interact_cast.get_collider()
		if target_collider.is_in_group("placeable"):
			if target_collider.is_in_group("chopping_board") and item.is_in_group("choppable"):
				drop_position = target_collider.global_position + Vector3(0, 1.2, 0)
				drop_rotation = Vector3.ZERO
			elif target_collider.is_in_group("THE_THING"):
				drop_position = target_collider.global_position + Vector3(0, 0, 0)
				drop_rotation = Vector3.ZERO
			elif not target_collider.is_in_group("chopping_board") and item.is_in_group("meat"):
				drop_position = target_collider.global_position + Vector3(0, 0.4, 0)
				drop_rotation = Vector3.ZERO
				
	item.show()
	item.global_position = drop_position
	item.global_rotation = drop_rotation
	item.freeze = false
	
	var collision_shape = item.find_child("CollisionShape3D")
	if collision_shape: collision_shape.disabled = false
		
	if GameData.connected:
		GDSync.set_gdsync_owner(item, GDSync.get_host())
		GDSync.call_func_all(sync_drop, [item.get_path(), drop_position, drop_rotation])
		
	update_hand_visuals()
	check_two_handed_status()
	update_inventory_ui()


func stack_object(plate: Node3D):
	var item = held_item
	inventory[current_slot][3].erase(item)
	inventory[current_slot][1] -= 1
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: inventory[current_slot][2] = null
	if slot_is_empty and is_instance_valid(hand_item): hand_item.queue_free()
	
	plate.stack_item(item)
	update_hand_visuals()
	update_inventory_ui()


func handle_inventory_slots():
	if holding_two_handed: return 
		
	var previous_slot = current_slot
	if Input.is_action_just_pressed("1"): current_slot = "1"
	elif Input.is_action_just_pressed("2"): current_slot = "2"
	elif Input.is_action_just_pressed("3"): current_slot = "3"
	elif Input.is_action_just_pressed("4"): current_slot = "4"
	
	if previous_slot != current_slot: 
		update_hand_visuals()
		check_two_handed_status()
		update_inventory_ui()


func update_hand_visuals():
	var active_slot_node = hand.find_child("slot" + current_slot)
	
	for slot_node in hand.get_children():
		for child in slot_node.get_children(): child.queue_free()
		slot_node.hide()
		
	if active_slot_node: active_slot_node.show()
		
	var current_stack = inventory[current_slot][3]
	if current_stack.size() > 0 and is_instance_valid(current_stack[-1]):
		held_item = current_stack[-1]
		hand_item = held_item.duplicate() 
		if "type" in held_item: hand_item.type = held_item.type
		
		# Unique structural name initialization prevents path matching system interference
		hand_item.name = "HeldItemVisual_Slot" + str(current_slot)
			
		active_slot_node.add_child(hand_item)
		hand_item.position = Vector3.ZERO
		hand_item.rotation = Vector3.ZERO
		hand_item.show()
		
		if hand_item is RigidBody3D: hand_item.freeze = true
		var collision_shape = hand_item.find_child("CollisionShape3D")
		if collision_shape: collision_shape.disabled = true
	else:
		hand_item = null; held_item = null
		
	check_two_handed_status()


func update_inventory_ui():
	for slot_key in inventory:
		var slot_label = inventory[slot_key][0]
		if not is_instance_valid(slot_label): continue
		
		var slot_type = inventory[slot_key][2]
		var quantity = inventory[slot_key][1]
		var stack = inventory[slot_key][3]
		
		if slot_type != null and quantity > 0:
			if slot_type == "plate" and stack.size() > 0 and is_instance_valid(stack[-1]) and stack[-1].stacked_items.size() > 0:
				var item_names = []
				for item in stack[-1].stacked_items: 
					if is_instance_valid(item): item_names.append(item.type)
				slot_label.text = "%s\n%s (%s) (%d)" % [slot_key, slot_type, ", ".join(item_names), quantity]
			else: 
				slot_label.text = "%s\n%s (%d)" % [slot_key, slot_type, quantity]
		else: 
			slot_label.text = str(slot_key) + "\nempty"
			
		slot_label.scale = Vector2(1.2, 1.2) if str(slot_key) == current_slot else Vector2(1.0, 1.0)


func check_two_handed_status() -> void:
	holding_two_handed = is_instance_valid(held_item) and "is_two_handed" in held_item and held_item.is_two_handed


# ==========================================
# MOVEMENT & UTILITIES
# ==========================================

func handle_interactions(target: Node3D):
	var current_target: Node3D = target if (is_instance_valid(target) and _can_interact_with(target)) else null

	# Manage visual overlay swaps efficiently
	if current_target != last_highlighted_target:
		if is_instance_valid(last_highlighted_target):
			_set_mesh_outline(last_highlighted_target, false)
		if is_instance_valid(current_target):
			_set_mesh_outline(current_target, true)
		last_highlighted_target = current_target

	# Clean up ghost references safely 
	if inventory[current_slot][1] > 0 and not is_instance_valid(held_item):
		inventory[current_slot][3].clear()
		inventory[current_slot][1] = 0
		inventory[current_slot][2] = null
		if is_instance_valid(hand_item): hand_item.queue_free()
		update_hand_visuals()
		update_inventory_ui()
		
	if Input.is_action_pressed("ui_accept") and is_on_floor(): 
		velocity.y = JUMP_VELOCITY
		
	if holding_two_handed:
		if Input.is_action_just_pressed("right_click"): drop_object()
		return

	# Action Executions
	if is_instance_valid(current_target):
		if Input.is_action_just_pressed("left_click"):
			if current_target.is_in_group("punchable"): 
				current_target._on_punched()
			elif current_target.is_in_group("storage_button"):
				current_target.spawn_item.emit(current_target.name)
			elif current_target.is_in_group("pickupable") and can_pickup: 
				if "freeze" in current_target and current_target.freeze: return 
				pickup_object(current_target)
			elif current_target.is_in_group("door"): 
				current_target.open_door()
				
		if Input.is_action_just_pressed("right_click"):
			if current_target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
				stack_object(current_target)
				return
				
	if Input.is_action_just_pressed("right_click") and inventory[current_slot][2] != null and can_pickup and not holding_two_handed: 
		drop_object()

func handle_movement():
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	speed_multiplier = 1.5 if Input.is_action_pressed("sprint") else 1.0
	var movement_direction = (transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	
	velocity.x = movement_direction.x * SPEED * speed_multiplier if movement_direction else move_toward(velocity.x, 0, SPEED)
	velocity.z = movement_direction.z * SPEED * speed_multiplier if movement_direction else move_toward(velocity.z, 0, SPEED)


func _set_mesh_outline(node: Node, active: bool) -> void:
	if node is MeshInstance3D:
		node.material_overlay = outline_material if active else null
	for child in node.get_children():
		_set_mesh_outline(child, active)


func wake_up_stacked_items(target_object: Node3D) -> void:
	var space_state = target_object.get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.6, 0.6, 0.6)
	
	query.shape = box
	query.transform = target_object.global_transform
	query.transform.origin += Vector3(0, 0.4, 0) 
	query.exclude = [target_object, self]
	
	var results = space_state.intersect_shape(query)
	for result in results:
		var collider = result.get("collider")
		if is_instance_valid(collider) and collider is RigidBody3D:
			if not collider.freeze: collider.sleeping = false


# ==========================================
# NETWORK SYNCHRONIZATION BACKENDS
# ==========================================

func _initialize_ownership() -> void:
	if not GameData.connected:
		is_owned = true
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if is_instance_valid(username_label): username_label.text = "Player (Offline)"
	else:
		is_owned = GDSync.is_gdsync_owner(self)
		if is_owned:
			if is_instance_valid(username_label): username_label.hide() 
			await get_tree().create_timer(0.2).timeout
			var local_name = GameData.username if GameData.username != "" else "Player"
			GDSync.call_func_all(sync_username, [local_name])
		else:
			await get_tree().create_timer(0.1).timeout
			GDSync.call_func_all(request_username_from_owner, [])


func owner_changed(_owner_id: int) -> void:
	is_owned = GDSync.is_gdsync_owner(self)
	if is_owned:
		if is_instance_valid($head/camera): $head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if is_instance_valid(username_label): username_label.hide()
	elif is_instance_valid($head/camera): 
		$head/camera.queue_free()


func request_username_from_owner(_params: Array = []) -> void:
	if is_owned:
		var local_name = GameData.username if GameData.username != "" else "Player"
		GDSync.call_func_all(sync_username, [local_name])


func sync_username(params: Array) -> void:
	var target_name = params[0]
	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned: username_label.show()


func sync_wake_up_stacked(params: Array) -> void:
	var target_node = get_node_or_null(params[0])
	if is_instance_valid(target_node): wake_up_stacked_items(target_node)


func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.freeze = false
		var collision_shape = object.find_child("CollisionShape3D")
		if collision_shape: collision_shape.disabled = false
		object.global_position = params[1]
		object.global_rotation = params[2]
		object.show()


func take_damage(amount: float) -> void:
	if not is_owned or is_dead: return
	
	health -= amount
	if ui_healthbar:
		ui_healthbar.value = int(health)
	
	if health <= 0:
		die()


func get_inventory_items_for_score() -> Array:
	var item_list: Array = []
	if not "inventory" in self or inventory == null:
		return item_list
		
	for slot_key in inventory:
		var stack = inventory[slot_key][3]
		for item_data in stack:
			if item_data and "type" in item_data:
				item_list.append(item_data.type)
	return item_list


func clear_inventory_safely() -> void:
	if not "inventory" in self or inventory == null:
		return
		
	for slot_key in inventory:
		inventory[slot_key][1] = 0        
		inventory[slot_key][2] = null     
		inventory[slot_key][3].clear()    
		
	update_hand_visuals()
	update_inventory_ui()


func die() -> void:
	is_dead = true
	health = 0
	
	var drop_origin = global_position
	
	for slot_key in inventory:
		var stack = inventory[slot_key][3]
		while stack.size() > 0:
			var scatter_radius = 1.5
			var random_angle = randf() * TAU
			var random_distance = randf() * scatter_radius
			
			var target_scatter_pos = drop_origin + Vector3(
				cos(random_angle) * random_distance,
				0.5, 
				sin(random_angle) * random_distance
			)
			
			current_slot = slot_key
			drop_object(target_scatter_pos, Vector3.ZERO)
			
	global_position = drop_origin
			
	for slot_key in inventory:
		inventory[slot_key][1] = 0
		inventory[slot_key][2] = null
		inventory[slot_key][3].clear()
		
	update_hand_visuals()
	update_inventory_ui()
	
	if GameData.connected:
		GDSync.call_func_all(sync_player_death, [get_path()])
	else:
		_execute_local_respawn()


func sync_player_death(params: Array) -> void:
	var dead_player = get_node_or_null(params[0])
	if dead_player == self and is_owned:
		_execute_local_respawn()


func _execute_local_respawn() -> void:
	global_position = Vector3(5, 5, 0) 
	health = max_health
	is_dead = false
	if ui_healthbar:
		ui_healthbar.value = int(health)


func _on_pickup_timer_timeout() -> void: 
	can_pickup = true
