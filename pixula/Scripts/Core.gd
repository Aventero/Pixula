extends Node2D
@onready var timer: Timer = $Timer
@onready var camera: Camera2D
@onready var texture_rect : TextureRect = $World/WorldTexture
@onready var color_atlas: Texture = load("res://Images/apollo.png")
@onready var color_atlas_image: Image = color_atlas.get_image()
@export var pixel_size: int = 16

var world_image: Image
var world_texture: ImageTexture
var debug_image: Image

# Pixel State
var pixels: Array[PackedInt32Array] = []
var active_pixels: Dictionary = {}
var moved_pixels: Dictionary = {}
var next_active_pixels: Dictionary = {}

# Window
@export var window_width: int = 1600
@export var window_height: int = 900
@onready var grid_width: int = window_width / pixel_size
@onready var grid_height: int = window_height / pixel_size

# Logic
const PROCESSED_BIT_START: int = 0
const ACTIVE_BIT_START: int = 1
const MATERIAL_BITS_START: int = 5
const MATERIAL_BITS_MASK:int = 0b1111 # 4 Bit = 16 materials
const VARIANT_BITS_START: int = 13
const VARIANT_BITS_MASK: int = 0b1111111 # 7 Bit "of color"

# Benchmarking
var is_benchmark: bool = false
var highest_simulation_time: float = 0
var total_simulation_time: float = 0
var total_frames: int = 0

# 0 - 31 -> 32 Possible Materials (Material Space)
enum MaterialType {
	AIR = 0,
	SAND = 1,
	WATER = 2,
	STONE = 3,
	DEBUG = 4
}

const COLOR_RANGES: Dictionary = {
	MaterialType.AIR: [36, 37],
	MaterialType.SAND: [19, 23],
	MaterialType.WATER: [1, 5],
	MaterialType.STONE: [3, 3],
	MaterialType.DEBUG: [27, 27],
}

const SWAP_RULES: Dictionary = {
	MaterialType.STONE: [],
	MaterialType.AIR: [],
	MaterialType.SAND: [MaterialType.AIR, MaterialType.WATER],
	MaterialType.WATER: [MaterialType.AIR],
}

func _ready() -> void:
	setup_image()
	setup_debug()
	get_window().size = Vector2(window_width, window_height)
	setup_pixels()

func setup_image() -> void:
	world_image = Image.create_empty(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	world_image.fill(Color(0, 0, 0, 0))
	world_texture = ImageTexture.create_from_image(world_image)
	texture_rect.texture = world_texture
	texture_rect.custom_minimum_size = Vector2(window_width, window_height)

func setup_debug() -> void:
	debug_image = Image.create_empty(grid_width * pixel_size, grid_height * pixel_size, false, Image.FORMAT_RGBA8)
	world_image.fill(Color(0, 0, 0, 0))
	var debug_texture = ImageTexture.create_from_image(debug_image)
	$World/DebugLayer/DebugTexture.texture = debug_texture

func _on_timer_timeout() -> void:
	simulate_active()
	world_texture.update(world_image)

func draw_active_cells() -> void:
	debug_image.fill(Color(0, 0, 0, 0))
	var red = Color.RED
	red.a = 1
	var blue = Color.BLUE
	blue.a = 1
	for pos in active_pixels:
		draw_pixel_rect_debug(pos, red)
	$World/DebugLayer/DebugTexture.texture.update(debug_image)

func draw_pixel_rect_debug(pos: Vector2i, color: Color) -> void:
	draw_rect_outline(debug_image, Rect2i(pos * pixel_size, Vector2i(1, 1) * pixel_size), color)

func draw_rect_outline(image: Image, rect: Rect2i, color: Color) -> void:
	# Draw horizontal lines
	for x in range(rect.position.x, rect.position.x + rect.size.x):
		image.set_pixel(x, rect.position.y, color)
		image.set_pixel(x, rect.position.y + rect.size.y - 1, color)
	# Draw vertical lines
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		image.set_pixel(rect.position.x, y, color)
		image.set_pixel(rect.position.x + rect.size.x - 1, y, color)

func simulate_active() -> void:
	var start_time: int = Time.get_ticks_usec()

	# SIMULATE
	for pos: Vector2i in active_pixels:
		simulate(pos.x, pos.y)

	# Reactivate processed pixels
	for pos in next_active_pixels:
		set_processed_at(pos.x, pos.y, false)

	if is_benchmark:
		var end_time: int = Time.get_ticks_usec()
		var current_simulation_time: float = (end_time - start_time) / 1000.0
		total_simulation_time += current_simulation_time
		total_frames += 1

		if highest_simulation_time < current_simulation_time:
			highest_simulation_time = current_simulation_time

		if active_pixels.is_empty() and next_active_pixels.is_empty():
			is_benchmark = false
			var average_time = total_simulation_time / total_frames
			print("Total: ", total_simulation_time, "ms | Average: ", average_time, "ms | Highest: ", highest_simulation_time, "ms | FPS: ", Engine.get_frames_per_second())
			return

	# Move next frame
	get_window().title = str(Engine.get_frames_per_second(), " | Active: ", active_pixels.size(), " | Next_Active: ", next_active_pixels.size())
	active_pixels = next_active_pixels.duplicate()
	next_active_pixels.clear()
	#draw_active_cells()

func benchmark_particles() -> void:
	# Clear
	total_frames = 0
	total_simulation_time = 0
	highest_simulation_time = 0
	setup_pixels()
	active_pixels.clear()
	next_active_pixels.clear()

	var particles_spawned: int = 0
	var benchmark_particle_count: int = 2000
	print("Benchmark with: ",benchmark_particle_count)
	while particles_spawned < benchmark_particle_count:
		var x: int = randi_range(0, grid_width - 1)
		var y: int = randi_range(0, grid_height -1)
		if get_material_at(x, y) == MaterialType.AIR:
			set_state_at(x, y, MaterialType.SAND, get_random_variant(MaterialType.SAND), false, true)
			activate_surrounding_pixels(x, y)
			particles_spawned += 1

	is_benchmark = true

### Setup, Input
func setup_pixels() -> void:
	pixels.resize(grid_height)
	for y: int in grid_height:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(grid_width)
		pixels[y] = row
		for x: int in grid_width:
			set_state_at(x, y, MaterialType.AIR, get_random_variant(MaterialType.AIR), false, false)

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_released("STATS"):
		benchmark_particles()

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 0, MaterialType.SAND)

	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.WATER)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: MaterialType) -> void:
	for y: int in range(max(0, center_y - radius), min(grid_height, center_y + radius + 1)):
		for x: int in range(max(0, center_x - radius), min(grid_width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_state_at(x, y, material_type, get_random_variant(material_type), false, true)
				activate_surrounding_pixels(x, y)

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

### Mechanics
func simulate(x: int, y: int) -> void:
	var current_material: MaterialType = get_material_at(x, y)
	if is_processed_at(x, y):
		return
	set_processed_at(x, y, true)

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
	var new_x: int = x + x_direction
	if not is_valid_position(new_x, y):
		return false

	if can_swap(process_material, get_material_at(new_x, y)):
		swap_particle(x, y, new_x, y)
		return true

	return false

func move_down(x: int, y: int, process_material: MaterialType) -> bool:
	if not is_valid_position(x, y + 1):
		return false

	if can_swap(process_material, get_material_at(x, y + 1)):
		swap_particle(x, y, x, y + 1)
		return true

	return false

func move_diagonal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if (x + y) % 2 == 0 else -1
	var new_x: int = x + x_direction

	if not is_valid_position(new_x, y + 1):
		return false

	if can_swap(process_material, get_material_at(new_x, y + 1)):
		swap_particle(x, y, new_x, y + 1)
		return true

	return false

const directions: Array[Vector2i] = [
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, 0),
	Vector2i(1, -1),
]

func activate_surrounding_pixels(x: int, y: int) -> void:
	for dir: Vector2i in directions:
		var activate_pos_x: int = x + dir.x
		var activate_pos_y: int = y + dir.y
		if not is_valid_position(activate_pos_x, activate_pos_y):
			continue
		if get_material_at(activate_pos_x, activate_pos_y) != MaterialType.AIR:
			set_active_at(activate_pos_x, activate_pos_y, true)


func get_color_for_variant(variant: int) -> Color:
	var atlas_coords: Vector2i = Vector2i(variant, 0)
	return color_atlas_image.get_pixel(atlas_coords.x,  atlas_coords.y)

func draw_pixel_at(x: int, y: int) -> void:
	var variant: int = get_pixel_variant_at(x, y)
	var color: Color = get_color_for_variant(variant)
	world_image.set_pixel(x, y, color)

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	# Swap the state
	var tmp: int = pixels[destination_y][destination_x]
	pixels[destination_y][destination_x] = pixels[source_y][source_x]
	pixels[source_y][source_x] = tmp

	# Draw only the changed cells
	draw_pixel_at(source_x, source_y)
	draw_pixel_at(destination_x, destination_y)

	activate_surrounding_pixels(source_x, source_y)
	#activate_surrounding_pixels(destination_x, destination_y)

func set_active_at(x: int, y: int, active: bool) -> void:
	var pos: Vector2i = Vector2i(x, y)
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
	var variants: PackedInt32Array = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func get_mouse_tile_pos() -> Vector2i:
	return Vector2i(get_local_mouse_position().abs() / pixel_size).clamp(Vector2i(0, 0), Vector2i(grid_width - 1, grid_height - 1))
