extends Node2D

### EXPORTS AND CONSTANTS ###
@export var timer: Timer
@export var camera: Camera2D
const pixel_size: int = 10
const window_width: int = 1600
const window_height: int = 900
const grid_width: int = window_width / pixel_size

### MATERIALS AND RULES ###
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

### WORLD STATE
@export var color_atlas: Texture2D
@export var texture_rect: TextureRect
var world_image: Image
var world_texture: ImageTexture
@onready var grid_height: int = window_height / pixel_size
@onready var color_atlas_image: Image = color_atlas.get_image()

### PIXEL STATE
var pixels: Array[PackedInt32Array] = []
var pixel_variants: Dictionary = {}
var processed_pixels: Dictionary = {}
var active_pixels: Dictionary = {}
var next_active_pixels: Dictionary = {}

const directions: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

### BENCHMARKING
var is_benchmark: bool = false
var highest_simulation_time: float = 0

### INITIALIZATION
func _ready() -> void:
	setup_image()
	get_window().size = Vector2(window_width, window_height)
	setup_pixels()

func setup_image() -> void:
	world_image = Image.create_empty(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	world_image.fill(Color(0, 0, 0, 0))
	world_texture = ImageTexture.create_from_image(world_image)
	texture_rect.texture = world_texture
	texture_rect.custom_minimum_size = Vector2(window_width, window_height)

func setup_pixels() -> void:
	pixels.resize(grid_height)
	for y: int in grid_height:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(grid_width)
		pixels[y] = row
		for x: int in grid_width:
			set_state_at(Vector2i(x, y), MaterialType.AIR, get_random_variant(MaterialType.AIR), false, false)

### INPUT
func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event.is_action_released("STATS"):
		benchmark_particles()
	if event.is_action_released("GET_MATERIAL"):
		print(get_material_at(get_mouse_tile_pos().x, get_mouse_tile_pos().y))


func _process(_delta: float) -> void:
	handle_spawn_input()

func handle_spawn_input() -> void:
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.SAND)
	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 0, MaterialType.WATER)

### SIMULATION CORE
func _on_timer_timeout() -> void:
	simulate_active()
	draw_world()

func draw_world() -> void:
	world_texture.update(world_image)

func simulate_active() -> void:
	update_window_title()
	if is_benchmark:
		benchmark_simulation()
	else:
		normal_simulation()


func normal_simulation() -> void:
	for pos: Vector2i in active_pixels:
		simulate(pos.x, pos.y)
	active_pixels = next_active_pixels.duplicate()
	next_active_pixels.clear()

### BENCHMARKING ###
func benchmark_simulation() -> void:
	var start_time: int = Time.get_ticks_usec()
	for pos: Vector2i in active_pixels:
		simulate(pos.x, pos.y)

	active_pixels = next_active_pixels.duplicate()
	next_active_pixels.clear()

	var end_time: int = Time.get_ticks_usec()
	var current_simulation_time: float = (end_time - start_time) / 1000.0
	highest_simulation_time = max(highest_simulation_time, current_simulation_time)

	if active_pixels.is_empty():
		is_benchmark = false
		print("BENCHMARK COMPLETE - HIGHEST TIME: ", highest_simulation_time)

func benchmark_particles() -> void:
	highest_simulation_time = 0
	setup_pixels()
	active_pixels.clear()
	next_active_pixels.clear()

	var particles_spawned: int = 0
	var benchmark_particle_count: int = 8000
	print("Starting benchmark with: ", benchmark_particle_count, " particles")

	while particles_spawned < benchmark_particle_count:
		var pos: Vector2i = Vector2i(randi_range(0, grid_width - 1), randi_range(0, grid_height - 1))
		if get_material_at(pos.x, pos.y) == MaterialType.AIR:
			set_state_at(pos, MaterialType.SAND, get_random_variant(MaterialType.SAND), false, true)
			activate_surrounding_pixels(pos)
			particles_spawned += 1

	print("Benchmark initialization complete")
	is_benchmark = true

### MATERIAL MECHANICS
func simulate(x: int, y: int) -> void:
	var current_material: MaterialType = get_material_at(x, y)
	match current_material:
		MaterialType.SAND:
			sand_mechanic(x, y, current_material)
		MaterialType.WATER:
			water_mechanic(x, y, current_material)

### MATERIAL MECHANICS ###
func sand_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		if not move_diagonal(x, y, process_material):
			set_active_at(Vector2i(x, y), false)
			return

	set_active_at(Vector2i(x, y), true)

func water_mechanic(x: int, y: int, process_material: MaterialType) -> void:
	if not move_down(x, y, process_material):
		if not move_diagonal(x, y, process_material):
			if not move_horizontal(x, y, process_material):
				set_active_at(Vector2i(x, y), false)
				return

	set_active_at(Vector2i(x, y), true)

func move_horizontal(x: int, y: int, process_material: MaterialType) -> bool:
	var x_direction: int = 1 if randi_range(0, 1) == 0 else -1
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

const WATER_DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, 0),				 Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
]

func is_stuck(x: int, y: int, active_material: MaterialType) -> bool:
	for dir: Vector2i in WATER_DIRECTIONS:
		if not is_valid_position(x + dir.x, y + dir.y):
			continue
		if can_swap(active_material, get_material_at(x + dir.x, y + dir.y)):
			return false
	return true

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	var source_pos: Vector2i = Vector2i(source_x, source_y)
	var dest_pos: Vector2i = Vector2i(destination_x, destination_y)

	# Swap material
	var tmp_material: int = pixels[destination_y][destination_x]
	pixels[destination_y][destination_x] = pixels[source_y][source_x]
	pixels[source_y][source_x] = tmp_material

	# Swap variant
	#var tmp_variant: int = pixel_variants[dest_pos]
	#pixel_variants[dest_pos] = pixel_variants[source_pos]
	#pixel_variants[source_pos] = tmp_variant

	# Swap processed state
	#var tmp_processed: bool = processed_pixels.get(dest_pos, false)
	#processed_pixels[dest_pos] = processed_pixels.get(source_pos, false)
	#processed_pixels[source_pos] = tmp_processed

	# Update visuals and state
	draw_pixel_at(source_pos)
	draw_pixel_at(dest_pos)
	#processed_pixels[source_pos] = false
	#processed_pixels[dest_pos] = false

	activate_surrounding_pixels(source_pos)

func set_state_at(pos: Vector2i, material_type: MaterialType, variant: int, has_processed: bool = false, activate: bool = false) -> void:
	if not is_valid_position(pos.x, pos.y):
		return

	pixels[pos.y][pos.x] = material_type
	pixel_variants[pos] = variant
	processed_pixels[pos] = has_processed
	set_active_at(pos, activate)
	draw_pixel_at(pos)

func set_active_at(pos: Vector2i, active: bool) -> void:
	#processed_pixels[pos] = false
	if active and get_material_at(pos.x, pos.y) != MaterialType.AIR:
		next_active_pixels[pos] = true
	else:
		next_active_pixels.erase(pos)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: MaterialType) -> void:
	for y: int in range(max(0, center_y - radius), min(grid_height, center_y + radius + 1)):
		for x: int in range(max(0, center_x - radius), min(grid_width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_state_at(Vector2i(x, y), material_type, get_random_variant(material_type), false, true)
				activate_surrounding_pixels(Vector2i(x, y))

func activate_surrounding_pixels(pos: Vector2i) -> void:
	for direction: Vector2i in directions:
		var activation_pos: Vector2i = pos + direction
		if not is_valid_position(activation_pos.x, activation_pos.y):
			continue
		set_active_at(activation_pos, true)

### UTILITY FUNCTIONS ###
func get_material_at(x: int, y: int) -> MaterialType:
	return pixels[y][x]

func get_pixel_variant_at(x: int, y: int) -> int:
	var pos: Vector2i = Vector2i(x, y)
	return pixel_variants.get(pos, 0)

func get_random_variant(material_type: MaterialType) -> int:
	var variants: PackedInt32Array = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

func get_color_for_variant(variant: int) -> Color:
	var atlas_coords: Vector2i = Vector2i(variant, 0)
	return color_atlas_image.get_pixel(atlas_coords.x, atlas_coords.y)

func draw_pixel_at(pos: Vector2i) -> void:
	var variant: int = pixel_variants[pos]
	var color: Color = get_color_for_variant(variant)
	world_image.set_pixel(pos.x, pos.y, color)

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func get_mouse_tile_pos() -> Vector2i:
	return Vector2i(get_local_mouse_position().abs() / pixel_size).clamp(
		Vector2i.ZERO,
		Vector2i(grid_width - 1, grid_height - 1)
	)

func update_window_title() -> void:
	get_window().title = str(
		Engine.get_frames_per_second(),
		" | Active: ", active_pixels.size(),
		" | Next Active: ", next_active_pixels.size()
	)
