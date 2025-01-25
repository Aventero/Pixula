class_name MaterialButton
extends Button

signal material_pressed(type : MainEntry.MaterialType)
@export var material_type: MainEntry.MaterialType = MainEntry.MaterialType.AIR

func _ready() -> void:
	material = material.duplicate() # Make it unique
	toggled.connect(_on_toggled)

func _pressed() -> void:
	material_pressed.emit(material_type)

func _on_toggled(button_pressed: bool):
	# De selected
	if !button_pressed:
		material.set_shader_parameter("speed_multiplier", 1.0)
	else:
		material.set_shader_parameter("speed_multiplier", 5.0)
