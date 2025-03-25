extends Node2D

const WIDTH = 8
const HEIGHT = 8
const CELL_SIZE = WIDTH * HEIGHT

const AIR = 0
const SAND = 1
const WATER = 2
const WALL = 4

var rd: RenderingDevice
var compute_shader: RID
var compute_pipeline: RID
var input_buffer: RID
var output_buffer: RID
var uniform_set: RID
var buffer_size: int

func setup_buffers() -> void:
	# Data thats send to the compute shader
	var cells = PackedInt32Array()
	cells.resize(CELL_SIZE)
	for i in range(cells.size()):
		cells[i] = AIR
		
	cells[0] = SAND
	cells[1] = SAND
	print(cells)
	
	print("--------------------------------------------------")
	var packed_data_array = cells.to_byte_array()
	input_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	output_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	buffer_size = packed_data_array.size()

func _ready() -> void:
	
	# Set rendering device used for this compute shader
	rd = RenderingServer.create_local_rendering_device()
	
	# Initial compute shader setup
	var compute_shader_file: Resource = load("res://Shaders/pixula_compute.glsl")
	var compute_shader_bytecode: RDShaderSPIRV = compute_shader_file.get_spirv()
	compute_shader = rd.shader_create_from_spirv(compute_shader_bytecode)
	compute_pipeline = rd.compute_pipeline_create(compute_shader)
	
	setup_buffers()
	create_uniform_set()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		if event.is_action_pressed("SPAWN_SAND"):
			simulate()
			swap_buffers()
			create_uniform_set()
			
			# Print after complete cycle
			var final_byte_data = rd.buffer_get_data(input_buffer)
			var final_data = final_byte_data.to_int32_array()
			print(final_data)

func simulate() -> void:
	# GPU - GPU Buffer copy!
	rd.buffer_copy(input_buffer, output_buffer, 0, 0, buffer_size)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, compute_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, 1, 1, 1)
	rd.compute_list_end()
	
	# Force CPU to wait for the GPU to finish the command list
	rd.submit()
	rd.sync()

func swap_buffers() -> void:
	var temp = input_buffer
	input_buffer = output_buffer
	output_buffer = temp

func create_uniform_set() -> void:
	var input_uniform: RefCounted = RDUniform.new()
	input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	input_uniform.binding = 0
	input_uniform.add_id(input_buffer)
	
	var output_uniform: RefCounted = RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 1
	output_uniform.add_id(output_buffer)

	## Have to free uniform set if it exists already
	if uniform_set:
		rd.free_rid(uniform_set)

	# bind the uniforms to slot 0
	uniform_set = rd.uniform_set_create([input_uniform, output_uniform], compute_shader, 0)
