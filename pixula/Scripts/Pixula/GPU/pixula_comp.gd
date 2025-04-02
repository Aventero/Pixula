class_name PixulaCompute
extends Node2D

# Smallest width is 32 cause 16 work groups
const WIDTH = 512
const HEIGHT = WIDTH / 2
const PIXELS = WIDTH * HEIGHT
const WORK_GROUP = 16
const MAX_MOUSE_POSITIONS = 200

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

var pressure_shader: RID
var pressure_pipeline: RID
var pressure_uniform_set: RID

var visualization_shader: RID
var visualization_pipeline: RID
var visualization_uniform_set: RID

# Texture
var render_texture: RID
var render_device_texture: Texture2DRD = Texture2DRD.new()
var push_constants: PackedByteArray
var palette_sampler: RID
var palette_texture: RID
@export var palette: Texture2D

# Spawning
var mouse_buffer: RID
var is_spawning: bool = false
var spawn_radius: int = 0
var current_spawn_material: int = MouseHandler.MaterialType.AIR
var mouse_pos: Vector2i
var active_mouse_positions = 0
var pending_mouse_positions: Array[Vector2i]

func disable_spawning() -> void:
	is_spawning = false
	spawn_radius = 0
	current_spawn_material = 0
	update_mouse_positions(Array([]))

func set_spawning(_is_spawning: bool, radius, material_to_spawn: MouseHandler.MaterialType, mouse_positions: Array) -> void:
	is_spawning = _is_spawning
	spawn_radius = radius
	current_spawn_material = int(material_to_spawn)
	pending_mouse_positions.append_array(mouse_positions)

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
	
	# clear
	pending_mouse_positions.clear()
		
func set_push_constants() -> void:
	push_constants = PackedByteArray()
	push_constants.resize(32)
	push_constants.encode_s32(0, WIDTH)
	push_constants.encode_s32(4, HEIGHT)
	push_constants.encode_s32(8, int(is_spawning))
	push_constants.encode_s32(12, spawn_radius)
	push_constants.encode_s32(16, int(current_spawn_material))
	push_constants.encode_s32(20, randi_range(0, 100))
	
func setup_mouse_buffer() -> void:
	var mouse_buffer_size = (4 + MAX_MOUSE_POSITIONS * 4 * 2)
	var initial_data = PackedByteArray()
	initial_data.resize(mouse_buffer_size)
	mouse_buffer = rd.storage_buffer_create(mouse_buffer_size, initial_data)

func setup_in_out_buffers() -> void:
	var buffer_data := PackedByteArray()

	var struct_size_bytes: int = 10 * 4
	buffer_data.resize(PIXELS * struct_size_bytes)
	for i in range(PIXELS):
		var offset = i * struct_size_bytes
		buffer_data.encode_s32(offset, 0)           # material
		buffer_data.encode_s32(offset + 4, 0)       # frame
		buffer_data.encode_s32(offset + 8, -1)      # color_index
		
		buffer_data.encode_float(offset + 12, 0.0)  # velocity_x
		buffer_data.encode_float(offset + 16, 0.0)  # velocity_y
		
		buffer_data.encode_s32(offset + 20, 0)    	# anything
		
		buffer_data.encode_float(offset + 24, 0)    # acc velocity_x
		buffer_data.encode_float(offset + 28, 0)    # acc velocity_y
		
		buffer_data.encode_float(offset + 32, 0)    # pressure_x
		buffer_data.encode_float(offset + 36, 0)    # pressure_y

	input_buffer = rd.storage_buffer_create(buffer_data.size(), buffer_data)
	output_buffer = rd.storage_buffer_create(buffer_data.size(), buffer_data)
	buffer_size = buffer_data.size()

func setup_output_texture() -> void:
	# Create format for the texture
	var tf = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = WIDTH
	tf.height = HEIGHT
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	
	# Create GPU texture
	render_texture = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(render_texture, Color(0, 0, 0, 0), 0, 1, 0, 1)
	render_device_texture.texture_rd_rid = render_texture
	
	# Set it to the displaying Texture Rect
	$CanvasLayer/TextureRect.texture = render_device_texture

func setup_palette() -> void:
	
	var sampler = RDSamplerState.new()
	sampler.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	palette_sampler = rd.sampler_create(sampler)
	
	var format = RDTextureFormat.new()
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	format.width = palette.get_image().get_width()
	format.height = palette.get_image().get_height()
	format.mipmaps = 1
	format.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
	palette_texture = rd.texture_create(
		format,
		RDTextureView.new(),
		[palette.get_image().get_data()]
	)

func _initial_setup() -> void:

	# Set rendering device used for this compute shader
	rd = RenderingServer.get_rendering_device()
	
	# Pressure Shader
	var pressure_shader_file: Resource = load("res://Shaders/pixula_pressure.glsl")
	var pressure_shader_bytecode: RDShaderSPIRV = pressure_shader_file.get_spirv()
	pressure_shader = rd.shader_create_from_spirv(pressure_shader_bytecode)
	pressure_pipeline = rd.compute_pipeline_create(pressure_shader)
	
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
	setup_palette()
	setup_output_texture()
	
	create_simulation_uniform_set()
	create_visualization_uniform_set()
	
func _ready() -> void:
	RenderingServer.call_on_render_thread(_initial_setup)

func process_simulation() -> void:
	RenderingServer.call_on_render_thread(update_simulation)

func update_simulation() -> void:
	set_push_constants()
	update_mouse_positions(pending_mouse_positions)
	simulate()
	
func simulate() -> void:
	# Pressure & Spawn mouse stuff
	create_simulation_uniform_set()
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pressure_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, pressure_uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	
	swap_buffers()
	rd.buffer_copy(input_buffer, output_buffer, 0, 0, buffer_size)
	create_simulation_uniform_set()
	
	## Simulate
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, simulation_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, simulation_uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	
	# Draw
	create_visualization_uniform_set()
	compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, visualization_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, visualization_uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list,  WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	
	swap_buffers()
	rd.buffer_copy(input_buffer, output_buffer, 0, 0, buffer_size)
	
	
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
	pressure_uniform_set = rd.uniform_set_create([input_uniform, output_uniform, mouse_uniform], pressure_shader, 0)
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
	
	var palette_uniform = RDUniform.new()
	palette_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	palette_uniform.binding = 2
	palette_uniform.add_id(palette_sampler) # First sampler
	palette_uniform.add_id(palette_texture) # Then texture
	
	if visualization_uniform_set:
		rd.free_rid(visualization_uniform_set)
	
	visualization_uniform_set = rd.uniform_set_create([sim_buffer_uniform, texture_uniform, palette_uniform], visualization_shader, 0)
