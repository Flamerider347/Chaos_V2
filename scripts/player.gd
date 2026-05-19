extends CharacterBody3D

var is_owned: bool = false
var held_item: RigidBody3D = null  
var hand_item = null # Tracks our local visual duplicate clone
var can_pickup = true
var current_slot = "1"

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
var mouse_sensitivity = 0.003

var inventory = {"1": ["triangle", 0, null, []], "2": ["triangle", 0, null, []], "3": ["triangle", 0, null, []], "4": ["triangle", 0, null, []]}

@onready var interact_cast : RayCast3D = $head/interact_cast
@onready var hand = $hand
@onready var pickup_timer = $pickup_timer

func _ready() -> void:
	add_to_group("player")
	for i in inventory: inventory[i][0] = get_node("/root/main/UI/item_slots/slot" + str(i))
	GDSync.expose_node(self)
	GDSync.expose_func(sync_drop)
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	
	if not GameData.connected:
		is_owned = true; $head/camera.make_current(); Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	update_inventory_ui()

func owner_changed(_owner_id: int) -> void:
	is_owned = GDSync.is_gdsync_owner(self)
	if is_owned:
		if is_instance_valid($head/camera): $head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif is_instance_valid($head/camera): $head/camera.queue_free()

func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused: return
	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x += -event.relative.y * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)

func _physics_process(_delta: float) -> void:
	mouse_sensitivity = get_node("/root/main/Pause_UI/sensitivity").value
	if GameData.paused:
		velocity.x = 0; velocity.z = 0
		if not is_on_floor(): velocity.y -= GRAVITY * _delta
		move_and_slide(); return

	if not is_on_floor(): velocity.y -= GRAVITY * _delta

	# MANAGING POSITIONS (The Simplified Hybrid Logic)
	for slot_key in inventory:
		var stack = inventory[slot_key][3]
		if stack.size() > 0:
			var active_slot_node = hand.find_child("slot" + current_slot)
			
			if slot_key == current_slot and is_instance_valid(active_slot_node):
				for item in stack:
					if is_instance_valid(item):
						# Snap the real item exactly to your hand node for EVERYONE
						item.global_transform = active_slot_node.global_transform
						item.show()
						
						# Hide meshes on YOUR screen recursively so nested plate foods disappear,
						# but leave them completely untouched and visible on other players' viewports.
						set_meshes_visible_recursive(item, !is_owned)
			else:
				# If the slot is inactive, push it into the sky pool out of the way
				for item in stack:
					if is_instance_valid(item):
						item.global_position = Vector3(0, 50, 0)
						set_meshes_visible_recursive(item, true)

	if not is_owned: return

	# Local placement preview raycast logic
	if is_instance_valid(hand_item) and interact_cast.is_colliding():
		var collider = interact_cast.get_collider()
		if is_instance_valid(collider):
			if collider.is_in_group("placeable") and hand_item.is_in_group("choppable"):
				hand_item.global_position = collider.global_position + Vector3(0, 0.5, 0)
			elif collider.is_in_group("plate") and hand_item.is_in_group("plate_stackable") and "calculate_stack_height" in collider:
				hand_item.global_position = collider.global_position + Vector3(0, collider.calculate_stack_height(), 0)
			else:
				hand_item.position = Vector3.ZERO; hand_item.rotation = Vector3.ZERO
		else:
			hand_item.position = Vector3.ZERO; hand_item.rotation = Vector3.ZERO
	elif is_instance_valid(hand_item):
		hand_item.position = Vector3.ZERO; hand_item.rotation = Vector3.ZERO

	handle_inventory_slots(); handle_interactions(); handle_movement()
	move_and_slide()

func handle_inventory_slots():
	if is_instance_valid(held_item) and held_item.is_in_group("plate"): return 
	var prev = current_slot
	if Input.is_action_just_pressed("1"): current_slot = "1"
	elif Input.is_action_just_pressed("2"): current_slot = "2"
	elif Input.is_action_just_pressed("3"): current_slot = "3"
	elif Input.is_action_just_pressed("4"): current_slot = "4"
	if prev != current_slot: update_hand_visuals(); update_inventory_ui()

func update_hand_visuals():
	var active_slot_node = hand.find_child("slot" + current_slot)
	for slot_node in hand.get_children():
		for child in slot_node.get_children(): child.queue_free()
		slot_node.hide()
	if active_slot_node: active_slot_node.show()

	var current_stack = inventory[current_slot][3]
	if current_stack.size() > 0 and is_instance_valid(current_stack[-1]):
		held_item = current_stack[-1]
		
		# Duplicate locally for your own camera view (Lag-free)
		hand_item = held_item.duplicate()
		active_slot_node.add_child(hand_item)
		
		# Ensure your local duplicate's visual meshes are 100% visible
		set_meshes_visible_recursive(hand_item, true)
				
		hand_item.position = Vector3.ZERO; hand_item.rotation = Vector3.ZERO; hand_item.show()
		if hand_item is RigidBody3D: hand_item.freeze = true
		var col = hand_item.find_child("CollisionShape3D")
		if col: col.disabled = true
	else:
		hand_item = null; held_item = null

func update_inventory_ui():
	for i in inventory:
		var slot_label = inventory[i][0]
		if not is_instance_valid(slot_label): continue
		var type_str = inventory[i][2]
		var qty = inventory[i][1]
		var stack = inventory[i][3]
		
		if type_str != null and qty > 0:
			if type_str == "plate" and stack.size() > 0 and is_instance_valid(stack[-1]) and stack[-1].stacked_items.size() > 0:
				var names = []
				for item in stack[-1].stacked_items: 
					if is_instance_valid(item): names.append(item.type if "type" in item else item.name)
				slot_label.text = "%s\n%s (%s) (%d)" % [i, type_str, ", ".join(names), qty]
			else: slot_label.text = "%s\n%s (%d)" % [i, type_str, qty]
		else: slot_label.text = str(i) + "\nempty"
		slot_label.scale = Vector2(1.2, 1.2) if str(i) == current_slot else Vector2(1.0, 1.0)

func handle_interactions():
	if Input.is_action_just_pressed("ui_accept") and is_on_floor(): velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("left_click") and interact_cast.is_colliding():
		var col = interact_cast.get_collider()
		if col.is_in_group("punchable"): col._on_punched()
		elif col.is_in_group("pickupable") and can_pickup: pickup_object(col)
		elif col.is_in_group("door"): col.open_door()

	if Input.is_action_just_pressed("right_click"):
		if interact_cast.is_colliding():
			var col = interact_cast.get_collider()
			if col.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable"):
				stack_object(col); return
		if inventory[current_slot][2] != null and can_pickup: drop_object()

func handle_movement():
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	velocity.x = dir.x * SPEED if dir else move_toward(velocity.x, 0, SPEED)
	velocity.z = dir.z * SPEED if dir else move_toward(velocity.z, 0, SPEED)

func pickup_object(object):
	for i in inventory:
		if inventory[i][2] == object.type or inventory[i][2] == null:
			inventory[i][2] = object.type; inventory[i][1] += 1; inventory[i][3].append(object)
			current_slot = str(i)
			can_pickup = false; pickup_timer.start()
			
			if GameData.connected: GDSync.set_gdsync_owner(object, GDSync.get_client_id())
			
			object.freeze = true
			var col = object.find_child("CollisionShape3D")
			if col: col.disabled = true
			
			update_hand_visuals(); update_inventory_ui(); break

func stack_object(plate):
	var item = held_item
	inventory[current_slot][3].erase(item)
	inventory[current_slot][1] -= 1
	
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: 
		inventory[current_slot][2] = null
	
	if slot_is_empty and is_instance_valid(hand_item): 
		hand_item.queue_free()
		
	# Restore visual mesh system recursively before pinning it onto the plate
	set_meshes_visible_recursive(item, true)
	
	plate.stack_item(item)
	update_hand_visuals(); update_inventory_ui()

func drop_object():
	var item = inventory[current_slot][3].pop_back()
	inventory[current_slot][1] -= 1
	
	var slot_is_empty = inventory[current_slot][1] <= 0
	if slot_is_empty: 
		inventory[current_slot][2] = null
	
	can_pickup = false; pickup_timer.start()
	
	# Only free the visual duplicate asset if we are completely out of items in this slot
	if slot_is_empty and is_instance_valid(hand_item): 
		hand_item.queue_free()
	
	var drop_pos = hand.global_position
	var drop_rot = hand.global_rotation
	if interact_cast.is_colliding():
		var target_col = interact_cast.get_collider()
		if target_col.is_in_group("placeable") and item.is_in_group("choppable"):
			drop_pos = target_col.global_position + Vector3(0, 0.5, 0); drop_rot = Vector3.ZERO 
	
	# Force visibility of the actual dropped node back to true so you see it on the ground
	set_meshes_visible_recursive(item, true)

	item.global_position = drop_pos; item.global_rotation = drop_rot
	item.freeze = false
	var col = item.find_child("CollisionShape3D")
	if col: col.disabled = false
	item.show()
	
	if GameData.connected:
		GDSync.set_gdsync_owner(item, GDSync.get_host())
		GDSync.call_func_all(sync_drop, [item.get_path(), drop_pos, drop_rot])
	update_hand_visuals(); update_inventory_ui()
	
func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.freeze = false
		var col = object.find_child("CollisionShape3D")
		if col: col.disabled = false
		object.global_position = params[1]; object.global_rotation = params[2]
		object.show()

# Recursive Helper to drill down into objects (like food items pinned onto a plate node)
func set_meshes_visible_recursive(node: Node, visible_state: bool) -> void:
	if not is_instance_valid(node): return
	if node is MeshInstance3D:
		node.visible = visible_state
	for child in node.get_children():
		set_meshes_visible_recursive(child, visible_state)

func _on_pickup_timer_timeout() -> void: can_pickup = true
