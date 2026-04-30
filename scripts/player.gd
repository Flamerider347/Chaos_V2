extends CharacterBody3D

var is_owned: bool = false

const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const GRAVITY = 9.8
const MOUSE_SENSITIVITY = 0.003

func _ready() -> void:
	GDSync.connect_gdsync_owner_changed(self, owner_changed)

func owner_changed(_owner_id: int) -> void:
	is_owned = GDSync.is_gdsync_owner(self)
	if is_owned:
		$head/camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		$head/camera.queue_free()

func _input(event: InputEvent) -> void:
	if not is_owned or GameData.paused:
		return
	if event is InputEventMouseMotion:
		self.rotation_degrees.y += -event.relative.x * MOUSE_SENSITIVITY * 5
		$head.rotation_degrees.x += -event.relative.y * MOUSE_SENSITIVITY * 5
		$head.rotation_degrees.x = clamp($head.rotation_degrees.x, -40, 50)

func _physics_process(delta: float) -> void:
	if not is_owned:
		return
	
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	if not GameData.paused:
		if Input.is_action_just_pressed("ui_accept") and is_on_floor():
			velocity.y = JUMP_VELOCITY
	
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
