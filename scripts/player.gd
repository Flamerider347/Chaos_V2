extends CharacterBody3D

var is_owned: bool = false
const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const MOUSE_SENSITIVITY = 0.003
var held_item = null
var can_pickup = true

@onready var interact_cast = $head/interact_cast
@onready var hand = $hand

func _ready() -> void:
	GDSync.expose_func(sync_held_item_position)
	is_owned = false
	GDSync.connect_gdsync_owner_changed(self, owner_changed)
	GDSync.expose_func(sync_pickup)
	GDSync.expose_func(sync_drop)
	await get_tree().create_timer(1.0).timeout
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

func _physics_process(delta: float) -> void:
	if not is_owned:
		return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if not GameData.paused:
		if Input.is_action_just_pressed("left_click"):
			if held_item != null and can_pickup:
				drop_object(held_item)
			elif interact_cast.is_colliding():
				if interact_cast.get_collider().is_in_group("punchable"):
					interact_cast.get_collider()._on_punched()
				elif interact_cast.get_collider().is_in_group("pickupable") and can_pickup and held_item == null:
					pickup_object(interact_cast.get_collider())
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	
	if held_item != null and GameData.connected:
		GDSync.call_func_all(sync_held_item_position, [held_item.get_path(), held_item.global_position])
	var input_dir = Vector2.ZERO
	if not GameData.paused:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	
	move_and_slide()

func pickup_object(object):
	if object.is_held:
		return
	held_item = object
	can_pickup = false
	$pickup_timer.start()
	if GameData.connected:
		GDSync.call_func_all(sync_pickup, [object.get_path(), hand.get_path()])
	sync_pickup([object.get_path(), hand.get_path()])

func drop_object(object):
	held_item = null
	can_pickup = false
	$pickup_timer.start()
	if GameData.connected:
		GDSync.call_func_all(sync_drop, [object.get_path()])
	sync_drop([object.get_path()])

func sync_pickup(params: Array) -> void:
	var object = get_node_or_null(params[0])
	var target_hand = get_node_or_null(params[1])
	if object and target_hand:
		object.is_held = true
		object.freeze = true
		object.reparent(target_hand)
		object.position = Vector3.ZERO

func sync_drop(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.is_held = false
		object.freeze = false
		object.reparent(get_node("/root/main/game/items"))

func sync_held_item_position(params: Array) -> void:
	var object = get_node_or_null(params[0])
	if object:
		object.global_position = params[1]

func _on_pickup_timer_timeout() -> void:
	can_pickup = true
