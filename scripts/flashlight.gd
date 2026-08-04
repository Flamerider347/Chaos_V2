extends RigidBody3D

var type: String = "flashlight"
var charge: float = 100.0
var using: bool = false

func drain_battery(delta: float) -> void:
	if using and charge > 0:
		charge = maxf(0.0, charge - delta)

func is_active() -> bool:
	return using and charge > 0

func _process(_delta: float) -> void:
	if not using and charge > 0:
		$power_label.hide()
	else:
		$power_label.text = "FLAT"
