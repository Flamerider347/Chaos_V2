extends RigidBody3D

var type: String = "flashlight"
var charge: float = 100.0
var using: bool = false

func drain_battery(delta: float) -> void:
	if using and charge > 0:
		charge = maxf(0.0, charge - 10.0 * delta)

func is_active() -> bool:
	return using and charge > 0
