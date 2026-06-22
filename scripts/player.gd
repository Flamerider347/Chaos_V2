extends CharacterBody3D

var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = false
var is_owned: bool = false
var speed_multiplier: float = 1.0
var held_item = null
var can_pickup: bool = true
var current_slot: String = "1"
var holding_two_handed: bool = false
var changed_slot = false

var inventory: Dictionary = {
	"1": [null, 0, null, []],
	"2": [null, 0, null, []],
	"3": [null, 0, null, []],
	"4": [null, 0, null, []]
}

var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 3.0
const GRAVITY: float = 9.8
var mouse_sensitivity: float = 0.003
var held_object_amount = 0

@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/loading")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider: Slider = get_node_or_null("/root/main/Pause_UI/sensitivity")
@onready var main_game_ui = get_node_or_null("/root/main/UI")
@onready var pause_menu_ui = get_node_or_null("/root/main/Pause_UI")


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
			if main_game_ui: main_game_ui.hide()
			if pause_menu_ui: pause_menu_ui.show()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			if main_game_ui: main_game_ui.show()
			if pause_menu_ui: pause_menu_ui.hide()

	if GameData.paused:
		return

	if event is InputEventMouseMotion:
		rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x - event.relative.y * mouse_sensitivity * 5, -90, 90)


func _physics_process(delta: float) -> void:
	if not is_owned:
		return

	holding_two_handed = false
	if is_instance_valid(held_item):
		if "is_two_handed" in held_item and held_item.is_two_handed:
			holding_two_handed = true
		elif held_item.is_in_group("plate") and "stacked_items" in held_item and held_item.stacked_items.size() > 0:
			holding_two_handed = true

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
		if position.y < -5:
			self.position = Vector3(0,2,0)

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
	else:
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

			if Input.is_action_just_pressed("right_click") and target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable") and not held_item.is_in_group("plate") and can_pickup:
				stack_object(target)
				return

		if Input.is_action_just_pressed("right_click") and inventory[current_slot][2] != null and can_pickup:
			drop_object()

	var vec: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	speed_multiplier = 1.5 if Input.is_action_pressed("sprint") else 1.0

	# 1. Calculate weighted speed and clamp it between 3.0 and 5.0
	# (Subtracting weight from SPEED ensures carrying more items slows you down)
	var weighted_speed: float = SPEED - (held_object_amount * 0.1) 
	weighted_speed = clampf(weighted_speed, 3.0, 5.0) * speed_multiplier
	if holding_two_handed: weighted_speed = 3.0

	var dir: Vector3 = (transform.basis * Vector3(vec.x, 0, vec.y)).normalized()

	if dir:
		# 2. Multiply by our safe, clamped speed
		velocity.x = dir.x * weighted_speed
		velocity.z = dir.z * weighted_speed
	else:
		# 3. Use the clamped speed as the deceleration step so stopping feels natural
		velocity.x = move_toward(velocity.x, 0, weighted_speed)
		velocity.z = move_toward(velocity.z, 0, weighted_speed)

	if not holding_two_handed:
		changed_slot = false
		if Input.is_action_just_pressed("1") and current_slot != "1":
			current_slot = "1"
			changed_slot = true
		elif Input.is_action_just_pressed("2") and current_slot != "2":
			current_slot = "2"
			changed_slot = true
		elif Input.is_action_just_pressed("3") and current_slot != "3":
			current_slot = "3"
			changed_slot = true
		elif Input.is_action_just_pressed("4") and current_slot != "4":
			current_slot = "4"
			changed_slot = true

		if changed_slot:
			if is_instance_valid(held_item):
				held_item.hide()
			held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
			rpc("sync_active_slot", current_slot)

	var slot_node = hand.find_child("slot" + current_slot)
	var is_snapping: bool = false

	if is_instance_valid(held_item) and inventory[current_slot][3].has(held_item) and is_instance_valid(target):
		if target.is_in_group("placeable"):
			if target.is_in_group("chopping_board") and held_item.is_in_group("choppable"):
				held_item.global_position = target.global_position + Vector3(0, 1.2, 0)
				held_item.global_rotation = Vector3.ZERO
				is_snapping = true
			elif target.is_in_group("THE_THING"):
				held_item.global_position = target.global_position + Vector3(0, 0.2, 0)
				held_item.global_rotation = Vector3.ZERO
				is_snapping = true
			elif target.is_in_group("delivery_area"):
				held_item.global_position = target.global_position + Vector3(0, 0.2, 0)
				held_item.global_rotation = Vector3.ZERO
				is_snapping = true
			elif not target.is_in_group("chopping_board") and held_item.is_in_group("meat"):
				held_item.global_position = target.global_position + Vector3(0, 0.4, 0)
				held_item.global_rotation = Vector3.ZERO
				is_snapping = true
		elif target.is_in_group("plate") and held_item.is_in_group("plate_stackable"):
			var y_stack_height = target.calculate_stack_height() + 0.1
			held_item.global_position = target.global_position + Vector3(0, y_stack_height, 0)
			held_item.global_rotation = Vector3.ZERO
			is_snapping = true
	if is_instance_valid(held_item):
		held_item.visible = is_snapping
		
		if "stacked_items" in held_item:
			for stacked_item in held_item.stacked_items:
				if is_instance_valid(stacked_item):
					stacked_item.visible = is_snapping

		if not is_snapping:
			held_item.global_position = hand.global_position
			held_item.global_rotation = hand.global_rotation
		else:
			if "stacked_items" in held_item:
				if is_instance_valid(slot_node) and slot_node.get_child_count() > 0:
					var visual_plate = slot_node.get_child(0)
					if is_instance_valid(visual_plate):
						for idx in range(held_item.stacked_items.size()):
							var stacked_item = held_item.stacked_items[idx]
							if is_instance_valid(stacked_item) and visual_plate.get_child_count() > idx:
								var visual_item = visual_plate.get_child(idx)
								stacked_item.global_transform = held_item.global_transform * visual_item.transform

	if is_instance_valid(slot_node):
		var target_visibility = not is_snapping
		if slot_node.visible != target_visibility:
			slot_node.visible = target_visibility
			rpc("sync_hand_slot_visibility", current_slot, target_visibility)
	move_and_slide()


func pickup_object(object):
	var picked_up = 0
	for i in inventory.keys():
		if inventory[i][2] == null:
			inventory[i][1] += 1
			inventory[i][2] = object.type
			inventory[i][3].append(object)
			picked_up = i
			break
		elif inventory[i][2] == object.type:
			inventory[i][1] += 1
			inventory[i][3].append(object)
			picked_up = i
			break

	if int(picked_up) != 0:
		held_object_amount += 1
		object.freeze = true
		var shape: CollisionShape3D = object.find_child("CollisionShape3D")
		if shape:
			shape.disabled = true
		object.hide()

		if "stacked_items" in object:
			for stacked_item in object.stacked_items:
				if is_instance_valid(stacked_item):
					stacked_item.freeze = true
					var s_shape: CollisionShape3D = stacked_item.find_child("CollisionShape3D")
					if s_shape: 
						s_shape.disabled = true
					stacked_item.hide()

		if inventory[picked_up][1] <= 1:
			rpc("sync_hand_item_added", str(picked_up), str(object.get_path()))
				
		current_slot = picked_up
		held_item = inventory[picked_up][3][-1]
		
		rpc("sync_active_slot", str(current_slot))
		update_inventory_ui()

		if multiplayer.is_server():
			notify_item_hidden(str(object.get_path()), true, multiplayer.get_unique_id())
		else:
			rpc_id(1, "notify_item_hidden", str(object.get_path()), true, multiplayer.get_unique_id())


func drop_object():
	if inventory[current_slot][2] == null or inventory[current_slot][3].is_empty():
		return

	inventory[current_slot][1] -= 1
	held_object_amount -= 1
	var dropped = inventory[current_slot][3].pop_back()
	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null

	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
		rpc("sync_hand_item_removed", str(current_slot))

	update_inventory_ui()

	var drop_pos: Vector3 = hand.global_position

	if interact_cast.is_colliding():
		var col = interact_cast.get_collider()
		if is_instance_valid(col) and col.is_in_group("placeable"):
			if col.is_in_group("chopping_board") and dropped.is_in_group("choppable"):
				drop_pos = col.global_position + Vector3(0, 1.2, 0)
			elif col.is_in_group("THE_THING"):
				drop_pos = col.global_position + Vector3(0, 0.2, 0)
				if dropped.is_in_group("storable"):
					dropped.set_collision_layer_value(3,false)
			elif col.is_in_group("delivery_area"):
				drop_pos = col.global_position + Vector3(0, 0.2, 0)
			elif not col.is_in_group("chopping_board") and dropped.is_in_group("meat"):
				drop_pos = col.global_position + Vector3(0, 0.4, 0)

	dropped.global_position = drop_pos
	dropped.global_rotation = Vector3.ZERO
	dropped.show()
	dropped.freeze = false
	var shape: CollisionShape3D = dropped.find_child("CollisionShape3D")
	if shape:
		shape.disabled = false

	if "stacked_items" in dropped:
		var slot_node = find_child("slot" + str(current_slot))
		if is_instance_valid(slot_node) and slot_node.get_child_count() > 0:
			var visual_plate = slot_node.get_child(0)
			if is_instance_valid(visual_plate):
				for idx in range(dropped.stacked_items.size()):
					var stacked_item = dropped.stacked_items[idx]
					if is_instance_valid(stacked_item) and visual_plate.get_child_count() > idx:
						var visual_item = visual_plate.get_child(idx)
						stacked_item.global_transform = dropped.global_transform * visual_item.transform
						stacked_item.show()
						stacked_item.freeze = true 
						var s_shape: CollisionShape3D = stacked_item.find_child("CollisionShape3D")
						if s_shape: 
							s_shape.disabled = true

	if multiplayer.is_server():
		notify_item_dropped(str(dropped.get_path()), drop_pos, multiplayer.get_unique_id())
	else:
		rpc_id(1, "notify_item_dropped", str(dropped.get_path()), drop_pos, multiplayer.get_unique_id())


func stack_object(plate: Node3D) -> void:
	if not is_instance_valid(held_item):
		return

	if held_item.is_in_group("pickupable"):
		held_item.remove_from_group("pickupable")
	held_item.freeze = true
	var shape: CollisionShape3D = held_item.find_child("CollisionShape3D")
	if shape: 
		shape.disabled = true

	plate.stack_item(held_item)
	can_pickup = false
	$pickup_timer.start()
	inventory[current_slot][3].erase(held_item)
	inventory[current_slot][1] -= 1
	held_object_amount -= 1
	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
		rpc("sync_hand_item_removed", str(current_slot))

	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	update_inventory_ui()


@rpc("any_peer", "call_local", "reliable")
func sync_active_slot(slot_key: String) -> void:
	current_slot = slot_key
	for i in hand.get_children():
		i.hide()
	var slot_node = hand.find_child("slot" + current_slot)
	if is_instance_valid(slot_node):
		slot_node.show()


@rpc("any_peer", "call_local", "reliable")
func sync_hand_item_added(slot_key: String, item_path: String) -> void:
	var world_object = get_node_or_null(item_path)
	var slot_node = hand.find_child("slot" + slot_key)
	
	if is_instance_valid(world_object) and is_instance_valid(slot_node):
		for child in slot_node.get_children():
			child.queue_free()
			
		var duplicate_mesh = world_object.duplicate()
		
		for child in duplicate_mesh.get_children():
			if child is MultiplayerSynchronizer or child is MultiplayerSpawner or child is RemoteTransform3D:
				child.free()
		
		_strip_network_nodes(duplicate_mesh)
		
		slot_node.add_child(duplicate_mesh)
		duplicate_mesh.position = Vector3.ZERO
		duplicate_mesh.rotation = Vector3.ZERO
		duplicate_mesh.show()
		
		if "stacked_items" in world_object:
			for stacked_item in world_object.stacked_items:
				if is_instance_valid(stacked_item):
					var item_copy = stacked_item.duplicate()
					
					for s_child in item_copy.get_children():
						if s_child is MultiplayerSynchronizer or s_child is MultiplayerSpawner or s_child is RemoteTransform3D:
							s_child.free()
							
					_strip_network_nodes(item_copy)
					duplicate_mesh.add_child(item_copy)
					
					var rel_transform = world_object.global_transform.affine_inverse() * stacked_item.global_transform
					item_copy.transform = rel_transform
					item_copy.show()


@rpc("any_peer", "call_local", "reliable")
func sync_hand_item_removed(slot_key: String) -> void:
	var slot_node = hand.find_child("slot" + slot_key)
	if is_instance_valid(slot_node):
		for child in slot_node.get_children():
			child.queue_free()


@rpc("any_peer", "reliable")
func notify_item_hidden(item_path: String, hidden: bool, sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	rpc("sync_item_hidden", item_path, hidden, sender_id)


@rpc("any_peer", "call_local", "reliable")
func sync_item_hidden(item_path: String, hidden: bool, sender_id: int) -> void:
	if multiplayer.get_unique_id() == sender_id:
		return
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item):
		return
	item.visible = not hidden
	item.freeze = hidden
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape:
		shape.disabled = hidden

	if "stacked_items" in item:
		for stacked_item in item.stacked_items:
			if is_instance_valid(stacked_item):
				stacked_item.visible = not hidden
				stacked_item.freeze = hidden
				var s_shape: CollisionShape3D = stacked_item.find_child("CollisionShape3D")
				if s_shape: 
					s_shape.disabled = hidden


@rpc("any_peer", "reliable")
func notify_item_dropped(item_path: String, drop_pos: Vector3, sender_id: int) -> void:
	if not multiplayer.is_server():
		return
	var item = get_node_or_null(item_path)
	if is_instance_valid(item):
		item.global_position = drop_pos
		item.global_rotation = Vector3.ZERO
		item.visible = true
		item.freeze = false
		var shape: CollisionShape3D = item.find_child("CollisionShape3D")
		if shape:
			shape.disabled = false

	rpc("sync_item_dropped", item_path, drop_pos, sender_id)


@rpc("any_peer", "call_local", "reliable")
func sync_item_dropped(item_path: String, drop_pos: Vector3, sender_id: int) -> void:
	if multiplayer.get_unique_id() == sender_id:
		return
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item):
		return
		
	var relative_transforms = []
	if "stacked_items" in item:
		for stacked_item in item.stacked_items:
			if is_instance_valid(stacked_item):
				relative_transforms.append(item.global_transform.affine_inverse() * stacked_item.global_transform)

	item.global_position = drop_pos
	item.global_rotation = Vector3.ZERO
	item.visible = true
	item.freeze = false
	var shape: CollisionShape3D = item.find_child("CollisionShape3D")
	if shape:
		shape.disabled = false

	if "stacked_items" in item:
		for idx in range(item.stacked_items.size()):
			var stacked_item = item.stacked_items[idx]
			if is_instance_valid(stacked_item) and idx < relative_transforms.size():
				if stacked_item.is_in_group("pickupable"):
					stacked_item.remove_from_group("pickupable")
				stacked_item.global_transform = item.global_transform * relative_transforms[idx]
				stacked_item.visible = true
				stacked_item.freeze = true 
				var s_shape: CollisionShape3D = stacked_item.find_child("CollisionShape3D")
				if s_shape: 
					s_shape.disabled = true 


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
			var item_type_string: String = str(item_type)
			var last_item: Node3D = inventory[s][3][-1] if inventory[s][3].size() > 0 else null

			if item_type_string == "plate" and is_instance_valid(last_item) and "stacked_items" in last_item and last_item.stacked_items.size() > 0:
				var contents: Array = []
				for item in last_item.stacked_items:
					if is_instance_valid(item):
						contents.append(item.type.capitalize())
				lbl.text = "%s\nPlate with %s" % [s, ", ".join(contents)]
			else:
				var multiplier_text: String = " x" + str(count) if count > 1 else ""
				lbl.text = "%s\n%s%s" % [s, item_type_string.capitalize(), multiplier_text]
		else:
			lbl.text = "%s\nEmpty" % s

		lbl.scale = Vector2(1.15, 1.15) if str(s) == current_slot else Vector2(1.0, 1.0)


@rpc("any_peer", "call_local", "unreliable")
func sync_hand_slot_visibility(slot_key: String, item_is_visible: bool) -> void:
	var slot_node = hand.find_child("slot" + slot_key)
	if is_instance_valid(slot_node):
		slot_node.visible = item_is_visible


func _strip_network_nodes(node: Node) -> void:
	if node is MultiplayerSynchronizer:
		node.public_visibility = false
		node.set_process(false)
		node.set_physics_process(false)
		
	if node is MultiplayerSpawner or node is RemoteTransform3D:
		node.set_process(false)
		node.set_physics_process(false)

	if node is RigidBody3D:
		node.freeze = true
		node.gravity_scale = 0.0
		node.collision_layer = 0
		node.collision_mask = 0
		node.process_mode = Node.PROCESS_MODE_DISABLED 

	if node is CollisionShape3D:
		node.disabled = true

	for child in node.get_children():
		_strip_network_nodes(child)


func _set_mesh_outline(node: Node, active: bool) -> void:
	if node is MeshInstance3D:
		node.material_overlay = outline_material if active else null
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
	held_item = null
	update_inventory_ui()


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
