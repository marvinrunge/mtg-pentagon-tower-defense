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


## The file as it stands on disk, or the legacy graphics options when there is no file yet.
static func load_file() -> ConfigFile:
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
