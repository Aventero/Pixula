extends Node2D

@onready var timer: Timer = $Timer

@export var circle_size: int = 3
var width: int = 1600
var height: int = 900

@export_group("C#")
@export var simulation : SimulationCore
@export var simulation_renderer : SimulationRenderer

@export_group("UI")
@export var spawn_radius_label: Label
@export var spawn_radius_slider: HSlider
@export var cell_size_label: Label
@export var cell_size_slider: HSlider
@export var main_container: Control
@export var air_button: Button
@export var sand_button: Button
@export var water_button: Button
@export var rock_button: Button
@export var wall_button: Button

var is_pressing_ui: bool = false
var selected_material: MaterialType = MaterialType.Sand  # Sand
var is_benchmark: bool = false
var enable_debug: bool = false
var sim_speed_seconds: float = 0.001

# Benchmarking
var highest_simulation_time: float = 0.0
var total_simulation_time: float = 0.0
var total_frames: int = 0

# THIS HAS TO BE THE SAME AS THE C# VERSION (sadly)
enum MaterialType {
	Air = 0,
	Sand = 1,
	Water = 2,
	Rock = 3,
	Wall = 4
}

func _ready():
	simulation.Initialize(width, height, simulation_renderer)
	setup_ui()
	get_window().size = Vector2i(width, height)

func setup_ui():
	spawn_radius_slider.value_changed.connect(_on_spawn_radius_changed)
	cell_size_slider.value_changed.connect(_on_cell_size_changed)

	spawn_radius_label.text = str(circle_size)
	spawn_radius_slider.value = circle_size
	cell_size_label.text = str(simulation.PixelSize)
	cell_size_slider.value = simulation.PixelSize

	# Setup material buttons
	$Overlay/MainPanelContainer/MarginContainer/VBoxContainer/AirButton.pressed.connect(func(): selected_material = MaterialType.Air)
	$Overlay/MainPanelContainer/MarginContainer/VBoxContainer/SandButton.pressed.connect(func(): selected_material = MaterialType.Sand)
	$Overlay/MainPanelContainer/MarginContainer/VBoxContainer/WaterButton.pressed.connect(func(): selected_material = MaterialType.Water)
	$Overlay/MainPanelContainer/MarginContainer/VBoxContainer/RockButton.pressed.connect(func(): selected_material = MaterialType.Rock)
	$Overlay/MainPanelContainer/MarginContainer/VBoxContainer/WallButton.pressed.connect(func(): selected_material = MaterialType.Wall)

	set_mouse_filter_on_ui(main_container)

func set_mouse_filter_on_ui(node: Node):
	if node is Button:
		node.gui_input.connect(_on_gui_input)
		node.mouse_exited.connect(_on_mouse_exit)

	if node is HSlider:
		node.gui_input.connect(_on_gui_input)
		node.mouse_exited.connect(_on_mouse_exit)

	for child in node.get_children():
		set_mouse_filter_on_ui(child)

func _on_spawn_radius_changed(value: float):
	circle_size = int(value)
	spawn_radius_label.text = str(circle_size)

func _on_cell_size_changed(value: float):
	simulation.ChangePixelSize(int(value))
	cell_size_label.text = str(value)

func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		is_pressing_ui = event.pressed

func _on_mouse_exit():
	is_pressing_ui = false

func _process(_delta):
	check_mouse_input()
	timer.wait_time = sim_speed_seconds
	var start_time = Time.get_ticks_msec()

	simulation.SimulateActive()

	if is_benchmark:
		benchmark_active(start_time)

	get_window().title = str(Engine.get_frames_per_second())
	var mouse_position = get_mouse_tile_pos()
	print(simulation.PixelSize)
	simulation_renderer.DrawSpawnPreview(mouse_position.x, mouse_position.y, circle_size,
											simulation.PixelSize, simulation.GridWidth, simulation.GridHeight)

func check_mouse_input():
	if Input.is_action_pressed("SPAWN_SAND") and not is_pressing_ui:
		var pos = get_mouse_tile_pos()
		simulation.SpawnInRadius(pos.x, pos.y, circle_size, selected_material)

	if Input.is_action_pressed("SPAWN_WATER") and not is_pressing_ui:
		var pos = get_mouse_tile_pos()
		simulation.SpawnInRadius(pos.x, pos.y, circle_size, MaterialType.Air)

func get_mouse_tile_pos() -> Vector2i:
	var current_size = DisplayServer.window_get_size()
	var scale_factor = Vector2(
		1600.0 / current_size.x,
		900.0 / current_size.y
	)
	var mouse_pos = (get_viewport().get_mouse_position() * scale_factor / simulation.PixelSize).abs()
	return mouse_pos.clamp(Vector2.ZERO, Vector2(simulation.GridWidth - 1, simulation.GridHeight - 1))

func _input(event):
	if event is InputEventMouseButton:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	if event.is_action_released("CHECK_MATERIAL"):
		var mouse_pos = get_mouse_tile_pos()
		print(simulation.GetMaterialAt(mouse_pos.x, mouse_pos.y))

	if event.is_action_released("STATS"):
		initialize_benchmark()

func initialize_benchmark():
	total_frames = 0
	total_simulation_time = 0
	highest_simulation_time = 0
	simulation.SetupPixels()  # Clear simulation

	# Spawn benchmark particles
	var particles_spawned = 0
	const BENCHMARK_PARTICLE_COUNT = 8000
	print("Benchmark with: ", BENCHMARK_PARTICLE_COUNT)

	while particles_spawned < BENCHMARK_PARTICLE_COUNT:
		var x = randi() % simulation.GridWidth
		var y = randi() % simulation.GridHeight
		if simulation.GetMaterialAt(x, y) == 0:  # Air
			simulation.SetStateAt(x, y, 1, simulation.GetRandomVariant(1))  # Sand
			particles_spawned += 1

	is_benchmark = true

func benchmark_active(start_time: int):
	var end_time = Time.get_ticks_msec()
	var current_simulation_time = end_time - start_time
	total_simulation_time += current_simulation_time
	total_frames += 1

	if highest_simulation_time < current_simulation_time:
		highest_simulation_time = current_simulation_time

	if simulation.IsSimulationIdle():
		is_benchmark = false
		var average_time = total_simulation_time / total_frames
		print("Total: %dms | Average: %dms | Highest: %dms | FPS: %d" %
			[total_simulation_time, average_time, highest_simulation_time, Engine.get_frames_per_second()])
