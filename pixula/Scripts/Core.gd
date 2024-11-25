extends Node2D

@export var map : TileMapLayer;

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	map.set_cell(Vector2i(32, 0), 0, Vector2i(3, 2), 0)
	map.set_cell(Vector2i(0, 1), 0, Vector2i(3, 2), 0)
	print("Cell placed?")
	print("Used cells", map.get_used_cells())
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
