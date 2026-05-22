extends RigidBody3D

var type = "meat"
var state = "raw"
var is_held: bool = false
var item_id: String = ""
var cookedness = 0.0
var cooking = false
@export var item_mesh: Mesh

func _ready() -> void:
	GDSync.expose_node(self)
	update_mesh_visibility_by_state()

func _physics_process(delta: float) -> void:
	if cooking:
		cookedness += 1 * delta
		print(cookedness)
		
		if cookedness > 10 and state != "burnt":
			state = "burnt"
			update_mesh_visibility_by_state()
		elif cookedness > 5 and cookedness <= 10 and state != "cooked":
			state = "cooked"
			update_mesh_visibility_by_state()

func update_mesh_visibility_by_state() -> void:
	if has_node("mesh_burnt"): $mesh_burnt.visible = (state == "burnt")
	if has_node("mesh_cooked"): $mesh_cooked.visible = (state == "cooked")
	if has_node("mesh_raw"): $mesh_raw.visible = (state == "raw")
	
	if state == "cooked":
		if not is_in_group("plate_stackable"):
			add_to_group("plate_stackable")
	else:
		if is_in_group("plate_stackable"):
			remove_from_group("plate_stackable")
