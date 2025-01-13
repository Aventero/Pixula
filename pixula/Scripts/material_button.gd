class_name MaterialButton
extends Button

signal material_pressed(type : MainEntry.MaterialType)
@export var material_type: MainEntry.MaterialType = MainEntry.MaterialType.AIR

func _pressed() -> void:
	material_pressed.emit(material_type)
