class_name SoundPlayerData
extends RefCounted

var volume_multiplier: float
var volume: float
var player: AudioStreamPlayer
var enabled: bool

func _init(_volume: int, _volume_multiplier: int) -> void:
	player = AudioStreamPlayer.new()
	volume_multiplier = _volume_multiplier
	volume = _volume
	enabled = true
