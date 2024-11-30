extends Node2D

@export var map : TileMapLayer
@export var timer : Timer
var pixel_size = 8
enum MATERIAL {AIR = 37, STONE = 41, SAND = 22, WATER = 2}

var pixel_array = []
var width : int
var height : int

func _ready() -> void:
	width = get_viewport_rect().size.x / pixel_size
	height = get_viewport_rect().size.y / pixel_size
	pixel_array.resize(width * height)
	setup_environment()

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_PARTICLE"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	if event.is_action_pressed("CHECK_MATERIAL"):
		var atlas_coord = map.get_cell_atlas_coords(get_mouse_tile_pos())
		print(atlas_to_material(atlas_coord))

func setup() -> void:
	return

func get_mouse_tile_pos() -> Vector2i:
	return map.local_to_map(get_local_mouse_position())

func _on_timer_timeout() -> void:
	sand_mechanic()
	pass

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_PARTICLE"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		set_particle(get_mouse_tile_pos().x, get_mouse_tile_pos().y, MATERIAL.SAND)
		set_particle(get_mouse_tile_pos().x - 1, get_mouse_tile_pos().y + 1, MATERIAL.SAND)
		set_particle(get_mouse_tile_pos().x + 0, get_mouse_tile_pos().y + 1, MATERIAL.SAND)
		set_particle(get_mouse_tile_pos().x + 1, get_mouse_tile_pos().y + 1, MATERIAL.SAND)

func sand_mechanic() -> void:
	var old_pixel_array = pixel_array.duplicate()
	
	for y in range(0, height):
		for x in range(0, width):
			var mat = old_pixel_array[x + (width * y)]
			var below = x + (width * (y + 1))
			var below_left = x - 1 + (width * (y + 1))
			var below_right = x + 1 + (width * (y + 1))
			
			if mat == MATERIAL.SAND && (y + 1 < height): # stay in bounds
				if old_pixel_array[below] == MATERIAL.AIR:
					swap_particle(x, y, x, y + 1, old_pixel_array)
				elif old_pixel_array[below_left] == MATERIAL.AIR && (x > 0):
					swap_particle(x, y, x - 1, y + 1, old_pixel_array)
				elif (x + 1 < width) && old_pixel_array[below_right] == MATERIAL.AIR:
					swap_particle(x, y, x + 1, y + 1, old_pixel_array)
	transfer_to_tilemap()

func swap_particle(posAx : int, posAy : int, posBx : int, posBy : int, old_pixel_array : Array) -> void:
	var posA = posAx + width * posAy
	var posB = posBx + width * posBy
	pixel_array[posA] = old_pixel_array[posB]
	pixel_array[posB] = old_pixel_array[posA]

func setup_environment() -> void:
	# Setup the arrays
	for y in range(0, height):
		for x in range(0, width):
			pixel_array[x + (width * y)] = MATERIAL.AIR
	
	transfer_to_tilemap()

func transfer_to_tilemap() -> void:
	# Fill it inside the tilemap
	for y in range(0, height):
		for x in range(0, width):
			var material = pixel_array[x + (width * y)]
			map.set_cell(Vector2i(x, y), 1, Vector2i(material, 0), 0)



func map_coord_to_material(map_coord : Vector2i) -> MATERIAL:
	return atlas_to_material(map.get_cell_atlas_coords(map_coord))

func atlas_to_material(atlas_coord : Vector2i) -> MATERIAL:
	return atlas_coord.x as MATERIAL
	
func set_particle(x : int, y : int, mat : MATERIAL) -> void:
	pixel_array[x + width * y] = mat
