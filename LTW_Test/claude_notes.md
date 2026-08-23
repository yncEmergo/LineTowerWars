# Code/Syntax & Naming conventions
- Be as typesafe as possible
  - never use ":=" in declarations, always write the type out: var time: float = 3.0
  - type function parameters and return values too: func move_to(target: Vector3) -> void
- References between nodes and classes always use @export
  - never use @onready
  - never use $ node paths
  - cross-class references go through Scripts/References.gd: a Node placed in the scene
    that holds every manager and config as @export and exposes them as static getters,
    reached as References.game_config, References.rts_camera and so on
  - a node held by References may read References back, the mutual dependency is fine
  - if a script reads the same References entry often, give it a getter property:
    var _config: GameConfig:
        get:
            return References.game_config
  - UI elements that will gain behaviour later (command slots, ability buttons) are
    prefab scenes, not nodes built in code
- Game-relevant settings belong in config resources (.tres), never in scripts
  - camera settings, unit stats, balancing values, match rules
  - example: Resources/Config/camera_config.tres backed by Scripts/Config/CameraConfig.gd
  - Resources/ is split by kind: Config, Materials, Shaders, UnitStats
  - Scenes/ is split by area, starting with Scenes/UI
  - only visual reference values stay in scripts as constants: placeholder mesh sizes,
    UI positions and offsets, placeholder colors
- Use @export_group for grouping variables
  - "References" and "Settings" are the default groups in most classes
- Naming
  - scripts and folders in PascalCase: Scripts/GameManager.gd, Scripts/Config/CameraConfig.gd
  - resources and scenes in snake_case: main_menu_ui.tscn, game_config.tres
  - every script gets a class_name matching its file name, even if nothing references it yet
- Other than that use the official Godot styleguide (might add some exceptions later)
  - declaration order: class_name, extends, docstring, signals, enums, constants,
    @export vars, public vars, private vars, then methods
  - max line length is 100 characters
- If anything is unclear, please just ask and I'll add it to the Claude.md
