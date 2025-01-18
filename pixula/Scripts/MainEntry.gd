class_name MainEntry
extends Node

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
@export var simulation_speed: float = 60.0 # 60Hz
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
	VAPOR = 7,
	CLOUD = 8,
	LAVA = 9,
	ACID = 10,
	ACID_VAPOR = 11,
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	simulator.Initialize(width, height, pixel_size, cell_size, spawn_radius)
	get_tree().root.size_changed.connect(_on_window_resize)
	get_window().size = Vector2i(width, height)
	setup_ui()
	setup_mouse_filter($Overlay/MainPanelContainer)

func _on_window_resize():
	if _is_handling_resize:
		return
	_is_handling_resize = true

	var window_size = Vector2i(get_viewport().get_visible_rect().size)

	# Find the next fitting size where pixel_size and cell_size fit
	var fitting_size = pixel_size * cell_size
	width = (window_size.x / fitting_size) * fitting_size
	height = (window_size.y / fitting_size) * fitting_size

	grid_width = width / pixel_size
	grid_height = height / pixel_size

	get_window().size = Vector2(width, height)
	_is_handling_resize = false
	simulator.ChangeSize(pixel_size, width, height, grid_width, grid_height)

func _process(delta: float) -> void:
	accumulator += delta

	while accumulator >= timestep:
		simulator.Simulate()
		accumulator = 0.0

	simulator.DrawImages()
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

func on_pixel_size_changed(value: float) -> void:
	pixel_size = int(value)
	simulator.PixelSize = pixel_size
	pixel_size_label.text = str(pixel_size)
	grid_width = width / pixel_size
	grid_height = height / pixel_size

func on_drag_ended(value_changed: bool) -> void:
	if value_changed:
		simulator.ChangeSize(pixel_size, width, height, grid_width, grid_height)

func setup_mouse_filter(control: Control) -> void:
	if control is Button:
		control.gui_input.connect(on_gui_input)

	if control is HSlider:
		control.gui_input.connect(on_gui_input)
		control.mouse_exited.connect(on_mouse_exit)

	for child in control.get_children():
		setup_mouse_filter(child)

func on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_is_pressing_ui = event.pressed

func on_mouse_exit() -> void:
	_is_pressing_ui = false

# Mouse
func check_mouse_input() -> void:
	simulator.MousePosition = Vector2i(get_mouse_tile_pos())
	if Input.is_action_pressed("SPAWN_SAND") && not _is_pressing_ui:
		spawn_material_at_mouse(selected_material)
	if Input.is_action_pressed("SPAWN_WATER") && not _is_pressing_ui:
		spawn_material_at_mouse(MaterialType.AIR)

	if Input.is_action_pressed("STATS") && not _is_pressing_ui:
		var mouse_pos = get_mouse_tile_pos()
		var color = simulator.GetColorAt(mouse_pos.x, mouse_pos.y)
		print("Color at: ", mouse_pos, ": ", color)

func spawn_material_at_mouse(material_type: MaterialType) -> void:
	var mouse_pos: Vector2i = get_mouse_tile_pos()
	simulator.SpawnInRadius(mouse_pos.x, mouse_pos.y, spawn_radius, material_type)

func get_mouse_tile_pos() -> Vector2i:
	var mousePos: Vector2i = Vector2i((get_viewport().get_mouse_position() / pixel_size).abs())
	return mousePos.clamp(Vector2i.ZERO, Vector2i(grid_width - 1, grid_height -1))

func _on_material_button_pressed(material_type: MaterialType) -> void:
	selected_material = material_type
