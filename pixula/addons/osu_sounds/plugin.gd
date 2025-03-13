@tool
extends EditorPlugin

var sound_player_datas: Dictionary[ActionType, SoundPlayerData]

# sounds
var typing_sounds: Array[Resource]

# general settings
var initial_volume_db: int = -35
var volume_db: int = initial_volume_db

# Editor scanning
var primary_shader_wrapper = null
var shader_editor_container = null
var scan_timer: float = 0.0
var scan_interval: float = 1.0

var has_editor_focused: bool = false

enum ActionType {
	NONE,
	TYPING,
	DELETING,
	SELECTING,
	SELECTING_ALL,
	SELECTING_WORD,
	DESELECTING,
	CARET_MOVING,
	UNDO,
	REDO,
	COPY,
	PASTE,
	SAVE
}

var editors: Dictionary[String, SoundEditorInfo] = {}

func _enter_tree() -> void:
	initialize()
	load_sounds()

	# Set up process for checking typing
	set_process(true)

	# Find shader container after UI is fully loaded
	get_tree().create_timer(1.0).timeout.connect(find_shader_editor_wrapper)
	ProjectSettings.settings_changed.connect(_on_settings_changed)

func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_S and event.ctrl_pressed and not event.echo and not event.is_released() and has_editor_focused:
			play_sound(ActionType.SAVE)

func _exit_tree() -> void:
	for data: SoundPlayerData in sound_player_datas.values():
		data.player.queue_free()
	set_process(false)

func create_sound_player(action_type: ActionType, volume_multiplier: float = 1.0) -> AudioStreamPlayer:
	var player_data: SoundPlayerData = SoundPlayerData.new(volume_db, volume_multiplier, ActionType.keys()[action_type])
	player_data.volume_multiplier = volume_multiplier
	player_data.player.volume_db = volume_db * player_data.volume_multiplier
	add_child(player_data.player)
	sound_player_datas[action_type] = player_data
	return player_data.player

func _on_settings_changed() -> void:
	if ProjectSettings.has_setting("osu_sounds/volume_db"):
		volume_db = ProjectSettings.get_setting("osu_sounds/volume_db")
		for player_data: SoundPlayerData in sound_player_datas.values():
			var str: String = "osu_sounds/" + player_data.action_name
			player_data.player.volume_db = volume_db * player_data.volume_multiplier
			player_data.enabled = ProjectSettings.get_setting(str)


func initialize() -> void:
	create_sound_player(ActionType.TYPING)
	create_sound_player(ActionType.SELECTING, 1.2)
	create_sound_player(ActionType.SELECTING_WORD)
	create_sound_player(ActionType.DESELECTING, 1.3)
	create_sound_player(ActionType.SELECTING_ALL)
	create_sound_player(ActionType.CARET_MOVING, 1.5)
	create_sound_player(ActionType.REDO)
	create_sound_player(ActionType.UNDO)
	create_sound_player(ActionType.SAVE, 1.5)
	create_sound_player(ActionType.DELETING)
	create_sound_player(ActionType.COPY)
	create_sound_player(ActionType.PASTE, 1.3)

func load_sounds() -> void:
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-1.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-2.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-3.mp3"))
	typing_sounds.append(load("res://addons/osu_sounds/keyboard_sounds/key-press-4.mp3"))
	sound_player_datas[ActionType.TYPING].player.stream = typing_sounds[0]

	sound_player_datas[ActionType.SELECTING].player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-char.wav")
	sound_player_datas[ActionType.SELECTING_ALL].player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-word.wav")
	sound_player_datas[ActionType.SELECTING_WORD].player.stream = load("res://addons/osu_sounds/keyboard_sounds/select-all.wav")
	sound_player_datas[ActionType.DESELECTING].player.stream = load("res://addons/osu_sounds/keyboard_sounds/deselect.wav")
	sound_player_datas[ActionType.DELETING].player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-delete.mp3")
	sound_player_datas[ActionType.UNDO].player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-invalid.wav")
	sound_player_datas[ActionType.REDO].player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-confirm.mp3")
	sound_player_datas[ActionType.CARET_MOVING].player.stream = load("res://addons/osu_sounds/keyboard_sounds/key-movement.mp3")
	sound_player_datas[ActionType.SAVE].player.stream = load("res://addons/osu_sounds/keyboard_sounds/date-impact.wav")
	sound_player_datas[ActionType.COPY].player.stream = load("res://addons/osu_sounds/keyboard_sounds/check-on.wav")
	sound_player_datas[ActionType.PASTE].player.stream = load("res://addons/osu_sounds/keyboard_sounds/badge-dink-max.wav")

func add_new_editor(code_edit: CodeEdit, editor_id: String) -> void:
	if not editors.has(editor_id):
		editors[editor_id] = SoundEditorInfo.new(code_edit)

func play_random_typing_sound() -> void:
	var random_index = randi() % typing_sounds.size()
	sound_player_datas[ActionType.TYPING].player.stream = typing_sounds[random_index]
	play_sound(ActionType.TYPING)

func _enable_plugin() -> void:
	add_volume_setting()

func _disable_plugin() -> void:
	if ProjectSettings.has_setting("osu_sounds/volume_db"):
		ProjectSettings.set_setting("osu_sounds/volume_db", null)
		ProjectSettings.save()
	for player_data: SoundPlayerData in sound_player_datas.values():
		var str: String = "osu_sounds/" + player_data.action_name
		ProjectSettings.set_setting(str, null)
		ProjectSettings.save()

func add_volume_setting() -> void:
	# Volume setting
	if not ProjectSettings.has_setting("osu_sounds/volume_db"):
		ProjectSettings.set_setting("osu_sounds/volume_db", initial_volume_db)
		ProjectSettings.set_initial_value("osu_sounds/volume_db", initial_volume_db)
		var info = {
			"name": "osu_sounds/volume_db",
			"type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE,
			"hint_string": "-80, 0, 1"
		}
		ProjectSettings.add_property_info(info)
		ProjectSettings.set_as_basic("osu_sounds/volume_db", true)
	else:
		volume_db = ProjectSettings.get_setting("osu_sounds/volume_db")

	# Action settings
	for player_data: SoundPlayerData in sound_player_datas.values():
		var setting_name: String = "osu_sounds/" + player_data.action_name

		if not ProjectSettings.has_setting(setting_name):
			ProjectSettings.set_setting(setting_name, true)
			ProjectSettings.set_initial_value(setting_name, true)

			var info = {
				"name": setting_name,
				"type": TYPE_BOOL,
				"hint": PROPERTY_HINT_NONE,
				"hint_string": ""
			}

			ProjectSettings.add_property_info(info)
			ProjectSettings.set_as_basic(setting_name, true)
		else:
			player_data.enabled = ProjectSettings.get_setting(setting_name)

	ProjectSettings.save()

func _process(delta: float) -> void:
	periodic_editor_scan(delta)
	register_script_editor()

	var sound_played: bool = false
	has_editor_focused = false
	for editor_id: String in editors.keys():
		var info: SoundEditorInfo = editors[editor_id]
		if not is_instance_valid(info.code_edit):
			editors.erase(editor_id)
			continue
		if not sound_played:
			sound_played = play_editor_sounds(editor_id, info)

func periodic_editor_scan(delta: float) -> void:
	# Check for new shader editors periodically
	scan_timer += delta
	if scan_timer >= scan_interval:
		scan_timer = 0.0

		if shader_editor_container:
			check_container_for_shader_editors(shader_editor_container)
		elif not primary_shader_wrapper or not shader_editor_container:
			find_shader_editor_wrapper()

func register_script_editor() -> void:
	var current_editor = EditorInterface.get_script_editor().get_current_editor()
	if current_editor:
		var code_edit = current_editor.get_base_editor()
		if code_edit:
			# Use a consistent ID for the script editor
			var editor_id = "script_editor"

			if not editors.has(editor_id):
				add_new_editor(code_edit, editor_id)
			else:
				editors[editor_id].code_edit = code_edit

func play_shader_editor_sounds() -> bool:
	var sound_played = false
	for editor_id in editors:
		var editor_info: SoundEditorInfo = editors[editor_id]
		sound_played = play_editor_sounds(editor_id, editor_info)
		if sound_played:
			break

	return sound_played

func play_editor_sounds(editor_id: String, info: SoundEditorInfo) -> bool:
	var code_edit: CodeEdit = info.code_edit
	if not has_editor_focused:
		has_editor_focused = code_edit.has_focus()

	var current_char_count = code_edit.text.length()
	var current_caret_column = code_edit.get_caret_column()
	var current_caret_line = code_edit.get_caret_line()
	var caret_changed = (current_caret_column != info.caret_column|| current_caret_line != info.caret_line)

	# Determine what changed and in what order
	var action_type = ActionType.NONE

	# Check for text changes first
	if current_char_count > info.char_count:
		action_type = ActionType.TYPING
	elif current_char_count < info.char_count:
		action_type = ActionType.DELETING

	# Check for selection status
	var has_selection_now = code_edit.has_selection()
	var new_selection = code_edit.get_selected_text()
	var current_selection_length = new_selection.length()

	if has_selection_now && current_selection_length != info.selection_length:
		action_type = ActionType.SELECTING
	elif !has_selection_now && info.selection_length > 0:
		action_type = ActionType.DESELECTING
	elif action_type == ActionType.NONE && caret_changed:
		action_type = ActionType.CARET_MOVING

	var single_select: bool = abs(info.selection_length - current_selection_length) == 1

	if Input.is_action_just_pressed("ui_undo") and has_editor_focused:
		action_type = ActionType.UNDO

	if Input.is_action_just_pressed("ui_redo") and has_editor_focused:
		action_type = ActionType.REDO

	if Input.is_action_just_pressed("ui_copy") and has_editor_focused:
		action_type = ActionType.COPY

	if Input.is_action_just_pressed("ui_paste") and has_editor_focused:
		action_type = ActionType.PASTE

	info.char_count = current_char_count
	info.caret_column = current_caret_column
	info.caret_line = current_caret_line

	var sound_played: bool = handle_action(action_type, code_edit, current_selection_length, new_selection, info)

	if has_selection_now:
		info.has_unselected = false
		info.selection_length = current_selection_length
	else:
		info.selection_length = 0

	return sound_played

func play_sound(action_type: ActionType) -> void:
	var data = sound_player_datas[action_type]
	if data.enabled:
		data.player.play()

func handle_action(action_type: ActionType, code_edit: CodeEdit, current_selection_length: int, new_selection: String, info: SoundEditorInfo) -> bool:
	match action_type:
		ActionType.UNDO:
			play_sound(action_type)
			return true
		ActionType.REDO:
			play_sound(action_type)
			return true
		ActionType.COPY:
			play_sound(action_type)
			return true
		ActionType.PASTE:
			sound_player_datas[ActionType.PASTE].player.pitch_scale = 1.5
			play_sound(action_type)
			return true
		ActionType.TYPING:
			play_random_typing_sound()
			return true
		ActionType.DELETING:
			play_sound(action_type)
			return true
		ActionType.SELECTING:
			return handle_selection(code_edit, current_selection_length, new_selection, info)
		ActionType.DESELECTING:
			info.has_unselected = true
			info.selection_length = 0
			play_sound(action_type)
			return true
		ActionType.CARET_MOVING:
			play_sound(action_type)
			return true
	return false

func handle_selection(code_edit: CodeEdit, current_selection_length: int, new_selection: String, info: SoundEditorInfo) -> bool:
	var single_select: bool = abs(info.selection_length - current_selection_length) == 1
	var current_selection_mode = code_edit.get_selection_mode()

	match current_selection_mode:
		CodeEdit.SelectionMode.SELECTION_MODE_WORD:
			play_sound(ActionType.SELECTING_WORD)
			return true
		CodeEdit.SelectionMode.SELECTION_MODE_SHIFT, CodeEdit.SelectionMode.SELECTION_MODE_LINE:
			if single_select:
				return play_selection_sound(code_edit, current_selection_length, new_selection, info)
			else:
				play_sound(ActionType.SELECTING_ALL)
				return true
		_:
			return play_selection_sound(code_edit, current_selection_length, new_selection, info)
	return false

func play_selection_sound(code_edit: CodeEdit, selection_length: int, new_selection: String, info: SoundEditorInfo) -> bool:
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_delta = max(0.001, current_time - info.last_selection_time)  # Avoid division by zero

	# Calculate selection velocity (chars per second) dasd
	var selection_velocity = abs(selection_length - info.selection_length) / time_delta

	# Base cooldown and pitch calculations
	var selection_cooldown: float = 0.025
	var base_pitch = 0.8

	# Adjust pitch based on both selection length and velocity
	var length_factor = min(selection_length / 500.0, 0.25)
	var velocity_factor = min(selection_velocity / 500.0, 0.25)
	var pitch_scale = base_pitch + length_factor + velocity_factor

	if current_time - info.last_selection_time >= selection_cooldown:
		# Add slight randomization for variety
		sound_player_datas[ActionType.SELECTING].player.pitch_scale = pitch_scale * randf_range(0.975, 1.025)
		play_sound(ActionType.SELECTING)

		# Update tracking variables
		info.last_selection_time = current_time
		info.selection_length = selection_length
		return true
	else:
		# Still update the selected text but don't play sound
		info.selection_length = selection_length
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
				return

# Check a specific container for shader editors
func check_container_for_shader_editors(container: TabContainer) -> bool:
	if not is_instance_valid(container):
		return false

	var previous_editors = editors.duplicate()
	var found_any = false

	for i in range(container.get_tab_count()):
		var tab_control = container.get_tab_control(i)
		if not tab_control or "TextShaderEditor" not in tab_control.name: continue
		found_any = true

		# Find the CodeEdit component(s) in this tab
		var code_edits = []
		find_nodes_by_class(tab_control, "CodeEdit", code_edits)

		for ids in range(code_edits.size()):
			var code_edit = code_edits[ids]
			var editor_id = tab_control.name + "_" + str(ids)

			# Check if this is a new editor
			if not previous_editors.has(editor_id):
				add_new_editor(code_edit, editor_id)
			else:
				editors[editor_id].code_edit = code_edit

	return found_any

# Helper function to find nodes by class
func find_nodes_by_class(node: Node, class_string: String, result: Array) -> void:
	if node.get_class() == class_string:
		result.push_back(node)
	for child in node.get_children():
		find_nodes_by_class(child, class_string, result)
