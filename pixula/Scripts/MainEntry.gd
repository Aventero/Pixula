class_name MainEntry
extends Node

signal material_changed(material_type : MaterialType, cursor_size : int)

# UI
@onready var simulator: MainSharp = $MainSharp
@onready var spawn_radius_label: Label = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SpawnRadius/Panel/SpawnRadius
@onready var spawn_radius_slider: HSlider = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SpawnRadius/SpawnRadiusSlider
@onready var pixel_size_label: Label = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/CellSize/Panel/PixelSizeLabel
@onready var pixel_size_slider: HSlider = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/CellSize/PixelSizeSlider
@onready var speed_label: Label = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/Speed/Panel/SpeedLabel
@onready var speed_slider: HSlider = $Overlay/MainPanelContainer/MarginContainer/VBoxContainer/Speed/SpeedSlider
@onready var timer = $Timer

# Simulation
@export var spawn_radius = 5
@export var pixel_size = 8
@export var cell_size = 3

# Window
@export var width = 1600
@export var height = 900
@export var grid_height = height / pixel_size
@export var grid_width = width / pixel_size

# Sim speed
@export var simulation_speed: float = 120.0 # 60Hz
var timestep: float = 1.0/simulation_speed
var accumulator: float = 0.0

var selected_material: MaterialType = MaterialType.SAND
var _is_pressing_ui: bool = false
var _is_handling_resize = false

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

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	simulator.Initialize(width, height, pixel_size, cell_size, spawn_radius)
	setup_mouse_filter($Overlay/MainPanelContainer)
	get_tree().root.size_changed.connect(_on_window_resize)
	setup_ui()
	_on_window_resize()

func _on_window_resize():
	if _is_handling_resize:
		return
	_is_handling_resize = true

	var viewport_rect = get_viewport().get_visible_rect()

	# Find the next fitting size where pixel_size and cell_size fit
	var fitting_size = pixel_size * cell_size
	width = (viewport_rect.size.x / fitting_size) * fitting_size
	height = (viewport_rect.size.y / fitting_size) * fitting_size

	grid_width = width / pixel_size
	grid_height = height / pixel_size

	# Ensure we have valid dimensions
	if grid_width <= 0 or grid_height <= 0:
		grid_width = max(1, grid_width)
		grid_height = max(1, grid_height)

	# Set content size instead of window size
	simulator.ChangeSize(pixel_size, width, height, grid_width, grid_height)

	_is_handling_resize = false

func _process(delta: float) -> void:
	accumulator += delta

	while accumulator >= timestep:
		simulator.Simulate()
		accumulator = 0.0

	simulator.DrawWorld()
	check_mouse_input()

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
	simulator.SpawnRadius = spawn_radius
	spawn_radius_label.text = str(spawn_radius)
	material_changed.emit(selected_material, spawn_radius)

func on_pixel_size_changed(value: float) -> void:
	pixel_size = int(value)
	simulator.PixelSize = pixel_size
	pixel_size_label.text = str(pixel_size)
	grid_width = width / pixel_size
	grid_height = height / pixel_size
	material_changed.emit(selected_material, spawn_radius)


func on_drag_ended(value_changed: bool) -> void:
	if value_changed:
		simulator.ChangeSize(pixel_size, width, height, grid_width, grid_height)

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

func on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_is_pressing_ui = event.pressed

# Mouse
var previous_mouse_pos: Vector2i
var is_drawing: bool


func on_mouse_exit_ui() -> void:
	_is_pressing_ui = false

func _input(event: InputEvent) -> void:
	if event.is_action_released("SPAWN_WATER") or event.is_action_released("SPAWN_SAND"):
		is_drawing = false


func check_mouse_input() -> void:
	var current_mouse_pos: Vector2i = get_mouse_tile_pos()
	simulator.MousePosition = current_mouse_pos

	if _is_pressing_ui:
		is_drawing = false
		return

	# Start drawing on first press
	if Input.is_action_just_pressed("SPAWN_SAND") or Input.is_action_just_pressed("SPAWN_WATER"):
		is_drawing = true
		previous_mouse_pos = current_mouse_pos

	# Draw line while holding button
	if is_drawing:
		var material: MaterialType = MaterialType.AIR if Input.is_action_pressed("SPAWN_WATER") else selected_material
		var points: Array[Vector2i] = get_line_points(previous_mouse_pos, current_mouse_pos)

		for point in points:
			simulator.SpawnInRadius(point.x, point.y, spawn_radius, material)

		previous_mouse_pos = current_mouse_pos


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


func spawn_material_at_mouse(material_type: MaterialType) -> void:
	var mouse_pos: Vector2i = get_mouse_tile_pos()
	simulator.SpawnInRadius(mouse_pos.x, mouse_pos.y, spawn_radius, material_type)

func get_mouse_tile_pos() -> Vector2i:
	var mouse_pos = get_viewport().get_mouse_position()
	var viewport_rect = get_viewport().get_visible_rect()

	# Calculate grid position using viewport rect size
	var grid_x : int = int(mouse_pos.x / pixel_size)
	var grid_y : int = int(mouse_pos.y / pixel_size)

	return Vector2i(grid_x, grid_y).clamp(Vector2i.ZERO, Vector2i(grid_width - 1, grid_height - 1))

func _on_material_button_pressed(material_type: MaterialType) -> void:
	selected_material = material_type
	material_changed.emit(selected_material, spawn_radius)
