@tool
extends TextureRect

@export_tool_button("Initialize", "ColorRect")
var upload_button : Callable = initialize.bind()

@export_tool_button("Next Frame", "ColorRect")
var next_frame_button : Callable = update_shader.bind()

@export_tool_button("Reset", "ColorRect")
var reset_button : Callable = reset_variables.bind()

@export var world_viewport : SubViewport
var texture_a: ImageTexture
var texture_b: ImageTexture
var current_read: ImageTexture
var current_write: ImageTexture

@export var frame_count = 0

func _ready() -> void:
	initialize()

func reset_variables() -> void:
	frame_count = 0
	material.set_shader_parameter("iteration_count", frame_count)

func update_shader() -> void:
	# Set shader parameters
	material.set_shader_parameter("iteration_count", frame_count)
	material.set_shader_parameter("state_texture", current_read)
	texture = current_read
	
	# Render to the viewport
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	
	# Get result from viewport
	var viewport_texture = world_viewport.get_texture()
	var result_image = viewport_texture.get_image()
	
	# Check the dimensions
	var viewport_size = Vector2i(world_viewport.size.x, world_viewport.size.y)
	var result_size = Vector2i(result_image.get_width(), result_image.get_height())
	
	print("Viewport size: ", viewport_size)
	print("Result image size: ", result_size)
	
	# Create a new empty image with the correct format and size
	var new_image = Image.create(viewport_size.x, viewport_size.y, false, Image.FORMAT_RF)
	
	# Copy pixel by pixel to ensure correct format
	for x in viewport_size.x:
		for y in viewport_size.y:
			if x < result_size.x && y < result_size.y:
				var color = result_image.get_pixel(x, y)
				# Convert the color value to maintain your encoding
				new_image.set_pixel(x, y, Color(color.r, 0, 0, 1))
	
	# Update current_write with the new image
	current_write.update(new_image)
	
	# Swap textures
	var tmp = current_read
	current_read = current_write
	current_write = tmp
	
	frame_count += 1
	$"../../../TextureRect".material.set_shader_parameter("current_phase", frame_count)
func initialize() -> void:
	# Setup Viewport
	var image_a: Image = create_image()
	var image_b: Image = create_image()
	
	set_cell(image_a, 1, 1, MainEntry.MaterialType.SAND)
	
	texture_a = ImageTexture.create_from_image(image_a)
	texture_b = ImageTexture.create_from_image(image_b)
	
	current_read = texture_a
	current_write = texture_b
	
	material.set_shader_parameter("state_texture", current_read)

func create_image() -> Image:
	var material_type: int = MainEntry.MaterialType.AIR
	var grid_size : Vector2i = world_viewport.size
	var packed_byte_array : PackedByteArray = []
	packed_byte_array.resize(grid_size.x * grid_size.y * 4) # 4 bytes in 32 bit uint

	for x in grid_size.x:
		for y in grid_size.y:
			packed_byte_array.encode_u32((y*grid_size.x + x) * 4, material_type)

	return Image.create_from_data(grid_size.x, grid_size.y, false, Image.FORMAT_RF, packed_byte_array)

func set_cell(image: Image, x: int, y: int, cell_type: int) -> void:
	var pba = PackedByteArray()
	pba.resize(4)
	pba.encode_u32(0, cell_type)  # Encode cell_type as uint32
	var float_val = pba.decode_float(0)  # Convert to float for storage
	image.set_pixel(x, y, Color(float_val, 0.0, 0.0, 1.0))  # Store the float

func get_cell(image: Image, x: int, y: int) -> int:
	var pba = PackedByteArray()
	pba.resize(4)

	var float_val = image.get_pixel(x, y).r  # Retrieve float from image
	pba.encode_float(0, float_val)  # Convert back to packed byte array
	return pba.decode_u32(0)  # Decode as uint32
