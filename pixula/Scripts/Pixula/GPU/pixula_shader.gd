extends TextureRect
@export var viewport_a: SubViewport
@export var viewport_b: SubViewport
@export var sim_rect_a: TextureRect
@export var sim_rect_b: TextureRect
@export var sand_spawner: SandSpawner

var texture_a: ImageTexture
var texture_b: ImageTexture

# Timing variables
var frame_count: int = 0
var clock: float = 0
var frame_rate: float = 5

# Which viewport is currently being read from
var current_read: int = 0

func _ready() -> void:
	# Initialize viewports
	viewport_a.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	viewport_b.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	viewport_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_a.use_hdr_2d = true
	viewport_b.use_hdr_2d = true
	
	sim_rect_a.custom_minimum_size = Vector2(viewport_a.size)
	sim_rect_b.custom_minimum_size = Vector2(viewport_b.size)
	
	# Create and set initial images for both viewports
	var image_a: Image = create_image()
	var image_b: Image = create_empty_image()
	
	# Create ImageTextures and apply to TextureRects
	texture_a = ImageTexture.create_from_image(image_a)
	texture_b = ImageTexture.create_from_image(image_b)
	
	sim_rect_a.texture = texture_a
	sim_rect_b.texture = texture_b
	
	# Set shader parameters f"CanvasLayer/VisualRect"or first simulation
	sim_rect_b.material.set_shader_parameter("state_texture", texture_a)
	sim_rect_b.material.set_shader_parameter("iteration_count", frame_count)
	
	viewport_a.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	# Initially display viewport_a texture
	texture = viewport_a.get_texture()
	
	# Start reading from viewport_a
	current_read = 0
	

func _process(delta: float) -> void:
	clock += delta
	if clock >= 1.0/frame_rate:
		clock = 0
		update_simulation()

func create_empty_image() -> Image:
	var image = Image.create(viewport_a.size.x, viewport_a.size.y, false, Image.FORMAT_RGBH)
	for x in viewport_a.size.x:
		for y in viewport_a.size.y:
			image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.AIR])
	return image

func create_image() -> Image:
	var image = Image.create(viewport_a.size.x, viewport_a.size.y, false, Image.FORMAT_RGBH)
	var initial_count = 0
	for x in viewport_a.size.x:
		for y in viewport_a.size.y:
			if randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.SAND])
			elif randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.WATER])
			else:
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.AIR])
	print("Initial particles: ", initial_count)
	return image

func update_simulation() -> void:
	frame_count += 1
	
	# Define which viewport to read from and which to write to
	var read_viewport = viewport_a if current_read == 0 else viewport_b
	var write_viewport = viewport_b if current_read == 0 else viewport_a
	
	# Get corresponding TextureRects
	var write_sim_rect = sim_rect_b if current_read == 0 else sim_rect_a
	
	# Update shader parameters
	write_sim_rect.material.set_shader_parameter("state_texture", read_viewport.get_texture())
	write_sim_rect.material.set_shader_parameter("iteration_count", frame_count)
	
	# Handle sand spawning
	if sand_spawner.is_drawing:
		write_sim_rect.material.set_shader_parameter("spawn_in_texture", sand_spawner.get_spawn_texture())
		write_sim_rect.material.set_shader_parameter("is_spawning", true)
	else:
		write_sim_rect.material.set_shader_parameter("is_spawning", false)
	sand_spawner.clear_spawn_buffer()
	
	# Render to the write viewport
	write_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	# Debug check
	print("Frame: ", frame_count, " Current read: ", current_read)
	
	# Flip read/write viewports for next frame
	current_read = 1 - current_read
	
	# Update the visual display
	if current_read == 0:
		texture_b.update(write_viewport.get_texture().get_image())
		texture = texture_b
	else:
		texture_a.update(write_viewport.get_texture().get_image())
		texture = texture_a
