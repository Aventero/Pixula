class_name SandSpawner
extends Node

# Reference to your TextureRect controller
@export var world_rect: TextureRect
@export var spawn_radius: int = 10
@export var world_viewport : SubViewport

var spawn_texture: ImageTexture
var spawn_image: Image

# Material types
enum MaterialType {
	EMPTY = 0,
	SAND = 1,
	WALL = 4
}

var is_drawing: bool = false
var previous_mouse_pos: Vector2i

func _ready() -> void:
	# DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED) 
	setup_spawn_texture()


func setup_spawn_texture() -> void:
	# Setup spawn texture
	spawn_image = Image.create(world_viewport.size.x, world_viewport.size.y, false, Image.FORMAT_RGBAF)
	spawn_texture = ImageTexture.create_from_image(spawn_image)
	spawn_image.fill(Color(100, 100, 100, 100))
	print(spawn_image.get_pixel(0,0))
	print(spawn_image.get_pixel(1,1))
	spawn_texture.update(spawn_image)

func _process(_delta: float) -> void:
	$CanvasLayer/FPS_Label.text = str(Engine.get_frames_per_second())
	check_mouse_input()

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_SAND"):
		is_drawing = false

func check_mouse_input() -> void:
	var current_mouse_pos: Vector2i = get_mouse_tile_pos()
	if Input.is_action_just_pressed("SPAWN_SAND"):
		is_drawing = true
		previous_mouse_pos = current_mouse_pos
	if is_drawing:
		var points: Array[Vector2i] = get_line_points(previous_mouse_pos, current_mouse_pos)
		for point in points:
			spawn_in_radius(point.x, point.y, spawn_radius, MaterialType.SAND)
		previous_mouse_pos = current_mouse_pos
		

func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: int) -> void:
	# Draw to spawn buffer instead of directly to the simulation texture
	for x in range(max(0, center_x - radius), min(spawn_image.get_width(), center_x + radius + 1)):
		for y in range(max(0, center_y - radius), min(spawn_image.get_height(), center_y + radius + 1)):
			var dx = x - center_x
			var dy = y - center_y
			if dx * dx + dy * dy <= radius * radius:
				spawn_image.set_pixel(x, y, Color(material_type, 0.0, 0.0, 1.0))

# Get all points in a line between two points
func get_line_points(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	# Array to hold points in line
	var line_points: Array[Vector2i] = []

	# Calculate distances between points
	var distance_x: int = abs(end.x - start.x)
	var distance_y: int = abs(end.y - start.y)

	# Track current position
	var current_x: int = start.x
	var current_y: int = start.y

	# Direction to step in each axis
	var step_x: int = 1 if start.x < end.x else -1
	var step_y: int = 1 if start.y < end.y else -1

	# Decision variable for path
	var decision: int = distance_x - distance_y

	while true:
		line_points.append(Vector2i(current_x, current_y))

		if current_x == end.x and current_y == end.y:
			break

		# Double decision to avoid floating point
		var doubled_decision: int = 2 * decision

		# Step in x direction if needed
		if doubled_decision > -distance_y:
			decision -= distance_y
			current_x += step_x

		# Step in y direction if needed
		if doubled_decision < distance_x:
			decision += distance_x
			current_y += step_y

	return line_points

func get_spawn_texture() -> ImageTexture:
	spawn_texture.update(spawn_image)
	return spawn_texture

func clear_spawn_buffer() -> void:
	spawn_image.fill(Color(100, 100, 100, 100))

# Convert mouse position to grid coordinates
func get_mouse_tile_pos() -> Vector2i:
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var texture_size = world_rect.texture.get_size()
	
	# Calculate scale factors
	var scale_x = viewport_size.x / texture_size.x
	var scale_y = viewport_size.y / texture_size.y
	
	# Convert mouse position to texture coordinates
	var grid_x: int = int(mouse_pos.x / scale_x)
	var grid_y: int = int(mouse_pos.y / scale_y)
	
	return Vector2i(grid_x, grid_y).clamp(Vector2i.ZERO, Vector2i(texture_size.x - 1, texture_size.y - 1))
