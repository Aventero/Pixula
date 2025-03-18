class_name SandSpawner
extends Node

# Reference to your TextureRect controller
@export var texture_rect: TextureRect
@export var spawn_radius: int = 5

# Material types
enum MaterialType {
	EMPTY = 0,
	SAND = 1,
	WALL = 4
}

var is_drawing: bool = false
var previous_mouse_pos: Vector2i

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)  

func _process(_delta: float) -> void:
	DisplayServer.window_set_title("My Game - FPS: " + str(Engine.get_frames_per_second()))
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

# Spawn sand in a circular radius around the given point
func spawn_in_radius(center_x: int, center_y: int, radius: int, material_type: int) -> void:
	# Determine which texture to modify (always modify the one that will be read next)
	var target_texture = texture_rect.texture_a if texture_rect.current_read == 1 else texture_rect.texture_b
	var image = target_texture.get_image()
	
	# Calculate bounds of the circle
	for x in range(max(0, center_x - radius), min(image.get_width(), center_x + radius + 1)):
		for y in range(max(0, center_y - radius), min(image.get_height(), center_y + radius + 1)):
			# Check if the point is within the circular radius
			var dx = x - center_x
			var dy = y - center_y
			var distance_squared = dx * dx + dy * dy
			
			if distance_squared <= radius * radius:
				# Set the pixel to sand (red color)
				image.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))
	
	# Update the texture without creating a new one
	target_texture.update(image)

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

# Convert mouse position to grid coordinates
func get_mouse_tile_pos() -> Vector2i:
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_size = get_viewport().get_visible_rect().size
	var texture_size = texture_rect.texture.get_size()
	
	# Calculate scale factors
	var scale_x = viewport_size.x / texture_size.x
	var scale_y = viewport_size.y / texture_size.y
	
	# Convert mouse position to texture coordinates
	var grid_x: int = int(mouse_pos.x / scale_x)
	var grid_y: int = int(mouse_pos.y / scale_y)
	
	return Vector2i(grid_x, grid_y).clamp(Vector2i.ZERO, Vector2i(texture_size.x - 1, texture_size.y - 1))
