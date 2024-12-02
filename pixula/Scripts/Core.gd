extends Node2D

@export var map : TileMapLayer
@export var timer : Timer
@export var camera : Camera2D
@onready var pixel_size = camera.zoom.x
enum MATERIAL {AIR = 37, STONE = 41, SAND = 22, WATER = 2}

var pixel_dictionary : Dictionary

var pixel_array_2d = []
var pixel_array_2d_buffer  = []
@onready var width : int = get_viewport_rect().size.x / pixel_size
@onready var height : int = get_viewport_rect().size.y / pixel_size

func _ready() -> void:
	setup_environment()

func setup_environment() -> void:
	setup_array(pixel_array_2d)
	setup_array(pixel_array_2d_buffer)
	print("Amount of pixels: ", width * height)

func setup_array(array_to_set_up : Array) -> void:
	for y in range(height):
		var row = PackedInt32Array()
		row.resize(width)
		row.fill(MATERIAL.AIR)
		array_to_set_up.append(row)

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_PARTICLE"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	if event.is_action_pressed("CHECK_MATERIAL"):
		var atlas_coord = map.get_cell_atlas_coords(get_mouse_tile_pos())
		print(atlas_to_material(atlas_coord))

func get_mouse_tile_pos() -> Vector2i:
	var tilemap_pos = map.local_to_map(get_local_mouse_position()).abs()
	return tilemap_pos.clamp(Vector2i(0, 0), Vector2i(width - 1, height - 1))

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_PARTICLE"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		set_particle(get_mouse_tile_pos().x, get_mouse_tile_pos().y, get_random_sand())
		#set_particle(get_mouse_tile_pos().x - 1, get_mouse_tile_pos().y + 1, get_random_sand())
		#set_particle(get_mouse_tile_pos().x + 0, get_mouse_tile_pos().y + 1, get_random_sand())
		#set_particle(get_mouse_tile_pos().x + 1, get_mouse_tile_pos().y + 1, get_random_sand())
		#set_particle(get_mouse_tile_pos().x - 2, get_mouse_tile_pos().y + 2, get_random_sand())
		#set_particle(get_mouse_tile_pos().x + 0, get_mouse_tile_pos().y + 2, get_random_sand())
		#set_particle(get_mouse_tile_pos().x + 2, get_mouse_tile_pos().y + 2, get_random_sand())
	#sand_mechanic()

func _on_timer_timeout() -> void:
	for y in range(0, height):
		for x in range(0, width):
			sand_mechanic(x, y)

func get_random_sand() -> int:
	return randi_range(19, 23)

func sand_mechanic(x : int, y : int) -> void:
	# For each pixel do:
	var mat = pixel_array_2d[y][x]
	if mat >= 19 && mat <= 23 && (y + 1 < height):
		# Below
		if pixel_array_2d[y + 1][x] == MATERIAL.AIR:
			swap_particle(x, y, x, y + 1)
		# Below Left
		elif (x > 0) && pixel_array_2d[y + 1][x - 1] == MATERIAL.AIR && randi_range(0, 1) == 1: 
			swap_particle(x, y, x - 1, y + 1)
		# Below Right
		elif (x + 1 < width) && pixel_array_2d[y + 1][x + 1] == MATERIAL.AIR: 
			swap_particle(x, y, x + 1, y + 1)
	
	# Copy over the rest
	pixel_array_2d[y][x] = pixel_array_2d_buffer[y][x] 
	map.set_cell(Vector2i(x, y), 1, Vector2i(pixel_array_2d_buffer[y][x], 0), 0)

func swap_particle(posAx : int, posAy : int, posBx : int, posBy : int) -> void:
	pixel_array_2d_buffer[posBy][posBx] = pixel_array_2d[posAy][posAx]
	pixel_array_2d_buffer[posAy][posAx] = pixel_array_2d[posBy][posBx]

func map_coord_to_material(map_coord : Vector2i) -> MATERIAL:
	return atlas_to_material(map.get_cell_atlas_coords(map_coord))

func atlas_to_material(atlas_coord : Vector2i) -> MATERIAL:
	return atlas_coord.x as MATERIAL
	
func set_particle(x : int, y : int, mat : MATERIAL) -> void:
	if x < 0 or x >= width or y < 0 or y >= height:
		return
	pixel_array_2d[y][x] = mat
