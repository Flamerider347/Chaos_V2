extends Node3D

@export var day_length_seconds: float = 240.0

@onready var sun_light: DirectionalLight3D = $DirectionalLight3D
@onready var world_env: WorldEnvironment = $WorldEnvironment

var ui_time_label: Label = null
var current_time: float = 0.75 # Starts at 6:00 PM
var is_cycle_started: bool = false 
var current_day = 0

func _ready() -> void:
	GDSync.expose_func(sync_time_from_host)
	GDSync.expose_func(sync_start_trigger)
	
	if has_node("/root/main/UI/day_timer"):
		ui_time_label = get_node("/root/main/UI/day_timer") as Label
	else:
		ui_time_label = get_tree().current_scene.find_child("day_timer", true, false) as Label

	update_sky_and_lighting()

func _process(delta: float) -> void:
	if not is_cycle_started:
		return

	if GameData.paused and not GameData.connected:
		return
		
	if not GameData.connected or GDSync.is_host():
		current_time += delta / day_length_seconds
		
		# FIX: Custom Night Trigger (10:00 PM / 22:00 to 6:00 AM)
		# 22/24 = 0.9167, 6/24 = 0.25
		if current_time >= 0.8333333 or current_time < 0.25:
			GameData.is_night = true
		else:
			GameData.is_night = false
			
		if current_time > 1.0:
			current_time = 0.0
			current_day += 1
			$"../../UI/current_day".text = "Day: " + str(current_day)
			
		if GameData.connected:
			GDSync.call_func(sync_time_from_host, [current_time])
			
	if is_instance_valid(sun_light) and is_instance_valid(world_env):
		update_sky_and_lighting()
		
	if is_instance_valid(ui_time_label):
		update_ui_clock()

func start_day_cycle() -> void:
	if GameData.connected:
		if GDSync.is_host():
			GDSync.call_func_all(sync_start_trigger, [1])
	else:
		is_cycle_started = true

func sync_time_from_host(args) -> void:
	if GDSync.is_host():
		return
	if typeof(args) == TYPE_ARRAY and args.size() > 0:
		current_time = float(args[0])
	elif typeof(args) == TYPE_FLOAT or typeof(args) == TYPE_INT:
		current_time = float(args)

func sync_start_trigger(_dummy = null) -> void:
	is_cycle_started = true

func update_sky_and_lighting() -> void:
	# Calculate a normal rotation angle based on standard linear time progress
	var sun_angle = current_time * TAU - (TAU / 4.0) + (TAU / 2.0)
	sun_light.rotation.x = sun_angle
	sun_light.rotation.y = deg_to_rad(25.0) 
	
	# Determine solar curves based on your exact timestamp schedules
	var sun_fade: float = 0.0
	var sunset_blend: float = 0.0
	
	# --- CUSTOM SCHEDULE LIGHT MAPPING ---
	if current_time >= 0.25 and current_time < 0.3333:
		# Early Dawn (6 AM to 8 AM): Rising light values
		sun_fade = smoothstep(0.25, 0.3333, current_time) * 0.4
		sunset_blend = 1.0
	elif current_time >= 0.3333 and current_time < 0.4167:
		# Golden Dawn Peak (8 AM to 10 AM): Blending out sunset hues into crisp daylight
		sun_fade = lerp(0.4, 1.2, smoothstep(0.3333, 0.4167, current_time))
		sunset_blend = smoothstep(0.4167, 0.3333, current_time)
	elif current_time >= 0.4167 and current_time < 0.6667:
		# Full Bright Daylight (10 AM to 4 PM)
		sun_fade = 1.2
		sunset_blend = 0.0
	elif current_time >= 0.6667 and current_time < 0.75:
		# Dusk Transition (4 PM to 6 PM): Setting sun colors ignite
		sun_fade = 1.2
		sunset_blend = smoothstep(0.6667, 0.75, current_time)
	elif current_time >= 0.75 and current_time < 0.9167:
		# Late Dusk Twilight (6 PM to 10 PM): Light levels drop off to dark night
		sun_fade = smoothstep(0.9167, 0.75, current_time) * 0.3
		sunset_blend = smoothstep(0.9167, 0.75, current_time)
	else:
		# Pitch Black Night (10 PM to 6 AM)
		sun_fade = 0.0
		sunset_blend = 0.0

	# --- ENVIRONMENT COLOUR ASSIGNMENTS ---
	sun_light.light_energy = sun_fade
	
	var day_color = Color(1.0, 0.95, 0.85)
	var sunset_color = Color(0.95, 0.45, 0.15)
	var night_light_color = Color(0.05, 0.05, 0.15)
	
	# Mix environment targets smoothly based on schedule weight parameters
	if GameData.is_night:
		sun_light.light_color = night_light_color
	else:
		sun_light.light_color = day_color.lerp(sunset_color, sunset_blend)

	var env = world_env.environment
	if env:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var ambient_day_color = Color(0.6, 0.7, 0.8)
		var ambient_night_color = Color(0.2, 0.25, 0.35) # Darker ambient backdrop for scary nights
		
		# Base the room environment brightness directly on whether players are in daylight blocks
		var night_weight = 1.0 - (sun_fade / 1.2)
		env.ambient_light_color = ambient_day_color.lerp(ambient_night_color, night_weight)
		env.ambient_light_energy = lerp(1.0, 0.6, night_weight)

func update_ui_clock() -> void:
	# Keep time tracking matching the standard accurate linear hours
	var total_minutes = int(current_time * 24.0 * 60.0)
	var hours = int(total_minutes / 60.0) % 24
	var minutes = total_minutes % 60
	
	var am_pm = "AM"
	var display_hour = hours
	if hours >= 12:
		am_pm = "PM"
		if hours > 12:
			display_hour = hours - 12
	if display_hour == 0:
		display_hour = 12
		
	ui_time_label.text = "%02d:%02d %s" % [display_hour, minutes, am_pm]
