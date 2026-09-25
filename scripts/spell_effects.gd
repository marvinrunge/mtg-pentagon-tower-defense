extends RefCounted
class_name SpellEffects
## What each of the twenty-five spells actually DOES, once the cast has been paid for.
##
## Lifted out of Player, which was four thousand lines and half of them not about being a
## player. These bodies never needed the rest of it: a spell wants a caster, the rank it
## was cast at, and somewhere to put its effect - so they take the caster as an argument
## and read the rest off it, exactly as they did when they lived inside.
##
## Deliberately static, and deliberately not a node. There is no state here between casts;
## everything a spell remembers - a channel, a dash trail, a giant's timer - belongs to the
## player who cast it and stayed there.
##
## `Player.execute_spell` -> `_run_spell_effect` is still the only way in. The split is
## about where the code lives, not about how a spell is reached.

## Physics layer 5 alone - the lanes and the base plateau (project.godot's
## 3d_physics/layer_5="Environment"). For rays that must find the GROUND and nothing else:
## the default aim mask includes layer 1, which is the player layer but also, so that the
## player collides with it, the layer Wall of Frost sits on.
const ENVIRONMENT_MASK: int = 1 << 4


static func cast_red_fireball(caster: Player, charge_pct: float) -> void:
	var dir = -caster.camera.global_basis.z.normalized()
	# From the caster's HANDS, where the orb was, rather than from the camera. Spawning at the
	# camera is why a charged Fireball never looked thrown: the bolt simply appeared in front
	# of the view, with no relationship to the ball the player had spent three seconds
	# building. Falls back to the camera when there was no orb - a tapped cast, or a remote
	# player's spell arriving over the wire with no local charge behind it.
	var spawn_pos: Vector3 = caster._charge_muzzle if caster._charge_muzzle != Vector3.ZERO else caster.camera.global_position - caster.camera.global_basis.z * 1.5
	caster._charge_muzzle = Vector3.ZERO
	# Charge and rank multiply INTO each other: a rank-5 Fireball held to full is the
	# biggest single thing red can do, and that is the intended top of the colour.
	var radius = GameSettings.spell_red_fireball_base_radius * (0.8 + 0.7 * charge_pct) * caster._rank_area()
	var mult = (0.6 + 1.2 * charge_pct) * caster.get_spell_damage_multiplier() * caster._rank_damage()
	ProjectilePool.fire(spawn_pos, dir, 4, false, mult, -1.0, radius, caster)
	# The bolt carries its own trail and its own detonation, but nothing used to happen at
	# the CASTER - so a charged Fireball left the hand with no sign it had been thrown.
	caster._spawn_cast_flash(Player.FX_RED, 1.8 + charge_pct * 1.4)
	caster._play_sound(&"spell_cast", caster.global_position)


## The green ability: a running leap that ends in a ground slam.
##
## Two halves, split the same way every other committed move is. THIS half is the
## launch, fired when the cast starts: an impulse forward and up, with the ordinary
## movement code suspended for the flight so it cannot be steered away. The slam is
## the other half, and lands on the clip's own final impact frame - see
## `release_on_last` in SpellDatabase and _slam_ground below, which is what
## `execute_spell` actually calls.
static func cast_green_titanic_leap(caster: Player) -> void:
	var forward: Vector3 = -caster.transform.basis.z.normalized()
	forward.y = 0.0
	caster.velocity = forward.normalized() * GameSettings.spell_green_leap_speed
	caster.velocity.y = GameSettings.spell_green_leap_rise
	caster._leap_timer = GameSettings.spell_green_leap_duration
	# Dust off the take-off. The slam at the far end already had its ring; the launch that
	# throws the character across the arena had nothing at all.
	caster._spawn_ring(caster.global_position, Player.FX_GREEN, 2.0)
	caster._play_sound(&"blade_heavy_swing", caster.global_position)


## The landing. Everything within reach takes the hit and is thrown outwards from the
## point of impact, so the slam reads as a shockwave rather than as a melee swing.
static func _slam_ground(caster: Player) -> void:
	caster._leap_timer = 0.0
	caster._play_sound(&"heavy_landing", caster.global_position)
	caster._shake(
		GameSettings.spell_green_leap_shake_strength,
		GameSettings.spell_green_leap_shake_duration
	)
	var damage: float = GameSettings.spell_green_leap_damage * caster.get_spell_damage_multiplier() * caster._rank_damage()
	var radius: float = GameSettings.spell_green_leap_radius * caster._rank_area()
	for enemy: Node3D in caster.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - caster.global_position
		if offset.length() > radius:
			continue
		caster._deal_damage(enemy, damage, true)
		if enemy.has_method("apply_knockback"):
			offset.y = 0.0
			if offset.length_squared() < 0.01:
				offset = -caster.transform.basis.z
			enemy.apply_knockback(offset.normalized() * GameSettings.spell_green_leap_knockback)


static func cast_red_rain_ember(caster: Player) -> void:
	var space_state = caster.get_world_3d().direct_space_state
	var start = caster.camera.global_position
	var end = start - caster.camera.global_basis.z * 40.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 1)
	var result = space_state.intersect_ray(query)
	var target_pos = result.position if result else (caster.global_position - caster.transform.basis.z * 8.0)
	
	caster._place_networked({
		"kind": "dot_zone", "type": "fire_rain", "position": target_pos,
		"radius": GameSettings.spell_red_rain_ember_radius * caster._rank_area(),
		"dps": GameSettings.spell_red_rain_ember_dps * caster.get_spell_damage_multiplier() * caster._rank_damage(),
		"duration": GameSettings.spell_red_rain_ember_duration * caster._rank_duration(),
	})
	# The zone is the spell, but it lands somewhere else - so without this the caster
	# performs a full cast animation with nothing happening anywhere near them.
	caster._spawn_cast_flash(Player.FX_RED, 2.2)


## white_1. Charges the NEXT melee hit rather than dealing damage itself - see
## _apply_melee_damage, which spends the charge and exiles anything the hit kills.
static func cast_white_exalted_strike(caster: Player) -> void:
	caster.exalted_charges = GameSettings.rank_count(
		GameSettings.spell_white_exalted_charges, GameSettings.spell_white_exalted_charges_max, caster._casting_rank
	)
	# Resolved now, not on the hit: the charge can sit unspent through several other casts.
	caster._exalted_damage_mult = GameSettings.spell_white_exalted_damage_mult * caster._rank_damage()
	caster._exalted_reach_bonus = GameSettings.spell_white_exalted_reach_bonus * caster._rank_area()
	caster._play_sound(&"spell_exalted_strike", caster.global_position)
	caster._spawn_cast_flash(Color(1.0, 0.95, 0.7), 2.4)


## white_2. A base shield PER TARGET, grown a little for every ally beyond the first -
## white's power goes UP with more allies alive, and a pool divided between them said
## the opposite. Bound to the caster's max HP, like every white/green HP number.
static func cast_white_circle_of_protection(caster: Player) -> void:
	var allies: Array[Node3D] = caster._allies_in_radius(GameSettings.spell_white_circle_radius * caster._rank_area())
	if allies.is_empty():
		return
	var each: float = GameSettings.player_max_hp * GameSettings.spell_white_circle_shield_hp_mult * caster._rank_damage()
	each *= 1.0 + GameSettings.spell_white_circle_ally_bonus * float(allies.size() - 1)
	var duration: float = GameSettings.spell_white_circle_duration * caster._rank_duration()
	for ally: Node3D in allies:
		if ally.has_method("grant_protection_shield"):
			ally.grant_protection_shield(each, duration)
		elif ally.has_method("heal"):
			# A myr has no shield to give, so its share arrives as health. The pool is
			# still divided the same way - what changes is the form it takes.
			caster._credit_heal(ally, ally.heal(each))
		caster._spawn_ring(ally.global_position, Player.FX_WHITE, 1.6)
	caster._play_sound(&"spell_circle_protection", caster.global_position)


## white_3. Reflect and block, for a duration. Both halves are applied in take_damage.
static func cast_white_reprisal_ward(caster: Player) -> void:
	caster._reprisal_timer = GameSettings.spell_white_reprisal_duration * caster._rank_duration()
	# Both halves are chances, so both walk to a ceiling instead of being multiplied.
	caster._reprisal_reflect = GameSettings.rank_fraction(
		GameSettings.spell_white_reprisal_reflect, GameSettings.spell_white_reprisal_reflect_max, caster._casting_rank
	)
	caster._reprisal_block_chance = GameSettings.rank_fraction(
		GameSettings.spell_white_reprisal_block_chance, GameSettings.spell_white_reprisal_block_chance_max, caster._casting_rank
	)
	caster._spawn_cast_flash(Player.FX_WHITE, 2.6)
	caster._play_sound(&"spell_reprisal_ward", caster.global_position)


## white_4. White's one panic button: heavy damage, wide, around the caster.
static func cast_white_wrath_of_god(caster: Player) -> void:
	var damage: float = GameSettings.spell_white_wrath_damage * caster.get_spell_damage_multiplier() * caster._rank_damage()
	var radius: float = GameSettings.spell_white_wrath_radius * caster._rank_area()
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, radius):
		caster._deal_damage(enemy, damage, false)
	caster._play_sound(&"spell_wrath_of_god", caster.global_position)
	caster._shake(0.6, 0.4)
	# The full release beat rather than a ring: this is the loudest thing white does, and
	# it was drawn with exactly the same primitive as Circle of Protection healing a myr.
	caster._spawn_impact(caster.global_position, Player.FX_WHITE, radius)


## white_5. The only skill in all thirty that UNDOES a loss rather than preventing one,
## which is about as white as a mechanic gets - and the only one that touches the co-op
## revive system.
static func cast_white_rally_the_fallen(caster: Player) -> void:
	var heal_amount: float = GameSettings.player_max_hp * GameSettings.spell_white_rally_heal_hp_mult * caster._rank_damage()
	# How many people one cast can pick up. Rank 1 is a rescue; rank 5 is a wipe undone.
	var revives_left: int = GameSettings.rank_count(
		GameSettings.spell_white_rally_revives, GameSettings.spell_white_rally_revives_max, caster._casting_rank
	)
	for ally: Node3D in caster._allies_in_radius(GameSettings.spell_white_rally_radius * caster._rank_area()):
		if ally == caster:
			continue
		if "is_downed" in ally and ally.is_downed and ally.has_method("revive"):
			if revives_left <= 0:
				continue
			revives_left -= 1
			ally.revive()
			caster._spawn_ring(ally.global_position, Player.FX_WHITE, 2.2)
			continue
		if ally.has_method("heal"):
			caster._credit_heal(ally, ally.heal(heal_amount))
	# The caster is healed too, but never revived by their own cast - a downed player
	# cannot cast anything, so that branch could only ever be dead code.
	caster.heal(heal_amount)
	# The solo floor: nobody to revive means the cast instead wards the caster - the
	# next would-be death inside the window is refused. See die().
	caster._phoenix_ward_timer = GameSettings.spell_white_rally_ward_duration * caster._rank_duration()
	# The caster's own half of it. Rally reaches other people, so without this the one
	# player who cast it is the only one who sees nothing happen where they are standing.
	caster._spawn_cast_flash(Player.FX_WHITE, 2.8)
	caster._play_sound(&"spell_rally_fallen", caster.global_position)


## blue_1. Shoves the cone ahead far back and stuns whatever lands. The impact damage for
## anything thrown into a wall is EnemyBase's, on the knockback path.
##
## The shove is up as well as away: EnemyBase drives knockback through move_and_collide
## while its own gravity keeps running underneath on move_and_slide, so a vertical
## component arcs the enemy off the ground and drops it again on its own, with no airborne
## state to track and nothing to land them from.
static func cast_blue_unsummon(caster: Player) -> void:
	var pushed: int = 0
	# Push distance and stun duration are what rank buys here - the cone itself does not
	# widen, so aiming it stays the skill.
	var push: float = GameSettings.spell_blue_unsummon_knockback * caster._rank_area()
	var stun: float = GameSettings.spell_blue_unsummon_stun * caster._rank_duration()
	# The lift does NOT scale with rank. Rank buys distance and stun; a rank-5 Unsummon
	# throwing enemies twice as high would put them out of reach of everything else the
	# player could follow up with.
	var lift: float = GameSettings.spell_blue_unsummon_lift
	for enemy: Node3D in caster._enemies_in_cone(GameSettings.spell_blue_unsummon_range, GameSettings.spell_blue_unsummon_cone_dot):
		var away: Vector3 = enemy.global_position - caster.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -caster.transform.basis.z
		if enemy.has_method("apply_knockback"):
			enemy.apply_knockback(away.normalized() * push + Vector3.UP * lift)
		if enemy.has_method("apply_stun") and not (enemy.has_method("is_immune_to_control") and enemy.is_immune_to_control()):
			enemy.apply_stun(stun)
		pushed += 1
	# A blast of air down the cone, not a ring around the caster. Unsummon pushes in ONE
	# direction, and a ring told the player it had happened in every direction - including
	# behind them, where it is safe and nothing was shoved at all.
	var facing: Vector3 = -caster.transform.basis.z
	facing.y = 0.0
	caster._spawn_gust(
		caster.global_position + Vector3(0.0, 1.0, 0.0), facing,
		GameSettings.spell_blue_unsummon_range, Player.FX_BLUE
	)
	caster._play_sound(&"spell_unsummon", caster.global_position)
	if pushed > 0:
		caster._play_sound(&"blunt_hit", caster.global_position)
	# Shaken harder than it used to be, to match a shove that now lifts what it hits.
	caster._shake(0.45, 0.35)


## blue_2. Frost Breath freezes everything around the caster. BOSSES ARE SLOWED, NEVER FROZEN - that
## clause is what stops one blue skill deleting a boss fight.
static func cast_blue_frostwave(caster: Player) -> void:
	var damage: float = GameSettings.spell_blue_frostwave_damage * caster.get_spell_damage_multiplier() * caster._rank_damage()
	var radius: float = GameSettings.spell_blue_frostwave_radius * caster._rank_area()
	var freeze: float = GameSettings.spell_blue_frostwave_freeze * caster._rank_duration()
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, radius):
		caster._deal_damage(enemy, damage, false)
		var is_boss: bool = enemy.has_method("is_boss") and enemy.is_boss()
		if is_boss:
			if enemy.has_method("apply_frost_slow"):
				enemy.apply_frost_slow(GameSettings.spell_blue_frostwave_boss_slow * caster._rank_duration())
		elif "freeze_timer" in enemy:
			enemy.freeze_timer = maxf(enemy.freeze_timer, freeze)
	caster._spawn_ring(caster.global_position, Color(0.55, 0.85, 1.0), radius)
	# The settle beat: the ground it froze stays frozen for a few seconds after the wave
	# has gone, which is what makes the radius legible AFTER the fact.
	caster._place_ground_decal("decal_frost", Color(0.78, 0.92, 1.0, 0.75), radius, caster.global_position)
	caster._play_sound(&"spell_frostwave", caster.global_position)
	caster._shake(0.35, 0.3)


## blue_3. The eye Suction leaves behind: a zone that keeps dragging enemies toward
## its centre for its whole duration rather than pulling once. See SuctionZone.
static func cast_blue_suction(caster: Player) -> void:
	# RADIUS and DURATION scale, pull speed does not - walking out of the zone is the
	# counterplay, and a rank-5 yank that nothing can escape would remove it. What rank
	# really buys is how long the vortex stands there doing it.
	var radius: float = GameSettings.spell_blue_suction_radius * caster._rank_area()
	var center: Vector3 = caster._aim_point(radius)
	# Rank buys TIME here, on its own explicit curve - see the GameSettings comment. It is
	# multiplied by the Vigilance bonus but NOT by rank_duration_mult, which would count the
	# rank a second time on top of the curve.
	var duration: float = GameSettings.rank_fraction(
		GameSettings.spell_blue_suction_duration,
		GameSettings.spell_blue_suction_duration_max,
		caster._casting_rank
	) * caster._vigilance_mult()
	caster._place_networked({
		"kind": "suction", "position": center, "radius": radius, "duration": duration,
		"pull": GameSettings.spell_blue_suction_pull_speed,
	})
	# Prime the pull on everything already inside, so the drag starts on the cast frame
	# rather than one physics frame late.
	for enemy: Node3D in caster._enemies_in_radius(center, radius):
		if enemy.has_method("apply_suction"):
			enemy.apply_suction(center, GameSettings.spell_blue_suction_pull_speed)
	caster._spawn_ring(center, Color(0.35, 0.6, 1.0), radius * 0.6)
	caster._play_sound(&"spell_suction", center)


## blue_4. A solid ice barricade laid perpendicular to the aim direction, across the lane.
static func cast_blue_wall_of_frost(caster: Player) -> void:
	var center: Vector3 = caster._aim_point(12.0)
	var forward: Vector3 = center - caster.global_position
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = -caster.transform.basis.z
		forward.y = 0.0
	forward = forward.normalized()
	caster._place_networked({
		"kind": "wall_of_frost", "position": caster._ground_snap(center),
		"length": GameSettings.spell_blue_wall_of_frost_length * caster._rank_area(),
		"duration": GameSettings.spell_blue_wall_of_frost_duration * caster._rank_duration(),
		"damage": GameSettings.spell_blue_wall_of_frost_unsummon_bonus_damage * caster.get_spell_damage_multiplier() * caster._rank_damage(),
		# The yaw `look_at(position + forward)` would have produced. A Node3D's forward is
		# its own -Z, so aiming -Z along `forward` means aiming +Z along its negation.
		"yaw": atan2(-forward.x, -forward.z),
	})
	caster._play_sound(&"spell_frost_globe", center)


## blue_5. Displace: a short blue blink to the aimed ground point.
## A blink THROUGH things, which is the point of it - including the caster's own Wall of
## Frost, which it used to stop dead at. The wall is a StaticBody3D on physics layer 1 (so
## that the player collides with it), and both of the rays that place this blink hit layer
## 1 by default: the aim ray landed on the wall's face and the ground snap then dropped the
## caster onto its top. Both are pointed at ENVIRONMENT_MASK instead, so the only thing
## either of them can find is actual terrain and the wall is invisible to the spell.
static func cast_blue_displace(caster: Player) -> void:
	var from: Vector3 = caster.global_position
	var max_distance: float = GameSettings.spell_blue_displace_distance * caster._rank_area()
	var target: Vector3 = caster._ground_snap(
		caster._aim_point(max_distance, ENVIRONMENT_MASK), ENVIRONMENT_MASK)
	var offset: Vector3 = target - from
	offset.y = 0.0
	if offset.length() > max_distance:
		target = from + offset.normalized() * max_distance
		target = caster._ground_snap(target, ENVIRONMENT_MASK)
	caster._spawn_ring(from, Color(0.42, 0.72, 1.0), 1.7)
	caster.global_position = target
	caster.velocity = Vector3.ZERO
	caster._spawn_ring(caster.global_position, Color(0.68, 0.9, 1.0), 2.0)
	caster._play_sound(&"spell_cast", caster.global_position)


## black_1. A line, not a cone: the blade passes THROUGH everything it touches and misses
## everything it does not, which is what makes it a skill shot.
static func cast_black_doom_blade(caster: Player) -> void:
	var aim_target: Vector3 = caster._aim_point(GameSettings.spell_black_doom_blade_length, 5)
	var forward: Vector3 = aim_target - caster.global_position
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = -caster.transform.basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var length: float = GameSettings.spell_black_doom_blade_length * caster._rank_area()
	# "Width (barely)" in the design doc, so barely: a blade that widened with the rest
	# would stop being a line and start being a cone.
	var half_width: float = GameSettings.rank_fraction(
		GameSettings.spell_black_doom_blade_width, GameSettings.spell_black_doom_blade_width_max, caster._casting_rank
	) * 0.5
	var damage: float = GameSettings.spell_black_doom_blade_damage * caster.get_spell_damage_multiplier() * caster._rank_damage()

	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, length):
		var offset: Vector3 = enemy.global_position - caster.global_position
		offset.y = 0.0
		var along: float = offset.dot(forward)
		if along < 0.0 or along > length:
			continue
		# Distance from the line itself, which is what "only what the blade touches" means.
		if (offset - forward * along).length() > half_width:
			continue
		caster._deal_damage(enemy, damage, false)

	caster._spawn_beam(caster.global_position + Vector3(0.0, 1.1, 0.0), forward, length, Color(0.6, 0.15, 0.75))
	caster._play_sound(&"spell_doom_blade", caster.global_position)


## black_2. The colour's answer to being surrounded: they leave rather than stop. See
## EnemyBase.apply_fear, which moves the body rather than only suppressing the attack.
static func cast_black_fear(caster: Player) -> void:
	var radius: float = GameSettings.spell_black_fear_radius * caster._rank_area()
	var duration: float = GameSettings.spell_black_fear_duration * caster._rank_duration()
	# Scattering the pack is a COST in a game whose whole roster wants enemies clustered, so
	# the flee has to buy something back. Everything running is easier to kill while it runs,
	# which turns Fear from a button that undoes the player's own positioning into a window
	# they open on purpose - and gives black's two debuffs a reason to be cast together.
	var vulnerability: float = GameSettings.rank_fraction(
		GameSettings.spell_black_fear_vulnerability, GameSettings.spell_black_fear_vulnerability_max, caster._casting_rank
	)
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, radius):
		if enemy.has_method("apply_fear"):
			enemy.apply_fear(duration, caster.global_position)
			# Applied to everything in the radius, INCLUDING the bosses that shrug off the
			# flee itself - otherwise Fear is a blank card in exactly the fight where black
			# most needs one, and the spell reads as having failed.
			if enemy.has_method("apply_doom_curse"):
				enemy.apply_doom_curse(duration, vulnerability)
	caster._spawn_ring(caster.global_position, Color(0.45, 0.15, 0.6), radius)
	# Black's settle beat: the ground the shout emptied stays marked, so the player can see
	# where their own safe circle was after the enemies have scattered out of it.
	caster._place_ground_decal("decal_blight", Color(0.16, 0.05, 0.22, 0.8), radius, caster.global_position)
	caster._play_sound(&"spell_fear", caster.global_position)


## black_3. The only outright delete in the game. Bosses are executed ONLY below the
## threshold - without that clause this one skill would end every wave boss on sight.
static func cast_black_kill(caster: Player) -> void:
	var target: Node3D = null
	var forward: Vector3 = -caster.camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best_dot: float = 0.55
	# Whatever the player is most directly looking at, rather than whatever is nearest:
	# a single-target execute that picked its own victim would be a different skill.
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, GameSettings.spell_black_kill_range * caster._rank_area()):
		var to_enemy: Vector3 = enemy.global_position - caster.global_position
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.01:
			continue
		var alignment: float = forward.dot(to_enemy.normalized())
		if alignment > best_dot:
			best_dot = alignment
			target = enemy

	if target == null:
		return
	if target.has_method("is_boss") and target.is_boss():
		var ratio: float = HealthReader.ratio(target)
		# The window a boss can be executed inside is what rank widens - the cooldown is
		# the other half, in _get_spell_cooldown.
		var threshold: float = GameSettings.rank_fraction(
			GameSettings.spell_black_kill_boss_threshold, GameSettings.spell_black_kill_boss_threshold_max, caster._casting_rank
		)
		if ratio < 0.0 or ratio > threshold:
			# Too healthy to execute. The cooldown is still spent - the risk of calling it
			# early is what makes the threshold a decision rather than a formality.
			caster._notify("Not weak enough to kill")
			return
	caster._spawn_ring(target.global_position, Color(0.35, 0.05, 0.45), 2.4)
	caster._play_sound(&"spell_kill", target.global_position)
	caster._shake(0.5, 0.3, target.global_position)
	# An ordinary death, not an exile: the corpse stays on the field, which is what makes
	# Kill feed Zombify inside the same colour.
	if target.has_method("die"):
		target.die()


## black_4. Laid across the player's line of sight rather than along it - see SoulWall,
## where the placement rule is explained.
static func cast_black_wall_of_souls(caster: Player) -> void:
	var center: Vector3 = caster._aim_point(20.0)
	var facing: Vector3 = -caster.camera.global_basis.z
	facing.y = 0.0
	var info: Dictionary = {
		"kind": "soul_wall", "position": center,
		"length": GameSettings.spell_black_wall_length * caster._rank_area(),
		"duration": GameSettings.spell_black_wall_duration,
		"mark_duration": GameSettings.spell_black_wall_mark_duration * caster._rank_duration(),
		# x2 damage is the headline at rank 1; x4 would eclipse every other black skill.
		"mark_mult": GameSettings.rank_fraction(
			GameSettings.spell_black_wall_mark_mult, GameSettings.spell_black_wall_mark_mult_max, caster._casting_rank
		),
	}
	if facing.length_squared() > 0.01:
		# The wall lies ACROSS the approach the player is looking down, so its NORMAL is
		# what points back at them. A yaw of atan2(x, z) already aims local +Z along
		# `facing`, and the curtain's normal is its local +Z - the extra quarter turn this
		# used to add turned the wall edge-on and laid it ALONG the lane instead, which is
		# the one orientation that blocks nothing.
		info["yaw"] = atan2(facing.x, facing.z)
	caster._place_networked(info)
	caster._play_sound(&"spell_wall_of_souls", center)


## black_5. Turns the corpse registry - which until now existed only to cap how many dead
## bodies stayed in the scene - into a resource.
static func cast_black_zombify(caster: Player) -> void:
	var corpses: Array[EnemyBase] = EnemyBase.corpses()
	if corpses.is_empty():
		caster._notify("No corpses to raise")
		return
	# Nearest first, so the spell raises what the player is standing over rather than
	# something that died in another lane five waves ago.
	corpses.sort_custom(func(a: EnemyBase, b: EnemyBase) -> bool:
		return caster.global_position.distance_squared_to(a.global_position) < caster.global_position.distance_squared_to(b.global_position))

	var raised: int = 0
	var to_raise: int = GameSettings.rank_count(
		GameSettings.spell_black_zombify_count, GameSettings.spell_black_zombify_count_max, caster._casting_rank
	)
	for corpse: EnemyBase in corpses:
		if raised >= to_raise:
			break
		var where: Vector3 = corpse.global_position
		var source: EnemyData = corpse.enemy_data
		EnemyBase.consume_corpse(corpse)
		# A corpse's own position is where the enemy DIED, which can be off the navmesh
		# edge or mid-clip - so the summon is dropped onto the ground actually under it.
		#
		# The corpse's EnemyData cannot be sent, so what TemporaryAlly actually reads off
		# it travels instead: the colour and the class it picks the model from.
		caster._place_networked({
			"kind": "undead",
			"position": caster._ground_snap(where) + Vector3(0.0, 0.5, 0.0),
			"hp": GameSettings.spell_black_zombify_hp * caster._rank_damage(),
			"duration": GameSettings.spell_black_zombify_duration * caster._rank_duration(),
			"damage": GameSettings.spell_black_zombify_damage * caster.get_spell_damage_multiplier() * caster._rank_damage(),
			"color": source.color_identity if source != null else "",
			"class": source.enemy_class if source != null else "",
		})
		caster._spawn_ring(where, Player.FX_BLACK, 1.8)
		raised += 1
	caster._play_sound(&"spell_zombify", caster.global_position)


## red_2, first half. Fired when the cast STARTS, like Titanic Brawl: the dash has to be
## under way by the time the release frame lights the trail behind it.
static func cast_red_fire_dash(caster: Player) -> void:
	var forward: Vector3 = -caster.transform.basis.z
	forward.y = 0.0
	# Distance is speed x time, and it is the DISTANCE the design doc scales - so the
	# speed rises and the dash stays as short as it reads.
	caster.velocity = forward.normalized() * GameSettings.spell_red_dash_speed * caster._rank_area()
	caster.velocity.y = 0.0
	caster._dash_timer = GameSettings.spell_red_dash_duration
	caster._dash_trail_timer = 0.0
	# Fixed now: the trail keeps being laid after the cast is over, by which time
	# _casting_rank may belong to something else entirely.
	caster._dash_trail_dps = GameSettings.spell_red_dash_trail_dps * caster.get_spell_damage_multiplier() * caster._rank_damage()
	caster._dash_trail_duration = GameSettings.spell_red_dash_trail_duration * caster._rank_duration()
	caster._dash_trail_radius = GameSettings.spell_red_dash_trail_radius * caster._rank_area()
	caster._play_sound(&"spell_fire_dash", caster.global_position)


## red_2, second half. Everything the dash passed over is already burning by now - the
## trail is dropped along the way in _physics_process; this is the last segment plus the
## noise that sells it.
static func _lay_fire_trail(caster: Player) -> void:
	_drop_trail_segment(caster)
	caster._shake(0.25, 0.2)


## One burning patch of the dash's wake. Small and short-lived individually - it is the
## line of them that does the damage.
static func _drop_trail_segment(caster: Player) -> void:
	# Nothing to drop when this machine never ran the dash. `cast_red_fire_dash` sets
	# these three, and it runs on the CASTER - so on the server's copy of a client's
	# avatar they are still zero, and the release frame was asking every peer to spawn a
	# zone of radius zero lasting zero seconds. The caster's own segments, laid along the
	# way, are the trail; this only ever added the last one.
	if caster._dash_trail_radius <= 0.0:
		return
	caster._place_networked({
		"kind": "dot_zone", "type": "fire_patch", "position": caster.global_position,
		"radius": caster._dash_trail_radius, "dps": caster._dash_trail_dps, "duration": caster._dash_trail_duration,
	})


## red_4. Starts the channel; the damage is paid out per frame in _update_channel while
## the button stays down. Held spells are the only ones whose effect is not a single
## moment, which is why this one function does almost nothing.
## Only the STATE is set here, and only on the server. The flames and the loop that go
## with it are built by _sync_channel_fx, on every peer, from `_channel_id` - a channel is
## the one spell whose visual is not a moment but a condition, so it is replicated as a
## condition rather than as an event.
##
## `held` comes from the caster's own keyboard (see execute_spell). Started from the
## number-key hotbar instead there is no hold to watch, so the channel runs its length.
static func cast_red_fire_cone(caster: Player, held: bool) -> void:
	if caster._channel_id != "" or caster.spell_cooldown_timers.get("red_4", 0.0) > 0.0:
		return
	caster._channel_id = "red_4"
	caster._channel_timer = GameSettings.spell_red_fire_cone_max_duration
	caster._channel_held = held
	caster._channel_release_sent = false
	caster._channel_slot = caster.active_spell_index
	caster._channel_rank = caster._casting_rank
	caster._sync_channel_fx()


## red_5. The smallest area in the game and the biggest single number, telegraphed so the
## precision is the player's rather than the spell's.
static func cast_red_lightning_bolt(caster: Player) -> void:
	# "Radius (slightly)" in the design doc: the smallest area in the game is the point of
	# the skill, so rank buys damage and only a little forgiveness on the aim.
	var bolt_radius: float = GameSettings.spell_red_bolt_radius * GameSettings.rank_fraction(1.0, 1.25, caster._casting_rank)
	var bolt_damage: float = GameSettings.spell_red_bolt_damage * caster._rank_damage()
	# Fixed at cast time along with everything else the delayed strike needs: by the time it
	# lands the player may have ranked up, died, or be casting something else entirely.
	var elite_mult: float = GameSettings.rank_fraction(
		GameSettings.spell_red_bolt_elite_mult, GameSettings.spell_red_bolt_elite_mult_max, caster._casting_rank
	)
	var target: Vector3 = caster._aim_point(GameSettings.spell_red_bolt_range, 5)
	# AttackIndicator parents itself to whatever it is told to mark - the enemies pass
	# themselves, so the telegraph tracks them. A ground strike has nothing to track, so
	# it gets an anchor of its own to sit on, built on every peer: a telegraph only the
	# host can see is a spell the rest of the party has no warning about, and this is the
	# one skill in the game that asks the player to stand out of its way.
	#
	# The telegraph clears ITSELF on the same delay, wherever it was built. Nothing here
	# holds a reference to it, because on four of the five machines there is nothing to
	# hold - see MainController._build_bolt_telegraph.
	caster._place_networked({
		"kind": "bolt_telegraph", "position": target,
		"radius": bolt_radius, "delay": GameSettings.spell_red_bolt_delay,
	})

	# The strike lands AFTER the telegraph, not with it - a warning that resolves on the
	# frame it appears is not a warning. Which also means the player can be dead, or the
	# whole scene gone, by the time it arrives.
	var timer: SceneTreeTimer = caster.get_tree().create_timer(GameSettings.spell_red_bolt_delay)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(caster) or not caster.is_inside_tree():
			return
		var damage: float = bolt_damage * caster.get_spell_damage_multiplier()
		for enemy: Node3D in caster._enemies_in_radius(target, bolt_radius):
			caster._deal_damage(enemy, damage * caster._bolt_target_multiplier(enemy, elite_mult), false)
		caster._spawn_beam(target + Vector3(0.0, 18.0, 0.0), Vector3.DOWN, 18.0, Color(0.75, 0.9, 1.0))
		caster._spawn_ring(target, Color(0.8, 0.9, 1.0), bolt_radius)
		caster._play_sound(&"spell_lightning_bolt", target)
		caster._shake(0.55, 0.35, target))


## green_2. Bigger AND tougher: the size is what the player sees, the health is what the
## skill actually does. `_sync_auras` owns the health half so it cannot drift.
static func cast_green_giant_growth(caster: Player) -> void:
	caster.is_giant = true
	caster.giant_timer = GameSettings.spell_green_giant_duration * caster._rank_duration()
	caster._giant_bonus_hp = GameSettings.player_max_hp * GameSettings.spell_green_giant_bonus_hp_mult * caster._rank_damage()
	var giant_scale: float = GameSettings.rank_fraction(
		GameSettings.spell_green_giant_scale, GameSettings.spell_green_giant_scale_max, caster._casting_rank
	)
	# The melee halves key off this, so it is fixed at cast time rather than re-read from
	# the tweened `scale` every frame - which would still be mid-grow when the first
	# swing went out.
	# The growth itself is driven by _sync_giant_scale, on every peer, from this number.
	# The tween used to be started here - which is to say on the server, because that is
	# where a spell resolves - so the caster got bigger on the host's screen and on no
	# other, their own included.
	caster._giant_scale_mult = giant_scale
	caster._sync_auras()
	# Gaining maximum health should ARRIVE as health, or the buff reads as a downgrade
	# for the first few seconds while the bar sits at a lower fraction than before.
	caster.heal(caster._giant_bonus_hp, false)
	# Giant Growth had NO effect of any kind: the character silently got bigger, which
	# reads as a rendering glitch rather than as a spell. The ring is sized to what the
	# player has just become, so the growth is announced at the scale it actually is.
	caster._spawn_cast_flash(Player.FX_GREEN, 3.0)
	caster._spawn_ring(caster.global_position, Player.FX_GREEN, 2.2 * giant_scale)
	caster._play_sound(&"spell_giant_growth", caster.global_position)


## green_3. Ground where enemies deal nothing. Half of green's crystal-defence pair.
static func cast_green_fog(caster: Player) -> void:
	var target: Vector3 = caster._aim_point(20.0)
	caster._place_networked({
		"kind": "dot_zone", "type": "fog", "position": target,
		"radius": GameSettings.spell_green_fog_radius * caster._rank_area(),
		"dps": 0.0,
		"duration": GameSettings.spell_green_fog_duration * caster._rank_duration(),
	})


## green_4. The other half: pulls enemies off the crystal and the myrs and onto the
## player, which is the only skill in the game that moves aggro deliberately.
static func cast_green_roar(caster: Player) -> void:
	var taunted: int = 0
	var radius: float = GameSettings.spell_green_roar_radius * caster._rank_area()
	for enemy: Node3D in caster._enemies_in_radius(caster.global_position, radius):
		if enemy.has_method("apply_taunt"):
			enemy.apply_taunt(caster, GameSettings.spell_green_roar_duration * caster._rank_duration())
			taunted += 1
	# A shout is a front leaving the caster, which is what the release beat draws.
	caster._spawn_impact(caster.global_position, Player.FX_GREEN, radius)
	caster._play_sound(&"spell_roar", caster.global_position)
	caster._shake(0.3, 0.3)
	if taunted > 0:
		caster._notify("%d enemies turned on you" % taunted)


## green_5. Damage reduction AND immunity to knockback, stun and freeze - the only answer
## in the game to being controlled. Both halves are read where they apply: take_damage
## for the reduction, _try_hit_reaction and apply_slow for the immunity.
static func cast_green_ironbark(caster: Player) -> void:
	caster._ironbark_timer = GameSettings.spell_green_ironbark_duration * caster._rank_duration()
	# A fraction, so it walks to a ceiling: x2 on 0.6 is 1.2, which is immunity.
	caster._ironbark_reduction = GameSettings.rank_fraction(
		GameSettings.spell_green_ironbark_reduction, GameSettings.spell_green_ironbark_reduction_max, caster._casting_rank
	)
	caster._stagger_timer = 0.0
	# Bark rather than leaf: green's earth end of the palette, so Ironbark cannot be
	# mistaken for Giant Growth at a glance.
	caster._spawn_cast_flash(Color(0.52, 0.40, 0.22), 2.2)
	caster._play_sound(&"spell_ironbark", caster.global_position)
