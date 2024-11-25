extends Node2D

@export var map : TileMapLayer
@export var timer : Timer
var pixel_size = 15
enum MATERIAL {AIR = 37, STONE = 41, SAND = 22, WATER = 2}


func _ready() -> void:
	setup_environment()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("SPAWN_PARTICLE"):
		set_particle(get_mouse_tile_pos(), MATERIAL.SAND)
	if event.is_action_pressed("CHECK_MATERIAL"):
		var atlas_coord = map.get_cell_atlas_coords(get_mouse_tile_pos())
		print(atlas_to_material(atlas_coord))

func get_mouse_tile_pos() -> Vector2i:
	return map.local_to_map(get_local_mouse_position())
	

func _on_timer_timeout() -> void:
	sand_mechanic()
	pass

func _process(_delta: float) -> void:
	pass

func sand_mechanic() -> void:
	# Problem sand in, accessed multiple times in this for loop
	# Create new tilemap or layer and push everything on there
	# delete the old one
	for cell_pos in map.get_used_cells():
		if (map_coord_to_material(cell_pos) == MATERIAL.SAND):
			var bottom_cell = map.get_neighbor_cell(cell_pos, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)
			var material_below = map_coord_to_material(bottom_cell)
			if material_below == MATERIAL.AIR:
				print("Sand at: ", cell_pos)
				swap_particle(cell_pos, bottom_cell)

func setup_environment() -> void:
	for x in range(0, get_viewport_rect().size.x / pixel_size):
		for y in range(0, get_viewport_rect().size.y / pixel_size):
			set_particle(Vector2i(x, y), MATERIAL.AIR)

func set_particle(pos : Vector2i, particle_atlas_coord : MATERIAL) -> void:
	map.set_cell(pos, 1, Vector2i(particle_atlas_coord, 0), 0)
	pass

func swap_particle(posA : Vector2i, posB : Vector2i) -> void:
	var tmp_atlas_coords = map.get_cell_atlas_coords(posA)
	set_particle(posA, map.get_cell_atlas_coords(posB).x)
	set_particle(posB, tmp_atlas_coords.x)

func map_coord_to_material(map_coord : Vector2i) -> MATERIAL:
	return atlas_to_material(map.get_cell_atlas_coords(map_coord))

func atlas_to_material(atlas_coord : Vector2i) -> MATERIAL:
	return atlas_coord.x as MATERIAL
