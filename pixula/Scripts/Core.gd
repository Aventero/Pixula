extends Node2D

@export var map: TileMapLayer
@export var timer: Timer
@export var camera: Camera2D
@export var pixel_size = 16

var pixels: Array[Array] = []
var active_pixels: Dictionary = {}
var next_active_pixels: Dictionary = {}

@export var window_width: int = 1600
@export var window_height: int = 900
@onready var grid_width: int = window_width / pixel_size
@onready var grid_height: int = window_height / pixel_size

const PROCESSED_BIT_START = 0
const ACTIVE_BIT_START = 1
const MATERIAL_BITS_START = 5
const MATERIAL_BITS_MASK = 0b1111 # 4 Bit = 16 materials
const VARIANT_BITS_START = 13
const VARIANT_BITS_MASK = 0b1111111 # 7 Bit "of color"

# 0 - 31 -> 32 Possible Materials (Material Space)
enum MaterialType {
	AIR = 0,
	SAND = 1,
	WATER = 2,
	STONE = 3,
	DEBUG = 4
}

const COLOR_RANGES = {
	MaterialType.AIR: [36, 37],
	MaterialType.SAND: [19, 23],
	MaterialType.WATER: [1, 5],
	MaterialType.STONE: [3, 3],
	MaterialType.DEBUG: [27, 27],
}

const SWAP_RULES = {
	MaterialType.STONE: [],
	MaterialType.AIR: [],
	MaterialType.SAND: [MaterialType.AIR, MaterialType.WATER],
	MaterialType.WATER: [MaterialType.AIR],
}

func _ready() -> void:
	get_window().size = Vector2(window_width, window_height)
	map.scale = Vector2(pixel_size, pixel_size)
	setup_pixels()

func _on_timer_timeout() -> void:
	simulate_active()

func simulate_active() -> void:
	for pos in active_pixels:
		simulate(pos.x, pos.y)

	# Move next frame
	active_pixels = next_active_pixels.duplicate()
	next_active_pixels.clear()

### Setup, Input
func setup_pixels() -> void:
	pixels.resize(grid_height)
	for y in grid_height:
		pixels[y] = [] # new array
		pixels[y].resize(grid_width) # make space
		for x in grid_width:
			set_state_at(x, y, MaterialType.AIR, get_random_variant(MaterialType.AIR), false, false)

	# First Draw
	for y in range(grid_height):
		for x in range(grid_width):
			var mat_variant = get_pixel_variant_at(x, y)
			map.set_cell(Vector2i(x, y), 1, Vector2i(mat_variant, 0), 0)

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_released("STATS"):
		print("Active: ", active_pixels.size())
		print("Active NEXT FRAME: ", next_active_pixels.size())

func _process(_delta: float) -> void:
	get_window().title = str(Engine.get_frames_per_second(), " | Active: ", active_pixels.size())
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.SAND)

	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.WATER)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: MaterialType) -> void:
	for y in range(max(0, center_y - radius), min(grid_height, center_y + radius + 1)):
		for x in range(max(0, center_x - radius), min(grid_width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_state_at(x, y, material_type, get_random_variant(material_type), false, true)

### Low level pixel manipulation ###
func set_state_at(x: int, y: int, material_type: MaterialType, variant: int, has_processed: bool = false, activate: bool = false) -> void:
	if not is_valid_position(x,y):
		return

	# the "\" is for allowing linebreaks
	pixels[y][x] = ((has_processed as int) << PROCESSED_BIT_START) | \
							(material_type << MATERIAL_BITS_START) | \
							(variant << VARIANT_BITS_START)
	set_active_at(x, y, activate)
	draw_pixel_at(x, y)

func set_active_at(x: int, y: int, active: bool) -> void:
	var pos = Vector2i(x, y)
	if active:
		next_active_pixels[pos] = true
	else:
		next_active_pixels.erase(pos)

	# Update the bit in pixel data
	pixels[y][x] = (pixels[y][x] & ~(1 << ACTIVE_BIT_START)) | ((active as int) << ACTIVE_BIT_START)

func set_processed_at(x: int, y: int, has_processed: bool) -> void:
	pixels[y][x] = (pixels[y][x] & ~1) | (has_processed as int)

func get_material_at(x: int, y: int) -> MaterialType:
	return (pixels[y][x] >> MATERIAL_BITS_START) & MATERIAL_BITS_MASK as MaterialType

func get_pixel_variant_at(x: int, y: int) -> int:
	return (pixels[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func is_processed_at(x: int, y: int) -> bool:
	return (pixels[y][x] >> PROCESSED_BIT_START) & 0b1

func is_active_at(x: int, y: int) -> bool:
	return (pixels[y][x] >> ACTIVE_BIT_START) & 0b1

func get_random_variant(material_type: MaterialType) -> int:
	var variants = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

### Mechanics
func simulate(x: int, y: int) -> void:
	var current_material: MaterialType = get_material_at(x, y)

	if current_material == MaterialType.SAND:
		sand_mechanic(x, y, current_material)

	if current_material == MaterialType.WATER:
		water_mechanic(x, y, current_material)

func sand_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		if not move_diagonal(x, y, process_material):
			set_active_at(x, y, false)

func water_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		if not move_diagonal(x, y, process_material):
			if not move_horizontal(x, y, process_material):
				set_active_at(x, y, false)

func move_horizontal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if y % 2 == 0 else -1
	var new_x = x + x_direction
	if not is_valid_position(new_x, y):
		return false

	if can_swap(process_material, get_material_at(new_x, y)):
		swap_particle(x, y, new_x, y)
		return true

	return true

func move_down(x: int, y: int, process_material: MaterialType) -> bool:
	if not is_valid_position(x, y + 1):
		return false

	if can_swap(process_material, get_material_at(x, y + 1)):
		swap_particle(x, y, x, y + 1)
		return true

	return false

func move_diagonal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if (x + y) % 2 == 0 else -1
	var new_x = x + x_direction

	if not is_valid_position(new_x, y + 1):
		return false

	if can_swap(process_material, get_material_at(new_x, y + 1)):
		swap_particle(x, y, new_x, y + 1)
		return true

	return false

const directions = [
	Vector2i(-1, -1),  # Top left
	Vector2i(0, -1),   # Top
	Vector2i(1, -1),   # Top right
	Vector2i(-1, 0),   # Left
	Vector2i(1, 0),    # Right
	Vector2i(-1, 1),   # Bottom left
	Vector2i(0, 1),    # Bottom
	Vector2i(1, 1)     # Bottom right
]

func activate_surrounding_pixels(x: int, y: int) -> void:
	for dir in directions:
		var activate_pos_x = x + dir.x
		var activate_pos_y = y + dir.y
		if not is_valid_position(activate_pos_x, activate_pos_y):
			continue
		if get_material_at(activate_pos_x, activate_pos_y) != MaterialType.AIR:
			set_active_at(activate_pos_x, activate_pos_y, true)

func draw_pixel_at(x: int, y: int) -> void:
	var mat_variant = get_pixel_variant_at(x, y)
	map.set_cell(Vector2i(x, y), 1, Vector2i(mat_variant, 0), 0)

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	# Swap the state
	var tmp = pixels[destination_y][destination_x]
	pixels[destination_y][destination_x] = pixels[source_y][source_x]
	pixels[source_y][source_x] = tmp

	# Draw only the changed cells
	draw_pixel_at(source_x, source_y)
	draw_pixel_at(destination_x, destination_y)

	activate_surrounding_pixels(destination_x, destination_y)
	activate_surrounding_pixels(source_x, source_y)

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func get_mouse_tile_pos() -> Vector2i:
	return Vector2i(get_local_mouse_position().abs() / pixel_size).clamp(Vector2i(0, 0), Vector2i(grid_width - 1, grid_height - 1))
