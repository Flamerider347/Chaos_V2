extends RigidBody3D
var type = "generic thing"
var is_held: bool = false
var item_id: String = ""

@export var item_mesh: Mesh

func _ready() -> void:
	GDSync.expose_node(self)

func _physics_process(_delta: float) -> void:
	if self.position.y < -10:
		self.queue_free()
