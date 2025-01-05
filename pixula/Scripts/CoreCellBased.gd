extends CanvasItem

@export var timer: Timer
@export var camera: Camera2D
@export var pixel_size: int = 16

@export var color_atlas: Texture2D
@export var texture_rect : TextureRect
var world_image: Image
var world_texture: ImageTexture

# Pixel State
var current_pixels: Array[PackedInt32Array] = []
var next_pixels: Array[PackedInt32Array] = []

# Window
@export var window_width: int = 1600
@export var window_height: int = 900
@onready var grid_width: int = window_width / pixel_size
@onready var grid_height: int = window_height / pixel_size
@onready var color_atlas_image: Image = color_atlas.get_image()

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

# Constants for grid
var current_active_cells: Dictionary = {}
var next_active_cells: Dictionary = {}
const CELL_SIZE: int = 4

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
	get_window().size = Vector2(window_width, window_height)
	setup_pixels()

func setup_image() -> void:
	world_image = Image.create_empty(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	world_image.fill(Color(0, 0, 0, 0))
	world_texture = ImageTexture.create_from_image(world_image)
	texture_rect.texture = world_texture
	texture_rect.custom_minimum_size = Vector2(window_width, window_height)

func _on_timer_timeout() -> void:
	simulate_active()
	world_texture.update(world_image)

func _draw() -> void:
	draw_active_cells()

func draw_active_cells() -> void:
	var debug_color = Color(1, 0, 0, 1.0)
	for cell in current_active_cells:
		var rect = Rect2(
			cell.x * CELL_SIZE * pixel_size,
			cell.y * CELL_SIZE * pixel_size,
			CELL_SIZE * pixel_size,
			CELL_SIZE * pixel_size
		)
		draw_rect(rect, debug_color, false, 1, false)

func get_cell(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / CELL_SIZE, pos.y / CELL_SIZE)

func activate_cell(pos: Vector2i) -> void:
	var cell_pos: Vector2i = get_cell(pos)
	next_active_cells[cell_pos] = true
func simulate_active() -> void:
	var start_time: int = 0
	if is_benchmark:
		start_time = Time.get_ticks_usec()

	next_pixels = current_pixels.duplicate(true)
	for cell in current_active_cells:
		var cell_x = cell.x * CELL_SIZE
		var cell_y = cell.y * CELL_SIZE
		for x in range(cell_x, cell_x + CELL_SIZE):
			for y in range(cell_y, cell_y + CELL_SIZE):
				if is_valid_position(x, y):
					if simulate(x, y):  # If something changed
						activate_neighboring_cells(x, y)

	current_active_cells = next_active_cells.duplicate(true)
	next_active_cells.clear()

	var tmp = current_pixels
	current_pixels = next_pixels
	next_pixels = tmp

	if is_benchmark:
		var end_time: int = Time.get_ticks_usec()
		var current_simulation_time: float = (end_time - start_time) / 1000.0
		if highest_simulation_time < current_simulation_time:
			highest_simulation_time = current_simulation_time
			print("New highest simulation time: ", highest_simulation_time, "ms")
			print("Active cells: ", current_active_cells.size())

	queue_redraw()
	get_window().title = str(Engine.get_frames_per_second(), " | Active_cells: ", current_active_cells.size())

func activate_neighboring_cells(x: int, y: int) -> void:
	var cell_pos = get_cell(Vector2i(x, y))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var neighbor_cell = cell_pos + Vector2i(dx, dy)
			# Check against both minimum and maximum bounds
			if neighbor_cell.x >= 0 and neighbor_cell.y >= 0 and \
			   neighbor_cell.x < grid_width/CELL_SIZE and neighbor_cell.y < grid_height/CELL_SIZE:
				next_active_cells[neighbor_cell] = true

func benchmark_particles() -> void:
	# Clear

	highest_simulation_time = 0
	setup_pixels()
	current_active_cells.clear()
	next_active_cells.clear()

	# Spawn 2k particles
	var particles_spawned: int = 0
	var benchmark_particle_count: int = 8000
	print("Benchmark with: ",benchmark_particle_count)
	while particles_spawned < benchmark_particle_count:
		var x: int = randi_range(0, grid_width - 1)
		var y: int = randi_range(0, grid_height -1)
		if get_material_at(x, y) == MaterialType.AIR:
			set_state_at(x, y, MaterialType.SAND, get_random_variant(MaterialType.SAND), false, true)
			particles_spawned += 1

	is_benchmark = true

### Setup, Input
func setup_pixels() -> void:
	current_pixels.resize(grid_height)
	for y: int in grid_height:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(grid_width)
		current_pixels[y] = row
		for x: int in grid_width:
			set_state_at(x, y, MaterialType.AIR, get_random_variant(MaterialType.AIR), false, false)
	next_pixels = current_pixels.duplicate(true)

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_released("STATS"):
		benchmark_particles()

	if event.is_action_released("CHECK_MATERIAL"):
		print(get_material_at(get_mouse_tile_pos().x, get_mouse_tile_pos().y))

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 5, MaterialType.SAND)

	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, 3, MaterialType.WATER)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: MaterialType) -> void:
	for y: int in range(max(0, center_y - radius), min(grid_height, center_y + radius + 1)):
		for x: int in range(max(0, center_x - radius), min(grid_width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_state_at(x, y, material_type, get_random_variant(material_type), false, true)
				set_active_at(x, y, true)

func set_state_at(x: int, y: int, material_type: MaterialType, variant: int, has_processed: bool = false, activate: bool = false) -> void:
	if not is_valid_position(x,y):
		return

	# the "\" is for allowing linebreaks
	current_pixels[y][x] = ((has_processed as int) << PROCESSED_BIT_START) | \
							(material_type << MATERIAL_BITS_START) | \
							(variant << VARIANT_BITS_START)
	draw_pixel_at(x, y)
	activate_cell(Vector2i(x, y))

### Mechanics
func simulate(x: int, y: int) -> bool:
	var current_material: MaterialType = get_material_at(x, y)
	set_processed_at(x, y, true)

	if current_material == MaterialType.SAND:
		return sand_mechanic(x, y, current_material)

	if current_material == MaterialType.WATER:
		water_mechanic(x, y, current_material)

	return false

func sand_mechanic(x: int, y: int, process_material: MaterialType) -> bool:
	if move_down(x, y, process_material) or move_diagonal(x, y, process_material):
		return true
	return false

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
	Vector2i(-1, -1), Vector2i(0, 1), Vector2i(1, 1),
	Vector2i(-1, 0), 				  Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, -1), Vector2i(1, -1),
]

func get_color_for_variant(variant: int) -> Color:
	var atlas_coords: Vector2i = Vector2i(variant, 0)
	return color_atlas_image.get_pixel(atlas_coords.x,  atlas_coords.y)

func draw_pixel_at(x: int, y: int) -> void:
	var variant: int = get_pixel_variant_at(x, y)
	var color: Color = get_color_for_variant(variant)
	world_image.set_pixel(x, y, color)

func draw_pixel_at_new(x: int, y: int) -> void:
	var variant: int = get_pixel_variant_at_new(x, y)
	var color: Color = get_color_for_variant(variant)
	world_image.set_pixel(x, y, color)

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	# Swap in Next Simulation
	next_pixels[destination_y][destination_x] = current_pixels[source_y][source_x]
	next_pixels[source_y][source_x] = current_pixels[destination_y][destination_x]

	# Draw only the changed cells
	draw_pixel_at_new(source_x, source_y)
	draw_pixel_at_new(destination_x, destination_y)

	set_active_at(source_x, source_y, true)
	set_active_at(destination_x, destination_y, true)

func set_active_at(x: int, y: int, active: bool) -> void:
	var pos: Vector2i = Vector2i(x, y)
	if active:
		activate_cell(pos)

	# Update the bit in pixel data
	current_pixels[y][x] = (current_pixels[y][x] & ~(1 << ACTIVE_BIT_START)) | ((active as int) << ACTIVE_BIT_START)

func set_processed_at(x: int, y: int, has_processed: bool) -> void:
	current_pixels[y][x] = (current_pixels[y][x] & ~1) | (has_processed as int)

func get_material_at(x: int, y: int) -> MaterialType:
	return (current_pixels[y][x] >> MATERIAL_BITS_START) & MATERIAL_BITS_MASK as MaterialType

func get_pixel_variant_at(x: int, y: int) -> int:
	return (current_pixels[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func get_pixel_variant_at_new(x: int, y: int) -> int:
	return (next_pixels[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func is_processed_at(x: int, y: int) -> bool:
	return (current_pixels[y][x] >> PROCESSED_BIT_START) & 0b1

func get_random_variant(material_type: MaterialType) -> int:
	var variants: PackedInt32Array = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func get_mouse_tile_pos() -> Vector2i:
	return Vector2i(get_local_mouse_position().abs() / pixel_size).clamp(Vector2i(0, 0), Vector2i(grid_width - 1, grid_height - 1))
