extends TextureRect
@export var world_viewport : SubViewport
var texture_a: ImageTexture
var texture_b: ImageTexture
var current_read: int = 0

@export var frame_count: int = -1
var clock: float = 0
var frame_rate: float = 300.0
var is_spawning_pixels: bool = false
@export var sand_spawner: SandSpawner

func _ready() -> void:
	world_viewport.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	world_viewport.set_update_mode(SubViewport.UPDATE_DISABLED)
	world_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world_viewport.transparent_bg = false
	initialize()

func _process(delta: float) -> void:
	clock += delta
	if clock >= 1.0/frame_rate:
		clock = 0
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
			if randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, Color(1.0, 0.8, 0.0, 1.0))
				continue
			if randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, Color(0.0, 0.6, 1.0, 1.0))
				continue
			else:
				image.set_pixel(x, y, Color(0.1, 0.1, 0.1, 1.0))
	print(initial_count)
	return image
	
func set_cell(image: Image, x: int, y: int, cell_type: Color) -> void:
	image.set_pixel(x, y, cell_type)

func update_simulation() -> void:
	frame_count += 1
	$"../../../TextureRect".material.set_shader_parameter("current_phase", frame_count)
	var current_texture = texture_a if current_read == 0 else texture_b
	material.set_shader_parameter("state_texture", current_texture)
	material.set_shader_parameter("iteration_count", frame_count)
	
	spawn_sand()
	
	# Render to the viewport
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	var result_image = world_viewport.get_texture().get_image()
	swap_textures(result_image)

func swap_textures(result_image: Image) -> void:
	if current_read == 0:
		texture_b.update(result_image)
		texture = texture_b
	else:
		texture_a.update(result_image)
		texture = texture_a
	
	# Swap whats currently read
	current_read = 1 - current_read

func spawn_sand() -> void:
	# Get and set the spawn texture
	if sand_spawner.is_drawing:
		material.set_shader_parameter("spawn_in_texture", sand_spawner.get_spawn_texture())
		material.set_shader_parameter("is_spawning", true)
	else:
		material.set_shader_parameter("is_spawning", false)
	sand_spawner.clear_spawn_buffer()
	
func _on_count_pixels_pressed() -> void:
	var image = texture.get_image()
	var count: int = 0
	for x in world_viewport.size.x:
		for y in world_viewport.size.y:
			if image.get_pixel(x, y) == Color(1.0, 0.0, 0.0, 1.0):
				count += 1
	print("Pixels in: ", count)


func _on_next_frame_pressed() -> void:
	clock += 2;
