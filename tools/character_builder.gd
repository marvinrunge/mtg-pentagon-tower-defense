class_name CharacterBuilder
extends RefCounted
## Builds every Melee/Ranged/Mage enemy scene from the new (2026-08-25) mesh and
## animation set, replacing tools/melee_character_builder.gd's output entirely
## (output paths: res://scenes/melee/<race>_melee.tscn, res://scenes/ranged/<race>_ranged.tscn,
## res://scenes/mage/<race>_mage.tscn - mage previously had no dedicated visual at all).
##
## Structurally the same problem solved for bosses/myrs (tools/boss_character_builder.gd,
## tools/myr_character_builder.gd): Mixamo-rigged meshes at a tiny raw import scale,
## clips borrowed across files needing a per-character grounding correction. See
## those files' own comments for why each technique is needed; not re-derived here.
##
## Source layout:
##   assets/enemies/<class>/<race>/<race>_<class>.fbx   mesh (+ own embedded clip)
##   assets/animations/character/<set>/{walk,attack,hit,death}.fbx   shared clips
##   assets/animations/unused/<set>/<run>.fbx                        the run cycle
##   assets/animations/character/mage/attack_<color>.fbx             per-colour mage attack
##   assets/animations/character/common/{throw_object,death_fallback}.fbx
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/build_characters.gd
##
## Deadlocks if an editor already holds the project lock; while the editor is open,
## call CharacterBuilder.build_all() through Godot MCP's execute_editor_script -
## and if this file has already been edited/re-run more than once in that same
## long-lived session, don't trust ResourceLoader.load(path, "", CACHE_MODE_REPLACE)
## to see the latest source; read it with FileAccess and compile a class_name-
## stripped throwaway GDScript instead (see .agents/learnings.md).

const AnimationImpact = preload("res://tools/animation_impact.gd")

const ANIM_ROOT := "res://assets/animations/character/"
## Mixamo shipped a run cycle for every rig in the cast and nothing ever used one, so they
## were filed here rather than alongside the clips the builder reads. They are sources like
## any other now; the folder name is history, not a status.
const UNUSED_ROOT := "res://assets/animations/unused/"
const CHAR_ROOT := "res://assets/enemies/"
const WEAPON_ROOT := "res://assets/weapons/"
const SCENE_DIR := "res://scenes/"

## Matches the 1.7-tall collision box in scenes/enemy.tscn, same as every other
## non-boss enemy visual this project has ever built.
const TARGET_HEIGHT := 1.7

## What the game actually renders these characters at. The builder normalises a character
## to TARGET_HEIGHT at a root scale of 85, and then EnemyBase instantiates the finished
## scene and OVERWRITES that with 100 (scripts/enemy_base.gd, the visual block) - so an
## enemy on screen is 1.18x the size the builder aimed at. Weapons are sized against this
## number rather than against the skeleton's build-time scale, so WEAPON_MODELS.length is
## the length the weapon has in front of the player rather than on the workbench.
const RUNTIME_VISUAL_SCALE := 100.0

const FOOT_BONES := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
const GROUND_SAMPLE_COUNT := 20

## Sentinel meaning "use this character's own mesh-embedded clip" for a given
## slot, instead of a shared file - only goblin_ranged's "walk" needs this (its
## own mesh was downloaded bundled with its own orc-walk cycle, per the user's
## explicit instruction to use that rather than a shared file).
const OWN_MESH_CLIP := "__OWN_MESH__"

const RACE_BY_COLOR := {
	"White": "human", "Blue": "merfolk", "Black": "zombie", "Red": "goblin", "Green": "elf",
}

## The clips a character plays to MOVE, as opposed to the one-shot attack/hit/death ones.
## Both are looped here; both also need a measured `stride_speed`, which is what lets
## EnemyBase pick between them and play the winner at the rate the enemy is really
## travelling - but that measurement cannot be taken from inside this builder (it needs a
## live scene tree) and is applied afterwards by tools/locomotion_pass.gd.
const LOCOMOTION_CLIPS: Array[String] = ["walk", "run"]

## animation-set name -> clip slot -> source fbx (or OWN_MESH_CLIP).
##
## The "run" entries come out of assets/animations/unused/, which is where every rig's run
## cycle had been sitting unused since the cast was built: enemies only ever had a walk, so
## a Melee travelling at 2.5 units per second played a 1.04-unit walk cycle and skated.
## Sets with no run of their own borrow the nearest rig's, exactly as they already borrow
## walk and attack - noted per entry below.
const CLIP_SETS := {
	# Attack borrowed from standing_melee per the user's instruction (2026-09-02)
	# that the human's own swing reads as too strange - it is a shield-bash-then-slash
	# that measured two impacts, at 25% and 55%, against the one clean strike at 40%
	# every other melee enemy uses. Walk/hit/death stay sword-and-shield's own.
	"sword_and_shield": {
		"walk": ANIM_ROOT + "sword_and_shield/walk.fbx",
		"run": UNUSED_ROOT + "sword_and_shield/Sword And Shield Run.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"hit": ANIM_ROOT + "sword_and_shield/hit.fbx",
		"death": ANIM_ROOT + "sword_and_shield/death.fbx",
	},
	# Mixamo's standing-melee pack has no death clip of its own (same gap noted
	# for the fire/frost giant bosses) - borrows the shared fallback.
	"standing_melee": {
		"walk": ANIM_ROOT + "standing_melee/walk.fbx",
		"run": UNUSED_ROOT + "standing_melee/standing run forward.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"hit": ANIM_ROOT + "standing_melee/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	# Walk/attack borrowed from standing_melee per the user's explicit request
	# (2026-08-25) that melee zombies move/attack like goblin-melee; hit/death
	# stay zombie-specific.
	"zombie": {
		# Melee zombies already borrow standing_melee's walk and attack; the zombie rig's
		# own run is kept here, though, because a shambling sprint is the whole read.
		"walk": ANIM_ROOT + "standing_melee/walk.fbx",
		"run": UNUSED_ROOT + "zombie/zombie running.fbx",
		"attack": ANIM_ROOT + "standing_melee/attack.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	"bow": {
		"walk": ANIM_ROOT + "bow/walk.fbx",
		"run": UNUSED_ROOT + "bow/Standing Run Forward.fbx",
		"attack": ANIM_ROOT + "bow/attack.fbx",
		"hit": ANIM_ROOT + "bow/hit.fbx",
		"death": ANIM_ROOT + "bow/death.fbx",
	},
	"crossbow": {
		"walk": ANIM_ROOT + "crossbow/walk.fbx",
		"run": UNUSED_ROOT + "crossbow/Rifle Run.fbx",
		"attack": ANIM_ROOT + "crossbow/attack.fbx",
		# Hit borrowed from the bow rig, because crossbow/hit.fbx is not a hit - it is a
		# SECOND death. Measured on the human: over its 1.77s the head drops to 13% of the
		# height it started at and stays down, against 5% for crossbow/death.fbx and 100%
		# for every genuine flinch in the cast. Human and Merfolk Ranged were therefore
		# dying every time they were grazed and standing back up afterwards.
		# bow/hit is the other RANGED rig, so the upper body reads right, and at 1.0s it
		# compresses far more kindly into enemy_hit_react_duration than 1.77s did.
		"hit": ANIM_ROOT + "bow/hit.fbx",
		"death": ANIM_ROOT + "crossbow/death.fbx",
	},
	"goblin_ranged": {
		# No run of its own - the mesh came bundled with a walk only. Borrows the zombie
		# rig's, which is the closest hunched silhouette in the set.
		"walk": OWN_MESH_CLIP,
		"run": UNUSED_ROOT + "zombie/zombie running.fbx",
		"attack": ANIM_ROOT + "common/throw_object.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	"zombie_ranged": {
		"walk": ANIM_ROOT + "zombie/walk.fbx",
		"run": UNUSED_ROOT + "zombie/zombie running.fbx",
		"attack": ANIM_ROOT + "common/throw_object.fbx",
		"hit": ANIM_ROOT + "zombie/hit.fbx",
		"death": ANIM_ROOT + "common/death_fallback.fbx",
	},
	# "attack" is deliberately absent - every mage gets a different one, added
	# per-character in _build_character (config.attack below).
	"mage": {
		"walk": ANIM_ROOT + "mage/walk.fbx",
		"run": UNUSED_ROOT + "mage/Standing Run Forward.fbx",
		"hit": ANIM_ROOT + "mage/hit.fbx",
		"death": ANIM_ROOT + "mage/death.fbx",
	},
}

## WEAPON_GLB is the MELEE path (right hand, +Y-up model, the hand-tuned lean constants
## below). WEAPON_MODEL is the ranged one: a real glb with its own orientation, described
## per weapon in WEAPON_MODELS. BOW and CROSSBOW are the stand-in boxes those replaced and
## are now unreferenced - kept only so _build_prop_mesh still reads as the history of what
## was there, and safe to delete with them.
enum Prop { NONE, WEAPON_GLB, BOW, CROSSBOW, STONE, BONE_SMALL, WEAPON_MODEL }


## Where each ranged weapon model came from and how it is worn, one entry per weapon.
##
## Deliberately per weapon rather than one shared correction like the melee kit's
## WEAPON_LEAN_DEGREES. Those three constants work because every melee weapon is the same
## shape - a ~2m blade running up +Y, held in a fist. These three agree about nothing:
## measured off the imported meshes, the bow runs along +X, the crossbow along +Z and the
## harpoon along +X again, and all three are 1.0 long where a melee weapon is 2.0. A single
## correction covering that would just be three magic numbers wearing a trenchcoat.
##
##   glb      the model
##   bone     which hand wears it. The left, for all three: it is the bow hand, and the
##            fore-end hand on a crossbow, which is also where the stand-ins hung.
##   length   how long it should end up IN THE WORLD, in metres, measured along `axis`.
##            The characters are normalised to 1.7m, so these are readable as real sizes.
##   axis     the model's OWN long axis, as measured. Used both to scale it (see
##            _attach_weapon_model) and to know what is being rotated where.
##   aim      the direction, IN THE CHARACTER'S OWN SPACE, that `axis` should end up
##            pointing while the character is standing in `pose`. Up is up; Vector3.BACK
##            is the way the character faces. Converted into the skeleton's frame at build
##            time, which is a quarter turn off the character's own. A bow stands upright across the bow hand; a crossbow and
##            a harpoon point down-range. Stated in world terms and converted into the
##            bone's frame at build time, so it does not have to be re-derived per rig.
##   pose     the clip, and how far into it, that `aim` is measured against. NOT the rest
##            pose: these rigs' walk and attack clips are authored for a character already
##            holding this kind of weapon, so the hand is rolled well away from rest in
##            exactly the poses the weapon is seen in. Aiming a bow upright in the rest
##            pose puts it flat on its side for the whole march. "walk" is the default
##            because it is what the player looks at for most of a wave.
##   roll     degrees to spin the weapon about `aim`, which is the one thing aiming an
##            axis cannot settle - a bow aligned upright can still be facing edge-on.
##   grip     metres to shift it after rotating, so the part that should sit in the fist
##            does. World units, divided down by the armature scale at build time.
##
## `roll` and `grip` are the only hand-found numbers here, and only because nothing in the
## model says which way is front. Everything else is derived: see _attach_weapon_model.
##
## They are the STARTING point, not the last word. Anything further is adjusted with the
## gizmo in the editor and then captured by tools/capture_weapon_fit.gd into
## WEAPON_FIT_PATH, which this applies on top - see _weapon_fit. That indirection exists
## because a rebuild rewrites these scenes from scratch, so an edit that lives only in the
## .tscn is an edit that disappears the next time anything is rebuilt.
## Hand adjustments captured out of the editor, laid on top of the derived placement.
##
## A separate data file rather than more numbers in WEAPON_MODELS below, because it is
## WRITTEN by a tool: tools/capture_weapon_fit.gd rewrites it every time it runs, and a
## tool that rewrites its own source file is a tool that can break the build it belongs
## to. Missing or empty is the normal state for a weapon nobody has needed to nudge.
const WEAPON_FIT_PATH := "res://assets/weapons/weapon_fit.json"

const WEAPON_MODELS := {
	"Ranged/Green": {
		"glb": WEAPON_ROOT + "elf-bow.glb",
		"bone": "mixamorig_LeftHand",
		"length": 1.6,
		"axis": Vector3.RIGHT,
		"aim": Vector3.UP,
		"pose": ["walk", 0.5],
		"roll": 0.0,
		"grip": Vector3(0.0, 0.0, 0.0),
	},
	"Ranged/White": {
		"glb": WEAPON_ROOT + "human-crossbow.glb",
		"bone": "mixamorig_LeftHand",
		"length": 1.0,
		"axis": Vector3.BACK,
		"aim": Vector3.BACK,
		"pose": ["walk", 0.5],
		"roll": 0.0,
		"grip": Vector3(0.0, 0.0, 0.0),
	},
	"Ranged/Blue": {
		"glb": WEAPON_ROOT + "merfolk-harpoon.glb",
		"bone": "mixamorig_LeftHand",
		"length": 1.0,
		"axis": Vector3.RIGHT,
		"aim": Vector3.BACK,
		"pose": ["walk", 0.5],
		"roll": 0.0,
		"grip": Vector3(0.0, 0.0, 0.0),
	},
}

const CHARACTERS := {
	"Melee": {
		"White": {"mesh": CHAR_ROOT + "melee/human/human_melee.fbx", "set": "sword_and_shield", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "human/human_weapon.glb"},
		"Green": {"mesh": CHAR_ROOT + "melee/elf/elf_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "elf/elf_weapon.glb"},
		"Blue": {"mesh": CHAR_ROOT + "melee/merfolk/merfolk_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "merfolk/merfolk_weapon.glb"},
		"Black": {"mesh": CHAR_ROOT + "melee/zombie/zombie_melee.fbx", "set": "zombie", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "zombie/zombie_weapon.glb"},
		"Red": {"mesh": CHAR_ROOT + "melee/goblin/goblin_melee.fbx", "set": "standing_melee", "prop": Prop.WEAPON_GLB, "weapon_glb": WEAPON_ROOT + "goblin/goblin_weapon.glb"},
	},
	"Ranged": {
		"Green": {"mesh": CHAR_ROOT + "ranged/elf/elf_ranged.fbx", "set": "bow", "prop": Prop.WEAPON_MODEL, "model": "Ranged/Green"},
		"White": {"mesh": CHAR_ROOT + "ranged/human/human_ranged.fbx", "set": "crossbow", "prop": Prop.WEAPON_MODEL, "model": "Ranged/White"},
		"Blue": {"mesh": CHAR_ROOT + "ranged/merfolk/merfolk_ranged.fbx", "set": "crossbow", "prop": Prop.WEAPON_MODEL, "model": "Ranged/Blue"},
		"Red": {"mesh": CHAR_ROOT + "ranged/goblin/goblin_ranged.fbx", "set": "goblin_ranged", "prop": Prop.STONE},
		"Black": {"mesh": CHAR_ROOT + "ranged/zombie/zombie_ranged.fbx", "set": "zombie_ranged", "prop": Prop.BONE_SMALL},
	},
	"Mage": {
		"White": {"mesh": CHAR_ROOT + "mage/human/human_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_white.fbx"},
		"Blue": {"mesh": CHAR_ROOT + "mage/merfolk/merfolk_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_blue.fbx"},
		"Black": {"mesh": CHAR_ROOT + "mage/zombie/zombie_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_black.fbx"},
		"Red": {"mesh": CHAR_ROOT + "mage/goblin/goblin_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_red.fbx"},
		"Green": {"mesh": CHAR_ROOT + "mage/elf/elf_mage.fbx", "set": "mage", "attack": ANIM_ROOT + "mage/attack_green.fbx"},
	},
}

## Confirmed via direct inspection that these new meshes use "mixamorig_"-
## prefixed bone names (unlike the OLD melee assets tools/melee_character_builder.gd
## targets, which use bare names like "RightHand" - a different export/import
## convention, not a mistake in either file).
const WEAPON_GRIP_BONE := "mixamorig_RightHand"
const WEAPON_WORLD_SCALE := 0.5
const WEAPON_GRIP_DROP_WORLD := 0.08
const WEAPON_TWIST_DEGREES := 90.0
const WEAPON_LEAN_AXIS := Vector3(0.0, 0.0, 1.0)
const WEAPON_LEAN_DEGREES := 70.791
const WEAPON_GRIP_EXTRA_OFFSET_WORLD := Vector3(-0.136396, -0.08001, 0.012326)


static func build_all() -> void:
	var built := 0
	for class_key in CHARACTERS.keys():
		var suffix: String = class_key.to_lower()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR + suffix + "/"))
		for color in CHARACTERS[class_key].keys():
			var config: Dictionary = CHARACTERS[class_key][color]
			var race: String = RACE_BY_COLOR[color]
			if _build_character(color, race, suffix, config):
				built += 1

	print("Done. Built %d character scenes." % built)


static func _build_character(color: String, race: String, class_suffix: String, config: Dictionary) -> bool:
	var mesh_fbx_path: String = config["mesh"]
	var base_scene: PackedScene = ResourceLoader.load(mesh_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if base_scene == null:
		push_error("Could not load mesh %s" % mesh_fbx_path)
		return false
	var root: Node3D = base_scene.instantiate()
	root.name = race.capitalize() + class_suffix.capitalize()

	var anim_player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
	if anim_player == null:
		push_error("%s has no AnimationPlayer" % mesh_fbx_path)
		return false

	var mesh_node: MeshInstance3D = _find_mesh_instance(root)
	if mesh_node == null:
		push_error("%s has no MeshInstance3D" % mesh_fbx_path)
		return false
	var array_mesh: ArrayMesh = mesh_node.mesh
	array_mesh.surface_set_material(0, _build_albedo_material(mesh_fbx_path))

	# Root scale/lift must be set BEFORE grounding: the correction is measured
	# in this same (post-normalization) coordinate frame.
	_normalize_to_target_height(root, mesh_node)

	var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
	if skeleton == null:
		push_error("%s has no Skeleton3D" % mesh_fbx_path)
		return false

	var template: AnimationLibrary = _build_template_library(CLIP_SETS[config["set"]], mesh_fbx_path)
	if template == null:
		return false
	if config.has("attack"):
		var attack_anim := _extract_animation(config["attack"])
		if attack_anim == null:
			push_error("Could not extract per-character attack clip %s" % config["attack"])
			return false
		attack_anim.loop_mode = Animation.LOOP_NONE
		_strip_horizontal_root_motion(attack_anim, "mixamorig_Hips")
		template.add_animation("attack", attack_anim)

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)

	var library: AnimationLibrary = _ground_correct_library(template, anim_player, root, skeleton)
	# Records where the swing actually connects, so EnemyBase can pay the hit out on
	# that frame instead of on the frame the swing started. Measured after grounding
	# because that is the clip that ships; the vertical shift is a constant and does
	# not move the peak either way.
	var impact_ratio: float = AnimationImpact.annotate(library, "attack", skeleton, anim_player, root)
	var output_name: String = "%s_%s" % [race, class_suffix]
	var library_path: String = ANIM_ROOT + "lib_%s.tres" % output_name
	if ResourceSaver.save(library, library_path) != OK:
		push_error("Failed saving animation library %s" % library_path)
		return false
	anim_player.add_animation_library("", ResourceLoader.load(library_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	# current_animation isn't serialized by pack(); autoplay is what persists, and
	# EnemyBase pauses it on the first frame as its resting pose.
	anim_player.autoplay = "walk"

	var prop_type: int = config.get("prop", Prop.NONE)
	if prop_type == Prop.WEAPON_GLB:
		_attach_weapon(skeleton, config["weapon_glb"])
	elif prop_type == Prop.WEAPON_MODEL:
		_attach_weapon_model(skeleton, anim_player, root, config, WEAPON_MODELS[config["model"]])
	elif prop_type != Prop.NONE:
		_attach_prop(skeleton, prop_type)

	_own_recursive(root, root)

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("PackedScene.pack failed for %s" % output_name)
		return false
	var output_path: String = SCENE_DIR + class_suffix + "/%s.tscn" % output_name
	if ResourceSaver.save(packed, output_path) != OK:
		push_error("ResourceSaver.save failed for %s" % output_name)
		return false

	print("Saved ", output_path, " (set=", config["set"], ", attack impact at ", "%.0f%%" % (impact_ratio * 100.0), ")")
	root.queue_free()
	return true


static func _build_template_library(clip_set: Dictionary, mesh_fbx_path: String) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	for clip_name in clip_set.keys():
		var source_path: String = clip_set[clip_name]
		var anim: Animation
		if source_path == OWN_MESH_CLIP:
			anim = _extract_animation(mesh_fbx_path)
		else:
			anim = _extract_animation(source_path)
		if anim == null:
			push_error("Could not extract clip '%s' from %s" % [clip_name, source_path if source_path != OWN_MESH_CLIP else mesh_fbx_path])
			return null
		anim.loop_mode = Animation.LOOP_LINEAR if clip_name in LOCOMOTION_CLIPS else Animation.LOOP_NONE
		_strip_horizontal_root_motion(anim, "mixamorig_Hips")
		library.add_animation(clip_name, anim)
	return library


## Where a given clip slot's source fbx lives for this character, resolving the
## "use the mesh's own embedded clip" sentinel. "" when the set does not define the slot.
## Shared with tools/add_run_clips.gd so the two cannot disagree about what a run is.
static func _clip_source(config: Dictionary, clip_name: String) -> String:
	var clip_set: Dictionary = CLIP_SETS[config["set"]]
	if not clip_set.has(clip_name):
		return ""
	var source: String = String(clip_set[clip_name])
	return String(config["mesh"]) if source == OWN_MESH_CLIP else source


static func _extract_animation(source_fbx_path: String) -> Animation:
	var source_scene: PackedScene = ResourceLoader.load(source_fbx_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if source_scene == null:
		return null
	var source_root: Node = source_scene.instantiate()
	var player: AnimationPlayer = source_root.find_child("AnimationPlayer", true, false)
	if player == null or player.get_animation_list().is_empty():
		source_root.queue_free()
		return null
	var anim: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	source_root.queue_free()
	return anim


static func _strip_horizontal_root_motion(anim: Animation, bone_name: String) -> void:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			continue
		var key_count := anim.track_get_key_count(track_idx)
		if key_count == 0:
			return
		var base_value: Vector3 = anim.track_get_key_value(track_idx, 0)
		for key_idx in key_count:
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, Vector3(base_value.x, value.y, base_value.z))
		return


## Per-character copy of `template_library` with every clip's Hips position
## track shifted vertically so its lowest ground-contact point actually touches
## y=0 on THIS character's own (already height-normalized) skeleton - see
## tools/boss_character_builder.gd's matching function for why this is needed
## even for a mesh's own embedded clip (a Mixamo-export quirk, not a cross-file
## mismatch).
static func _ground_correct_library(template_library: AnimationLibrary, anim_player: AnimationPlayer, root: Node3D, skeleton: Skeleton3D) -> AnimationLibrary:
	var skeleton_to_root: Transform3D = _transform_to_ancestor(skeleton, root)
	var factor: float = root.transform.basis.get_scale().y
	var corrected := AnimationLibrary.new()

	for clip_name in template_library.get_animation_list():
		var anim: Animation = template_library.get_animation(clip_name).duplicate(true)
		var min_foot_y: float = _measure_min_foot_height(anim_player, skeleton, root, skeleton_to_root, anim)
		if is_finite(min_foot_y):
			_shift_hips_y(anim, "mixamorig_Hips", -min_foot_y / factor)
		else:
			push_warning("Could not measure foot height for clip '%s'; leaving ungrounded" % clip_name)
		corrected.add_animation(clip_name, anim)

	for lib_name in anim_player.get_animation_library_list():
		anim_player.remove_animation_library(lib_name)
	return corrected


static func _measure_min_foot_height(anim_player: AnimationPlayer, skeleton: Skeleton3D, root: Node3D, skeleton_to_root: Transform3D, anim: Animation) -> float:
	var foot_indices: Array[int] = []
	for bone_name in FOOT_BONES:
		var idx := skeleton.find_bone(bone_name)
		if idx != -1:
			foot_indices.append(idx)
	if foot_indices.is_empty():
		return INF

	var temp_library := AnimationLibrary.new()
	const TEMP_CLIP_NAME := "__ground_measure__"
	temp_library.add_animation(TEMP_CLIP_NAME, anim)
	anim_player.add_animation_library("__ground__", temp_library)
	anim_player.play("__ground__/" + TEMP_CLIP_NAME)

	var min_y := INF
	for i in range(GROUND_SAMPLE_COUNT + 1):
		var t: float = anim.length * float(i) / float(GROUND_SAMPLE_COUNT)
		anim_player.seek(t, true)
		for idx in foot_indices:
			var world_equiv: Transform3D = root.transform * skeleton_to_root * skeleton.get_bone_global_pose(idx)
			min_y = minf(min_y, world_equiv.origin.y)

	anim_player.stop()
	anim_player.remove_animation_library("__ground__")
	return min_y


static func _shift_hips_y(anim: Animation, bone_name: String, delta_y: float) -> void:
	for track_idx in anim.get_track_count():
		if anim.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue
		if not str(anim.track_get_path(track_idx)).ends_with(":" + bone_name):
			continue
		for key_idx in anim.track_get_key_count(track_idx):
			var value: Vector3 = anim.track_get_key_value(track_idx, key_idx)
			anim.track_set_key_value(track_idx, key_idx, value + Vector3(0.0, delta_y, 0.0))
		return


static func _normalize_to_target_height(root: Node3D, mesh_node: MeshInstance3D) -> void:
	var mesh_to_root: Transform3D = _transform_to_ancestor(mesh_node, root)
	var bounds: AABB = mesh_to_root * mesh_node.mesh.get_aabb()
	if bounds.size.y <= 0.0:
		push_error("Degenerate mesh bounds for %s; leaving scale untouched" % root.name)
		return
	var factor: float = TARGET_HEIGHT / bounds.size.y
	var basis: Basis = root.transform.basis.orthonormalized().scaled(Vector3.ONE * factor)
	root.transform = Transform3D(basis, Vector3(0.0, -bounds.position.y * factor, 0.0))


static func _transform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var chain: Array[Node3D] = []
	var current: Node = node
	while current != null and current != ancestor:
		if current is Node3D:
			chain.append(current as Node3D)
		current = current.get_parent()
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for n in chain:
		accum = accum * n.transform
	return accum


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh is ArrayMesh:
			return node as MeshInstance3D
		for child in node.get_children():
			stack.append(child)
	return null


## Rebuild the material from the albedo Godot extracts alongside the fbx rather
## than trusting the fbx's own imported material - the embedded-texture path
## has repeatedly pointed at a stale/duplicated extraction this project, and
## glTF/FBX metallic defaults render as chrome skin.
static func _build_albedo_material(mesh_fbx_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo_path: String = mesh_fbx_path.replace(".fbx", "_0.png")
	var albedo: Texture2D = ResourceLoader.load(albedo_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if albedo == null:
		push_warning("No albedo found at %s; character will render untextured" % albedo_path)
	else:
		mat.albedo_texture = albedo
	mat.metallic = 0.0
	mat.roughness = 1.0
	return mat


## Ported unchanged from tools/melee_character_builder.gd - the existing weapon
## glbs and hand-tuned constants above are still valid, they're unrelated to
## which body mesh holds them. Grips the weapon into WEAPON_GRIP_BONE via a
## BoneAttachment3D; the correction is computed per-skeleton (hand rest orientation
## differs per character), canceling that rotation then applying the shared
## twist/lean/offset tuning.
static func _attach_weapon(skeleton: Skeleton3D, weapon_glb_path: String) -> void:
	if skeleton == null:
		push_error("No Skeleton3D found for weapon attachment")
		return

	var attachment := BoneAttachment3D.new()
	attachment.name = "RightHandAttachment"
	attachment.bone_name = WEAPON_GRIP_BONE
	skeleton.add_child(attachment)

	var weapon_scene: PackedScene = ResourceLoader.load(weapon_glb_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	var weapon_root: Node3D = weapon_scene.instantiate()
	weapon_root.name = "Weapon"

	var armature_scale: float = _get_node_global_scale(skeleton).y
	var local_scale: float = WEAPON_WORLD_SCALE / armature_scale
	var local_grip_drop: float = WEAPON_GRIP_DROP_WORLD / armature_scale

	var hand_rest: Transform3D = _get_bone_global_rest(skeleton, WEAPON_GRIP_BONE)
	var intrinsic_rotation: Basis = Basis(Vector3.UP, deg_to_rad(WEAPON_TWIST_DEGREES)) * Basis(WEAPON_LEAN_AXIS, deg_to_rad(WEAPON_LEAN_DEGREES))
	var correction: Basis = hand_rest.basis.inverse() * intrinsic_rotation
	var grip_point_local: Vector3 = Vector3(0.0, local_scale - local_grip_drop, 0.0) + WEAPON_GRIP_EXTRA_OFFSET_WORLD / armature_scale
	weapon_root.transform = Transform3D(
		correction.scaled(Vector3.ONE * local_scale),
		correction * grip_point_local
	)

	attachment.add_child(weapon_root)

	var weapon_mesh_node: MeshInstance3D = weapon_root.find_child("mesh_node", true, false)
	if weapon_mesh_node and weapon_mesh_node.mesh:
		var weapon_array_mesh: ArrayMesh = weapon_mesh_node.mesh
		weapon_array_mesh.surface_set_material(0, _build_weapon_material(weapon_glb_path))


## A real ranged weapon model, worn per its WEAPON_MODELS entry.
##
## Two things are done here that _attach_weapon (the melee path) does not:
##
## The scale is MEASURED, not assumed. _attach_weapon multiplies by a fixed
## WEAPON_WORLD_SCALE, which only works because every melee weapon is authored 2m long; a
## re-export at a different size would silently change how big the weapon looks. Here the
## model's own extent along its long axis is measured and divided out, so `length` means
## what it says in metres however the model is later re-exported.
##
## The material is LEFT ALONE. _attach_weapon rebuilds it from loose `_albedo.jpg` files
## beside the glb, because the melee weapons shipped their textures that way and the glTF
## importer ignores them. These three shipped with their textures embedded and import
## fully bound already - running the melee path over them would look for a
## `elf-bow_albedo.jpg` that does not exist and strip the texturing instead of fixing it.
static func _attach_weapon_model(skeleton: Skeleton3D, anim_player: AnimationPlayer, root: Node3D, config: Dictionary, model: Dictionary) -> void:
	if skeleton == null:
		push_error("No Skeleton3D found for weapon attachment")
		return
	var bone_name: String = String(model["bone"])
	if skeleton.find_bone(bone_name) == -1:
		push_warning("No bone '%s'; falling back to %s" % [bone_name, WEAPON_GRIP_BONE])
		bone_name = WEAPON_GRIP_BONE

	var weapon_scene: PackedScene = ResourceLoader.load(String(model["glb"]), "", ResourceLoader.CACHE_MODE_REPLACE)
	if weapon_scene == null:
		push_error("Could not load weapon model %s" % model["glb"])
		return
	var weapon_root: Node3D = weapon_scene.instantiate()
	weapon_root.name = "Weapon"

	var attachment := BoneAttachment3D.new()
	attachment.name = "WeaponAttachment"
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)

	var axis: Vector3 = model["axis"]
	var extent: float = _model_extent(weapon_root, axis)
	if extent <= 0.0001:
		push_warning("Weapon %s measures nothing along %s; left unscaled" % [model["glb"], axis])
		extent = 1.0
	# PROVISIONAL. The pose this is aimed against is read off a skeleton that is not in a
	# scene tree, and such a skeleton does not pose reliably - measured, the hand comes
	# back up to forty degrees away from where the same frame puts it once the character is
	# actually in a tree. tools/weapon_fit_pass.gd recomputes this from the live pose and
	# rewrites it; that pass is part of a build, not an optional extra.
	weapon_root.transform = weapon_transform(
		String(config["model"]),
		model,
		_grip_basis(skeleton, anim_player, bone_name, model, String(config["model"])),
		_transform_to_ancestor(skeleton, root).basis.orthonormalized(),
		extent,
		_get_node_global_scale(skeleton).y
	)
	attachment.add_child(weapon_root)


## Grip bases measured in a live scene tree, keyed as WEAPON_MODELS is, handed back by
## tools/weapon_fit_pass.gd between a build's two passes. Empty on a cold build, which is
## precisely why a cold build's weapon placement is provisional - see _grip_basis.
static var measured_grip_bases: Dictionary = {}


## The hand adjustments captured out of the editor. See WEAPON_FIT_PATH.
static func _weapon_fit(model_key: String) -> Dictionary:
	if not FileAccess.file_exists(WEAPON_FIT_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(WEAPON_FIT_PATH))
	if not (parsed is Dictionary):
		push_warning("%s is not readable JSON; ignoring captured weapon fits" % WEAPON_FIT_PATH)
		return {}
	var entry: Variant = (parsed as Dictionary).get(model_key, {})
	return entry if entry is Dictionary else {}


## Where a weapon sits on its bone, given the orientation of the hand wearing it.
##
## Shared by the builder and tools/weapon_fit_pass.gd so there is exactly one formula.
static func weapon_transform(model_key: String, model: Dictionary, grip_basis: Basis, skeleton_to_root: Basis, extent: float, armature_scale: float) -> Transform3D:
	# `aim` is written in the CHARACTER's own space - "up", "the way it is facing" - but a
	# bone pose is in SKELETON space, so it is converted before use.
	var aim: Vector3 = (skeleton_to_root.inverse() * Vector3(model["aim"])).normalized()
	var axis: Vector3 = Vector3(model["axis"]).normalized()
	# The model's long axis is swung onto the direction it should point (Quaternion's arc
	# constructor does exactly this), rolled about that direction to settle which face is
	# front, and pulled back into the hand's frame - the same cancellation _attach_weapon
	# does, and for the same reason: a hand bone's local axes are whatever the rig
	# exported, so a rotation written in them only holds for one skeleton.
	var to_aim := Basis(Quaternion(axis, aim))
	var roll := Basis(aim, deg_to_rad(float(model.get("roll", 0.0))))
	var correction: Basis = grip_basis.orthonormalized().inverse() * roll * to_aim
	var origin: Vector3 = correction * (skeleton_to_root.inverse() * Vector3(model["grip"]) / armature_scale)

	# The captured hand adjustment, applied at the END so it reads as "and then turn the
	# weapon a bit in its own frame" - which is exactly what dragging its gizmo did.
	var fit: Dictionary = _weapon_fit(model_key)
	# Stored as a QUATERNION, not euler degrees. Euler is what a person wants to read, but
	# get_euler() -> from_euler() does not round-trip exactly here: captured back and
	# applied again it moved the three weapons by 1.3, 2.9 and 3.8 degrees, which is a
	# rebuild quietly walking away from hand-tuned placement. A quaternion is the rotation
	# itself, with no axis-order convention to disagree about.
	if fit.has("rotation_quat"):
		var q: Array = fit["rotation_quat"]
		correction = correction * Basis(Quaternion(
			float(q[0]), float(q[1]), float(q[2]), float(q[3])).normalized())
	# Position is taken verbatim when captured: it is already the local offset the editor
	# produced, and re-deriving it from `grip` would only undo the nudge.
	if fit.has("origin"):
		var captured: Array = fit["origin"]
		origin = Vector3(float(captured[0]), float(captured[1]), float(captured[2]))

	# Against RUNTIME_VISUAL_SCALE rather than the skeleton's own build-time scale, so
	# `length` is the size the weapon really is in the game - see the constant. Scale stays
	# DERIVED even when a fit is captured, so resizing a weapon is still one number in
	# WEAPON_MODELS rather than something that has to be dragged again.
	var local_scale: float = (float(model["length"]) / maxf(extent, 0.0001)) / RUNTIME_VISUAL_SCALE
	return Transform3D(correction.scaled(Vector3.ONE * local_scale), origin)


## The orientation `aim` is measured against: the grip bone as it sits in the middle of
## the weapon's own reference clip, NOT in the rest pose.
##
## It has to be the animated pose. These rigs' walk and attack clips are authored for a
## character already carrying this class of weapon, so the hand is rolled a long way from
## rest in precisely the poses the weapon is ever seen in - a bow aimed upright against the
## rest pose lies flat on its side for the entire march, which is what the first version of
## this did.
##
## Falls back to the rest pose, with a warning, if the clip is missing or if posing turns
## out not to have taken (an un-posed skeleton returns its rest basis, so the comparison is
## also the check).
static func _grip_basis(skeleton: Skeleton3D, anim_player: AnimationPlayer, bone_name: String, model: Dictionary, model_key: String = "") -> Basis:
	# A basis measured in a LIVE TREE always wins; it is the only trustworthy one, and
	# tools/weapon_fit_pass.gd hands it back between a build's two passes.
	if measured_grip_bases.has(model_key):
		return measured_grip_bases[model_key]
	# Orthonormalised, always. A bone pose basis carries the rig's own bone scaling, and
	# these Mixamo rigs do not scale their bones uniformly - inverting a sheared basis and
	# multiplying a direction through it turns the weapon by tens of degrees. Only the
	# ORIENTATION of the hand is wanted here; the size is handled by local_scale.
	var rest: Basis = _get_bone_global_rest(skeleton, bone_name).basis.orthonormalized()
	var pose: Array = model.get("pose", [])
	if anim_player == null or pose.size() < 2:
		return rest
	var clip_name: String = String(pose[0])
	if not anim_player.has_animation(clip_name):
		push_warning("No clip '%s' to aim %s against; using the rest pose" % [clip_name, model["glb"]])
		return rest
	var bone_index: int = skeleton.find_bone(bone_name)
	if bone_index == -1:
		return rest

	var previous: String = anim_player.current_animation
	var clip: Animation = anim_player.get_animation(clip_name)
	anim_player.play(clip_name)
	anim_player.seek(clip.length * clampf(float(pose[1]), 0.0, 1.0), true)
	var posed: Basis = skeleton.get_bone_global_pose(bone_index).basis.orthonormalized()
	anim_player.stop()
	if previous != "":
		anim_player.play(previous)
		anim_player.stop()

	if posed.is_equal_approx(rest):
		push_warning("Posing '%s' changed nothing for %s; using the rest pose" % [clip_name, model["glb"]])
		return rest
	return posed


## How far the model reaches along one of its own axes, from the combined AABB of every
## mesh in it. Read off the instantiated scene rather than the file, so anything the
## import settings do to the geometry is already included.
static func _model_extent(root: Node3D, axis: Vector3) -> float:
	var bounds := AABB()
	var found: bool = false
	for mesh_instance: MeshInstance3D in _mesh_instances(root):
		if mesh_instance.mesh == null:
			continue
		var local: AABB = mesh_instance.transform * mesh_instance.get_aabb()
		bounds = local if not found else bounds.merge(local)
		found = true
	if not found:
		return 0.0
	return absf(bounds.size.x * axis.x) + absf(bounds.size.y * axis.y) + absf(bounds.size.z * axis.z)


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_mesh_instances(child))
	return found


## Simple placeholder props (procedurally-built stone/bone for the two throwing classes,
## and the bow/crossbow stand-ins that WEAPON_MODELS has since replaced) - held
## at the grip bone's own origin with no hand-rest cancellation, unlike
## _attach_weapon(). That correction exists to make a REAL weapon look right;
## it's not worth the complexity for shapes the user has already said are
## temporary and will be replaced.
static func _attach_prop(skeleton: Skeleton3D, prop_type: int) -> void:
	if skeleton == null:
		return
	var bone_name: String = "mixamorig_LeftHand" if prop_type in [Prop.BOW, Prop.CROSSBOW] else WEAPON_GRIP_BONE
	if skeleton.find_bone(bone_name) == -1:
		bone_name = WEAPON_GRIP_BONE

	var attachment := BoneAttachment3D.new()
	attachment.name = "PropAttachment"
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)

	var armature_scale: float = _get_node_global_scale(skeleton).y
	var prop := _build_prop_mesh(prop_type, armature_scale)
	attachment.add_child(prop)


static func _build_prop_mesh(prop_type: int, armature_scale: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop"
	match prop_type:
		Prop.STONE:
			var mesh := CSGSphere3D.new()
			mesh.radius = 0.05 / armature_scale
			mesh.radial_segments = 8
			mesh.rings = 6
			# Slightly irregular, not a perfect sphere - reads as a thrown rock
			# rather than a ball at this size.
			mesh.scale = Vector3(1.0, 0.8, 1.15)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.42, 0.40, 0.38)
			mat.roughness = 0.95
			mesh.material = mat
			root.add_child(mesh)
		Prop.BONE_SMALL:
			# A small thrown bone: thin shaft with two rounded knobs, scaled down
			# from the melee zombie club's own rough proportions per instruction.
			var shaft := CSGCylinder3D.new()
			shaft.radius = 0.012 / armature_scale
			shaft.height = 0.16 / armature_scale
			shaft.rotation_degrees.x = 90.0
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.88, 0.85, 0.76)
			mat.roughness = 0.7
			shaft.material = mat
			root.add_child(shaft)
			for offset_sign in [-1.0, 1.0]:
				var knob := CSGSphere3D.new()
				knob.radius = 0.022 / armature_scale
				knob.position = Vector3(0.0, 0.0, offset_sign * 0.08 / armature_scale)
				knob.material = mat
				root.add_child(knob)
		Prop.BOW:
			# Thin vertical stave - a clear "this is a stand-in" shape until the
			# real bow model is delivered.
			var mesh := CSGBox3D.new()
			mesh.size = Vector3(0.03, 0.9, 0.03) / armature_scale
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.35, 0.24, 0.14)
			mat.roughness = 0.8
			mesh.material = mat
			root.add_child(mesh)
		Prop.CROSSBOW:
			var mesh := CSGBox3D.new()
			mesh.size = Vector3(0.08, 0.18, 0.45) / armature_scale
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.22, 0.2, 0.19)
			mat.roughness = 0.6
			mesh.material = mat
			root.add_child(mesh)
	return root


## The weapon glb embeds its own texture data and Godot's glTF importer re-extracts
## it under a name derived from the glb's own filename + material slot name,
## ignoring loose renamed files sitting alongside it - rebuild the material
## explicitly instead (same fix as _build_albedo_material, ported unchanged
## from tools/melee_character_builder.gd).
static func _build_weapon_material(weapon_glb_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ResourceLoader.load(weapon_glb_path.replace(".glb", "_albedo.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.normal_enabled = true
	mat.normal_texture = ResourceLoader.load(weapon_glb_path.replace(".glb", "_normal.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	var metallic_roughness: Texture2D = ResourceLoader.load(weapon_glb_path.replace(".glb", "_metallic_roughness.jpg"), "", ResourceLoader.CACHE_MODE_REPLACE)
	mat.metallic = 1.0
	mat.metallic_texture = metallic_roughness
	mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	mat.roughness = 1.0
	mat.roughness_texture = metallic_roughness
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	return mat


static func _get_node_global_scale(node: Node3D) -> Vector3:
	var scale := Vector3.ONE
	var current: Node = node
	while current is Node3D:
		scale *= (current as Node3D).transform.basis.get_scale()
		current = current.get_parent()
	return scale


static func _get_bone_global_rest(skeleton: Skeleton3D, bone_name: String) -> Transform3D:
	var chain: Array[int] = []
	var bone_idx := skeleton.find_bone(bone_name)
	while bone_idx != -1:
		chain.append(bone_idx)
		bone_idx = skeleton.get_bone_parent(bone_idx)
	chain.reverse()
	var accum := Transform3D.IDENTITY
	for b in chain:
		accum = accum * skeleton.get_bone_rest(b)
	return accum


## Gives `owner` every node that should be SAVED with the scene, which pack() uses to
## decide what to write.
##
## Stops at an instanced sub-scene. Its root is owned - that is what makes it save as an
## instance - but its internals belong to the scene it came from, and owning those makes
## pack() write them out a SECOND time as siblings of the instance. The result is a weapon
## whose mesh exists twice and renders twice, overlapping itself.
##
## This is not hypothetical and it is not new: every weapon this builder has ever produced
## carries the duplicate. It is almost certainly the real cause of the doubled
## human_melee weapon recorded on 2026-08-23, which was put down to load() caching at the
## time. Already-built scenes keep the duplicate until they are rebuilt.
static func _own_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path != "":
			continue
		_own_recursive(child, owner)
