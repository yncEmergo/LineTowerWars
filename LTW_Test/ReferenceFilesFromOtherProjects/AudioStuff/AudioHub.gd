# @tool
# class_name AudioHub
# extends Node

# # has to have same order as buses in the godot audio tab
# enum Bus 
# {
# 	Master,
# 	Atmo,
# 	SFX,
# 	UI,
# 	Music,
# 	Speech,
# 	Ignore # should always be last
# }

# @export_group("Debug")
# @export var play_debug_stream: bool:
# 	get:
# 		return play_debug_stream
# 	set(value):
# 		if value && debug_stream != null:
# 			play_sound(debug_stream, Bus.Master)
# 		play_debug_stream = false
# 			
# @export var debug_stream: AudioStream

# @export_group("References")
# @export var _audio_config: AudioConfig

# static var instance: AudioHub
# static var audio_config: AudioConfig:
# 	get:
# 		return instance._audio_config

# var audio_stream_players: Array[AudioStreamPlayer]
# var music_audio_stream_player: AudioStreamPlayer
# var current_running_music_clip: String
# var voice_audio_stream_player: AudioStreamPlayer

# func _init() -> void:
# 	if instance != null:
# 		push_error("There is already an AudioHub in the scene. This should never happen. AudioHub is autoload and should not be placed in scenes.")
# 	instance = self

# static func setup_for_run (run: Run) -> void:
# 	run.phase_entered.connect(instance.on_phase_change)
# 	GameManager.ui_controller.map_ui.map_opened.connect(instance.on_map_opened)
# 	GameManager.ui_controller.shop_ui.shop_opened.connect(instance.on_shop_opened)
# 	GameManager.train_editor.train_editor_opened.connect(instance.on_editor_opened)
# 	GameManager.ui_controller.map_ui.map_closed.connect(instance.on_return_to_idle)
# 	GameManager.ui_controller.shop_ui.shop_closed.connect(instance.on_return_to_idle)
# 	GameManager.train_editor.train_editor_closed.connect(instance.on_return_to_idle)

# func _add_new_audio_stream_player() -> AudioStreamPlayer:
# 	var new_audio_stream_player: AudioStreamPlayer = AudioStreamPlayer.new()
# 	audio_stream_players.append(new_audio_stream_player)
# 	add_child(new_audio_stream_player)
# 	return new_audio_stream_player

# static func change_bus_volume(value: float, bus: Bus) -> void:
# 	AudioServer.set_bus_volume_db(bus, linear_to_db(value))

# ## Volume offset wird wsl langfristig vom Bus überschrieben? Not sure though
# static func play_sound(stream: AudioStream, bus: Bus) -> void:
# 	var player: AudioStreamPlayer = instance.get_idle_audio_stream_player()
# 	player.bus = _bus_enum_to_string_name(bus)
# 	if stream is EmergoAudioStreamRandomizer:
# 		player.volume_db = (stream as EmergoAudioStreamRandomizer).volume_offset
# 	player.stream = stream
# 	player.play()
# 	await player.finished
# 	player.volume_db = 0
# 	#print_debug("Play sound: " + stream.resource_name)

# static func play_sound_with_parameters(stream: AudioStream, bus: Bus, pitch_scale:float) -> void:
# 	var player: AudioStreamPlayer = instance.get_idle_audio_stream_player()
# 	var og_pitch_scale: float = player.pitch_scale
# 	if pitch_scale > 0:
# 		player.pitch_scale = pitch_scale

# 	player.bus = _bus_enum_to_string_name(bus)
# 	if stream is EmergoAudioStreamRandomizer:
# 		player.volume_db = (stream as EmergoAudioStreamRandomizer).volume_offset
# 	player.stream = stream
# 	player.play()
# 	await player.finished
# 	player.volume_db = 0
# 	player.pitch_scale = og_pitch_scale

# static func play_voice_sound(stream: AudioStream, bus: Bus, pitch_scale: float = 1.0) -> void:
# 	var player: AudioStreamPlayer = instance.get_voice_audio_stream_player()
# 	player.bus = _bus_enum_to_string_name(bus)
# 	if stream is EmergoAudioStreamRandomizer:
# 		player.volume_db = (stream as EmergoAudioStreamRandomizer).volume_offset
# 	player.stream = stream
# 	player.pitch_scale = pitch_scale
# 	player.stop()
# 	player.play()
# 	await player.finished
# 	player.volume_db = 0
# 	player.pitch_scale = 1.0

# ## intervall play call gets skipped if the cancel condition function returns true
# ## if bus not set or set to Bus.Ignore the bus will not be changed
# static func play_sound_local(
# 		stream: AudioStream,
# 		player: AudioStreamPlayer3D,
# 		sender: Node,
# 		bus: Bus = Bus.Ignore,
# 		skip_condition: Callable = func() -> bool: return false
# 		) -> void:
# 	if !sender.is_inside_tree() || stream == null:
# 		return

# 	if !skip_condition.call():
# 		if bus != Bus.Ignore:
# 			player.bus = _bus_enum_to_string_name(bus)
# 		if stream is EmergoAudioStreamRandomizer:
# 			player.volume_db = (stream as EmergoAudioStreamRandomizer).volume_offset
# 		player.stream = stream
# 		player.play()

# 	if stream is IntervalAudioStream:
# 		var delay_values: Vector2 = (stream as IntervalAudioStream).intervall
# 		var delay: float = randf_range(delay_values.x, delay_values.y)
# 		await player.finished
# 		player.volume_db = 0
# 		if sender == null || !sender.is_inside_tree():
# 			return
# 		await sender.get_tree().create_timer(delay).timeout
# 		if sender == null || player == null:
# 			return
# 		play_sound_local(stream, player, sender, bus, skip_condition)


# static func play_intervall_non_stop(player: AudioStreamPlayer3D,
# 		sender: Node,
# 		exclusive_audio_stream_player: AudioStreamPlayer3D = null,
# 		previous_delay: float = 10,
# 		bus: Bus = Bus.Ignore
# 		) -> void:
# 	
# 	
# 	## Skip if the exclusive audio stream player is playing
# 	if player.stream != null || exclusive_audio_stream_player == null || !exclusive_audio_stream_player.playing:
# 		var stream: IntervalAudioStream = player.stream
# 		if stream is not IntervalAudioStream:
# 			push_error("play_intervall_non_stop called with non IntervalAudioStream")
# 			return
# 		if bus != Bus.Ignore:
# 			player.bus = _bus_enum_to_string_name(bus)
# 		if stream is EmergoAudioStreamRandomizer:
# 			player.volume_db = (stream as EmergoAudioStreamRandomizer).volume_offset
# 			#print_debug("Volume offsett for: " + str(stream.get_stream(0)))
# 		player.play()

# 		var delay_values: Vector2 = stream.intervall
# 		previous_delay = randf_range(delay_values.x, delay_values.y)

# 	await player.finished
# 	player.volume_db = 0
# 	if sender == null || !sender.is_inside_tree():
# 		return
# 	await sender.get_tree().create_timer(previous_delay).timeout
# 	if sender == null || !sender.is_inside_tree():
# 		return
# 	play_intervall_non_stop(player, sender, exclusive_audio_stream_player, previous_delay)



# ## Returns an already existing idle AudioStreamPlayer
# ## If there are none, creates a new one and returns it
# func get_idle_audio_stream_player() -> AudioStreamPlayer:
# 	var tmp: AudioStreamPlayer
# 	for player: AudioStreamPlayer in audio_stream_players:
# 		if player.playing:
# 			continue
# 		
# 		tmp = player
# 	
# 	if tmp == null:
# 		tmp = _add_new_audio_stream_player()
# 	
# 	return tmp

# func get_voice_audio_stream_player() -> AudioStreamPlayer:
# 	#we dont want the voice audio stream player to be in the regualr audio stream players rotation
# 	#since it should only play one voice line at the same time and not be interrupted by other sounds
# 	if !voice_audio_stream_player:
# 		voice_audio_stream_player = AudioStreamPlayer.new()
# 		add_child(voice_audio_stream_player)
# 		voice_audio_stream_player.name = "VoiceAudioStreamPlayer"
# 	
# 	return voice_audio_stream_player
# #region Fade volume
# static func fade_out_volume_3d(audio_player: AudioStreamPlayer3D, duration: float) -> void:
# 	var tween: Tween = audio_player.get_tree().create_tween()
# 	tween.tween_property(audio_player, "volume_db", -30.0, duration)
# 	tween.set_trans(Tween.TRANS_CUBIC)
# 	tween.set_ease(Tween.EASE_IN)
# 	tween.tween_callback(audio_player.stop)
# 	tween.play()

# static func fade_in_volume_3d(audio_player: AudioStreamPlayer3D, duration: float, end_volume: float = 0.0) -> void:
# 	audio_player.play()
# 	audio_player.volume_db = -30.0
# 	var tween: Tween = audio_player.get_tree().create_tween()
# 	tween.tween_property(audio_player, "volume_db", end_volume, duration)
# 	tween.set_trans(Tween.TRANS_CUBIC)
# 	tween.set_ease(Tween.EASE_IN)
# 	tween.play()

# static func fade_out_volume(audio_player: AudioStreamPlayer, duration: float) -> void:
# 	var tween: Tween = audio_player.get_tree().create_tween()
# 	tween.tween_property(audio_player, "volume_db", -30.0, duration)
# 	tween.set_trans(Tween.TRANS_CUBIC)
# 	tween.set_ease(Tween.EASE_IN)
# 	tween.tween_callback(audio_player.stop)
# 	tween.play()

# static func fade_in_volume(audio_player: AudioStreamPlayer, duration: float, end_volume: float = 0.0) -> void:
# 	audio_player.play()
# 	audio_player.volume_db = -30.0
# 	var tween: Tween = audio_player.get_tree().create_tween()
# 	tween.tween_property(audio_player, "volume_db", end_volume, duration)
# 	tween.set_trans(Tween.TRANS_CUBIC)
# 	tween.set_ease(Tween.EASE_IN)
# 	tween.play()

# #endregion
# #region Bus to StringName
# static func _bus_enum_to_string_name(bus: Bus) -> StringName:
# 	match bus:
# 		Bus.Master:
# 			return &"Master"
# 		Bus.SFX:
# 			return &"SFX"
# 		Bus.Music:
# 			return &"Music"
# 		Bus.UI:
# 			return &"UI"
# 		Bus.Atmo:
# 			return &"Atmo"
# 		Bus.Speech:
# 			return &"Speech"
# 	return &"Master"
# #endregion

# #region Music
# func on_phase_change(_phase: Run.Phases) -> void:
# 	_wait_one_frame_and_change_music()
# 	
# 	#match phase:
# 		#Run.Phases.STOPPING:
# 			#pass
# 		#Run.Phases.STOPPED:
# 			#_wait_one_frame_and_change_music()
# 			#pass
# 		#Run.Phases.DRIVING:
# 			#pass
# 		#Run.Phases.ACCELERATING:
# 			#_wait_one_frame_and_change_music()
# 			#pass

# func on_shop_opened() -> void:
# 	#print_debug("Shop opened")
# 	_wait_one_frame_and_change_music()
# 	pass

# func on_map_opened() -> void:
# 	#print_debug("Map Opened")
# 	_wait_one_frame_and_change_music()
# 	pass

# func on_editor_opened() -> void:
# 	#print_debug("editor opened")
# 	_wait_one_frame_and_change_music()
# 	pass

# func on_return_to_idle() -> void:
# 	#print_debug("Back to idle")
# 	_wait_one_frame_and_change_music()
# 	pass

# func _wait_one_frame_and_change_music () -> void:
# 	if instance.music_audio_stream_player == null:
# 		setup_music_audio_stream_player()

# 	await get_tree().process_frame
# 	if GameManager.model.run.current_phase != Run.Phases.STOPPED:
# 		if instance.current_running_music_clip != "main_theme":
# 			instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("main_theme")
# 			instance.current_running_music_clip = "main_theme"
# 	elif GameManager.ui_controller.shop_ui.is_shop_open:
# 		if instance.current_running_music_clip != "station_shop":
# 			instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("station_shop")
# 			instance.current_running_music_clip = "station_shop"
# 	elif GameManager.ui_controller.map_ui.is_open:
# 		if instance.current_running_music_clip != "station_idle":
# 			instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("station_idle")
# 			instance.current_running_music_clip = "station_idle"
# 	elif GameManager.train_editor.is_train_editor_open:
# 		if instance.current_running_music_clip != "station_editor":
# 			instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("station_editor")
# 			instance.current_running_music_clip = "station_editor"
# 	else:
# 		if instance.current_running_music_clip != "station_idle":
# 			instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("station_idle")
# 			instance.current_running_music_clip = "station_idle"

# static func setup_music_audio_stream_player() -> void:
# 	if instance.music_audio_stream_player != null:
# 		return

# 	instance.music_audio_stream_player = instance._add_new_audio_stream_player()
# 	instance.music_audio_stream_player.bus = _bus_enum_to_string_name(Bus.Music)
# 	instance.music_audio_stream_player.stream = audio_config.interactive_music
# 	instance.music_audio_stream_player.play()

# static func play_menu_music() -> void:
# 	setup_music_audio_stream_player()
# 	instance.music_audio_stream_player.get_stream_playback().switch_to_clip_by_name("menu_theme")
# 	instance.current_running_music_clip = "menu_theme"
