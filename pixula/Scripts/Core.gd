extends Node2D

@export var map: TileMapLayer
@export var timer: Timer
@export var camera: Camera2D
@onready var pixel_size = camera.zoom.x

var pixel_array_2d: Array[Array] = []
@onready var width: int = get_viewport_rect().size.x / pixel_size
@onready var height: int = get_viewport_rect().size.y / pixel_size

const PROCESSED_BIT = 0
const MATERIAL_BITS_START = 5
const MATERIAL_BITS_MASK = 0b11111 # 5 Bit = 32
const VARIANT_BITS_START = 12
const VARIANT_BITS_MASK = 0b1111111 # 7 Bit

# 0 - 31 -> 32 Possible Materials (Material Space)
enum MaterialType {
	AIR = 0,
	SAND = 1,
	WATER = 2,
	STONE = 3,
}

const COLOR_RANGES = {
	MaterialType.AIR: [36, 37],
	MaterialType.SAND: [19, 23],
	MaterialType.WATER: [0, 5],
	MaterialType.STONE: [3, 3]
}

const SWAP_RULES = {
	MaterialType.STONE: [],
	MaterialType.AIR: [],
	MaterialType.SAND: [MaterialType.AIR, MaterialType.WATER],
	MaterialType.WATER: [MaterialType.AIR],
}

func _ready() -> void:
	setup_pixels()

func _on_timer_timeout() -> void:
	var sand_count = 0
	for y in range(0, height):
		for x in range(0, width):
			simulate(x, y)

	#var water_count = 0
	#for y in range(0, height):
		#for x in range(0, width):
			#if get_process_material_at(x, y) == MaterialType.WATER:
				#water_count += 1
	#print("Water: ", water_count)
	#water_count = 0
	transfer_to_tilemap()

### Setup, Input
func setup_pixels() -> void:
	pixel_array_2d.resize(height)
	for y in height:
		pixel_array_2d[y] = [] # new array
		pixel_array_2d[y].resize(width) # make space
		for x in width:
			set_pixel_state_at(x, y, MaterialType.AIR, get_random_variant(MaterialType.AIR))

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	#if event.is_action_pressed("CHECK_MATERIAL"):
		#var atlas_coord = map.get_cell_atlas_coords(get_mouse_tile_pos())
		#print(atlas_to_material(atlas_coord))

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 2, MaterialType.SAND)

	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.WATER)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material: MaterialType) -> void:
	for y in range(max(0, center_y - radius), min(height, center_y + radius + 1)):
		for x in range(max(0, center_x - radius), min(width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_pixel_state_at(x, y, material, get_random_variant(material))

func set_pixel_state_at(x: int, y: int, material_type: MaterialType, variant: int, has_processed: bool = false) -> void:
	if not is_valid_position(x,y):
		return

	pixel_array_2d[y][x] = ((has_processed as int) << PROCESSED_BIT) | \
							(material_type << MATERIAL_BITS_START) | \
							(variant << VARIANT_BITS_START)

func set_pixel_processed_at(x: int, y: int, has_processed: bool) -> void:
	pixel_array_2d[y][x] = (pixel_array_2d[y][x] & ~1) | (has_processed as int) # clear first bit and set it

func get_process_material_at(x: int, y: int) -> MaterialType:
	return (pixel_array_2d[y][x] >> MATERIAL_BITS_START) & MATERIAL_BITS_MASK as MaterialType

func get_pixel_variant_at(x: int, y: int) -> int:
	return (pixel_array_2d[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func is_pixel_processed_at(x: int, y: int) -> bool:
	return (pixel_array_2d[y][x] >> PROCESSED_BIT) & 0x1

func get_random_variant(material_type: MaterialType) -> int:
	var variants = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

func transfer_to_tilemap() -> void:
	for y in range(height):
		for x in range(width):
			var mat_variant = get_pixel_variant_at(x, y)
			map.set_cell(Vector2i(x, y), 1, Vector2i(mat_variant, 0), 0)
			set_pixel_processed_at(x, y, false)

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

### Mechanics
func simulate(x: int, y: int) -> void:
	if is_pixel_processed_at(x, y):
		return

	var current_material: MaterialType = get_process_material_at(x, y)

	# Is some sand material
	if current_material == MaterialType.SAND:
		sand_mechanic(x, y, current_material)

	# Is some water material
	if current_material == MaterialType.WATER:
		water_mechanic(x, y, current_material)

	set_pixel_processed_at(x, y, true) # Mark as processed

func sand_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		move_diagonal(x, y, process_material)

func water_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		if not move_diagonal(x, y, process_material):
			move_horizontal(x, y, process_material)

func move_horizontal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if y % 2 == 0 else -1
	if not is_valid_position(x + x_direction, y):
		return false

	if get_process_material_at(x + x_direction, y) == MaterialType.AIR:
		swap_particle(x, y, x + x_direction, y)
		return true

	return false

func move_down(x: int, y: int, process_material: MaterialType) -> bool:
	if not is_valid_position(x, y + 1):
		return false

	if can_swap(get_process_material_at(x, y), get_process_material_at(x, y + 1)) && is_valid_position(x, y + 1):
		swap_particle(x, y, x, y + 1)
		return true

	return false

func move_diagonal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if (x + y) % 2 == 0 else -1
	var new_x = x + x_direction

	if not is_valid_position(new_x, y + 1):
		return false

	if get_process_material_at(new_x, y + 1) == MaterialType.AIR:
		swap_particle(x, y, new_x, y + 1)
		return true

	return false

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	if not can_swap(get_process_material_at(source_x, source_y), get_process_material_at(destination_x, destination_y)):
		return

	var tmp = pixel_array_2d[destination_y][destination_x]
	pixel_array_2d[destination_y][destination_x] = pixel_array_2d[source_y][source_x]
	pixel_array_2d[source_y][source_x] = tmp

	# The destination pixel is processed, otherwise it would get re-processed
	set_pixel_processed_at(destination_x, destination_y, true)
	set_pixel_processed_at(source_x, source_y, false)
### Helper

func get_mouse_tile_pos() -> Vector2i:
	var tilemap_pos = map.local_to_map(get_local_mouse_position()).abs()
	return tilemap_pos.clamp(Vector2i(0, 0), Vector2i(width - 1, height - 1))
