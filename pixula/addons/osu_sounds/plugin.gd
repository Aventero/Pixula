@tool
extends EditorPlugin

var typing_sound_player: AudioStreamPlayer = null
var selection_sound_player: AudioStreamPlayer = null

var script_editor: ScriptEditor = null
var last_script_char_count: int = 0
var volume_db = -30.0

var shader_editors = {}  # Track shader editors as a dictionary
var last_char_counts = {}  # Track character counts for editors
var last_selection_state = {}  # Track selection state for each editor

var primary_shader_wrapper = null  # The WindowWrapper that hosts shader editors
var shader_editor_container = null  # The TabContainer that hosts shader editors
var scan_timer: float = 0.0
var scan_interval: float = 1.0  # Check for new editors every second

func _enter_tree() -> void:
	initialize()
	load_sounds()
	add_volume_setting()

	# Load script editor
	script_editor = EditorInterface.get_script_editor()

	# Set up process for checking typing
	set_process(true)

	# Find shader container after UI is fully loaded
	get_tree().create_timer(1.0).timeout.connect(find_shader_editor_wrapper)


func _exit_tree() -> void:
	if typing_sound_player:
		typing_sound_player.queue_free()
	if selection_sound_player:
		selection_sound_player.queue_free()
	set_process(false)

func initialize() -> void:
	typing_sound_player = AudioStreamPlayer.new()
	typing_sound_player.volume_db = volume_db
	add_child(typing_sound_player)

	# Add selection sound player
	selection_sound_player = AudioStreamPlayer.new()
	selection_sound_player.volume_db = volume_db * 1.1
	add_child(selection_sound_player)

func load_sounds() -> void:
	var typing_sound: Resource = load("res://addons/osu_sounds/keyboard_sounds/key-press-1.mp3")
	typing_sound_player.stream = typing_sound

	var selection_sound: Resource = load("res://addons/osu_sounds/keyboard_sounds/select-char.wav")
	selection_sound_player.stream = selection_sound

func add_volume_setting() -> void:
	if not ProjectSettings.has_setting("osu_sounds/volume_db"):
		# Add the volume setting for the plugin
		ProjectSettings.set_setting("osu_sounds/volume_db", volume_db)
		ProjectSettings.set_initial_value("osu_sounds/volume_db", volume_db)
		ProjectSettings.set_as_basic("osu_sounds/volume_db", true)
		var info: Dictionary = {
			"name": "osu_sounds/volume_db",
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "-80, 6, 0.1" # Min, Max, Steps
		}
		ProjectSettings.add_property_info(info)
		ProjectSettings.save()
	else:
		# Load existing volume from settings.
		volume_db = ProjectSettings.get_setting("osu_sounds/volume_db")
		typing_sound_player.volume_db = volume_db

func _process(delta: float) -> void:
	periodic_shader_editor_scan(delta)

	var sound_played: bool = false
	if script_editor:
		sound_played = play_script_editor_sounds()

	if not sound_played:
		play_shader_editor_sounds()

func periodic_shader_editor_scan(delta: float) -> void:
	# Check for new shader editors periodically
	scan_timer += delta
	if scan_timer >= scan_interval:
		scan_timer = 0.0

		# Check volume changes
		if ProjectSettings.has_setting("osu_sounds/volume_db"):
			var current_volume: float = ProjectSettings.get_setting("osu_sounds/volume_db")
			volume_db = current_volume
			typing_sound_player.volume_db = volume_db

		# If already found the wrapper, just check its tab container
		if is_instance_valid(shader_editor_container):
			check_container_for_shader_editors(shader_editor_container)
		# If no wrapper found yet or it became invalid, keep looking for it
		elif not is_instance_valid(primary_shader_wrapper) or not is_instance_valid(shader_editor_container):
			find_shader_editor_wrapper()

var selected_text: String = "none"

var last_selection_time: float = 0.0
var last_selection_length: int = 0
var selection_velocity: float = 0.0


func play_script_editor_sounds() -> bool:
	var current_editor = script_editor.get_current_editor()
	if current_editor:
		var code_edit: CodeEdit = current_editor.get_base_editor()
		if code_edit:
			# Wrote Text logic (unchanged)
			var current_char_count = code_edit.text.length()
			if current_char_count > last_script_char_count:
				typing_sound_player.play()
				last_script_char_count = current_char_count
				return true
			last_script_char_count = current_char_count

			if code_edit.has_selection():
				return play_selection_sound(code_edit)

	return false

func play_selection_sound(code_edit: CodeEdit) -> bool:
	var new_selection: String = code_edit.get_selected_text()
	var selection_length = new_selection.length()

	if selected_text.length() != selection_length:
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_delta = max(0.001, current_time - last_selection_time)  # Avoid division by zero

		# Calculate selection velocity (chars per second) dasd
		selection_velocity = abs(selection_length - last_selection_length) / time_delta

		# Base cooldown and pitch calculations
		var selection_cooldown: float = 0.025
		var base_pitch = 0.9

		# Adjust pitch based on both selection length and velocity
		var length_factor = min(selection_length / 500.0, 0.25)
		var velocity_factor = min(selection_velocity / 500.0, 0.25)
		var pitch_scale = base_pitch + length_factor + velocity_factor

		if current_time - last_selection_time >= selection_cooldown:
			# Add slight randomization for variety
			selection_sound_player.pitch_scale = pitch_scale * randf_range(0.975, 1.025)
			selection_sound_player.play()

			print("length_factor: ", length_factor, " velocity_factor: ", velocity_factor, " Pitch: ", selection_sound_player.pitch_scale)

			# Update tracking variables
			last_selection_time = current_time
			last_selection_length = selection_length
			selected_text = new_selection
			return true
		else:
			# Still update the selected text but don't play sound
			selected_text = new_selection
			last_selection_length = selection_length
	return false

func play_shader_editor_sounds() -> bool:
	var sound_played = false
	for editor_id in shader_editors:
		var editor_info = shader_editors[editor_id]
		var code_edit = editor_info["editor"]
		if is_instance_valid(code_edit):
			var current_char_count = code_edit.get_text().length()
			var previous_count = last_char_counts.get(editor_id, 0)

			# Typing?
			if current_char_count > previous_count:
				typing_sound_player.play()
				sound_played = true
			last_char_counts[editor_id] = current_char_count

			if sound_played:
				break

	return sound_played

func find_shader_editor_wrapper() -> void:
	var base_control = EditorInterface.get_base_control()

	# If no existing editors found, search through all WindowWrappers
	var window_wrappers = []
	find_nodes_by_class(base_control, "WindowWrapper", window_wrappers)

	for wrapper in window_wrappers:
		var tab_containers = []
		find_nodes_by_class(wrapper, "TabContainer", tab_containers)
		for container in tab_containers:
			# Check for any hint this might be a shader container
			if check_container_for_shader_editors(container):
				primary_shader_wrapper = wrapper
				shader_editor_container = container
				print("DEBUG: Identified potential shader container: " + container.name)
				return

# Check a specific container for shader editors
func check_container_for_shader_editors(container: TabContainer) -> bool:
	if not is_instance_valid(container):
		return false

	var previous_editors = shader_editors.duplicate()
	var found_any = false

	for i in range(container.get_tab_count()):
		var tab_control = container.get_tab_control(i)

		if not tab_control or "TextShaderEditor" not in tab_control.name: continue

		found_any = true

		# Find the CodeEdit component(s) in this tab
		var code_edits = []

		find_nodes_by_class(tab_control, "CodeEdit", code_edits)

		for idx in range(code_edits.size()):
			var code_edit = code_edits[idx]
			var editor_id = tab_control.name + "_" + str(idx)

			# Check if this is a new editor
			if not previous_editors.has(editor_id):
				print("DEBUG: Found new shader editor: " + editor_id)
			else:
				# Keep the previous character count
				var previous_count = last_char_counts.get(editor_id, 0)
				last_char_counts[editor_id] = previous_count

			shader_editors[editor_id] = {
				"editor": code_edit,
				"parent_tab": container,
				"tab_index": i
			}

	return found_any

# Helper function to find nodes by class
func find_nodes_by_class(node: Node, class_string: String, result: Array) -> void:
	if node.get_class() == class_string:
		result.push_back(node)
	for child in node.get_children():
		find_nodes_by_class(child, class_string, result)
