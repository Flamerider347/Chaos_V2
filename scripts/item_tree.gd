extends Node3D

var item_left = 5

@onready var iteminstantiator = $iteminstantiator

func _ready() -> void:
	GDSync.expose_func(_on_punched)
	GDSync.expose_var(self, "item_left")

var _last_item_left = 5

func _process(_delta: float) -> void:
	if item_left != _last_item_left:
		_last_item_left = item_left
		$Label3D.text = str(item_left)

func _on_punched():
	if not GDSync.is_host():
		GDSync.call_func_on(GDSync.get_host(), _on_punched)
		return
	if item_left > 0:
		item_left -= 1
		GDSync.sync_var(self, "item_left")
		$Label3D.text = str(item_left)
		var spawned_item = iteminstantiator.instantiate_node()
		
		spawned_item.type = self.name.left(-5)
		
		var angle: float = randf_range(0, 2*PI)
		spawned_item.position = global_position + Vector3(sin(angle), 0.2, cos(angle))*randf_range(1, 3)
		GDSync.set_gdsync_owner(spawned_item, GDSync.get_client_id())
		$item_timer.start(10)

func _on_item_timer_timeout() -> void:
	item_left += 1
	GDSync.sync_var(self, "item_left")
	$Label3D.text = str(item_left)
