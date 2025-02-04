extends Sprite2D

# Contains new cursor for each material
var material_cursors : Dictionary = {}
@export var main_entry : MainEntry

func _ready() -> void:
	#Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	load_material_cursors()
	set_material_as_cursor(MainEntry.MaterialType.AIR)

func _process(_delta: float) -> void:
	global_position = main_entry.get_mouse_tile_pos() * main_entry.pixel_size
	main_entry.simulator.DrawDebug()

func load_material_cursors():
	for material_name in MainEntry.MaterialType.keys():
		var material_value : MainEntry.MaterialType = MainEntry.MaterialType[material_name]
		var path : String = get_icon_path(material_value)
		if ResourceLoader.exists(path):
			material_cursors[material_value] = load(path)

func get_icon_path(material_type : MainEntry.MaterialType) -> String:
	var material_name : String = str(MainEntry.MaterialType.keys()[material_type]).to_lower().capitalize()
	material_name = material_name.replace(" ", "_")
	return "res://UI/Sprites/Material_Icons/%s_Icon.png" % material_name

func _on_main_material_changed(material_type: MainEntry.MaterialType, spawn_radius : int) -> void:
	set_material_as_cursor(material_type, 3.0 + (spawn_radius / 4.0))

func set_material_as_cursor(selected_material: MainEntry.MaterialType, cursor_scale : float = 3.0):
	if material_cursors.has(selected_material):
		var cursor_texture = material_cursors[selected_material]
		var image : Image = cursor_texture.get_image()

		# Scale up the image
		var new_width : int = image.get_width() * cursor_scale
		var new_height : int = image.get_height() * cursor_scale
		image.resize(new_width, new_height, Image.INTERPOLATE_NEAREST)


		var border_color : Color = Color.BLACK  # or any color you want
		## Top and bottom lines
		for x in range(new_width):
			image.set_pixel(x, 0, border_color)  # Top
			image.set_pixel(x, new_height - 1, border_color)  # Bottom

		# Left and right lines
		for y in range(new_height):
			image.set_pixel(0, y, border_color)  # Left
			image.set_pixel(new_width - 1, y, border_color)  # Right

		# Create new texture from scaled image
		var viewport_rect = get_viewport().get_visible_rect()

		self.texture = ImageTexture.create_from_image(image)
		print("pixel size", main_entry.pixel_size)
		self.offset = Vector2(main_entry.pixel_size / 2.0 ,main_entry.pixel_size / 2.0)
