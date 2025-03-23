class_name FramebufferSwapper
extends TextureRect

@onready var parent_viewport: SubViewport = get_parent() as SubViewport
@export var sand_spawner: SandSpawner
@export var other_buffer: FramebufferSwapper
@export var is_writing_buffer = false
@export var render_output_rect: TextureRect 
static var frame_count = 0

func _ready() -> void:
	setup_viewport()
	setup_texture()

func get_viewport_render() -> ViewportTexture:
	return parent_viewport.get_texture()

func setup_viewport() -> void:
	parent_viewport.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	parent_viewport.set_update_mode(SubViewport.UPDATE_DISABLED)
	parent_viewport.transparent_bg = false
	parent_viewport.use_hdr_2d = true

func setup_texture() -> void:
	var image_a: Image = create_and_fill_image()
	texture = ImageTexture.create_from_image(image_a)
	material.set_shader_parameter("state_texture", texture)
	material.set_shader_parameter("iteration_count", 0)

func create_and_fill_image() -> Image:
	var image = Image.create(parent_viewport.size.x, parent_viewport.size.y, false, Image.FORMAT_RGBH)
	var initial_count = 0
	for x in parent_viewport.size.x:
		for y in parent_viewport.size.y:
			if randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.SAND])
				continue
			if randf_range(0, 1) <= 0.1:
				initial_count += 1
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.WATER])
				continue
			else:
				image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.AIR])
	print(initial_count)
	return image

func spawn_sand(mouse_pos: Vector2i, spawn_radius: int, material_type: SandSpawner.MaterialType) -> void:
	material.set_shader_parameter("mouse_pos", mouse_pos)
	material.set_shader_parameter("spawn_radius", spawn_radius)
	material.set_shader_parameter("spawn_material", material_type)

func enable_spawning(is_spawning: bool) -> void:
	material.set_shader_parameter("is_spawning", is_spawning)

func _process(_delta: float) -> void:
	if is_writing_buffer:
		render_simulation()

func swap_buffers() -> void:
	is_writing_buffer = not is_writing_buffer

func render_simulation() -> void:
	other_buffer.material.set_shader_parameter("state_texture", parent_viewport.get_texture())
	other_buffer.material.set_shader_parameter("iteration_count", frame_count)
	
	parent_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	render_output_rect.texture = parent_viewport.get_texture()
	
	is_writing_buffer = false  # We're done writing
	other_buffer.is_writing_buffer = true  # Other buffer will write next
	
	frame_count += 1
