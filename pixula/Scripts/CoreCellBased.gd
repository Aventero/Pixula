extends CanvasItem

# External
@onready var timer: Timer = $Timer
@onready var camera: Camera2D
@onready var texture_rect : TextureRect = $World/WorldTexture
@onready var color_atlas: Texture = load("res://Images/apollo.png")
@onready var color_atlas_image: Image = color_atlas.get_image()

# Drawing
var world_image: Image
var world_texture: ImageTexture
var debug_image: Image

# Pixel State
var current_pixels: Array[PackedInt32Array] = [] # Pixels in the CURRENT frame
var next_pixels: Array[PackedInt32Array] = [] # Pixels in the NEXT frame
var moved_pixels: Dictionary = {} # Pixels that moved in the CURRENT FRAME

# Simulation
@export var enable_debug: bool = false
@export_range(0.001, 2) var sim_speed_seconds = 0.001
@export_range(2, 32) var cell_size: int = 5

# Window
@export var window_width: int = 1600
@export var window_height: int = 900
@onready var grid_width: int = window_width / pixel_size
@onready var grid_height: int = window_height / pixel_size

# Pixel Logic
const MATERIAL_BITS_START: int = 5
const MATERIAL_BITS_MASK:int = 0b1111 # 4 Bit = 16 materials
const VARIANT_BITS_START: int = 13
const VARIANT_BITS_MASK: int = 0b1111111 # 7 Bit "of color"

# Benchmarking
var is_benchmark: bool = false
var highest_simulation_time: float = 0
var total_simulation_time: float = 0
var total_frames: int = 0

# Debug
var total_particles: int = 0
var last_particle_count: int = 0

# Grid cells
@export var circle_size: int = 3
@export var pixel_size: int = 16
var current_active_cells: Dictionary = {}
var next_active_cells: Dictionary = {}

# 0 - 31 -> 32 Possible Materials (Material Space)hahah
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
	setup_images()
	setup_debug()
	get_window().size = Vector2(window_width, window_height)
	setup_pixels()

func setup_images() -> void:
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

func draw_active_cells() -> void:
	debug_image.fill(Color(0, 0, 0, 0))
	var red = Color.RED
	red.a = 1
	var blue = Color.BLUE
	blue.a = 1
	for pos in next_active_cells:
		draw_cell_debug(pos, red)
	$World/DebugLayer/DebugTexture.texture.update(debug_image)

func draw_cell_debug(cell_pos: Vector2i, color: Color) -> void:
	var pixel_draw_pos = cell_pos * cell_size * pixel_size
	var cell_draw_size = cell_size * pixel_size

	# Draw outline
	var rect = Rect2i(pixel_draw_pos, Vector2i(cell_draw_size, cell_draw_size))
	draw_rect_outline(debug_image, rect, color)

func draw_rect_outline(image: Image, rect: Rect2i, color: Color) -> void:
	# Check if the rectangle goes outside the scren
	var r = rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))

	for x in range(r.position.x, r.position.x + r.size.x):
		image.set_pixel(x, r.position.y, color)
		image.set_pixel(x, r.position.y + r.size.y - 1, color)

	for y in range(r.position.y, r.position.y + r.size.y):
		image.set_pixel(r.position.x, y, color)
		image.set_pixel(r.position.x + r.size.x - 1, y, color)

# Simulation Start
func _on_timer_timeout() -> void:
	timer.wait_time = sim_speed_seconds
	var start_time: int = Time.get_ticks_usec()

	simulate_active()

	if is_benchmark:
		benchmark_active(start_time)

	if enable_debug:
		draw_active_cells()
	world_texture.update(world_image)
	get_window().title = str(Engine.get_frames_per_second())

func simulate_active() -> void:

	# Move cells with information as current frame
	next_pixels = current_pixels.duplicate(true)
	current_active_cells = next_active_cells.duplicate(true)
	next_active_cells.clear()

	var pixels_to_simulate: Array[Vector2i] = []
	for cell in current_active_cells:
		var cell_x = cell.x * cell_size
		var cell_y = cell.y * cell_size
		for x in range(cell_x, cell_x + cell_size):
			for y in range(cell_y, cell_y + cell_size):
				if is_valid_position(x, y):
					pixels_to_simulate.append(Vector2i(x, y))

	# Randomize to avoid directional bias
	pixels_to_simulate.shuffle()

	# Simulate.
	for pixel_pos in pixels_to_simulate:
		if simulate(pixel_pos.x, pixel_pos.y):
			activate_neighboring_cells(pixel_pos.x, pixel_pos.y)
	moved_pixels.clear()

	var tmp = current_pixels
	current_pixels = next_pixels
	next_pixels = tmp

func activate_neighboring_cells(x: int, y: int) -> void:
	var cell_pos = get_cell(Vector2i(x, y))

	# Position in the cell
	# 1 2
	# 3 4  in a 2 by 2
	var pos_in_cell: Vector2i = Vector2i(x % cell_size, y % cell_size)

	var edges_to_activate: Array[Vector2i] = []

	if pos_in_cell.x == 0:
		edges_to_activate.append(Vector2i.LEFT)
	elif pos_in_cell.x == cell_size - 1:
		edges_to_activate.append(Vector2i.RIGHT)

	if pos_in_cell.y == 0:
		edges_to_activate.append(Vector2i.UP)
	elif pos_in_cell.y == cell_size - 1:
		edges_to_activate.append(Vector2i.DOWN)

	# Activate bordering cell
	for edge in edges_to_activate:
		var neighbor = cell_pos + edge
		if is_valid_cell(neighbor):
			next_active_cells[neighbor] = true

	# Activate cornering diagonal cell
	if edges_to_activate.size() == 2:
		var diagonal = edges_to_activate[0] + edges_to_activate[1]
		var neighbor = cell_pos + diagonal
		if is_valid_cell(neighbor):
			next_active_cells[neighbor] = true

func is_valid_cell(cell_pos: Vector2i) -> bool:
	return cell_pos.x >= 0 and cell_pos.x < grid_width/cell_size and \
		  cell_pos.y >= 0 and cell_pos.y < grid_height/cell_size

func get_cell(pos: Vector2i) -> Vector2i:
	return Vector2i(pos.x / cell_size, pos.y / cell_size)

func activate_cell(pos: Vector2i) -> void:
	var cell_pos: Vector2i = get_cell(pos)
	next_active_cells[cell_pos] = true

# Benchmark
func benchmark_active(start_time: int) -> void:
	var end_time: int = Time.get_ticks_usec()
	var current_simulation_time: float = (end_time - start_time) / 1000.0
	total_simulation_time += current_simulation_time
	total_frames += 1

	if highest_simulation_time < current_simulation_time:
		highest_simulation_time = current_simulation_time

	if current_active_cells.is_empty() and next_active_cells.is_empty():
		is_benchmark = false
		var average_time = total_simulation_time / total_frames
		print("Total: ", total_simulation_time, "ms | Average: ", average_time, "ms | Highest: ", highest_simulation_time, "ms | FPS: ", Engine.get_frames_per_second())
		return

func initialize_benchmark_particles() -> void:
	# Clear
	total_frames = 0
	total_simulation_time = 0
	highest_simulation_time = 0
	setup_pixels()
	current_active_cells.clear()
	next_active_cells.clear()

	# Spawn 2k particles
	var particles_spawned: int = 0
	var benchmark_particle_count: int = 1000
	print("Benchmark with: ",benchmark_particle_count)
	while particles_spawned < benchmark_particle_count:
		var x: int = randi_range(0, grid_width - 1)
		var y: int = randi_range(0, grid_height -1)
		if get_material_at(x, y) == MaterialType.AIR:
			set_state_at(x, y, MaterialType.SAND, get_random_variant(MaterialType.SAND))
			particles_spawned += 1

	is_benchmark = true

func debug_count_particles() -> void:
	# Reset counter
	total_particles = 0

	# Count all non-air particles
	for y in range(grid_height):
		for x in range(grid_width):
			if get_material_at(x, y) != MaterialType.AIR:
				total_particles += 1

	# Print if count changed
	if total_particles != last_particle_count:
		print("Particle count changed: ", last_particle_count, " -> ", total_particles)
		last_particle_count = total_particles

### Setup, Input
func setup_pixels() -> void:
	current_pixels.resize(grid_height)
	for y: int in grid_height:
		var row: PackedInt32Array = PackedInt32Array()
		row.resize(grid_width)
		current_pixels[y] = row
		for x: int in grid_width:
			set_state_at(x, y, MaterialType.AIR, get_random_variant(MaterialType.AIR))
	next_pixels = current_pixels.duplicate(true)

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND") || event.is_action_released("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_released("STATS"):
		initialize_benchmark_particles()

	if event.is_action_released("CHECK_MATERIAL"):
		print(get_material_at(get_mouse_tile_pos().x, get_mouse_tile_pos().y))

func _process(_delta: float) -> void:
	if Input.is_action_pressed("SPAWN_SAND"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, circle_size, MaterialType.SAND)

	if Input.is_action_pressed("SPAWN_WATER"):
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		spawn_in_radius(get_mouse_tile_pos().x, get_mouse_tile_pos().y, circle_size, MaterialType.WATER)

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: MaterialType) -> void:
	for y: int in range(max(0, center_y - radius), min(grid_height, center_y + radius + 1)):
		for x: int in range(max(0, center_x - radius), min(grid_width, center_x + radius + 1)):
			if Vector2(center_x, center_y).distance_to(Vector2(x, y)) <= radius:
				set_state_at(x, y, material_type, get_random_variant(material_type))
				activate_cell(Vector2i(x, y))

func set_state_at(x: int, y: int, material_type: MaterialType, variant: int) -> void:
	if not is_valid_position(x,y):
		return

	# the "\" is for allowing linebreaks
	current_pixels[y][x] =  (material_type << MATERIAL_BITS_START) | \
							(variant << VARIANT_BITS_START)
	draw_pixel_at(x, y)
	activate_cell(Vector2i(x, y))

### Mechanics
func simulate(x: int, y: int) -> bool:
	var current_material: MaterialType = get_material_at(x, y)

	## Will still be true, a pixel might be moving
	if has_moved(Vector2i(x, y)):
		return false

	if current_material == MaterialType.SAND:
		return sand_mechanic(x, y, current_material)

	if current_material == MaterialType.WATER:
		return water_mechanic(x, y, current_material)

	return false

func sand_mechanic(x: int, y: int, process_material: MaterialType) -> bool:
	if move_down(x, y, process_material):
		return true

	if move_diagonal(x, y, process_material):
		return true

	return false

func water_mechanic(x: int, y: int, process_material: MaterialType) -> bool:
	if move_down(x, y, process_material) or move_diagonal(x, y, process_material) or move_horizontal(x, y, process_material):
		return true
	return false

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
	var direction: Vector2i = Vector2(-1, 1) if (x + y) % 2 == 0 else Vector2(1, 1)
	var newPos: Vector2i = Vector2i(x, y) + direction

	if not is_valid_position(newPos.x, newPos.y):
		return false

	if can_swap(process_material, get_material_at(newPos.x, newPos.y)):
		swap_particle(x, y, newPos.x, newPos.y)
		return true

	return false

func swap_particle(source_x: int, source_y: int, destination_x: int, destination_y: int) -> void:
	# Swap in Next Simulation
	var temp = next_pixels[destination_y][destination_x]
	next_pixels[destination_y][destination_x] = current_pixels[source_y][source_x]
	next_pixels[source_y][source_x] = temp

	draw_pixel_at_new(source_x, source_y)
	draw_pixel_at_new(destination_x, destination_y)

	var source: Vector2i = Vector2i(source_x, source_y)
	var destination: Vector2i = Vector2i(destination_x, destination_y)

	moved_pixels[source] = true
	moved_pixels[destination] = true

	activate_cell(source)
	activate_cell(destination)

func has_moved(moved_position: Vector2i) -> bool:
	return moved_pixels.has(moved_position)

# Drawing
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

func get_random_variant(material_type: MaterialType) -> int:
	var variants: PackedInt32Array = COLOR_RANGES[material_type]
	return randi_range(variants[0], variants[1])

func set_processed_at(x: int, y: int, has_processed: bool) -> void:
	current_pixels[y][x] = (current_pixels[y][x] & ~1) | (has_processed as int)

func get_material_at(x: int, y: int) -> MaterialType:
	return (current_pixels[y][x] >> MATERIAL_BITS_START) & MATERIAL_BITS_MASK as MaterialType

func get_pixel_variant_at(x: int, y: int) -> int:
	return (current_pixels[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func get_pixel_variant_at_new(x: int, y: int) -> int:
	return (next_pixels[y][x] >> VARIANT_BITS_START) & VARIANT_BITS_MASK

func can_swap(source: MaterialType, swapping_partner: MaterialType) -> bool:
	return swapping_partner in SWAP_RULES.get(source, [])

func is_valid_position(x: int, y: int) -> bool:
	return x >= 0 and x < grid_width and y >= 0 and y < grid_height

func get_mouse_tile_pos() -> Vector2i:
	return Vector2i(get_local_mouse_position().abs() / pixel_size).clamp(Vector2i(0, 0), Vector2i(grid_width - 1, grid_height - 1))
