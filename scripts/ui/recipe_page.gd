extends Node2D
class_name RecipePage

@onready var title: Label = $page/info_list/title
@onready var value: Label = $page/info_list/value
@onready var components: Label = $page/info_list/components
@onready var anim_player: AnimationPlayer = $AnimationPlayer


func despawn_left():
	anim_player.play("despawn_left")
	await anim_player.animation_finished
	queue_free()

func despawn_right():
	anim_player.play("despawn_right")
	await anim_player.animation_finished
	queue_free()
