class_name SoundEditorInfo
extends RefCounted

var code_edit: CodeEdit
var char_count: int
var caret_column: int
var caret_line: int
var selection_length: int
var has_unselected: bool
var last_selection_time: float

func _init(p_code_edit: CodeEdit) -> void:
	code_edit = p_code_edit
	char_count = p_code_edit.text.length()
	caret_column = p_code_edit.get_caret_column()
	caret_line = p_code_edit.get_caret_line()
	selection_length = 0
	has_unselected = false
	last_selection_time = 0.0
# asdadadadasasaaaaasds
