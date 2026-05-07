extends CharacterBody3D

var is_owned: bool = false
var held_item = null
var can_pickup = true
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const MOUSE_SENSITIVITY = 0.003

@onready var interact_cast = $head/interact_cast
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
		self.rotation_degrees.y += -event.relative.x * MOUSE_SENSITIVITY * 5
		$head.rotation_degrees.x += -event.relative.y * MOUSE_SENSITIVITY * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -90, 90)

func _physics_process(_delta: float) -> void:
	if not is_owned:
		return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * _delta
	if held_item != null and interact_cast.is_colliding():
		if interact_cast.get_collider().is_in_group("placeable") and held_item.is_in_group("choppable"):
			held_item.global_position = interact_cast.get_collider().global_position + Vector3(0,0.5,0)
			held_item.show()

	elif held_item != null:
		held_item.global_position = $hand.global_position
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
			if interact_cast.get_collider().is_in_group("plate") and held_item != null and held_item.is_in_group("plate_stackable"):
				var plate = interact_cast.get_collider()
				if GameData.connected:
					GDSync.call_func_all(held_item)
				plate.stack_item(held_item)
				hand.hide()
				held_item = null
				

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

func pickup_object(object):
	held_item = object
	can_pickup = false
	object.freeze = true
	object.find_child("CollisionShape3D").disabled = true
	$pickup_timer.start()
	object.global_position = $hand.global_position
	object.rotation = Vector3.ZERO
	$hand.mesh = object.get_node("mesh").mesh
	$hand.visible = true
	object.hide()
	if GameData.connected:
		GDSync.set_gdsync_owner(object, GDSync.get_client_id())

func drop_object(object):
	held_item = null
	can_pickup = false
	object.freeze = false
	object.find_child("CollisionShape3D").disabled = false
	$pickup_timer.start()
	$hand.visible = false
	object.show()
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
