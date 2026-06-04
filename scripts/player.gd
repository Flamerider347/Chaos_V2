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
var held_item = null
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
	if is_instance_valid(held_item) and held_item.get_multiplayer_authority() == multiplayer.get_unique_id():
		held_item.global_position = hand.global_position
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

#Pickup/put down stuff

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


#Movement Stuff

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

#Inventory slots

	if holding_two_handed:
		return 
	var changed_slot = false
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
		held_item = inventory[current_slot][3][0]
		for i in hand.get_children():
			i.hide()
		hand.find_child("slot" + str(current_slot)).show()

	move_and_slide()

func pickup_object(object):
	var picked_up = 0
	for i in inventory.keys():
		print(inventory[i][2])
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
		update_inventory_ui()
		object.freeze = true
		object.set_multiplayer_authority(multiplayer.get_unique_id())
		var shape: CollisionShape3D = object.find_child("CollisionShape3D")
		if shape:
			shape.disabled = true
		object.hide()
		if inventory[picked_up][1] <= 1:
			var object_2 = object.duplicate()
			for child in object_2.get_children():
				if child is MultiplayerSynchronizer:
					child.queue_free()
			find_child("slot"+str(picked_up)).add_child(object_2)
			object_2.show()
			object_2.position = Vector3.ZERO
			object_2.rotation = Vector3.ZERO

func drop_object():
	var dropped = null
	if inventory[current_slot][2] == null:
		return
	if inventory[current_slot][2]:
		if inventory[current_slot][3].size() >=1:
			inventory[current_slot][1] -= 1
			dropped = inventory[current_slot][3][-1]
			inventory[current_slot][3].erase(dropped)
	if dropped != null:
		update_inventory_ui()
		dropped.set_multiplayer_authority(1)
		dropped.freeze = false
		var shape: CollisionShape3D = dropped.find_child("CollisionShape3D")
		if shape:
			shape.disabled = false
		dropped.global_position = hand.global_position
		dropped.global_rotation = Vector3.ZERO
		dropped.show()
		if inventory[current_slot][1] <1:
			inventory[current_slot][2] = null
			for i in find_child("slot" +str(current_slot)).get_children():
				i.queue_free()

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
