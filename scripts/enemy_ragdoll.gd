class_name EnemyRagdoll
extends Node
## A killed enemy going limp: its skeleton driven by physics for a few seconds, then frozen
## where it came to rest (stage 2 of the death launch, see EnemyBase._start_death_launch).
##
## Cosmetic and local to each peer. The server still throws the body itself the stage-1
## way, so the corpse - what Zombify raises and what every screen agrees on - lies where the
## same launch carries it; the ragdoll sets off with that same velocity and comes down close
## by. Who ragdolls, and how many at once, is each player's own graphics setting.
##
## Built at the moment of death rather than shipped in the scene: fourteen bodies on every
## living enemy would cost on every frame of every wave, for the few seconds each one spends
## dead. Only bones the rig actually has are built - the rigs are not all the same skeleton.
##
## NOT Godot's PhysicalBone3D. The rigs are tiny and scaled up a hundredfold in the scene,
## and a physics body does not keep a scale: the bones came back from the simulation with
## the hundredfold missing and the mesh exploded into sheets across the screen. These are
## plain rigid bodies in world units instead, and their poses are written into the skeleton
## here - position and rotation only, so the rig's own scale is never touched.
##
## While it simulates the model is taken out of the body's transform (`top_level`), so the
## body can go on being moved by the server - its replicated flight on a client - without
## dragging the ragdoll along with it.

## [bone, the child it points at, radius as a fraction of rig height, mass, swing deg,
## twist deg]. A cone at every joint rather than hinges at the elbows and knees: a hinge
## needs its axis and the sign of its limits right per rig, and getting either wrong bends a
## knee backwards, which reads far worse than a joint a little too loose.
const BONES := [
	["Hips", "Spine", 0.085, 6.0, 0.0, 0.0],
	["Spine", "Spine1", 0.08, 4.0, 18.0, 10.0],
	["Spine1", "Spine2", 0.085, 4.0, 18.0, 10.0],
	["Spine2", "Neck", 0.095, 5.0, 18.0, 10.0],
	["Neck", "Head", 0.035, 1.0, 30.0, 20.0],
	["Head", "HeadTop_End", 0.065, 3.0, 30.0, 20.0],
	["LeftArm", "LeftForeArm", 0.035, 2.0, 75.0, 30.0],
	["LeftForeArm", "LeftHand", 0.03, 1.5, 70.0, 10.0],
	["RightArm", "RightForeArm", 0.035, 2.0, 75.0, 30.0],
	["RightForeArm", "RightHand", 0.03, 1.5, 70.0, 10.0],
	["LeftUpLeg", "LeftLeg", 0.05, 5.0, 55.0, 15.0],
	["LeftLeg", "LeftFoot", 0.04, 3.0, 65.0, 5.0],
	["RightUpLeg", "RightLeg", 0.05, 5.0, 55.0, 15.0],
	["RightLeg", "RightFoot", 0.04, 3.0, 65.0, 5.0],
]
const PREFIX := "mixamorig_"

## Ragdolls simulating right now, on this machine - the cap is on these.
static var _active: int = 0

var _skeleton: Skeleton3D
var _anim: AnimationPlayer
## bone index -> RigidBody3D, and bone index -> the bone's frame relative to its body.
var _bodies: Dictionary = {}
var _bone_in_body: Dictionary = {}
var _simulating: bool = false
var _time: float = 0.0


## Whether this machine should ragdoll a body thrown at `launch_speed` m/s, by its own
## graphics setting and by how many are already going.
static func wanted(launch_speed: float) -> bool:
	var level: int = GraphicsSettings.ragdoll_quality
	if level == GraphicsSettings.RagdollQuality.OFF:
		return false
	var caps: Array[int] = GameSettings.ragdoll_max_active
	if _active >= caps[clampi(level, 0, caps.size() - 1)]:
		return false
	if level == GraphicsSettings.RagdollQuality.LIMITED:
		return launch_speed >= GameSettings.ragdoll_limited_min_launch_speed
	return true


static func active_count() -> int:
	return _active


## Turns the model under `visual_root` into a ragdoll thrown with `launch`. Null when the
## rig has no skeleton this can work with; the caller then keeps its ordinary death.
static func start(host: Node3D, visual_root: Node3D, anim: AnimationPlayer, launch: Vector3) -> EnemyRagdoll:
	var skeleton: Skeleton3D = visual_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone(PREFIX + "Hips") < 0:
		return null
	var ragdoll := EnemyRagdoll.new()
	ragdoll.name = "Ragdoll"
	ragdoll._skeleton = skeleton
	ragdoll._anim = anim
	host.add_child(ragdoll)
	ragdoll._build(visual_root, launch)
	return ragdoll


func _build(visual_root: Node3D, launch: Vector3) -> void:
	# The pose it died in is what goes limp: the clip stops here and nothing plays over it.
	if _anim != null:
		_anim.pause()
		_anim.active = false
	visual_root.top_level = true

	var skeleton_xform: Transform3D = _skeleton.global_transform
	var height: float = _rig_height() * skeleton_xform.basis.get_scale().x
	for spec: Array in BONES:
		var bone: int = _skeleton.find_bone(PREFIX + String(spec[0]))
		if bone < 0:
			continue
		var child: int = _skeleton.find_bone(PREFIX + String(spec[1]))
		var bone_world: Transform3D = skeleton_xform * _skeleton.get_bone_global_pose(bone)
		var start: Vector3 = bone_world.origin
		var finish: Vector3
		if child >= 0:
			finish = (skeleton_xform * _skeleton.get_bone_global_pose(child)).origin
		else:
			finish = start + bone_world.basis.orthonormalized().y * height * 0.12
		if start.distance_to(finish) < height * 0.01:
			finish = start + bone_world.basis.orthonormalized().y * height * 0.05
		var body := _body(start, finish, height * float(spec[2]), float(spec[3]))
		add_child(body)
		_bodies[bone] = body
		# Where the bone sits in its body, rotation and position only - the rig's scale stays
		# the skeleton's business.
		var bone_frame := Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)
		_bone_in_body[bone] = body.global_transform.affine_inverse() * bone_frame

	# Each body hangs off the nearest ancestor that has one.
	for bone: int in _bodies:
		var parent: int = _skeleton.get_bone_parent(bone)
		while parent >= 0 and not _bodies.has(parent):
			parent = _skeleton.get_bone_parent(parent)
		if parent < 0:
			continue
		var spec: Array = _spec_for(bone)
		_joint(_bodies[parent], _bodies[bone], (skeleton_xform * _skeleton.get_bone_global_pose(bone)).origin,
			(_bodies[bone] as RigidBody3D).global_basis.z * -1.0, float(spec[4]), float(spec[5]))

	# Limbs pass through the torso rather than wedging against it: a ragdoll that fought
	# itself jittered on the ground, and from above nobody sees an arm inside a chest.
	var all: Array = _bodies.values()
	for a: int in all.size():
		for b: int in range(a + 1, all.size()):
			(all[a] as RigidBody3D).add_collision_exception_with(all[b])
	# Thrown the way the body is, every part a little differently so it tumbles.
	for body: RigidBody3D in all:
		body.linear_velocity = launch + Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.6), randf_range(-0.6, 0.6))
		body.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))
	_simulating = true
	_active += 1


func _spec_for(bone: int) -> Array:
	var bone_name: String = _skeleton.get_bone_name(bone).trim_prefix(PREFIX)
	for spec: Array in BONES:
		if spec[0] == bone_name:
			return spec
	return BONES[0]


## Feet to head in skeleton units, which every size here is a fraction of.
func _rig_height() -> float:
	var head: int = _skeleton.find_bone(PREFIX + "Head")
	var foot: int = _skeleton.find_bone(PREFIX + "LeftFoot")
	if head < 0 or foot < 0:
		return 0.008
	return maxf(_skeleton.get_bone_global_rest(head).origin.y - _skeleton.get_bone_global_rest(foot).origin.y, 0.001)


## A capsule from `start` to `finish`, in world units, looking down the bone.
func _body(start: Vector3, finish: Vector3, radius: float, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	var direction: Vector3 = (finish - start).normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	# A plain Node parent puts no transform over it: this is a world transform.
	body.transform = Transform3D(Basis.looking_at(direction, up), (start + finish) * 0.5)
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = maxf(start.distance_to(finish) + radius, radius * 2.0 + 0.001)
	var shape := CollisionShape3D.new()
	shape.shape = capsule
	# The capsule's own axis is Y; the body looks along -Z, down the bone.
	shape.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	body.add_child(shape)
	body.mass = mass
	var material := PhysicsMaterial.new()
	material.friction = 0.9
	material.bounce = 0.05
	body.physics_material_override = material
	body.linear_damp = 0.3
	body.angular_damp = 3.0
	body.collision_layer = 0
	body.collision_mask = EnemyBase.ENVIRONMENT_LAYER
	return body


## A cone at the bone's own origin, its twist axis down the child bone.
func _joint(parent: RigidBody3D, child: RigidBody3D, at: Vector3, along: Vector3, swing: float, twist: float) -> void:
	var joint := ConeTwistJoint3D.new()
	var x: Vector3 = along.normalized()
	var helper := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	var z: Vector3 = x.cross(helper).normalized()
	var y: Vector3 = z.cross(x).normalized()
	joint.transform = Transform3D(Basis(x, y, z), at)
	joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(swing))
	joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(twist))
	joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.8)
	joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
	add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(child)


func _physics_process(delta: float) -> void:
	if not _simulating:
		return
	_apply_pose()
	_time += delta
	if _time < GameSettings.ragdoll_min_seconds:
		return
	if _time >= GameSettings.ragdoll_max_seconds or _at_rest():
		_freeze()


func _at_rest() -> bool:
	for body: RigidBody3D in _bodies.values():
		if body.linear_velocity.length_squared() > 0.04 or body.angular_velocity.length_squared() > 0.5:
			return false
	return true


## The bodies' poses, written into the skeleton.
##
## Built bone by bone in skeleton order, so every parent's final pose is known before its
## children: a bone that has a body takes the body's pose, one that does not (a hand, a
## shoulder, the fingers) keeps where it hangs off its parent.
func _apply_pose() -> void:
	var count: int = _skeleton.get_bone_count()
	var finals: Array[Transform3D] = []
	finals.resize(count)
	var skeleton_xform: Transform3D = _skeleton.global_transform
	var skeleton_rotation_inverse: Basis = skeleton_xform.basis.orthonormalized().inverse()
	var skeleton_inverse: Transform3D = skeleton_xform.affine_inverse()
	for bone: int in count:
		var parent: int = _skeleton.get_bone_parent(bone)
		var parent_final: Transform3D = finals[parent] if parent >= 0 else Transform3D()
		if _bodies.has(bone):
			var world: Transform3D = (_bodies[bone] as RigidBody3D).global_transform * (_bone_in_body[bone] as Transform3D)
			finals[bone] = Transform3D(skeleton_rotation_inverse * world.basis.orthonormalized(), skeleton_inverse * world.origin)
			var local: Transform3D = parent_final.affine_inverse() * finals[bone]
			_skeleton.set_bone_pose_position(bone, local.origin)
			_skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
		else:
			finals[bone] = parent_final * _skeleton.get_bone_pose(bone)


## The last pose stays in the skeleton; the bodies go. From here on the corpse costs what
## any other corpse costs.
func _freeze() -> void:
	_apply_pose()
	_simulating = false
	for child: Node in get_children():
		child.queue_free()
	_bodies.clear()
	_bone_in_body.clear()
	_active -= 1
	set_physics_process(false)


func _exit_tree() -> void:
	# Freed mid-flight - raised by Zombify, or the corpse cap reached it.
	if _simulating:
		_simulating = false
		_active -= 1
