class_name MouseHandler
extends Node2D
@onready var spawn_radius_label: Label = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SpawnRadius/Panel/SpawnRadius"
@onready var spawn_radius_slider: HSlider = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SpawnRadius/SpawnRadiusSlider"
@onready var pixel_size_label: Label = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/CellSize/Panel/PixelSizeLabel"
@onready var pixel_size_slider: HSlider = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/CellSize/PixelSizeSlider"
@onready var speed_label: Label = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/Speed/Panel/SpeedLabel"
@onready var speed_slider: HSlider = $"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/Speed/SpeedSlider"

@onready var pixula_compute: PixulaCompute = $".."

var selected_material: MaterialType = MaterialType.SAND
var _is_pressing_ui: bool = false

signal material_changed(material_type : MaterialType, cursor_size : int)

# Simulation
@export var spawn_radius = 5
@export var pixel_size = 8

# Sim speed
@export var simulation_speed: float = 120.0 # 60Hz
var timestep: float = 1.0/simulation_speed
var accumulator: float = 0.0

# Material types
enum MaterialType {
	AIR = 0,
	SAND = 1,
	WATER = 2,
	ROCK = 3,
	WALL = 4,
	WOOD = 5,
	FIRE = 6,
	WATER_VAPOR = 7,
	WATER_CLOUD = 8,
	LAVA = 9,
	ACID = 10,
	ACID_VAPOR = 11,
	ACID_CLOUD = 12,
	VOID = 13,
	MIMIC = 14,
	SEED = 15,
	PLANT = 16,
	POISON = 17,
	Ash = 18,
	OIL = 19,
	EMBER = 20,
	SMOKE = 21,
}

var is_drawing: bool = false
var previous_mouse_pos: Vector2i

func _ready() -> void:
	#DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	setup_mouse_filter($"../Overlay/MainPanelContainer")
	setup_ui()

var clock: float = 0
func _process(delta: float) -> void:
	get_window().title = str(Engine.get_frames_per_second())
	$"../Overlay/MainPanelContainer/MarginContainer/VBoxContainer/FPS_Label".text = str(Engine.get_frames_per_second())
	check_mouse_input()
	clock += delta
	if clock > timestep:
		clock = 0
		pixula_compute.process_simulation()

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_WATER") or event.is_action_released("SPAWN_SAND"):
		pixula_compute.disable_spawning()
		is_drawing = false

func check_mouse_input() -> void:
	var current_mouse_pos: Vector2i = get_mouse_tile_pos()
	
	if _is_pressing_ui:
		is_drawing = false
		return
		
	if Input.is_action_just_pressed("SPAWN_WATER") or Input.is_action_just_pressed("SPAWN_SAND"):
		is_drawing = true
		previous_mouse_pos = current_mouse_pos
		
	if is_drawing:
		var mat: MaterialType = MaterialType.AIR if Input.is_action_pressed("SPAWN_WATER") else selected_material
		var points: Array[Vector2i] = get_line_points(previous_mouse_pos, current_mouse_pos)
		pixula_compute.set_spawning(true, spawn_radius, mat, points)
		previous_mouse_pos = current_mouse_pos

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
	var tex_rect: TextureRect = $"../CanvasLayer/TextureRect"
	var texture_size: Vector2i = tex_rect.texture.get_size()
	
	# Calculate scale factors
	var scale_x = viewport_size.x / texture_size.x
	var scale_y = viewport_size.y / texture_size.y
	
	# Convert mouse position to texture coordinates
	var grid_x: int = int(mouse_pos.x / scale_x)
	var grid_y: int = int(mouse_pos.y / scale_y)
	
	return Vector2i(grid_x, grid_y).clamp(Vector2i.ZERO, Vector2i(texture_size.x - 1, texture_size.y - 1))

# UI Setup
func setup_ui() -> void:
	
	# Setup Spawn Radius
	spawn_radius_label.text = str(spawn_radius)
	spawn_radius_slider.value = spawn_radius
	spawn_radius_slider.value_changed.connect(on_radius_slider_changed)

	# Setup Pixel Size
	pixel_size_label.text = str(pixel_size)
	pixel_size_slider.value = pixel_size
	pixel_size_slider.value_changed.connect(on_pixel_size_changed)
	pixel_size_slider.drag_ended.connect(on_drag_ended)

	# Setup Speed
	speed_label.text = str(int(simulation_speed))
	speed_slider.value = simulation_speed
	speed_slider.value_changed.connect(on_speed_slider_changed)

func on_speed_slider_changed(value: float) -> void:
	simulation_speed = value
	timestep = 1.0/simulation_speed
	speed_label.text = str(int(simulation_speed))

func on_radius_slider_changed(value: float) -> void:
	spawn_radius = int(value)
	#simulator.SpawnRadius = spawn_radius
	spawn_radius_label.text = str(spawn_radius)
	material_changed.emit(selected_material, spawn_radius)

func on_pixel_size_changed(value: float) -> void:
	pixel_size = int(value)
	pixel_size_label.text = str(pixel_size)
	material_changed.emit(selected_material, spawn_radius)

func on_drag_ended(_value_changed: bool) -> void:
	pass
	#if value_changed:
		#simulator.ChangeSize(pixel_size, width, height, grid_width, grid_height)

func setup_mouse_filter(control: Control) -> void:
	if control is Button:
		control.gui_input.connect(on_gui_input)
	if control is ScrollContainer:
		control.gui_input.connect(on_gui_input)
		control.mouse_exited.connect(on_mouse_exit_ui)

		# Get and connect scrollbars
		var v_scrollbar = control.get_v_scroll_bar()
		if v_scrollbar:
			v_scrollbar.gui_input.connect(on_gui_input)
			v_scrollbar.mouse_exited.connect(on_mouse_exit_ui)

		var h_scrollbar = control.get_h_scroll_bar()
		if h_scrollbar:
			h_scrollbar.gui_input.connect(on_gui_input)
			h_scrollbar.mouse_exited.connect(on_mouse_exit_ui)

	if control is HSlider:
		control.gui_input.connect(on_gui_input)
		control.mouse_exited.connect(on_mouse_exit_ui)

	for child in control.get_children():
		setup_mouse_filter(child)

func _on_material_button_pressed(material_type: MaterialType) -> void:
	selected_material = material_type
	material_changed.emit(selected_material, spawn_radius)

func on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_is_pressing_ui = event.pressed

func on_mouse_exit_ui() -> void:
	_is_pressing_ui = false
