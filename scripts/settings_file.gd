extends RefCounted
## The one file every remembered preference lives in.
##
## Two autoloads write to it - GraphicsSettings (the renderer and what it draws) and
## UserSettings (the name, the volume, the HUD readouts) - each into its own section. They
## go through here rather than each owning a file because a player's settings are one thing
## to them: one file to back up, one file to delete when something goes wrong.
##
## Every write LOADS the file first and changes only its own section, so neither writer can
## wipe what the other saved. That is also why there is no cached ConfigFile here: two
## callers holding their own copies would each save a stale view of the other's section.
##
## Deliberately no `class_name`, preloaded by path instead - see scripts/icon_style.gd for
## why a new global class is a hazard on the headless runs that validate the project.

const PATH := "user://settings.cfg"
## Where graphics options were kept before everything moved into PATH. Read once, the first
## time PATH does not exist yet, so an existing player keeps the options they already chose.
const LEGACY_GRAPHICS_PATH := "user://graphics_settings.cfg"


## The game was called MTG-Pentagon-Tower-Defense until it became Pentafall, and Godot keeps
## user:// in a folder named after the project - so the rename moved it, and a returning
## player would have started over with default settings, signed out of online play.
const OLD_USER_DIR_NAME := "MTG-Pentagon-Tower-Defense"
## What lives in user:// and is worth carrying over. override.cfg is the renderer choice,
## which Godot reads before any script runs, so it takes effect from the launch after this.
const CARRIED_OVER: Array[String] = ["settings.cfg", "graphics_settings.cfg", "override.cfg", "online_auth.json", "online_config.json"]
static var _migrated: bool = false


## Copies a returning player's files from the old project folder, once, and only those the
## new folder does not have yet - nothing written under the new name is ever overwritten.
static func migrate_from_old_name() -> void:
	if _migrated:
		return
	_migrated = true
	var new_dir: String = OS.get_user_data_dir()
	var old_dir: String = new_dir.get_base_dir().path_join(OLD_USER_DIR_NAME)
	if old_dir == new_dir or not DirAccess.dir_exists_absolute(old_dir):
		return
	for file: String in CARRIED_OVER:
		var from: String = old_dir.path_join(file)
		var to: String = new_dir.path_join(file)
		if FileAccess.file_exists(from) and not FileAccess.file_exists(to):
			DirAccess.copy_absolute(from, to)
			print("Settings: carried %s over from %s" % [file, OLD_USER_DIR_NAME])


## The file as it stands on disk, or the legacy graphics options when there is no file yet.
static func load_file() -> ConfigFile:
	migrate_from_old_name()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		return cfg
	var legacy := ConfigFile.new()
	if legacy.load(LEGACY_GRAPHICS_PATH) == OK and legacy.has_section("graphics"):
		for key: String in legacy.get_section_keys("graphics"):
			cfg.set_value("graphics", key, legacy.get_value("graphics", key))
	return cfg


## Writes `values` into `section`, leaving every other section as it was on disk.
static func write_section(section: String, values: Dictionary) -> Error:
	var cfg: ConfigFile = load_file()
	for key: String in values:
		cfg.set_value(section, key, values[key])
	return cfg.save(PATH)
