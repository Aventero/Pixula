@tool
extends EditorPlugin

# sound players
var typing_sound_player: AudioStreamPlayer = null
var deleting_sound_player: AudioStreamPlayer = null
var selecting_sound_player: AudioStreamPlayer = null
var selecting_word_sound_player: AudioStreamPlayer = null
var selecting_all_sound_player: AudioStreamPlayer = null
var deselecting_sound_player: AudioStreamPlayer = null
var caret_sound_player: AudioStreamPlayer = null
var undo_sound_player: AudioStreamPlayer = null
var redo_sound_player: AudioStreamPlayer = null
var save_sound_player: AudioStreamPlayer = null

# sounds
var typing_sounds: Array[Resource]

# general settings
var volume_db = -35.0

# typing & deleting
var last_char_counts = {}
var last_selection_state = {}
var last_script_char_count: int = 0

# Editor scanning
var script_editor: ScriptEditor = null
var shader_editors = {}
var primary_shader_wrapper = null
var shader_editor_container = null
var scan_timer: float = 0.0
var scan_interval: float = 1.0

# select
var selected_text: String = "none"
var last_selection_time: float = 0.0
var last_selection_length: int = 0
var selection_velocity: float = 0.0
var last_selection_mode: CodeEdit.SelectionMode = CodeEdit.SELECTION_MODE_NONE
var has_unselected: bool = false

# caret
var last_caret_column: int = 0
var last_caret_line: int = 0

# editor
var has_editor_focused: bool = false

# enum
enum ActionType {
	NONE,
	TYPING,
	DELETING,
	SELECTING,
	DESELECTING,
	CARET_MOVING,
	UNDO,
	REDO,
}

func _enter_tree() -> void:
	initialize()
	load_sounds()

	# Load script editor
	script_editor = EditorInterface.get_script_editor()

	# Set up process for checking typing
	set_process(true)

	# Find shader container after UI is fully loaded
	get_tree().create_timer(1.0).timeout.connect(find_shader_editor_wrapper)

func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_S and event.ctrl_pressed and not event.echo and not event.is_released() and has_editor_focused:
			save_sound_player.play()

func _exit_tree() -> void:
	if typing_sound_player:
		typing_sound_player.queue_free()
	if selecting_sound_player:
		selecting_sound_player.queue_free()
	if deleting_sound_player:
		deleting_sound_player.queue_free()
	if selecting_word_sound_player:
		selecting_word_sound_player.queue_free()
	if selecting_all_sound_player:
		selecting_all_sound_player.queue_free()
	if deselecting_sound_player:
		deselecting_sound_player.queue_free()
	if caret_sound_player:
		caret_sound_player.queue_free()
	if undo_sound_player:
		undo_sound_player.queue_free()
	if redo_sound_player:
		redo_sound_player.queue_free()
	if save_sound_player:
		save_sound_player.queue_free()

	set_process(false)

func create_sound_player(volume_multiplier: float = 1.0) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.volume_db = volume_db * volume_multiplier
	add_child(player)
	return player

func initialize() -> void:
	typing_sound_player = create_sound_player()
	selecting_sound_player = create_sound_player(1.2)
	selecting_word_sound_player = create_sound_player()
	deselecting_sound_player = create_sound_player(1.3)
	selecting_all_sound_player = create_sound_player()
	caret_sound_player = create_sound_player(1.5)
	redo_sound_player = create_sound_player()
	undo_sound_player = create_sound_player()
	save_sound_player = create_sound_player(1.5)
	deleting_sound_player = create_sound_player()

func load_sounds() -> void:
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-1.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-2.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-3.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-4.mp3"))
	typing_sound_player.stream = typing_sounds[0]

	selecting_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-char.wav")
	selecting_all_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-word.wav")
	selecting_word_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-all.wav")
	deselecting_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/deselect.wav")
	undo_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-invalid.wav")
	redo_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-confirm.mp3")
	caret_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-movement.mp3")
	save_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/badge-dink.wav")
	deleting_sound_player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-delete.mp3")

func play_random_typing_sound() -> void:
	var random_index = randi() % typing_sounds.size()
	typing_sound_player.stream = typing_sounds[random_index]
	typing_sound_player.play()

func _enable_plugin() -> void:
	add_volume_setting()

func _disable_plugin() -> void:
	if ProjectSettings.has_setting("osu_sounds/volume_db"):
		ProjectSettings.set_setting("osu_sounds/volume_db", null)
		ProjectSettings.save()

func add_volume_setting() -> void:
	if not ProjectSettings.has_setting("osu_sounds/volume_db"):
		ProjectSettings.set_setting("osu_sounds/volume_db", volume_db)
		ProjectSettings.set_initial_value("osu_sounds/volume_db", volume_db)

		# Make sure to add the property info BEFORE calling set_as_basic
		var info: Dictionary = {
			"name": "osu_sounds/volume_db",
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "-80, 0, 0.1"
		}
		ProjectSettings.add_property_info(info)
		ProjectSettings.set_as_basic("osu_sounds/volume_db", true)
		ProjectSettings.save()
	else:
		# Load existing volume from settings.
		volume_db = ProjectSettings.get_setting("osu_sounds/volume_db")
		typing_sound_player.volume_db = volume_db

func _process(delta: float) -> void:
	periodic_shader_editor_scan(delta)

	# Try script editor first, only check shader editors if no sound was played
	var sound_played = play_script_editor_sounds()
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

func play_editor_sounds(code_edit: CodeEdit) -> bool:
	if code_edit:
		has_editor_focused = code_edit.has_focus()
		var current_char_count = code_edit.text.length()
		var current_caret_column = code_edit.get_caret_column()
		var current_caret_line = code_edit.get_caret_line()
		var caret_changed = (current_caret_column != last_caret_column || current_caret_line != last_caret_line)

		# Determine what changed and in what order
		var action_type = ActionType.NONE

		# Check for text changes first
		if current_char_count > last_script_char_count:
			action_type = ActionType.TYPING
		elif current_char_count < last_script_char_count:
			action_type = ActionType.DELETING

		# Check for selection status
		var has_selection_now = code_edit.has_selection()
		var new_selection = code_edit.get_selected_text()
		var current_selection_length = new_selection.length()

		if has_selection_now && current_selection_length != last_selection_length:
			action_type = ActionType.SELECTING
		elif !has_selection_now && last_selection_length > 0:
			action_type = ActionType.DESELECTING
		elif action_type == ActionType.NONE && caret_changed:
			action_type = ActionType.CARET_MOVING

		var single_select: bool = abs(last_selection_length - current_selection_length) == 1

		if Input.is_action_just_pressed("ui_undo") and has_editor_focused:
			action_type = ActionType.UNDO

		if Input.is_action_just_pressed("ui_redo") and has_editor_focused:
			action_type = ActionType.REDO

		# Always update tracking variables
		last_script_char_count = current_char_count
		last_caret_column = current_caret_column
		last_caret_line = current_caret_line

		# Handle sound based on action type
		var sound_played: bool = handle_action(action_type, code_edit, current_selection_length, new_selection)

		if has_selection_now:
			has_unselected = false
			last_selection_length = current_selection_length
		else:
			last_selection_length = 0

		return sound_played
	return false

func play_script_editor_sounds() -> bool:
	var current_editor = script_editor.get_current_editor()
	if current_editor:
		var code_edit: CodeEdit = current_editor.get_base_editor()
		return play_editor_sounds(code_edit)
	return false

func play_shader_editor_sounds() -> bool:
	var sound_played = false
	for editor_id in shader_editors:
		var editor_info = shader_editors[editor_id]
		var code_edit: CodeEdit = editor_info["editor"]
		if is_instance_valid(code_edit):
			sound_played = play_editor_sounds(code_edit)
			if sound_played:
				break

	return sound_played

func handle_action(action_type: ActionType, code_edit: CodeEdit, current_selection_length: int, new_selection: String) -> bool:
	match action_type:
		ActionType.UNDO:
			undo_sound_player.play()
			return true
		ActionType.REDO:
			redo_sound_player.play()
			return true
		ActionType.TYPING:
			play_random_typing_sound()
			return true
		ActionType.DELETING:
			deleting_sound_player.play()
			return true
		ActionType.SELECTING:
			handle_selection(code_edit, current_selection_length, new_selection)
			return true
		ActionType.DESELECTING:
			has_unselected = true
			last_selection_length = 0
			deselecting_sound_player.play()
			return true
		ActionType.CARET_MOVING:
			caret_sound_player.play()
			return true
	return false

func handle_selection(code_edit: CodeEdit, current_selection_length: int, new_selection: String) -> void:
	var single_select: bool = abs(last_selection_length - current_selection_length) == 1
	var current_selection_mode = code_edit.get_selection_mode()

	match current_selection_mode:
		CodeEdit.SelectionMode.SELECTION_MODE_WORD:
			selecting_word_sound_player.play()
		CodeEdit.SelectionMode.SELECTION_MODE_SHIFT, CodeEdit.SelectionMode.SELECTION_MODE_LINE:
			if single_select:
				play_selection_sound(code_edit, current_selection_length, new_selection)
			else:
				selecting_all_sound_player.play()
		_:
			play_selection_sound(code_edit, current_selection_length, new_selection)
	last_selection_length = current_selection_length

func play_selection_sound(code_edit: CodeEdit, selection_length: int, new_selection: String) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_delta = max(0.001, current_time - last_selection_time)  # Avoid division by zero

	# Calculate selection velocity (chars per second) dasd
	selection_velocity = abs(selection_length - last_selection_length) / time_delta

	# Base cooldown and pitch calculations
	var selection_cooldown: float = 0.025
	var base_pitch = 0.8

	# Adjust pitch based on both selection length and velocity
	var length_factor = min(selection_length / 500.0, 0.25)
	var velocity_factor = min(selection_velocity / 500.0, 0.25)
	var pitch_scale = base_pitch + length_factor + velocity_factor

	if current_time - last_selection_time >= selection_cooldown:
		# Add slight randomization for variety
		selecting_sound_player.pitch_scale = pitch_scale * randf_range(0.975, 1.025)
		selecting_sound_player.play()

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
