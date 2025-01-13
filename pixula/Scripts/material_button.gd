# MaterialButton.gd
extends Button

@export var material_type: int = 0
@export var main : Node2D

func _ready():
	pressed.connect(_on_pressed)

func _on_pressed():
	main.selected_material = material_type
