extends CharacterBody3D

var is_owned: bool = false
var held_item: RigidBody3D = null  
var hand_item = null 
var can_pickup = true
var current_slot = "1"
var holding_two_handed: bool = false

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
var mouse_sensitivity = 0.003

var inventory = {
	"1": ["triangle", 0, null, []], 
	"2": ["triangle", 0, null, []], 
	"3": ["triangle", 0, null, []], 
	"4": ["triangle", 0, null, []]
}

@onready var interact_cast : RayCast3D = $head/interact_cast
@onready var hand = $hand
@onready var pickup_timer = $pickup_timer
@onready var username_label : Label3D = $username

func _ready() -> void:
	add_to_group("player")
	for slot_key in inventory: 
		inventory[slot_key][0] = get_node("/root/main/UI/item_slots/slot" + str(slot_key))
	
	GDSync.expose_node(self)
	GDSync.expose_func(sync_drop)
	GDSync.expose_func(sync_wake_up_stacked)
	GDSync.expose_func(sync_username)
	GDSync.expose_func(request_username_from_owner) # New handshake function
	
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	
	if not GameData.connected:
		is_owned = true
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if is_instance_valid(username_label):
			username_label.text = "Player (Offline)"
	else:
		is_owned = GDSync.is_gdsync_owner(self)
		if is_owned:
			if is_instance_valid(username_label):
				username_label.hide() # Hide own name tag locally
			
			# Broadcast name out after a short safety delay
			await get_tree().create_timer(0.2).timeout
			var local_name = GameData.username if GameData.username != "" else "Player"
			GDSync.call_func_all(sync_username, [local_name])
		else:
			# We don't own this player node. Let's ask its real owner to tell us their name!
			await get_tree().create_timer(0.1).timeout
			GDSync.call_func_all(request_username_from_owner, [])
			
	update_inventory_ui()

func owner_changed(_owner_id: int) -> void:
	is_owned = GDSync.is_gdsync_owner(self)
	if is_owned:
		if is_instance_valid($head/camera): 
			$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if is_instance_valid(username_label):
			username_label.hide()
	elif is_instance_valid($head/camera): 
		$head/camera.queue_free()

# HANDSHAKE: Remote players call this on our machine to ask for our name
func request_username_from_owner(_params: Array = []) -> void:
	if is_owned:
		var local_name = GameData.username if GameData.username != "" else "Player"
		GDSync.call_func_all(sync_username, [local_name])

# REPLICATION: Sets the text visible over the player models
func sync_username(params: Array) -> void:
	var target_name = params[0]
	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned:
			username_label.show()

func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused: 
		return
	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x += -event.relative.y * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)

func _physics_process(_delta: float) -> void:
	if not is_owned:
		return

	mouse_sensitivity = get_node("/root/main/Pause_UI/sensitivity").value
	
	if not is_on_floor(): 
		velocity.y -= GRAVITY * _delta
		
	if GameData.paused:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
		
	var active_slot_node = hand.find_child("slot" + current_slot)
	var target_transform : Transform3D
	var is_colliding_with_placeable: bool = false
	
	if is_instance_valid(active_slot_node):
		target_transform = active_slot_node.global_transform
		if interact_cast.is_colliding():
			var collider = interact_cast.get_collider()
			if is_instance_valid(collider) and is_instance_valid(held_item) and held_item.is_inside_tree():
				if (collider.is_in_group("placeable") and held_item.is_in_group("choppable")) or \
				   (collider.is_in_group("placeable") and not collider.is_in_group("chopping_board") and held_item.is_in_group("meat")) or \
				   (collider.is_in_group("THE_THING")):
					target_transform.origin = collider.global_position + Vector3(0, 0.5, 0)
					target_transform.basis = Basis.IDENTITY
					is_colliding_with_placeable = true
				elif collider.is_in_group("plate") and held_item.is_in_group("plate_stackable") and "calculate_stack_height" in collider:
					target_transform.origin = collider.global_position + Vector3(0, collider.calculate_stack_height(), 0)
					target_transform.basis = Basis.IDENTITY
					is_colliding_with_placeable = true
					
	get_node("/root/main/UI/colliding").visible = interact_cast.is_colliding() and is_colliding_with_placeable
			
	for slot_key in inventory:
		var stack = inventory[slot_key][3]
		if stack.size() > 0:
			if slot_key == current_slot and is_instance_valid(active_slot_node):
				for item in stack:
					if is_instance_valid(item):
						item.global_transform = target_transform
						item.visible = is_colliding_with_placeable
			else:
				for item in stack:
					if is_instance_valid(item):
						item.global_position = Vector3(0, -20, 0)
						item.show()
						
	if is_instance_valid(hand_item):
		hand_item.show()
		hand_item.position = Vector3.ZERO
		hand_item.rotation = Vector3.ZERO
		
	handle_inventory_slots()
	handle_interactions()
	handle_movement()
	move_and_slide()

func check_two_handed_status() -> void:
	holding_two_handed = is_instance_valid(held_item) and "is_two_handed" in held_item and held_item.is_two_handed

func handle_inventory_slots():
	if holding_two_handed: 
		return 
		
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
		for child in slot_node.get_children(): 
			child.queue_free()
		slot_node.hide()
		
	if active_slot_node: 
		active_slot_node.show()
		
	var current_stack = inventory[current_slot][3]
	if current_stack.size() > 0 and is_instance_valid(current_stack[-1]):
		held_item = current_stack[-1]
		hand_item = held_item.duplicate() 
		
		if "type" in held_item:
			hand_item.type = held_item.type
			
		active_slot_node.add_child(hand_item)
		hand_item.position = Vector3.ZERO
		hand_item.rotation = Vector3.ZERO
		hand_item.show()
		
		if hand_item is RigidBody3D: 
			hand_item.freeze = true
			
		var collision_shape = hand_item.find_child("CollisionShape3D")
		if collision_shape: 
			collision_shape.disabled = true
	else:
		hand_item = null
		held_item = null
		
	check_two_handed_status()

func update_inventory_ui():
	for slot_key in inventory:
		var slot_label = inventory[slot_key][0]
		if not is_instance_valid(slot_label): 
			continue
		var slot_type = inventory[slot_key][2]
		var quantity = inventory[slot_key][1]
		var stack = inventory[slot_key][3]
		
		if slot_type != null and quantity > 0:
			if slot_type == "plate" and stack.size() > 0 and is_instance_valid(stack[-1]) and stack[-1].stacked_items.size() > 0:
				var item_names = []
				for item in stack[-1].stacked_items: 
					if is_instance_valid(item): 
						item_names.append(item.type)
				slot_label.text = "%s\n%s (%s) (%d)" % [slot_key, slot_type, ", ".join(item_names), quantity]
			else: 
				slot_label.text = "%s\n%s (%d)" % [slot_key, slot_type, quantity]
		else: 
			slot_label.text = str(slot_key) + "\nempty"
		slot_label.scale = Vector2(1.2, 1.2) if str(slot_key) == current_slot else Vector2(1.0, 1.0)

func handle_interactions():
	if inventory[current_slot][1] > 0 and not is_instance_valid(held_item):
		inventory[current_slot][3].clear()
		inventory[current_slot][1] = 0
		inventory[current_slot][2] = null
		if is_instance_valid(hand_item): 
			hand_item.queue_free()
		update_hand_visuals()
		update_inventory_ui()
		
	if Input.is_action_just_pressed("ui_accept") and is_on_floor(): 
		velocity.y = JUMP_VELOCITY
		
	if holding_two_handed:
		if Input.is_action_just_pressed("right_click"):
			drop_object()
		return

	if Input.is_action_just_pressed("left_click") and interact_cast.is_colliding():
		var interaction_target = interact_cast.get_collider()
		if interaction_target.is_in_group("punchable"): 
			interaction_target._on_punched()
		elif interaction_target.is_in_group("storage_button"):
			interaction_target.spawn_item.emit(interaction_target.name)
			
		elif interaction_target.is_in_group("pickupable") and can_pickup: 
			if "freeze" in interaction_target and interaction_target.freeze:
				return 
				
			pickup_object(interaction_target)
			
		elif interaction_target.is_in_group("door"): 
			interaction_target.open_door()
			
	if Input.is_action_just_pressed("right_click"):
		if interact_cast.is_colliding():
			var interaction_target = interact_cast.get_collider()
			if interaction_target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
				stack_object(interaction_target)
				return
		if inventory[current_slot][2] != null and can_pickup: 
			drop_object()

func handle_movement():
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var movement_direction = (transform.basis * Vector3(input_direction.x, 0, input_direction.y)).normalized()
	velocity.x = movement_direction.x * SPEED if movement_direction else move_toward(velocity.x, 0, SPEED)
	velocity.z = movement_direction.z * SPEED if movement_direction else move_toward(velocity.z, 0, SPEED)

func pickup_object(object: Node3D):
	var object_is_two_handed = object.is_two_handed if "is_two_handed" in object else object.is_in_group("two_handed")
	if object_is_two_handed:
		var has_empty_slot = false
		for slot_key in inventory:
			if inventory[slot_key][2] == null or inventory[slot_key][1] == 0:
				has_empty_slot = true
				break
		if not has_empty_slot: 
			return
			
	for slot_key in inventory:
		var slot_match_type = inventory[slot_key][2] == object.type
		var slot_is_empty = inventory[slot_key][2] == null
		if slot_is_empty or slot_match_type:
			
			if GameData.connected:
				GDSync.call_func_all(sync_wake_up_stacked, [object.get_path()])
			else:
				wake_up_stacked_items(object)
			
			inventory[slot_key][2] = object.type
			inventory[slot_key][1] += 1
			inventory[slot_key][3].append(object)
			current_slot = str(slot_key)
			can_pickup = false
			pickup_timer.start()
			
			if GameData.connected: 
				GDSync.set_gdsync_owner(object, GDSync.get_client_id())
				
			object.freeze = true
			var collision_shape = object.find_child("CollisionShape3D")
			if collision_shape: 
				collision_shape.disabled = true
				
			update_hand_visuals()
			update_inventory_ui()
			break

func sync_wake_up_stacked(params: Array) -> void:
	var target_node = get_node_or_null(params[0])
	if is_instance_valid(target_node):
		wake_up_stacked_items(target_node)

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
			if collider.freeze:
				continue
			collider.sleeping = false

func stack_object(plate: Node3D):
	var item = held_item
	inventory[current_slot][3].erase(item)
	inventory[current_slot][1] -= 1
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: 
		inventory[current_slot][2] = null
	if slot_is_empty and is_instance_valid(hand_item): 
		hand_item.queue_free()
	plate.stack_item(item)
	update_hand_visuals()
	update_inventory_ui()

func drop_object():
	var item = inventory[current_slot][3].pop_back()
	inventory[current_slot][1] -= 1
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: 
		inventory[current_slot][2] = null
	can_pickup = false
	pickup_timer.start()
	if slot_is_empty and is_instance_valid(hand_item): 
		hand_item.queue_free()
		
	var drop_position = hand.global_position
	var drop_rotation = hand.global_rotation
	
	if interact_cast.is_colliding():
		var target_collider = interact_cast.get_collider()
		if target_collider.is_in_group("placeable"):
			if (target_collider.is_in_group("chopping_board") and item.is_in_group("choppable")) or \
			   (not target_collider.is_in_group("chopping_board") and item.is_in_group("meat")) or \
			   (target_collider.is_in_group("THE_THING")):
				drop_position = target_collider.global_position + Vector3(0, 0.5, 0)
				drop_rotation = Vector3.ZERO
				
	item.show()
	item.global_position = drop_position
	item.global_rotation = drop_rotation
	item.freeze = false
	
	var collision_shape = item.find_child("CollisionShape3D")
	if collision_shape: 
		collision_shape.disabled = false
		
	if GameData.connected:
		GDSync.set_gdsync_owner(item, GDSync.get_host())
		GDSync.call_func_all(sync_drop, [item.get_path(), drop_position, drop_rotation])
		
	update_hand_visuals()
	check_two_handed_status()
	update_inventory_ui()

func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.freeze = false
		var collision_shape = object.find_child("CollisionShape3D")
		if collision_shape: 
			collision_shape.disabled = false
		object.global_position = params[1]
		object.global_rotation = params[2]
		object.show()

func _on_pickup_timer_timeout() -> void: 
	can_pickup = true
