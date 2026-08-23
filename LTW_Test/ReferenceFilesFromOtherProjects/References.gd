# class_name References
# extends Node

# static var instance: References

# func _init() -> void:
# 	if instance:
# 		instance.queue_free()
# 	instance = self

# @export var _ui_manager: UIManager
# @export var _game_config: GameConfig
# @export var _creatue_manager: CreatureManager
# @export var _tutorial_manager: TutorialManager
# @export var _ai_referee: AIReferee
# @export var _web_socket_manager: WebSocketManager
# @export var _login_form: LoginForm

# @export var _loading_spinner: LoadingSpinner

# @export var _steam_manager: SteamManager

# static var ui_manager: UIManager:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._ui_manager
# static var game_config: GameConfig:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._game_config
# static var creature_manager: CreatureManager:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._creatue_manager
# static var tutorial_manager: TutorialManager:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._tutorial_manager
# static var ai_referee: AIReferee:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._ai_referee
# static var web_socket_manager: WebSocketManager:
# 	get:
# 		if !instance:
# 			return null
# 		return instance._web_socket_manager
# static var login_form: LoginForm:
# 	get:
# 		return instance._login_form
# static var loading_spinner: LoadingSpinner:
# 	get:
# 		if ui_manager:
# 			return ui_manager.loading_spinner
# 		else:
# 			return instance._loading_spinner
# static var steam_manager: SteamManager:
# 	get:
# 		return instance._steam_manager
# # Technically not necessary to have for singletons, but more coherent imo
# #region Globals
# static var resolution_manager: ResolutionManager:
# 	get:
# 		return ResolutionManager.instance
# static var audio_hub: AudioHub:
# 	get:
# 		return AudioHub.instance
# static var user_manager: UserManager:
# 	get:
# 		return UserManager.instance
# static var scene_manager: SceneManager:
# 	get:
# 		return SceneManager.instance
# #endregion
