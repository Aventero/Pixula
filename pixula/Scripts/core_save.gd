class_name PixulaShaderCore

extends TextureRect
var current_read: int = 0

@export var frame_count: int = -1
@export var sand_spawner: SandSpawner
@export var simulation_viewport_a : SubViewport
@export var simulation_viewport_b : SubViewport

@export var visual_rect: TextureRect
@export var sim_rect_a: TextureRect
@export var sim_rect_b: TextureRect
var sim_texture_a: ImageTexture
var sim_texture_b: ImageTexture

var writing_viewport: SubViewport = simulation_viewport_b if current_read == 0 else simulation_viewport_a
var reading_rect: TextureRect = sim_rect_a if current_read == 0 else sim_rect_b
var writing_rect: TextureRect = sim_rect_b if current_read == 0 else sim_rect_a

var clock: float = 0
var frame_rate: float = 300.0
var is_spawning_pixels: bool = false

func _ready() -> void:
	# a
	simulation_viewport_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
	simulation_viewport_a.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	simulation_viewport_a.set_update_mode(SubViewport.UPDATE_DISABLED)
	simulation_viewport_a.transparent_bg = false
	simulation_viewport_a.use_hdr_2d = true
	
	# b
	simulation_viewport_b.render_target_update_mode = SubViewport.UPDATE_DISABLED
	simulation_viewport_b.set_clear_mode(SubViewport.CLEAR_MODE_ONCE)
	simulation_viewport_b.set_update_mode(SubViewport.UPDATE_DISABLED)
	simulation_viewport_b.transparent_bg = false
	simulation_viewport_b.use_hdr_2d = true
	
	initialize()
	
func _process(delta: float) -> void:
	clock += delta
	if clock >= 1.0/frame_rate:
		clock = 0
		update_simulation()

func initialize() -> void:
	var image_a: Image = create_and_fill_image()
	sim_texture_a = ImageTexture.create_from_image(image_a)
	sim_rect_a.material.set_shader_parameter("state_texture", sim_texture_a)
	sim_rect_a.material.set_shader_parameter("iteration_count", frame_count)

	var image_b: Image = create_and_fill_image()
	sim_texture_b = ImageTexture.create_from_image(image_b)
	sim_rect_b.material.set_shader_parameter("state_texture", sim_texture_a)
	sim_rect_b.material.set_shader_parameter("iteration_count", frame_count)
	
	sim_rect_a.texture = sim_texture_a ## THIS IS VERY VERY IMPORTANT
	sim_rect_b.texture = sim_texture_b ## THIS IS VERY VERY IMPORTANT
	
	self.texture = sim_texture_a
	current_read = 0
	swap_buffers()
	
func create_empty_image() -> Image:
	var image = Image.create(simulation_viewport_a.size.x, simulation_viewport_a.size.y, false, Image.FORMAT_RGBH)
	for x in simulation_viewport_a.size.x:
		for y in simulation_viewport_a.size.y:
			image.set_pixel(x, y, sand_spawner.material_color_lookup[SandSpawner.MaterialType.AIR])
	return image

func create_and_fill_image() -> Image:
	var image = Image.create(simulation_viewport_a.size.x, simulation_viewport_a.size.y, false, Image.FORMAT_RGBH)
	var initial_count = 0
	for x in simulation_viewport_a.size.x:
		for y in simulation_viewport_a.size.y:
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

func swap_buffers() -> void:
	writing_viewport = simulation_viewport_b if current_read == 0 else simulation_viewport_a
	reading_rect = sim_rect_a if current_read == 0 else sim_rect_b
	writing_rect = sim_rect_b if current_read == 0 else sim_rect_a

func update_simulation() -> void:
	reading_rect.material.set_shader_parameter("state_texture", writing_viewport.get_texture())
	reading_rect.material.set_shader_parameter("iteration_count", frame_count)
	swap_buffers()
	
	# Render!
	writing_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	
	# visualize
	visual_rect.texture = writing_viewport.get_texture()
	
	current_read = 1 - current_read
	frame_count += 1
	
func spawn_sand(mouse_pos: Vector2i, spawn_radius: int, material_type: SandSpawner.MaterialType) -> void:
	reading_rect.material.set_shader_parameter("mouse_pos", mouse_pos)
	reading_rect.material.set_shader_parameter("spawn_radius", spawn_radius)
	reading_rect.material.set_shader_parameter("spawn_material", material_type)
	writing_rect.material.set_shader_parameter("mouse_pos", mouse_pos)
	writing_rect.material.set_shader_parameter("spawn_radius", spawn_radius)
	writing_rect.material.set_shader_parameter("spawn_material", material_type)

func enable_spawning(is_spawning: bool) -> void:
	reading_rect.material.set_shader_parameter("is_spawning", is_spawning)
	writing_rect.material.set_shader_parameter("is_spawning", is_spawning)
