extends StaticBody3D

@export var capacity: int
@export var display_mesh: Mesh: 
	set(value): 
		display_mesh = value
		if is_node_ready():
			$"/item_mesh".mesh = display_mesh


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
