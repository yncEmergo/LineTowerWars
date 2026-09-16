# class_name AudioConfig
# extends Resource

# @export_group("UI Sounds")
# @export var shop_purchase_sound: AudioStream
# @export var shop_reroll_sound: AudioStream

# @export var menu_click: AudioStream
# @export var menu_click_disabled: AudioStream
# @export var menu_click_hover: AudioStream
# @export var menu_start_game: AudioStream
# @export var menu_whoosh: AudioStream
# @export var unlock_hover_whoosh: AudioStream
# @export var unlock_appear: AudioStream
# @export var unlock_pressed: AudioStream

# @export var booster_pack_open: AudioStream
# @export var booster_pack_hover: AudioStream

# @export var station_reward_hover: AudioStream
# @export var station_reward_open: AudioStream
# @export var station_reward_appear: AudioStream

# @export_group("Map")
# @export var map_open: AudioStream
# @export var map_close: AudioStream
# @export var map_station_hover: AudioStream
# @export var map_station_select: AudioStream
# @export var map_station_entered: AudioStream

# @export_group("Extradiegetic Soundeffects")
# @export var action_used_sound: AudioStream
# @export var lose_patience_sound: AudioStream
# @export var extacy_converted: AudioStream
# @export var drive_start: AudioStream
# @export var drive_stop: AudioStream
# @export var strike: AudioStream
# @export var game_over_by_strikes: AudioStream
# @export var game_over_by_money: AudioStream

# @export var ability_used_sound: AudioStream
# @export var ability_target_selected: AudioStream
# @export var ability_target_deselected: AudioStream
# @export var ability_not_usable: AudioStream

# @export_group("Train Atmo")
# @export var train_drive_interactive_cycle: AudioStream
# @export var train_rails_sound: AudioStream
# @export var train_station_stingers: AudioStream
# ## Currently not used, this is handled within station scenes
# @export var train_tation_atmo: AudioStream
# @export var train_announcements_atmo: AudioStream

# @export_group("Passenger Sounds")
# @export var passenger_grab: AudioStream
# @export var passenger_reset: AudioStream
# @export var passenger_drop: AudioStream
# @export var passenger_swap: AudioStream
# @export var passenger_lose_patience: AudioStream
# @export var passenger_leave_train_in_anger: AudioStream
# @export var passenger_leave_train: AudioStream
# @export var passenger_enter_train: AudioStream
# @export var passenger_cannot_enter_train: AudioStream
# @export var passenger_force_moved_generic: AudioStream
# @export var passenger_force_moved_smelly: AudioStream
# @export var passenger_force_moved_loud: AudioStream
# @export var passenger_gets_happy: AudioStream
# @export var passenger_gets_neutral: AudioStream
# @export var passenger_gets_angry: AudioStream
# @export var passenger_picked_up: AudioStream
# @export var passenger_swapped: AudioStream
# @export var passenger_is_negative_stinger: AudioStream
# @export var passenger_is_happy_stinger: AudioStream
# @export var passenger_is_neutral_stinger: AudioStream
# @export var passenger_is_angry_stinger: AudioStream

# @export var single_coin_received: AudioStream
# @export var multiple_coins_received: AudioStream
# @export var money_stolen_by_criminal: AudioStream

# @export_group("Train Editor")
# @export var module_drop: AudioStream
# @export var module_remove: AudioStream
# @export var module_rotate: AudioStream
# @export var module_decline_placement: AudioStream
# @export var module_preview_move: AudioStream
# @export var module_overbuilt: AudioStream

# @export_group("Music")
# @export var interactive_music: AudioStreamInteractive

# @export_group("Polaroid")
# @export var polaroid_opened: AudioStream

# @export_group("Ambient Dialogue")
# ## Short utterances played one after another while a passenger speaks. Used for every species
# ## that has no clips of its own below, so a newly added species is never silent.
# @export var ambient_dialogue_default_utterance_clips: Array[AudioStream]
# ## Optional utterances per species, so a shark can sound different from a sheep.
# ## Values are Array[AudioStream], the same shape as the default clips above.
# @export var species_to_ambient_dialogue_utterance_clips: Dictionary[PassengerSpecies, Array]

# @export_group("Test Sounds for Settings")
# @export var atmo_test_sound: AudioStream
# @export var sfx_test_sound: AudioStream
# @export var ui_test_sound: AudioStream
# @export var speech_test_sound: AudioStream

# @export var twitch_connect_clip: AudioStream

# ## Returns the utterances a passenger of this species speaks with, falling back to the
# ## default clips whenever the species has no own entry or its entry was left empty.
# func get_ambient_dialogue_utterance_clips(species: PassengerSpecies) -> Array:
# 	if species != null && species_to_ambient_dialogue_utterance_clips.has(species):
# 		var clips: Array = species_to_ambient_dialogue_utterance_clips[species]
# 		if !clips.is_empty():
# 			return clips
# 	return ambient_dialogue_default_utterance_clips
