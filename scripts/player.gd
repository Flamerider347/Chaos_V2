extends CharacterBody3D

var health: float = 100.0
var max_health: float = 100.0
var is_dead: bool = false
var is_in_kitchen: bool = false
var is_owned: bool = false
var last_outline_was_valid: bool = true

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 3.5
const GRAVITY: float = 9.8
const STACK_LIMIT: int = 3 # Max items per slot

var mouse_sensitivity: float = 0.003
var speed_multiplier: float = 1.0

var held_item = null
var held_object_amount: int = 0
var can_pickup: bool = true
var current_slot: String = "1"
var holding_two_handed: bool = false

var inventory: Dictionary = {
	"1": [null, 0, null, []],
	"2": [null, 0, null, []],
	"3": [null, 0, null, []],
	"4": [null, 0, null, []]
}
var ui_slot_icons: Dictionary = {}

@onready var slot_icons = {
	"tomato" : preload("res://Assets/2D art/food icons/foodicons_tomato.png"),
	#"tomato_chopped" : preload("res://Assets/2D art/food icons/foodicons_tomato.png"),
	"carrot" : preload("res://Assets/2D art/food icons/foodicons_carrot.png"),
	#"carrot_chopped" : preload("res://Assets/2D art/food icons/foodicons_carrot.png"),
	"meat" : preload("res://Assets/2D art/food icons/foodicons_raw-patty.png"),
	"meat_cooked" : preload("res://Assets/2D art/food icons/foodicons_patty.png"),
	#"meat_burnt" : preload("res://Assets/2D art/food icons/foodicons_patty.png"),
	"cheese" : preload("res://Assets/2D art/food icons/foodicons_cheese.png"),
	#"cheese_chopped" : preload("res://Assets/2D art/food icons/foodicons_cheese.png"),
	"bun" : preload("res://Assets/2D art/food icons/foodicons_bun.png")
}

var last_highlighted_target: Node3D = null
var outline_material: Material = preload("res://Assets/misc/outline_shader.tres")

@onready var interact_cast: RayCast3D = $head/interact_cast
@onready var interact_cast2: RayCast3D = $head/interact_cast2
@onready var hand: Node3D = $hand
@onready var pickup_timer: Timer = $pickup_timer
@onready var username_label: Label3D = $username

@onready var main_node = get_node_or_null("/root/main")
@onready var ui_colliding_label: Label = get_node_or_null("/root/main/UI/loading")
@onready var ui_healthbar = get_node_or_null("/root/main/UI/healthbar")
@onready var ui_sensitivity_slider: Slider = get_node_or_null("/root/main/Pause_UI/sensitivity")
@onready var main_game_ui = get_node_or_null("/root/main/UI")
@onready var pause_menu_ui = get_node_or_null("/root/main/Pause_UI")


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
		
	global_position = Vector3(randf_range(6,4), 1, randf_range(4,-4))
	update_inventory_ui()


func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused: return
	
	if event is InputEventMouseMotion:
		rotation_degrees.y -= event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x - event.relative.y * mouse_sensitivity * 5, -90, 90)


func _physics_process(delta: float) -> void:
	if not is_owned: return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		if position.y < -5: position = Vector3(0, 2, 0)
		
	if is_instance_valid(held_item) and held_item.get("type") == "flashlight":
		held_item.using = true
		held_item.drain_battery(delta)
		var item_label = get_node_or_null("/root/main/UI/item_slots/slot" + str(current_slot) + "/item")
		item_label.text = "Flashlight " + str(int(held_item.charge)) + "%"
		
		
		rpc("sync_flashlight_state", current_slot, held_item.charge, held_item.is_active())

	if GameData.paused:
		velocity.x = 0; velocity.z = 0
		move_and_slide()
		return
		
	_update_states(delta)
	_handle_slot_switching()
	
	var item_target = interact_cast.get_collider() if interact_cast.is_colliding() else null
	var surface_target = interact_cast2.get_collider() if interact_cast2.is_colliding() else null
	var active_target = item_target if is_instance_valid(item_target) else surface_target
	
	_update_outline(active_target)
	_handle_interactions(item_target, surface_target)
	_handle_snapping(surface_target)
	_handle_movement()


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
	if Input.is_action_pressed("jump") and is_on_floor(): velocity.y = JUMP_VELOCITY
	
	var vec: Vector2 = Input.get_vector("left", "right", "forward", "backwards")
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


func _handle_interactions(item_target: Node3D, surface_target: Node3D) -> void:
	if holding_two_handed and Input.is_action_just_pressed("right_click"):
		drop_object(surface_target)
		return
		
	if Input.is_action_just_pressed("left_click") and not holding_two_handed:
		if is_instance_valid(item_target):
			if item_target.is_in_group("punchable"): item_target._on_punched()
			elif item_target.is_in_group("pickupable") and can_pickup: pickup_object(item_target)
		elif is_instance_valid(surface_target):
			if surface_target.is_in_group("difficulty_button") and not GameData.closed_lobby:
				rpc("change_difficulty",str(surface_target.name))
			elif surface_target.is_in_group("storage_button"): surface_target.spawn_item.emit(surface_target.name)
			elif surface_target.is_in_group("door"): surface_target.open_door()
			elif surface_target.is_in_group("computer") and not GameData.using_computer and GameData.closed_lobby: computer_UI()
		
	if Input.is_action_just_pressed("right_click"):
		var plate_target = surface_target if is_instance_valid(surface_target) and surface_target.is_in_group("plate") else item_target
		
		if is_instance_valid(surface_target) and surface_target.is_in_group("drop_all"):
			surface_target.get_parent().drop_all(self)
		elif is_instance_valid(plate_target) and plate_target.is_in_group("plate") and is_instance_valid(held_item) and held_item.is_in_group("plate_stackable") and not held_item.is_in_group("plate") and can_pickup:
			stack_object(plate_target)
		elif current_slot != "0" and inventory[current_slot][2] != null and can_pickup:
			drop_object(surface_target)


func computer_UI() -> void:
	if is_instance_valid(main_node):
		var comp_ui = main_node.get_node_or_null("computer_UI")
		if comp_ui: comp_ui.show()
		if pause_menu_ui: pause_menu_ui.hide()
		if main_game_ui: main_game_ui.hide()
		GameData.paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		rpc("broadcast_using_computer")
		main_node.update_UI()

@rpc ("any_peer","call_local","reliable")
func change_difficulty(difficulty):
	GameData.difficulty = difficulty.to_lower().to_snake_case()
	print(GameData.difficulty)
	get_node("/root/main/game/world/kitchen/main_kitchen/appliances/current_difficulty/difficulty").text = difficulty
	get_node("/root/main/game/world/kitchen/main_kitchen/appliances/current_difficulty").material = get_node("/root/main/game/world/kitchen/main_kitchen/appliances/difficulty_table").find_child(difficulty).material

@rpc("any_peer", "call_local", "reliable")
func broadcast_using_computer() -> void:
	GameData.using_computer = true
	if is_instance_valid(main_node):
		var in_use_sign = main_node.get_node_or_null("game/world/kitchen/main_kitchen/appliances/Computer/in_use")
		if in_use_sign: in_use_sign.show()


func leave_computer_UI() -> void:
	if is_instance_valid(main_node):
		var comp_ui = main_node.get_node_or_null("computer_UI")
		if comp_ui: comp_ui.hide()
	GameData.paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _handle_snapping(surface_target: Node3D) -> void:
	if current_slot == "0" or not is_instance_valid(held_item): return
	
	var visual_slot = hand.find_child("slot" + current_slot)
	if not is_instance_valid(visual_slot): return
	
	var visual_item = visual_slot.get_child(0) if visual_slot.get_child_count() > 0 else null
	var is_snapping = false
	
	if is_instance_valid(visual_item) and is_instance_valid(surface_target):
		var snap_offset = Vector3.ZERO
		
		if surface_target.is_in_group("placeable") or surface_target.is_in_group("storage_hopper") or surface_target.is_in_group("THE_THING") or surface_target.is_in_group("chopping_board"):
			if surface_target.is_in_group("chopping_board") and held_item.is_in_group("choppable"): 
				snap_offset = Vector3(0, 1.2, 0)
			elif surface_target.is_in_group("storage_hopper") or surface_target.is_in_group("THE_THING") or surface_target.is_in_group("delivery_area"): 
				snap_offset = Vector3(0, 0.2, 0)
			elif not surface_target.is_in_group("chopping_board") and held_item.is_in_group("meat"): 
				snap_offset = Vector3(0, 0.4, 0)
		elif surface_target.is_in_group("plate") and held_item.is_in_group("plate_stackable"):
			var col_shape = surface_target.find_child("CollisionShape3D")
			var height_offset = col_shape.shape.height + 0.1 if is_instance_valid(col_shape) and "height" in col_shape.shape else 0.2
			snap_offset = Vector3(0, height_offset, 0)
			
		if snap_offset != Vector3.ZERO:
			visual_item.global_position = surface_target.global_position + snap_offset
			visual_item.global_rotation = surface_target.global_rotation
			is_snapping = true
			
	if is_instance_valid(visual_item) and not is_snapping:
		visual_item.position = Vector3.ZERO
		visual_item.rotation = Vector3.ZERO


func _handle_slot_switching() -> void:
	if holding_two_handed: return
	
	var pressed_slot = current_slot
	if Input.is_action_just_pressed("1"): pressed_slot = "1"
	elif Input.is_action_just_pressed("2"): pressed_slot = "2"
	elif Input.is_action_just_pressed("3"): pressed_slot = "3"
	elif Input.is_action_just_pressed("4"): pressed_slot = "4"
	
	if pressed_slot != current_slot: current_slot = pressed_slot
	elif pressed_slot != "0" and Input.is_action_just_pressed(pressed_slot): current_slot = "0"
	
	if current_slot != "0": held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	else: held_item = null
	
	if Input.is_action_just_pressed("1") or Input.is_action_just_pressed("2") or Input.is_action_just_pressed("3") or Input.is_action_just_pressed("4"):
		rpc("sync_active_slot", current_slot)
		update_inventory_ui()


func pickup_object(object: Node3D) -> void:
	if not is_instance_valid(object): return
	var plate_fix = false
	if object.get("type") == "plate" and object.get("stacked_items") != []:
		plate_fix = true
		
	var picked_up = "0"
	var current_limit = get_stack_limit()
	
	for i in inventory.keys():
		if inventory[i][2] == object.get("type") and inventory[i][1] < current_limit and not plate_fix:
			inventory[i][1] += 1
			inventory[i][3].append(object)
			picked_up = i
			break
			
	if picked_up == "0":
		for i in inventory.keys():
			if inventory[i][2] == null:
				inventory[i][1] += 1
				inventory[i][2] = object.get("type")
				inventory[i][3].append(object)
				picked_up = i
				
				# UPDATE ICON OR FALLBACK LABEL
				var item_label = get_node_or_null("/root/main/UI/item_slots/slot" + str(picked_up) + "/item")
				if object.get("type") in slot_icons and ui_slot_icons.has(str(i)):
					ui_slot_icons[str(i)].texture = slot_icons[object.get("type")]
					if is_instance_valid(item_label): item_label.text = ""
				else:
					if is_instance_valid(item_label):
						if object.get("type") == "plate":
							item_label.text = _get_plate_display_name(object)
						elif object.type == "flashlight":
							item_label.text = "Flashlight " + str(int(round(object.charge))) + "%"
						else:
							item_label.text = object.type.replace("_", " ").capitalize()
				break

	if picked_up != "0":
		held_object_amount += 1
		if inventory[picked_up][1] <= 1:
			rpc("sync_hand_item_added", picked_up, str(object.get_path()), object.global_transform)
		rpc("sync_world_item_pickup", str(object.get_path()))
		
		if is_in_kitchen:
			current_slot = picked_up
			held_item = inventory[picked_up][3][-1]
		rpc("sync_active_slot", current_slot)
		update_inventory_ui()

func _get_plate_display_name(plate_item: Node3D) -> String:
	if not is_instance_valid(plate_item) or not ("stacked_items" in plate_item):
		return "Plate"

	# Collect raw types directly (e.g., ["bun", "meat_cooked"])
	var raw_contents: Array = []
	for item in plate_item.stacked_items:
		if is_instance_valid(item) and "type" in item:
			raw_contents.append(item.type)

	# 1. Check if the stacked items match a completed recipe
	var rm = get_node_or_null("/root/RecipeManager")
	if is_instance_valid(rm) and rm.has_method("get_matching_recipe"):
		var recipe_name = rm.get_matching_recipe(raw_contents)
		if recipe_name != "":
			return recipe_name

	# 2. Fallback to "Incomplete Order" if items exist on the plate but match no recipe
	if raw_contents.size() > 0:
		return "Incomplete Order"

	return "Plate"
	
	
func drop_object(surface_target: Node3D = null) -> void:
	if current_slot == "0" or inventory[current_slot][2] == null or inventory[current_slot][3].is_empty(): return
	
	var drop_pos: Vector3 = hand.global_position
	if is_instance_valid(surface_target) and "current_cooking_item" in surface_target and surface_target.current_cooking_item != null: return
	
	inventory[current_slot][1] -= 1
	held_object_amount -= 1
	
	var dropped = inventory[current_slot][3].pop_back()
	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	
	if dropped.get("type") == "flashlight":
		dropped.using = false
	
	if inventory[current_slot][1] <= 0:
		inventory[current_slot][2] = null
		if ui_slot_icons.has(str(current_slot)): ui_slot_icons[str(current_slot)].texture = null
		get_node_or_null("/root/main/UI/item_slots/slot" + str(current_slot) + "/item").text = ""
		rpc("sync_hand_item_removed", current_slot)
		
	update_inventory_ui()
	
	if is_instance_valid(surface_target) and (surface_target.is_in_group("placeable") or surface_target.is_in_group("storage_hopper") or surface_target.is_in_group("THE_THING") or surface_target.is_in_group("delivery_area") or surface_target.is_in_group("chopping_board")):
		if surface_target.is_in_group("chopping_board") and dropped.is_in_group("choppable"): 
			drop_pos = surface_target.global_position + Vector3(0, 1.2, 0)
		elif surface_target.is_in_group("storage_hopper") or surface_target.is_in_group("THE_THING") or surface_target.is_in_group("delivery_area"):
			drop_pos = surface_target.global_position + Vector3(0, 0.2, 0)
			if dropped.is_in_group("storable"): 
				dropped.set_collision_layer_value(3, false)
		elif not surface_target.is_in_group("chopping_board") and dropped.is_in_group("meat"): 
			drop_pos = surface_target.global_position + Vector3(0, 0.4, 0)
		
	if multiplayer.is_server(): 
		notify_item_dropped(str(dropped.get_path()), drop_pos)
	else: 
		rpc_id(1, "notify_item_dropped", str(dropped.get_path()), drop_pos)


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
		get_node_or_null("/root/main/UI/item_slots/slot" + str(current_slot) + "/item").text = ""
		if ui_slot_icons.has(str(current_slot)): ui_slot_icons[str(current_slot)].texture = null
		rpc("sync_hand_item_removed", current_slot)
		
	held_item = inventory[current_slot][3][-1] if inventory[current_slot][3].size() > 0 else null
	
	# Update label of the plate being built if it is currently in inventory
	for slot_key in inventory:
		if inventory[slot_key][3].has(plate):
			var item_label = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key) + "/item")
			if is_instance_valid(item_label):
				item_label.text = _get_plate_display_name(plate)
				
	update_inventory_ui()


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


func update_inventory_ui() -> void:
	if not is_owned: return
	
	for s in inventory:
		var lbl: Label = inventory[s][0]
		var count: int = inventory[s][1]
		
		# Update quantity label (displays "x2", "x3", etc., or empty if 1 or less)
		if is_instance_valid(lbl):
			if inventory[s][2] != null and count > 1:
				lbl.text = "x" + str(count)
			else:
				lbl.text = ""
		
		# Update selected slot visual scale
		var slot_node = get_node_or_null("/root/main/UI/item_slots/slot" + str(s))
		if is_instance_valid(slot_node):
			slot_node.scale = Vector2(1.1, 1.1) if str(s) == current_slot else Vector2.ONE


func _setup_ui_slots() -> void:
	for slot_key in inventory:
		var ui_slot = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key) + "/slot_size")
		var ui_slot_texture = get_node_or_null("/root/main/UI/item_slots/slot" + str(slot_key) + "/slot_icon")
		
		if ui_slot_texture:
			ui_slot_texture.texture = null
			ui_slot_icons[str(slot_key)] = ui_slot_texture
			
		if ui_slot: inventory[slot_key][0] = ui_slot


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
	
	for child in node.get_children(): _strip_network_nodes(child)
	
	if node is MultiplayerSynchronizer or node is MultiplayerSpawner or node is RemoteTransform3D:
		node.name = "DELETED_NET_NODE"
		node.queue_free()
		if node.get_parent(): node.get_parent().remove_child(node)
		return
		
	if node is RigidBody3D:
		node.freeze = true
		node.gravity_scale = 0.0
		node.collision_layer = 0
		node.collision_mask = 0
		node.process_mode = Node.PROCESS_MODE_DISABLED
		
	if node is CollisionShape3D: node.disabled = true


func _can_interact_with(target: Node3D) -> bool:
	if not is_instance_valid(target): return false

	var current_limit = get_stack_limit()
	var inventory_has_space = false
	for slot_key in inventory:
		var slot_type = inventory[slot_key][2]
		var count = inventory[slot_key][1]
		if slot_type == null or (target.is_in_group("pickupable") and "type" in target and slot_type == target.type and count < current_limit):
			inventory_has_space = true
			break

	if target.is_in_group("punchable"):
		return not ("item_left" in target and target.item_left <= 0)

	if target.is_in_group("storage_button"):
		if "stored" in target and target.stored <= 0: return false
		if "stock" in target and target.stock <= 0: return false
		return true

	if target.is_in_group("pickupable"):
		return can_pickup and not holding_two_handed and inventory_has_space

	if target.is_in_group("door"): return true

	if target.is_in_group("plate"):
		return is_instance_valid(held_item) and held_item.is_in_group("plate_stackable") and not held_item.is_in_group("plate") and can_pickup

	if not is_instance_valid(held_item): return false

	if target.is_in_group("storage_hopper") or target.is_in_group("THE_THING") or target.is_in_group("delivery_area"):
		return held_item.is_in_group("storable")

	if target.is_in_group("chopping_board"):
		return held_item.is_in_group("choppable")

	if "current_cooking_item" in target or target.is_in_group("stove") or target.is_in_group("cooking_station"):
		if target.get("current_cooking_item") != null: return false
		return held_item.is_in_group("meat")

	return target.is_in_group("placeable")


func _update_outline(target: Node3D) -> void:
	_clear_held_item_outline()

	if is_instance_valid(target):
		var is_valid: bool = _can_interact_with(target)
		var is_empty_hand_target = target.is_in_group("punchable") or target.is_in_group("storage_button") or target.is_in_group("pickupable") or target.is_in_group("door")
		
		if not is_instance_valid(held_item) and not is_empty_hand_target:
			if is_instance_valid(last_highlighted_target):
				_set_mesh_outline(last_highlighted_target, false)
				last_highlighted_target = null
			return

		if target != last_highlighted_target or is_valid != last_outline_was_valid:
			if is_instance_valid(last_highlighted_target):
				_set_mesh_outline(last_highlighted_target, false)
				
			var color: Color = Color.GREEN if is_valid else Color.RED
			var thickness: float = 0.005 if is_valid else 0.012
			_set_mesh_outline(target, true, color, thickness)
			
			last_highlighted_target = target
			last_outline_was_valid = is_valid

		var is_valid_surface = (target.is_in_group("stove") or target.is_in_group("cooking_station") or target.is_in_group("chopping_board") or target.is_in_group("storage_hopper") or target.is_in_group("THE_THING") or target.is_in_group("delivery_area") or target.is_in_group("placeable") or target.is_in_group("plate"))

		if is_valid and is_valid_surface:
			_outline_held_item(true, Color.GREEN)
	else:
		if is_instance_valid(last_highlighted_target):
			_set_mesh_outline(last_highlighted_target, false)
		last_highlighted_target = null


func _set_mesh_outline(node: Node, active: bool, color: Color = Color.GREEN, thickness: float = 0.005) -> void:
	if node.is_in_group("no_outline"): return

	if node is MeshInstance3D:
		if active:
			var mat = outline_material.duplicate()
			mat.set_shader_parameter("outline_color", color)
			mat.set_shader_parameter("outline_thickness", thickness)
			node.material_overlay = mat
		else:
			node.material_overlay = null

	for child in node.get_children():
		_set_mesh_outline(child, active, color, thickness)


func _outline_held_item(active: bool, color: Color = Color.GREEN) -> void:
	if current_slot == "0": return
	var slot_node = hand.find_child("slot" + current_slot)
	if is_instance_valid(slot_node): _set_mesh_outline(slot_node, active, color)


func _clear_held_item_outline() -> void:
	if current_slot == "0": return
	var slot_node = hand.find_child("slot" + current_slot)
	if is_instance_valid(slot_node): _set_mesh_outline(slot_node, false)


func get_stack_limit() -> int:
	var value = GameData.get_upgrade_value("stack_size")
	if value == 0.0:
		return 3
	return int(value)

func _on_pickup_timer_timeout() -> void:
	can_pickup = true


@rpc("any_peer", "call_local", "reliable")
func rpc_pickup_object(item_path: NodePath) -> void:
	var item_node = get_node_or_null(item_path)
	if is_instance_valid(item_node): pickup_object(item_node)


@rpc("any_peer", "call_local", "reliable")
func sync_world_item_pickup(item_path: String) -> void:
	var item = get_node_or_null(item_path)
	if is_instance_valid(item):
		_set_physical_item_state(item, true)
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
func notify_item_dropped(item_path: String, drop_pos: Vector3) -> void:
	if not multiplayer.is_server(): return
	rpc("sync_item_dropped", item_path, drop_pos)


@rpc("any_peer", "call_local", "reliable")
func sync_item_dropped(item_path: String, drop_pos: Vector3) -> void:
	var item = get_node_or_null(item_path)
	if not is_instance_valid(item): return
	
	var relative_transforms = []
	if "stacked_items" in item:
		for stacked_item in item.stacked_items:
			if is_instance_valid(stacked_item):
				relative_transforms.append(item.global_transform.affine_inverse() * stacked_item.global_transform)
				
	item.global_position = drop_pos
	item.global_rotation = self.global_rotation
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


@rpc("any_peer", "call_local", "reliable")
func sync_player_death() -> void:
	if is_owned:
		global_position = Vector3(randf_range(6,4), 1, randf_range(4,-4))
		health = max_health
		is_dead = false
		if ui_healthbar: ui_healthbar.value = int(health)


@rpc("any_peer", "call_local", "reliable")
func sync_username(target_name: String) -> void:
	if not is_inside_tree(): await get_tree().process_frame
	if is_instance_valid(username_label):
		username_label.text = target_name
		if not is_owned: username_label.show()


@rpc("any_peer", "call_local", "unreliable")
func sync_flashlight_state(slot_key: String, current_charge: float, active: bool) -> void:
	if is_instance_valid(held_item):
		held_item.charge = current_charge
		held_item.using = active

	var slot_node = hand.find_child("slot" + slot_key)
	if not is_instance_valid(slot_node) or slot_node.get_child_count() == 0:
		return
		
	var hand_flashlight = slot_node.get_child(0)
	
	var spotlight: SpotLight3D = hand_flashlight.find_child("SpotLight3D", true, false)
	if is_instance_valid(spotlight):
		spotlight.visible = active
		spotlight.light_energy = 5.0 if active else 0.0

	var power_label = hand_flashlight.find_child("power_label", true, false)
	if is_instance_valid(power_label):
		var text_node = power_label if (power_label is Label or power_label is Label3D) else power_label.get_child(0)
		if is_instance_valid(text_node):
			text_node.text = (str(int(round(current_charge))) + "%") if current_charge > 0 else "Flat"


@rpc("any_peer", "reliable")
func request_username_from_owner() -> void:
	if not is_inside_tree(): await get_tree().process_frame
	if is_owned: rpc("sync_username", GameData.username if GameData.username != "" else "Player")
