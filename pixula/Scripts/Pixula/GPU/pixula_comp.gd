class_name PixulaCompute
extends Node2D

# Smallest width is 32 cause 16 work groups
const WIDTH = 512 * 2
const HEIGHT = WIDTH / 2
const CELL_SIZE = WIDTH * HEIGHT
const WORK_GROUP = 16
const MAX_MOUSE_POSITIONS = 100

const AIR = 0
const SAND = 1
const WATER = 2
const WALL = 4

var rd: RenderingDevice
var input_buffer: RID
var output_buffer: RID
var buffer_size: int

var simulation_shader: RID
var simulation_pipeline: RID
var simulation_uniform_set: RID

var visualization_shader: RID
var visualization_pipeline: RID
var visualization_uniform_set: RID

# Texture
var render_texture: RID
var render_device_texture: Texture2DRD = Texture2DRD.new()
var push_constants: PackedByteArray

# Spawning
var mouse_buffer: RID
var is_spawning: bool = false
var spawn_radius: int = 0
var current_spawn_material: MouseHandler.MaterialType = MouseHandler.MaterialType.AIR
var mouse_pos: Vector2i
var active_mouse_positions = 0


func disable_spawning() -> void:
	is_spawning = false
	spawn_radius = 0
	current_spawn_material = 0
	update_mouse_positions(Array([]))

func set_spawning(_is_spawning: bool, radius, material_to_spawn: MouseHandler.MaterialType, mouse_positions: Array) -> void:
	is_spawning = _is_spawning
	spawn_radius = radius
	current_spawn_material = int(material_to_spawn)
	update_mouse_positions(mouse_positions)

func update_mouse_positions(positions: Array) -> void:
	var count = min(positions.size(), MAX_MOUSE_POSITIONS)
	var mouse_data = PackedInt32Array()
	mouse_data.resize(1 + MAX_MOUSE_POSITIONS * 2)
	mouse_data.fill(0)
	
	mouse_data[0] = count
	
	# each of the current mouse position
	for i in range(count):
		mouse_data[1 + i] = int(positions[i].x)
		mouse_data[1 + MAX_MOUSE_POSITIONS + i] = int(positions[i].y) # start of second arrray
		
	# upload it!
	var mouse_data_bytes = mouse_data.to_byte_array()
	rd.buffer_update(mouse_buffer, 0, mouse_data_bytes.size(), mouse_data_bytes)
		
func set_push_constants() -> void:
	push_constants = PackedByteArray()
	push_constants.resize(32)
	push_constants.encode_s32(0, WIDTH)
	push_constants.encode_s32(4, HEIGHT)
	push_constants.encode_s32(8, int(is_spawning))
	push_constants.encode_s32(12, spawn_radius)
	push_constants.encode_s32(16, int(current_spawn_material))
	push_constants.encode_s32(20, mouse_pos.x)
	push_constants.encode_s32(24, mouse_pos.y)
	
func setup_mouse_buffer() -> void:
	# current_mouse_position_size = 4 byte
	# mouse_positions themselves = 100 * 8 bytes
	var buffer_size = (4 + MAX_MOUSE_POSITIONS * 8)
	var initial_data = PackedByteArray()
	initial_data.resize(buffer_size)
	mouse_buffer = rd.storage_buffer_create(buffer_size, initial_data)

func setup_in_out_buffers() -> void:
	var cells = PackedInt32Array()
	cells.resize(CELL_SIZE)
	
	var packed_data_array = cells.to_byte_array()
	input_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	output_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	buffer_size = packed_data_array.size()

func setup_output_texture():
	# Create format for the texture
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = WIDTH
	tf.height = HEIGHT
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	
	# Create GPU texture
	render_texture = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(render_texture, Color(0, 0, 0, 0), 0, 1, 0, 1)
	render_device_texture.texture_rd_rid = render_texture
	
	# Set it to the displaying Texture Rect
	$CanvasLayer/TextureRect.texture = render_device_texture

func _initial_setup() -> void:
	#DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Set rendering device used for this compute shader
	rd = RenderingServer.get_rendering_device()
	
	# Simulation Shader
	var sim_shader_file: Resource = load("res://Shaders/pixula_compute.glsl")
	var sim_shader_bytecode: RDShaderSPIRV = sim_shader_file.get_spirv()
	simulation_shader = rd.shader_create_from_spirv(sim_shader_bytecode)
	simulation_pipeline = rd.compute_pipeline_create(simulation_shader)
	
	# Draw Shader
	var vis_shader_file = load("res://Shaders/pixula_draw.glsl")
	var vis_shader_bytecode = vis_shader_file.get_spirv()
	visualization_shader = rd.shader_create_from_spirv(vis_shader_bytecode)
	visualization_pipeline = rd.compute_pipeline_create(visualization_shader)
	
	setup_in_out_buffers()
	setup_mouse_buffer()
	setup_output_texture()
	
	create_simulation_uniform_set()
	create_visualization_uniform_set()
	
func _ready() -> void:
	RenderingServer.call_on_render_thread(_initial_setup)

func update_simulation() -> void:
	rd.buffer_copy(input_buffer, output_buffer, 0, 0, buffer_size)
	set_push_constants()
	simulate()
	draw_simulation()
	swap_buffers()
	
	# Not exactly necessary to re-create them
	create_simulation_uniform_set()
	create_visualization_uniform_set()
	
var clock = 0
func _process(_delta: float) -> void:
	#clock += _delta
	#if clock > 1.0/144.0:
		#clock = 0
	RenderingServer.call_on_render_thread(update_simulation)
	
func simulate() -> void:
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, simulation_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, simulation_uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	

func draw_simulation() -> void:
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, visualization_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, visualization_uniform_set, 0)
	set_push_constants()
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list,  WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	

func count_materials(buffer_rid: RID, material_type: int) -> int:
	var byte_data = rd.buffer_get_data(buffer_rid)
	var data = byte_data.to_int32_array()
	var count = 0
	for value in data:
		if value == material_type:
			count += 1
	return count

func count_image_materials(image: Image) -> int:
	var count = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel_color = image.get_pixel(x, y)
			if pixel_color.r >= 0.2:
				count += 1
	return count
	
func swap_buffers() -> void:
	var temp = input_buffer
	input_buffer = output_buffer
	output_buffer = temp

func create_simulation_uniform_set() -> void:	
	var input_uniform: RefCounted = RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_uniform.binding = 0
	input_uniform.add_id(input_buffer)
	
	var output_uniform: RefCounted = RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)
	
	var mouse_uniform: RefCounted = RDUniform.new()
	mouse_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	mouse_uniform.binding = 2
	mouse_uniform.add_id(mouse_buffer)
	
	if simulation_uniform_set:
		rd.free_rid(simulation_uniform_set)

	# bind the uniforms to slot 0
	simulation_uniform_set = rd.uniform_set_create([input_uniform, output_uniform, mouse_uniform], simulation_shader, 0)

func create_visualization_uniform_set() -> void:
	var sim_buffer_uniform = RDUniform.new()
	sim_buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	sim_buffer_uniform.binding = 0
	sim_buffer_uniform.add_id(output_buffer)
	
	var texture_uniform = RDUniform.new()
	texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform.binding = 1
	texture_uniform.add_id(render_texture)
	
	if visualization_uniform_set:
		rd.free_rid(visualization_uniform_set)
	
	visualization_uniform_set = rd.uniform_set_create([sim_buffer_uniform, texture_uniform], visualization_shader, 0)
