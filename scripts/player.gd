extends CharacterBody3D

var is_owned: bool = false
var held_item = null
var hand_item = null
var can_pickup = true
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
var mouse_sensitivity = 0.003

@onready var interact_cast : RayCast3D = $head/interact_cast
@onready var hand = $hand
func _ready() -> void:
	$username.text = GameData.username
	GDSync.expose_node(self)
	GDSync.expose_func(sync_drop)
	is_owned = false
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	GDSync.expose_node(self)
	if not GameData.connected:
		is_owned = true
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

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
	if not is_owned or GameData.paused:
		return
	if event is InputEventMouseMotion:
		self.rotation_degrees.y += -event.relative.x * mouse_sensitivity * 5
		$head.rotation_degrees.x += -event.relative.y * mouse_sensitivity * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)

func _physics_process(_delta: float) -> void:
	mouse_sensitivity = get_node("/root/main/Pause_UI/sensitivity").value
	if not is_owned:
		return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * _delta


	if held_item != null and interact_cast.is_colliding():
		print(held_item.get_groups())
		if interact_cast.get_collider().is_in_group("placeable") and held_item.is_in_group("choppable"):
			held_item.global_position = interact_cast.get_collider().global_position + Vector3(0,0.5,0)
			held_item.show()
		elif interact_cast.get_collider().is_in_group("plate") and held_item.is_in_group("plate_stackable"):
			print("hello")
			held_item.global_position = interact_cast.get_collider().global_position + Vector3(0,0.1,0)
			held_item.show()
		else:
			held_item.global_position = hand.global_position
			held_item.global_rotation = hand_item.global_rotation
			held_item.hide()

	elif held_item != null:
		held_item.global_position = hand.global_position
		held_item.global_rotation = hand_item.global_rotation
		held_item.hide()

	if not GameData.paused:
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		if Input.is_action_just_pressed("left_click"):
			if held_item != null and can_pickup:
				drop_object(held_item)
	
			elif interact_cast.is_colliding():
				if interact_cast.get_collider().is_in_group("punchable"):
					interact_cast.get_collider()._on_punched()
				elif interact_cast.get_collider().is_in_group("pickupable") and can_pickup and held_item == null:
					pickup_object(interact_cast.get_collider())
				elif interact_cast.get_collider().is_in_group("door"):
					interact_cast.get_collider().open_door()
					
		if Input.is_action_just_pressed("right_click"):
			if interact_cast.is_colliding():
				if interact_cast.get_collider().is_in_group("plate") and held_item != null and held_item.is_in_group("plate_stackable"):
					stack_object(interact_cast.get_collider())

		var input_dir = Vector2.ZERO
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func stack_object(plate):
	if GameData.connected:
		GDSync.call_func_all(plate.stack_item, held_item)
	plate.stack_item(held_item)
	for i in hand.get_children():
		i.queue_free()
	held_item = null

func pickup_object(object):
	held_item = object
	can_pickup = false
	object.freeze = true
	object.find_child("CollisionShape3D").disabled = true
	object.rotation = Vector3.ZERO
	$pickup_timer.start()
	var object2 = object.duplicate()
	hand.add_child(object2)
	object2.position = Vector3.ZERO
	object2.rotation = Vector3.ZERO
	object.hide()
	hand_item = object2
	if GameData.connected:
		GDSync.set_gdsync_owner(object, GDSync.get_client_id())

func drop_object(object):
	for i in hand.get_children():
		i.queue_free()
	held_item = null
	can_pickup = false
	object.freeze = false
	object.find_child("CollisionShape3D").disabled = false
	$pickup_timer.start()
	object.show()
	object.rotation = hand_item.global_rotation
	if GameData.connected:
		GDSync.set_gdsync_owner(object, GDSync.get_host())
		GDSync.call_func_all(sync_drop, [object.get_path()])
	
func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.freeze = false
		object.find_child("CollisionShape3D").disabled = false
		object.show()

func _on_pickup_timer_timeout() -> void:
	can_pickup = true
