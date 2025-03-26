extends Node2D

const WIDTH = 2048 / 2
const HEIGHT = 1024 / 2
const CELL_SIZE = WIDTH * HEIGHT
const WORK_GROUP = 16

const AIR = 0
const SAND = 1
const WATER = 2
const WALL = 4

# Logic
var rd: RenderingDevice
var input_buffer: RID
var output_buffer: RID
var uniform_set: RID
var buffer_size: int

var simulation_shader: RID
var simulation_pipeline: RID
var visualization_shader: RID
var visualization_pipeline: RID
var visualization_uniform_set: RID

# Texture
var render_texture: RID
var img_texture: ImageTexture
func setup_buffers() -> void:
	# Data thats send to the compute shader
	var cells = PackedInt32Array()
	cells.resize(CELL_SIZE)
	var count = 0
	
	for i in range(cells.size()):
		cells[i] = randi_range(0, 1)
		if cells[i] == 1:
			count += 1
	print("initial: ", count)
	
	var packed_data_array = cells.to_byte_array()
	input_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	output_buffer = rd.storage_buffer_create(packed_data_array.size(), packed_data_array)
	buffer_size = packed_data_array.size()

func setup_texture():
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
	
	# Clear with transparent black
	rd.texture_clear(render_texture, Color(0, 0, 0, 0), 0, 1, 0, 1)
	
	# Create a regular image texture for display
	var img = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	img_texture = ImageTexture.create_from_image(img)

func update_display():
	# Get texture data asynchronously
	rd.texture_get_data_async(render_texture, 0, func(img_data):
		var img = Image.create_from_data(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8, img_data)
		img_texture.update(img)
	)

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Set rendering device used for this compute shader
	rd = RenderingServer.create_local_rendering_device()
	
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
	
	setup_buffers()
	setup_texture()
	
	create_simulation_uniform_set()
	create_visualization_uniform_set()
	
	$CanvasLayer/TextureRect.texture = img_texture
	

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		if event.is_action_pressed("SPAWN_SAND"):
			print("Simulated count now: ", count_materials(output_buffer, SAND))
			print("Image count now: ", count_image_materials(img_texture.get_image()))
			#simulate()
			#update_display()
			#swap_buffers()
			#create_uniform_set()

func update_simulation() -> void:
	simulate()
	draw_simulation()
	swap_buffers()
	create_simulation_uniform_set()
	create_visualization_uniform_set()
	

var clock: float = 0
func _process(delta: float) -> void:
	$Overlay/FPS_Label.text = str(Engine.get_frames_per_second())
	update_simulation()
	
func simulate() -> void:
	rd.buffer_copy(input_buffer, output_buffer, 0, 0, buffer_size)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, simulation_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()

func draw_simulation() -> void:
	# Step 2: Run visualization
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, visualization_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, visualization_uniform_set, 0)
	rd.compute_list_dispatch(compute_list,  WIDTH/WORK_GROUP, HEIGHT/WORK_GROUP, 1)
	rd.compute_list_end()
	
	rd.submit()
	rd.sync()
	
	update_display()

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

	if uniform_set:
		rd.free_rid(uniform_set)

	# bind the uniforms to slot 0
	uniform_set = rd.uniform_set_create([input_uniform, output_uniform], simulation_shader, 0)

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
