extends TextureRect
@export var world_viewport : SubViewport
var texture_a: ImageTexture
var texture_b: ImageTexture
var current_read: int = 0
@export var frame_count: int = 0
var clock: float = 0
var frame_rate: float = 60.0


func _ready() -> void:
	world_viewport.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	world_viewport.set_update_mode(SubViewport.UPDATE_DISABLED)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world_viewport.transparent_bg = false
	initialize()

func _process(delta: float) -> void:
		update_simulation()
	
func initialize() -> void:
	var image_a: Image = create_image()
	var image_b: Image = create_empty_image()
	
	texture_a = ImageTexture.create_from_image(image_a)
	texture_b = ImageTexture.create_from_image(image_b)
	
	material.set_shader_parameter("state_texture", texture_a)
	material.set_shader_parameter("iteration_count", frame_count)
	texture = texture_a
	current_read = 0

func create_empty_image() -> Image:
	var image = Image.create(world_viewport.size.x, world_viewport.size.y, false, Image.FORMAT_RGB8)
	for x in world_viewport.size.x:
		for y in world_viewport.size.y:
			image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	return image
	
func create_image() -> Image:
	var image = Image.create(world_viewport.size.x, world_viewport.size.y, false, Image.FORMAT_RGB8)
	var initial_count = 0
	for x in world_viewport.size.x:
		for y in world_viewport.size.y:
			if randf_range(0, 1) <= 0.2:
				initial_count += 1
				image.set_pixel(x, y, Color(1.0, 0.0, 0.0, 1.0))
			else:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 1.0))
	print(initial_count)
	return image
	
func set_cell(image: Image, x: int, y: int, cell_type: float) -> void:
	image.set_pixel(x, y, Color(cell_type, 0.0, 0.0, 1.0))

func update_simulation() -> void:
	frame_count += 1
	$"../../../TextureRect".material.set_shader_parameter("current_phase", frame_count)
	
	# Set the current read texture as shader input
	var current_texture: ImageTexture = texture_a if current_read == 0 else texture_b
	material.set_shader_parameter("state_texture", current_texture)
	material.set_shader_parameter("iteration_count", frame_count)
	
	# Render to the viewport (it will use the shader with the current texture)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	
	# Get the result and update the other texture
	var result_image = world_viewport.get_texture().get_image()
	
	# Update the non-current texture with the result
	if current_read == 0:
		texture_b.update(result_image)
		texture = texture_b
	else:
		texture_a.update(result_image)
		texture = texture_a
	
	# Swap read/write buffers
	current_read = 1 - current_read

func _on_count_pixels_pressed() -> void:
	var image = texture.get_image()
	var count: int = 0
	for x in world_viewport.size.x:
		for y in world_viewport.size.y:
			if image.get_pixel(x, y) == Color(1.0, 0.0, 0.0, 1.0):
				count += 1
	print("Pixels in: ", count)
