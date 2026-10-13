extends SceneTree
## Works out where a shield sits on a character's left hand and prints the Shield node's
## transform for its BoneAttachment3D, as .tscn text.
##
## Run with:
##   "G:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path . --script tools/fit_shields.gd
##
## Measured in a live tree on the pose the shield is seen in most (a Skeleton3D outside a
## tree poses wrong without saying so - see .agents/learnings.md, 2026-09-22):
##   - the grip sits in the palm, a little down the hand bone from the wrist;
##   - it is a centre grip (tools/blender_shields.py), so the face points the way the
##     forearm does - forward in the sword-and-shield walk - and it stands upright.
## The glb's own frame is front +Z, up +Y, origin on the grip.

const TARGETS := [
	{
		"scene": "res://scenes/melee/human_melee.tscn",
		"shield": "res://assets/weapons/human/human_shield.glb",
		# Shield height as a share of the character's: 0.83 m on a 1.8 m soldier.
		"height_ratio": 0.46,
		"clip": "walk", "at": 0.25,
	},
	{
		"scene": "res://scenes/bosses/white_paladin.tscn",
		"shield": "res://assets/weapons/bosses/white_paladin/white_paladin_shield.glb",
		"height_ratio": 0.6,
		"clip": "walk", "at": 0.25,
	},
]
const HAND := "mixamorig_LeftHand"
const FOREARM := "mixamorig_LeftForeArm"
## Wrist to the middle of the palm, as a share of the character's height.
const PALM_RATIO := 0.04


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for target: Dictionary in TARGETS:
		var root: Node3D = (load(target["scene"]) as PackedScene).instantiate()
		get_root().add_child(root)
		var skeleton: Skeleton3D = root.find_child("Skeleton3D", true, false)
		var player: AnimationPlayer = root.find_child("AnimationPlayer", true, false)
		player.play(String(target["clip"]))
		player.seek(player.current_animation_length * float(target["at"]), true)
		player.pause()
		await process_frame
		await process_frame

		var height: float = _height(root)
		var bone_world := func(bone: String) -> Transform3D:
			return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))
		var hand: Transform3D = bone_world.call(HAND)
		var forearm: Vector3 = (hand.origin - (bone_world.call(FOREARM) as Transform3D).origin).normalized()
		var palm: Vector3 = hand.origin + hand.basis.y.normalized() * height * PALM_RATIO

		var out: Vector3 = forearm
		var y: Vector3 = (Vector3.UP - out * out.dot(Vector3.UP)).normalized()
		var x: Vector3 = y.cross(out)
		var shield_world := Transform3D(Basis(x, y, out), palm)

		var shield: Node3D = (load(target["shield"]) as PackedScene).instantiate()
		var shield_height: float = _height(shield)
		shield.free()
		var size: float = height * float(target["height_ratio"]) / shield_height
		shield_world.basis = shield_world.basis.scaled(Vector3.ONE * size)

		var attachment_world: Transform3D = hand  # a BoneAttachment3D sits exactly on its bone
		var local: Transform3D = attachment_world.affine_inverse() * shield_world
		print("SHIELD %s height %.2f m, shield %.2f m -> %.2f m" % [target["scene"], height, shield_height, shield_height * size])
		print("SHIELD   forearm %s  out %s  up %s" % [forearm, out, y])
		print("SHIELD   bone_idx %d" % skeleton.find_bone(HAND))
		print("SHIELD   transform = %s" % var_to_str(local))
		root.free()
	quit()


## World-space height of every mesh under `node`, in its bind pose.
func _height(node: Node) -> float:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _global_of(mesh) * mesh.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y


func _global_of(node: Node3D) -> Transform3D:
	if node.is_inside_tree():
		return node.global_transform
	var t := Transform3D()
	var n: Node = node
	while n is Node3D:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
