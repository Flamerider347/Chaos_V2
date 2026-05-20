extends CharacterBody3D

var is_owned: bool = false
var held_item: RigidBody3D = null  
var hand_item = null
var can_pickup = true
var current_slot = "1"

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
var mouse_sensitivity = 0.003

var inventory = {
	"1" : ["triangle", 0, null, []],
	"2" : ["triangle", 0, null, []],
	"3" : ["triangle", 0, null, []],
	"4" : ["triangle", 0, null, []],
}

@onready var interact_cast : RayCast3D = $head/interact_cast
@onready var hand = $hand
@onready var pickup_timer = $pickup_timer

func _ready() -> void:
	add_to_group("player")
	for i in inventory:
		inventory[i][0] = get_node("/root/main/UI/item_slots/slot" + str(i))
		
	GDSync.expose_node(self)
	GDSync.expose_func(sync_drop)
	GDSync.expose_func(sync_hand_visual) # Exposed for holding visibility
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	
	is_owned = false
	if not GameData.connected:
		is_owned = true
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	update_inventory_ui()

func owner_changed(_owner_id: int) -> void:
	is_owned = GDSync.is_gdsync_owner(self)
	if is_owned:
		if is_instance_valid($head/camera):
			$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if is_instance_valid($head/camera):
			$head/camera.queue_free()

func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused: return
	if event is InputEventMouseMotion:
		self.rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x += -event.relative.y * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)

func _physics_process(_delta: float) -> void:
	mouse_sensitivity = get_node("/root/main/Pause_UI/sensitivity").value
	if not is_owned: return
	
	if GameData.paused:
		velocity.x = 0; velocity.z = 0
		if not is_on_floor(): velocity.y -= GRAVITY * _delta
		move_and_slide(); return

	if not is_on_floor(): velocity.y -= GRAVITY * _delta

	var current_held = held_item
	if current_held != null and is_instance_valid(current_held):
		if interact_cast.is_colliding():
			var collider = interact_cast.get_collider()
			if is_instance_valid(collider):
				if collider.is_in_group("placeable") and current_held.is_in_group("choppable"):
					current_held.global_position = collider.global_position + Vector3(0, 0.5, 0)
					current_held.show()
				elif collider.is_in_group("plate") and current_held.is_in_group("plate_stackable") and "calculate_stack_height" in collider:
					current_held.global_position = collider.global_position + Vector3(0, collider.calculate_stack_height(), 0)
					current_held.show()
				else: current_held.hide()
			else: current_held.hide()
		else: current_held.hide()
	else:
		held_item = null; hand_item = null

	if not GameData.paused:
		handle_inventory_slots()
		handle_interactions()
		handle_movement()
	move_and_slide()

func handle_inventory_slots():
	if held_item and is_instance_valid(held_item) and held_item.is_in_group("plate"): return 
	var change_slot = false
	if Input.is_action_just_pressed("1") and current_slot != "1": current_slot = "1"; change_slot = true
	elif Input.is_action_just_pressed("2") and current_slot != "2": current_slot = "2"; change_slot = true
	elif Input.is_action_just_pressed("3") and current_slot != "3": current_slot = "3"; change_slot = true
	elif Input.is_action_just_pressed("4") and current_slot != "4": current_slot = "4"; change_slot = true
	if change_slot: update_hand_visuals(); update_inventory_ui()

func update_hand_visuals():
	for slot_node in hand.get_children():
		for child in slot_node.get_children(): child.queue_free()
		slot_node.hide()

	var active_slot_node = hand.find_child("slot" + current_slot)
	if active_slot_node: active_slot_node.show()

	var current_stack = inventory[current_slot][3]
	if current_stack.size() > 0:
		var visual_target = current_stack[-1] 
		if is_instance_valid(visual_target):
			var duplicate_visual = visual_target.duplicate()
			if active_slot_node: active_slot_node.add_child(duplicate_visual)
			duplicate_visual.position = Vector3.ZERO
			duplicate_visual.rotation = Vector3.ZERO
			duplicate_visual.show()
			if duplicate_visual is RigidBody3D: duplicate_visual.freeze = true
			var col = duplicate_visual.find_child("CollisionShape3D")
			if col: col.disabled = true
			hand_item = duplicate_visual
			held_item = visual_target
			
			# Network: tell everyone what item type we are holding in this slot
			if GameData.connected:
				GDSync.call_func_all(sync_hand_visual, [visual_target.type, current_slot])
	else:
		hand_item = null; held_item = null
		if GameData.connected:
			GDSync.call_func_all(sync_hand_visual, ["", current_slot])

# Runs on other players' screens to generate the hand item for your puppet model
func sync_hand_visual(params: Array) -> void:
	if is_owned: return
	var item_type = params[0]
	var slot_id = params[1]
	
	var puppet_slot_node = hand.find_child("slot" + slot_id)
	if not puppet_slot_node: return
	
	for child in puppet_slot_node.get_children(): child.queue_free()
	
	if item_type != "":
		# Find a matching real item in the map to clone for visual display purposes
		for map_node in get_tree().get_nodes_in_group("pickupable"):
			if "type" in map_node and map_node.type == item_type:
				var visual_clone = map_node.duplicate()
				puppet_slot_node.add_child(visual_clone)
				visual_clone.position = Vector3.ZERO
				visual_clone.rotation = Vector3.ZERO
				if visual_clone is RigidBody3D: visual_clone.freeze = true
				var col = visual_clone.find_child("CollisionShape3D")
				if col: col.disabled = true
				visual_clone.show()
				break

func update_inventory_ui():
	for i in inventory:
		var slot_label = inventory[i][0]
		if not is_instance_valid(slot_label): continue
		var item_type = inventory[i][2]
		var quantity = inventory[i][1]
		var item_stack = inventory[i][3]
		
		if item_type != null and quantity > 0:
			if item_type == "plate" and item_stack.size() > 0:
				var top_plate = item_stack[-1]
				if is_instance_valid(top_plate) and top_plate.stacked_items.size() > 0:
					var contents_names = []
					for item in top_plate.stacked_items:
						if is_instance_valid(item): contents_names.append(item.type if "type" in item else item.name)
					slot_label.text = str(i) + "\n" + str(item_type) + " (" + ", ".join(contents_names) + ") (" + str(quantity) + ")"
				else: slot_label.text = str(i) + "\n" + str(item_type) + " (" + str(quantity) + ")"
			else: slot_label.text = str(i) + "\n" + str(item_type) + " (" + str(quantity) + ")"
		else: slot_label.text = str(i) + "\nempty"
		
		slot_label.scale = Vector2(1.2, 1.2) if str(i) == current_slot else Vector2(1.0, 1.0)
		slot_label.z_index = 1 if str(i) == current_slot else 0

func handle_interactions():
	if Input.is_action_just_pressed("ui_accept") and is_on_floor(): velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("left_click") and interact_cast.is_colliding():
		var collider = interact_cast.get_collider()
		if collider.is_in_group("punchable"): collider._on_punched()
		elif collider.is_in_group("pickupable") and can_pickup: pickup_object(collider)
		elif collider.is_in_group("door"): collider.open_door()

	if Input.is_action_just_pressed("right_click"):
		if interact_cast.is_colliding():
			var collider = interact_cast.get_collider()
			if collider.is_in_group("plate") and held_item != null and held_item.is_in_group("plate_stackable"):
				stack_object(collider)
				return
		if inventory[current_slot][2] != null and can_pickup: drop_object()

func handle_movement():
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED; velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED); velocity.z = move_toward(velocity.z, 0, SPEED)

func pickup_object(object):
	var picked_up = false
	for i in inventory:
		if inventory[i][2] == object.type or inventory[i][2] == null:
			inventory[i][2] = object.type; inventory[i][1] += 1; inventory[i][3].append(object)
			current_slot = str(i); picked_up = true; break
	if picked_up:
		can_pickup = false; pickup_timer.start()
		object.freeze = true
		var col = object.find_child("CollisionShape3D")
		if col: col.disabled = true
		object.hide()
		
		# JOLT FIX: Teleport the hidden item out of player collision range immediately
		object.global_position = Vector3(0, -50, 0)
		object.global_rotation = Vector3.ZERO
		
		if GameData.connected: GDSync.set_gdsync_owner(object, GDSync.get_client_id())
		update_hand_visuals(); update_inventory_ui()

func stack_object(plate):
	var item_to_stack = held_item
	held_item = null; hand_item = null
	inventory[current_slot][3].erase(item_to_stack)
	inventory[current_slot][1] -= 1
	if inventory[current_slot][1] <= 0: inventory[current_slot][2] = null
	
	plate.stack_item(item_to_stack)
	update_hand_visuals(); update_inventory_ui()

func drop_object():
	if not inventory[current_slot][2]: return
	var item_to_drop = inventory[current_slot][3].pop_back()
	inventory[current_slot][1] -= 1
	if inventory[current_slot][1] <= 0: inventory[current_slot][2] = null
	
	can_pickup = false; pickup_timer.start()
	var drop_pos = hand.global_position
	var drop_rot = hand.global_rotation
	if interact_cast.is_colliding():
		var collider = interact_cast.get_collider()
		if collider.is_in_group("placeable") and item_to_drop.is_in_group("choppable"):
			drop_pos = collider.global_position + Vector3(0, 0.5, 0); drop_rot = Vector3.ZERO 
	
	item_to_drop.global_position = drop_pos; item_to_drop.global_rotation = drop_rot
	item_to_drop.freeze = false
	var col = item_to_drop.find_child("CollisionShape3D")
	if col: col.disabled = false
	item_to_drop.show()
	
	if GameData.connected:
		GDSync.set_gdsync_owner(item_to_drop, GDSync.get_host())
		GDSync.call_func_all(sync_drop, [item_to_drop.get_path(), drop_pos, drop_rot])
	update_hand_visuals(); update_inventory_ui()
	
func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.freeze = false
		var col = object.find_child("CollisionShape3D")
		if col: col.disabled = false
		if params.size() > 2:
			object.global_position = params[1]; object.global_rotation = params[2]
		object.show()

func _on_pickup_timer_timeout() -> void: can_pickup = true
