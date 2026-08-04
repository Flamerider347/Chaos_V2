extends Control
var current_text = 0
var max_text = 10
var texts = [
	"Welcome to Kitchen Chaos V2! 
	I'll be your guide!
	For the next tip, press
	The right arrow key",
	"Use WASD and Space
	to move and jump
	Use a mouse/trackpad
	to look around",
	"Press 'Tab' to toggle pause menu, 
	where you'll find multiplayer codes 
	and the sensitivity changer.",
	"When you've invited all your friends
	(Or you're playing solo)
	Left click the door 
	to start the game",
	"Once you're outside, Left Click
	on a tree to make it drop an item
	Left click the item again to pick 
	the item up",
	"You have 4 inventory slots,
	which can be accessed by pressing 
	1,2,3 and 4 on your keyboard",
	"Each slot holds multiple items but
	you move slower with more items",
	"If you want to drop something,
	press the corresponding slot button
	(1,2,3,4) and then right click",
	"To chop items, press right click
	to drop them on the chopping board",
	"If you're overwhelmed by items,
	drop items into the hoppers by the door 
	to put them into the storage system
	for fast storage, use the drop all button",
	"To take items out of storage, 
	press left click on any button
	on the machine inside. 
	This is where plates are stored",
	"To stack items onto a plate, 
	hold the stackable item and press
	Right Click. You can't pickup
	or swap to other items while
	holding a plate with stacked items",
	"To submit an order, drop it in the hole
	in the middle of the kitchen
	you can also jump into the hole
	to sell your inventory...",
	"Submitting an order grants power
	that can be used for upgrades
	spend power wisely, because
	there's an increasing power cost
	each night",
	"Hungry and evil goblins lurk in the 
	shadows at night, but they hate light
	so you're safe in the kitchen
	as long as you have power...",
	"Daily power loss happens at
	6AM everyday, when the sun rises.
	Goblins despawn during the daytime
	That's about it, Good Luck!"
	
]
func _ready() -> void:
	max_text = texts.size() -1
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("close_tutorial"):
		if not self.visible:
			self.show()
			$"../UI/Label2".text = "Press X to hide tips
			Use arrow keys for
			previous/next tip"
		else:
			$"../UI/Label2".text = "Press X to show tips"
			self.hide()
			
	if self.get_parent().name == "menu_UI":
		return
		
	if Input.is_action_just_pressed("previous_tutorial") and current_text > 0:
		current_text -= 1
		
	if Input.is_action_just_pressed("next_tutorial") and current_text < max_text:
		current_text += 1
	$Label2.text = str(current_text+1)+"/"+str(max_text+1)
	$Label.text = texts[current_text]
