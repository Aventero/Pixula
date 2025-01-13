class_name MaterialButton
extends Button

signal material_pressed(type : MainEntry.MaterialType)
@export var material_type: MainEntry.MaterialType = 0

func _pressed() -> void:
	print(material_type)
	material_pressed.emit(material_type)
