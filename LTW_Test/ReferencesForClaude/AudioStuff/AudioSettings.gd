# ## Used to store audio settings in SettingsSave.
# class_name AudioSettings
# extends Resource

# @export var master_volume: float = INF
# @export var atmo_volume: float = INF
# @export var sfx_volume: float = INF
# @export var ui_volume: float = INF
# @export var music_volume: float = INF
# @export var speech_volume: float = INF

# func change_value_by_bus(bus: AudioHub.Bus, new_value: float, settings: SettingsSave) -> void:
# 	var trigger_save: bool = false
# 	match bus:
# 		AudioHub.Bus.Master:
# 			if master_volume != new_value:
# 				trigger_save = true
# 				master_volume = new_value
# 		AudioHub.Bus.Atmo:
# 			if atmo_volume != new_value:
# 				trigger_save = true
# 				atmo_volume = new_value
# 		AudioHub.Bus.SFX:
# 			if sfx_volume != new_value:
# 				trigger_save = true
# 				sfx_volume = new_value
# 		AudioHub.Bus.UI:
# 			if ui_volume != new_value:
# 				trigger_save = true
# 				ui_volume = new_value
# 		AudioHub.Bus.Music:
# 			if music_volume != new_value:
# 				trigger_save = true
# 				music_volume = new_value
# 		AudioHub.Bus.Speech:
# 			if speech_volume != new_value:
# 				trigger_save = true
# 				speech_volume = new_value

# 	if trigger_save:
# 		settings.save()
