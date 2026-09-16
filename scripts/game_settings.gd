extends Node

# ============================================================
# MAP
# ============================================================
@export var map_base_radius: float = 50.0

# ============================================================
# DAY / NIGHT
# ============================================================
## The in-game hour a run begins at. Applied to Sky3D by MainController._ready.
##
## A run used to open at 20:45, which is past DayNightPacing's 20:00 dusk - so the game
## started in the dark, with the night music and the night clock rate, before the player had
## done anything. That was not a decision: it is whatever time the Sky3D node happened to be
## scrubbed to when scenes/misc/main.tscn was last saved, and any editor session that touches
## the sky can move it again.
##
## 7:00 is morning proper rather than 6:00 dawn: the sun is up and low, which is the best
## light the arena gets, and it leaves thirteen of the fourteen daylight hours ahead - close
## to a full day_real_minutes before the first night falls.
##
## The .tscn still carries a matching value so the EDITOR preview is not night either. This
## one is what the game actually uses, the same split DayNightPacing documents for
## minutes_per_day.
@export var day_start_hour: float = 7.0

# ============================================================
# CRYSTAL
# ============================================================
@export var crystal_max_hp: float = 1000.0

# ============================================================
# PLAYER
# ============================================================
@export var player_max_hp: float = 100.0
## How many players the map spawns. 1 is single-player; the lobby will set this once
## Phase 1 of docs/MULTIPLAYER_PLAN.md lands. Everything downstream already scales -
## enemy damage, target selection and the Upkeep vote threshold all read the count.
@export var player_count: int = 1
## Matched to what the animation pack was authored for, rather than chosen first and
## patched over afterwards. run_forward covers 2.47 m/s at its own recorded speed, so
## moving at 2.5 plays that cycle at 1.0x - the legs turn over exactly as animated,
## with no stretching and no sliding.
##
## This is a large cut from the original 6.0, and it is the whole cost of playing the
## clips untouched: a 144 m lane now takes about a minute to cross on foot. Raising it
## does not break anything, it just reintroduces sped-up playback in proportion.
@export var player_base_speed: float = 2.5
@export var player_sprint_speed_mult: float = 1.5
@export var player_jump_velocity: float = 4.5
@export var player_mouse_sensitivity: float = 0.002
@export var player_gamepad_look_sensitivity: float = 2.5
## Myrs only. The player no longer harvests: mana banks automatically on kill, because
## the pool is the team's and there is nobody for a pickup to belong to. Walking a well
## round trip used to cost the player ~40 seconds for a single mana.
@export var player_mana_harvest_distance: float = 6.0
@export var player_mana_harvest_time: float = 3.0

# --- DOWNED / REVIVE ---
## Multiplayer: how long a downed player can be picked up before they respawn at the
## base. The clock keeps running while a teammate channels - help that arrives too
## late arrives too late.
@export var player_downed_duration: float = 20.0
## Solo there is nobody to channel, so the downed state is only a short death penalty.
@export var player_downed_solo_duration: float = 5.0
## The helper's channel. Broken by the HELPER moving, attacking or casting - not by
## taking damage, so rescues under fire stay possible.
@export var player_revive_channel_time: float = 3.0
@export var player_revive_range: float = 3.0
@export var player_base_proximity: float = 5.0
## How far from the crystal each player's spawn point sits.
##
## Players used to spawn at the world origin - solo literally at Vector3(0, 1, 0), which is
## INSIDE the crystal, and in a party on a 2.5-unit ring that is still inside its visual. The
## five points are now one per lane, so everyone starts facing the direction their enemies
## come from and nobody starts embedded in the objective.
##
## Must stay below player_base_proximity: spawning outside it would open a run with the "Press
## E to Manage Base" prompt already gone, and the first thing a player does is shop.
@export var player_spawn_ring_radius: float = 4.2
## Myrs only, for the same reason - the player never carries anything now.
@export var player_carry_speed_penalty: float = 0.5
@export var player_base_hp_regen: float = 1.0

# ============================================================
# PLAYER CAMERA
# ============================================================
## Classic over-the-shoulder third person. The offset shifts the whole orbit to the
## player's right so the character sits left of screen centre and the aim line stays
## clear; the height is the point the camera orbits around; the distance is the
## SpringArm3D's length, which still shortens automatically when geometry gets
## between the camera and the player.
##
## Pulled in from 4.5 on 2026-08-30. The offset and height are not guesses: 0.85 at
## 3.2 reproduces the 15-degree off-axis angle the old 1.2-at-4.5 rig framed the
## character with, and 1.80 is what that rig's orbit height actually was once the
## spring arm's own hidden +0.2 is folded in. So this is the same shot, just nearer.
@export var player_camera_shoulder_offset: float = 0.85
@export var player_camera_height: float = 1.80
@export var player_camera_distance: float = 3.2

# ============================================================
# PLAYER ANIMATION
# ============================================================
## Seconds of uninterrupted standing still before the player plays one of the
## "idle looking" variations instead of the plain idle loop.
@export var player_idle_variation_delay_min: float = 8.0
@export var player_idle_variation_delay_max: float = 16.0
## How far a locomotion clip may be sped up or slowed down to match real velocity
## before the feet start reading as skating either way.
@export var player_locomotion_speed_min: float = 0.6
## 1.5 rather than the old 1.8 or the 2.6 that a 5 m/s base needed. With base speed
## matched to the clips, ordinary movement and blocking both land on 1.0x and never
## come near this; it exists for sprint, which at 1.5x base wants exactly 1.5x playback
## - a genuine sprint turning the legs over faster, not a walk pretending to be one.
@export var player_locomotion_speed_max: float = 1.5
## Cross-fade lengths. Locomotion changes often, so it gets the longer blend;
## a strike has to land on the frame it says it does.
@export var player_anim_blend_locomotion: float = 0.16
## Long enough that one swing chaining into the next reads as a blend rather than a
## snap, short enough that a strike still lands on the frame it says it does.
@export var player_anim_blend_action: float = 0.12
## Time constant for easing the locomotion blend point toward where the player is actually
## going. The point is derived from post-collision velocity, which carries floor-snap and
## wall-slide noise, and a strafe turning into a forward run should read as a weight shift
## rather than a snap. Short enough that it never lags behind the stick in a way anyone feels.
@export var player_anim_blend_point_smoothing: float = 0.09

# ============================================================
# PLAYER MELEE COMBO
# ============================================================
## One stage of the light attack chain occupies this long; the stage is speed-scaled
## onto it, so a full chain runs one of these per click regardless of how the clip
## splits up.
@export var player_swing_duration: float = 0.5
## Swings fire when the attack button is RELEASED. A release before this counts as a
## tap and swings light; at or after it, heavy. Nothing is in flight while the button
## is down, so unlike the old fire-on-press scheme this has no upper bound tied to
## the swing's impact frame - it only has to be long enough that a deliberate tap
## does not overshoot it.
@export var player_heavy_hold_time: float = 0.25
## How long a resolved swing waits for the combo window to open before it is dropped.
## Without this, releasing a fraction too early is silently ignored and the chain
## feels like it is eating inputs.
@export var player_attack_buffer_time: float = 0.25
## The last FRACTION of a swing during which another attack chains instead of being
## dropped. Every chained swing cuts the one before it short at exactly this point,
## so a wide window throws the follow-through away on every hit of a combo: at 0.5
## the swing was cut the instant it landed, which read as the animations being
## truncated. 0.3 lets ~70% of each swing play. It costs nothing in feel because
## player_attack_buffer_time already holds an early release until the window opens.
@export var player_combo_window: float = 0.30
## SECONDS after a swing ends that the recorded combo symbols survive. Kept separate
## from player_combo_window, which is a fraction - the two used to be added together,
## mixing units.
@export var player_combo_grace: float = 0.45
## The heavy attack is a full 360 spin (1.22s of usable clip) rather than a single
## chop, so it gets its own, longer commitment instead of the light chain's cadence.
@export var player_heavy_duration: float = 0.9
## How long the heavy's wind-up can be held before it goes off on its own. The clip's
## whole discarded lead-in is stretched across this, so a full charge is a slow raise
## rather than a pose that snapped into place and then froze. Releasing early fires
## early; the strike that follows is identical either way, so this buys the player
## nothing but the timing.
@export var player_heavy_charge_max: float = 1.0
## How front-loaded the raise is inside that window. The wind-up's playback rate is
## the derivative of `1 - (1 - t)^this`, so at 3.0 the axe comes up three times faster
## than a flat rate at the start and has all but settled by two thirds through - which
## is what a wind-up being HELD should feel like, rather than one steady crawl. 1.0 is
## exactly the old flat rate; higher snaps harder and holds longer. The raise still
## finishes exactly as the charge does, whatever this is set to.
@export var player_heavy_charge_ease: float = 3.0
@export var player_heavy_damage_mult: float = 2.0
@export var player_heavy_knockback: float = 12.0
## Damage multiplier on the THIRD stage of the light chain, which only exists once
## the chain extension has been bought in the skill tree.
@export var player_combo_finisher_damage_mult: float = 1.5
## Skill points the tree charges for that extension.
@export var skill_point_cost_melee_combo: int = 3
## Legacy mana price, kept only so old saves and the tree's display do not break.
@export var melee_combo_unlock_cost: int = 12
## Seconds taken off every spell cooldown by each melee impact frame that connects.
## This is the melee/spell interlock: swinging between casts brings them back faster.
## Paid per impact frame, so a stage that lands two of them refunds twice over. A
## whiff refunds nothing. The kick's own cooldown is never refunded (see
## Player._reduce_spell_cooldowns).
@export var melee_hit_cooldown_reduction: float = 0.35

## Movement multiplier during a light attack STARTED ON THE MOVE, which is the only
## melee move the player can walk through - it plays on the upper body while the legs
## keep their walk cycle. A light attack started standing still takes the whole body
## and holds the player there instead, as do heavy attacks, kicks and staggers (see
## Player._advance_light_chain and Player._begin_action).
@export var player_attack_move_mult: float = 1.0

# ============================================================
# SOUND EFFECTS
# ============================================================
## Voices SoundBank keeps alive. Positional ones carry world impacts; the flat ones
## are for the few events with no place on the map. A wave lands far more hits than
## this per second, but they overlap for a fraction of a second each - the pool only
## has to cover that overlap, and the oldest voice is recycled past it.
@export var sfx_positional_voices: int = 16
@export var sfx_flat_voices: int = 4
@export var sfx_volume_db: float = -6.0
@export var music_enabled: bool = true
@export var music_volume_db: float = -6.0
## Random detune either side of 1.0, so a handful of recordings survive being heard
## thousands of times without reading as a loop.
@export var sfx_pitch_jitter: float = 0.08
## Minimum gap between two triggers of the SAME event. Thirty enemies connecting on
## one frame is one impact sound, not thirty stacked into a clipping mess.
@export var sfx_min_retrigger: float = 0.05
## Beyond this the sound is inaudible; unit_size sets how quickly it falls off on
## the way there.
@export var sfx_max_distance: float = 45.0
@export var sfx_unit_size: float = 8.0
## A sustained ambience sits under the action rather than in it, so it is quieter
## than an impact - but it carries further, because it is what tells the player
## where the crystal is from across the map.
@export var sfx_ambience_volume_db: float = -14.0
@export var sfx_ambience_max_distance: float = 70.0

# --- Sounds the whole map hears ---
#
# The lane spawners sit at radius 179 from the crystal, so two opposite ones are ~341
# units apart. At the ordinary sfx_max_distance of 45 a boss arriving in the red lane is
# not quiet from the crystal, it is SILENT - which is what these numbers fix.
#
# Still positional, deliberately: it matters WHICH lane the boss came from, and a flat 2D
# sound throws that away. What changes is only how far the falloff reaches.
@export var sfx_global_max_distance: float = 420.0
## unit_size is the distance at which attenuation starts biting. INVERSE_DISTANCE
## attenuates roughly by unit_size/distance, so 110 over the 341-unit worst case leaves
## about -10 dB - clearly audible, still obviously far away.
@export var sfx_global_unit_size: float = 110.0
## Voices held back for these events. A boss arrival is 4.5 seconds long and the ordinary
## pool is round-robin: during a wave, sixteen impacts recycle every voice in well under
## that, and the arrival gets cut off mid-roar. A sound nobody hears the end of is not
## much better than one nobody hears at all.
@export var sfx_global_voices: int = 3

## The kick a fireball detonation gives the camera. Still under the leap's slam - a
## fireball usually goes off across the map rather than under the player's feet - but
## well above a melee hit, because it is a detonation and should read as one.
@export var spell_red_fireball_shake_strength: float = 0.45
@export var spell_red_fireball_shake_duration: float = 0.35

# ============================================================
# GREEN: TITANIC BRAWL
# ============================================================
## The launch impulse. Forward speed decides how far the leap carries; the rise is
## tuned against the clip rather than to taste - the jump_attack clip lands its slam
## at 79% of a 1.1s cast, i.e. 0.87s in, and at the engine's 9.8 gravity an initial
## 4.25/s puts the character back on the floor at exactly that moment. Retune it
## alongside spell green_1's cast_duration, never on its own.
@export var spell_green_leap_speed: float = 11.0
@export var spell_green_leap_rise: float = 4.25
## How long the player's own movement input stays suspended. Ends early at the slam.
@export var spell_green_leap_duration: float = 1.1
## The slam. Heavy single-target damage spread over an area, which is what makes it
## worth a leap rather than a swing.
@export var spell_green_leap_damage: float = 90.0
@export var spell_green_leap_radius: float = 6.0
@export var spell_green_leap_knockback: float = 12.0
## The hardest shake in the game, and the only one the player lands on themselves:
## the slam happens directly under the camera, so it can carry more than a detonation
## going off at range without reading as a glitch.
@export var spell_green_leap_shake_strength: float = 0.75
@export var spell_green_leap_shake_duration: float = 0.45

# ============================================================
# PLAYER KICK
# ============================================================
@export var spell_melee_kick_damage: float = 12.0
@export var spell_melee_kick_range: float = 2.6
@export var spell_melee_kick_knockback: float = 14.0
@export var spell_cooldown_kick: float = 1.5

# ============================================================
# PLAYER BLOCK
# ============================================================
## Fraction of incoming damage a successful block removes.
@export var player_block_damage_reduction: float = 0.8
## Minimum dot() between the player's facing and the direction to the attacker for
## a hit to count as coming from the front. 0.35 is roughly a 140-degree arc.
@export var player_block_cone: float = 0.35
@export var player_block_speed_mult: float = 0.4

## Movement while a fight is still live, as a fraction of base speed.
##
## Exists because the animation follows the same rule: mid-fight the legs stay on the
## armed walk cycle, which covers 0.99 m/s. Running at full base speed on a walk cycle
## is exactly the foot-sliding this pass set out to remove, so combat movement is
## brought down to meet the clip rather than the clip stretched to meet it.
@export var player_combat_speed_mult: float = 0.45

## How long after the last swing, cast or block the player still counts as fighting.
## Long enough that walking between two hits does not flicker back to the travel run,
## short enough that leaving a fight lets you break into a run promptly.
@export var player_combat_linger: float = 0.5
## Bosses swing straight through a guard - blocking one does nothing.
@export var player_block_ignores_boss: bool = true
## How long the guard-flinch clip is squeezed into. Does not take control away -
## the player keeps blocking through it.
@export var player_block_react_duration: float = 0.35

# ============================================================
# PLAYER HIT REACTION
# ============================================================
## A hit only staggers the player when it takes at least this fraction of max HP in
## one go; chip damage would otherwise leave the character permanently flinching.
@export var player_hit_react_damage_pct: float = 0.12
## Minimum gap between staggers, so a burst of large hits can't lock the player out.
@export var player_hit_react_cooldown: float = 1.2
## How long a stagger takes control away. The raw reaction clips run 1.0-1.8s,
## which would be punishing; they get squeezed into this instead.
@export var player_hit_react_duration: float = 0.55

# ============================================================
# PLAYER SPELLS
# ============================================================
@export var spell_melee_range: float = 3.5
@export var spell_melee_cone: float = 0.5
@export var spell_melee_damage: float = 20.0
@export var spell_melee_knockback: float = 6.0
@export var skill_unlock_cost: int = 1
@export var spell_stab_debuff_damage: float = 5.0
@export var spell_stab_debuff_duration: float = 8.0
@export var spell_unsummon_teleport_distance: float = 15.0

# Infinite color affinity ranks. Every rank grants a constant 10% bonus.
@export var affinity_rank_mana_cost: int = 1
@export var affinity_rank_bonus_base: float = 0.10
@export var affinity_rank_bonus_early: float = 0.10
@export var affinity_rank_bonus_mid: float = 0.10
@export var affinity_rank_bonus_late: float = 0.10
## How much a player must have INVESTED IN A COLOUR to reach its Nth tier of spell, and
## its Nth rank of any of them. One ladder for both, because unlocking and deepening are
## the same question asked twice - "how committed are you to this colour" - and answering
## it with two unrelated systems is what made the old tree hard to reason about.
##
## Investment is counted by Player.color_investment: the colour's affinity ranks plus every
## rank held in its five spells. Not the affinity node alone - a player who has poured six
## points into Fireball has committed to red whether or not they bought a second affinity
## rank, and the ladder should see that.
##
## This REPLACED a team-level gate. The old rule froze a player out of their own colour on
## a clock they could not influence; this one is entirely in their hands, which is why the
## numbers can be this steep.
@export var color_investment_ladder: Array[int] = [1, 2, 5, 7, 10]
## Kept only for save compatibility and the detail panel's old wording. Nothing gates on it
## any more - see color_investment_ladder.
@export var affinity_spell_rank_requirements: Array[int] = [1, 5, 10, 15, 25]
@export var aura_skill_point_cost: int = 3

## How long a chargeable spell (SpellDatabase "chargeable") can be held before it fires
## on its own, and therefore how long a full-power cast takes to build. The release
## scales the payload by how much of this window was actually held - Fireball's radius
## and damage both ride that fraction (Player.cast_red_fireball) - with a floor of 20%
## for a tap, so a quick cast is weak rather than nothing.
##
## The cast clip's discarded lead-in is stretched across this window, so the caster
## visibly winds the spell up for as long as it is held (Player._begin_spell_windup).
##
## Cut from 5.0 on 2026-09-10. Fireball is the only chargeable spell, and five seconds was a
## long commitment mid-fight for what it buys: charge multiplies damage 0.6 -> 1.8 and radius
## 2.4 -> 4.5, which is a real payoff, but not one worth standing still five seconds for while
## a lane walks past you. Three keeps the same range of outcomes on a hold a fight can afford.
##
## Everything downstream is expressed as a FRACTION of this, so nothing else moves: the
## charge_pct the spell scales by is unchanged, and _begin_spell_windup stretches the cast
## clip's lead-in across whatever this says - the raise simply plays faster.
@export var spell_charge_max_time: float = 3.0

# Per-spell cooldowns moved to scripts/spell_database.gd, which owns one row per
# spell. Tier costs stay here: they are shared tuning, not per-spell data.

# --- MTG 5-Color Tier Costs ---
const TIER_COSTS: Array[int] = [1, 3, 7, 15, 30, 50]

func get_tier_cost(tier_index: int) -> int:
	if tier_index >= 0 and tier_index < TIER_COSTS.size():
		return TIER_COSTS[tier_index]
	return 1

# --- RED SKILLS ---
@export var spell_red_shock_damage: float = 70.0
@export var spell_red_fireball_base_radius: float = 3.0
@export var spell_red_fireball_base_damage: float = 60.0
@export var spell_red_rain_ember_duration: float = 5.0
@export var spell_red_rain_ember_radius: float = 6.0
@export var spell_red_rain_ember_dps: float = 25.0
@export var aura_fervor_speed_boost: float = 1.15

# --- BLUE SKILLS ---
@export var spell_blue_unsummon_knockback: float = 21.0
## How hard the shove also throws them UPWARD. A purely horizontal push slid enemies
## along the floor like furniture; lifting them makes the same shove read as a blast that
## picked them up, and it is what turns the landing into an event the player can watch.
##
## Not a full launch: at this against gravity the arc peaks about a metre up and is over
## in well under a second, so the stun that follows still lands on an enemy standing on
## the ground rather than one floating out of reach.
@export var spell_blue_unsummon_lift: float = 7.5
@export var spell_blue_unsummon_damage: float = 35.0
@export var spell_blue_unsummon_impact_damage: float = 80.0
@export var spell_blue_freeze_breath_shatter_damage: float = 90.0
@export var spell_blue_freeze_breath_shatter_radius: float = 4.0
@export var aura_rhystic_study_cdr_mult: float = 0.7
@export var aura_rhystic_study_shield_amount: float = 15.0
@export var aura_rhystic_study_shield_max: float = 45.0

# --- GREEN SKILLS ---
@export var aura_sylvan_library_hp_mult: float = 1.35
@export var aura_sylvan_library_regen: float = 3.0

# --- WHITE SKILLS ---
@export var spell_white_swords_exile_pct: float = 0.5
@export var spell_white_swords_damage_cap: float = 120.0
@export var spell_white_swords_ally_heal: float = 60.0
@export var spell_white_path_to_exile_exec_mult: float = 0.5
@export var spell_white_pacifism_debuff_mult: float = 0.5
## Glorious Anthem's shield is documented as PERMANENT, and it was not: it is assigned once in
## Player._sync_auras, which early-returns when the aura signature has not changed, so
## the first hit that broke it broke it for the rest of the run. It recharges out of combat now,
## which is what "permanent" has to mean for a shield that can be spent.
@export var aura_glorious_anthem_shield: float = 35.0
## Seconds without TAKING DAMAGE before it starts coming back, then how fast. Keyed off damage
## taken rather than the combat timer, which is set by the player's own swings - a white player
## meleeing safely behind their team is not the case this is meant to lock out.
@export var aura_glorious_anthem_recharge_delay: float = 6.0
@export var aura_glorious_anthem_recharge_rate: float = 10.0
@export var aura_glorious_anthem_damage_mult: float = 1.15

# --- BLACK SKILLS ---
@export var spell_black_drain_life_damage: float = 70.0
@export var spell_black_drain_life_lifesteal: float = 0.65
@export var aura_phyrexian_arena_hp_drain_pct: float = 0.015
@export var aura_phyrexian_arena_damage_mult: float = 1.25
@export var aura_phyrexian_arena_speed_mult: float = 1.15

# ============================================================
# SKILL ROSTER - docs/SKILL_DESIGN.md
# ============================================================
# Five rankable skills per colour plus a aura fork, exactly as the colour tables
# specify. What each skill DOES lives in Player; only its numbers live here, and only
# the ones a designer would want to reach for. Cooldowns are the one exception: they
# belong to the spell row in scripts/spell_database.gd, alongside the animation timing
# they have to agree with.

# --- WHITE: protection and restoration ---
## Exalted Strike (white_1). Charges are consumed by melee hits, not by time, so the
## buff cannot be wasted by walking around with it.
@export var spell_white_exalted_damage_mult: float = 2.4
@export var spell_white_exalted_reach_bonus: float = 2.0
@export var spell_white_exalted_charges: int = 1
## Circle of Protection (white_2). A BASE shield per ally, grown a little for every
## ally beyond the first - white's power goes UP with more allies alive, and dividing
## one pool said the opposite. Bound to player_max_hp like every white/green HP number.
## Circle of Protection (white_2). Cut from 2.2 on 2026-09-10, and that number was a bug rather
## than a balance choice: the spell used to be one POOL of 220 divided between everyone in range
## (spell_white_circle_shield_total), and when it became a shield PER ALLY the 220 came along
## unchanged. A five-player cast went from granting 220 shield in total to granting 1540, and
## even solo it was 2.2 whole health bars from one button.
##
## 0.35 of max HP is 35 a head at rank 1 and 70 at rank 5 - about three ordinary hits, four with
## the crowd bonus. Compare the tier-5 defensive skills it was outclassing: Ironbark is 60%
## reduction for six seconds, and Rally's ward brings you back at 40% health.
@export var spell_white_circle_shield_hp_mult: float = 0.35
@export var spell_white_circle_ally_bonus: float = 0.10
@export var spell_white_circle_radius: float = 12.0
## ...and it EXPIRES. Nothing else in the roster is permanent, and a shield that is not was the
## other half of the problem: with an 18s cooldown and no duration the correct play was to stand
## in the base spamming it until the pool was arbitrarily large, which is not a decision.
##
## Comfortably shorter than the 18s cooldown even at rank 5 with Vigilance (8 x 1.5 x 1.2 =
## 14.4s), so the shield cannot be kept up permanently by recasting either.
@export var spell_white_circle_duration: float = 8.0
## Reprisal Ward (white_3)
@export var spell_white_reprisal_reflect: float = 0.45
@export var spell_white_reprisal_block_chance: float = 0.3
@export var spell_white_reprisal_duration: float = 8.0
## Wrath of God (white_4). White's one panic button, so it hits hard and rarely.
@export var spell_white_wrath_radius: float = 10.0
@export var spell_white_wrath_damage: float = 170.0
## Rally the Fallen (white_5). The heal is bound to player_max_hp. The ward is the
## solo floor: with nobody to revive, the cast instead guarantees the caster survives
## the next would-be death inside its window, at this fraction of max HP.
@export var spell_white_rally_radius: float = 15.0
@export var spell_white_rally_heal_hp_mult: float = 2.5
@export var spell_white_rally_ward_duration: float = 10.0
@export var spell_white_rally_ward_hp_fraction: float = 0.4

# --- BLUE: control ---
## Unsummon (blue_1). Cone in front, not a circle: blue decides where the fight happens,
## and a shove that also cleared what is behind you would need no aiming at all.
@export var spell_blue_unsummon_range: float = 12.0
@export var spell_blue_unsummon_cone_dot: float = 0.2
@export var spell_blue_unsummon_stun: float = 1.5
## Frost Breath (blue_2). Bosses are SLOWED, never frozen - see the colour table.
@export var spell_blue_frostwave_radius: float = 8.5
@export var spell_blue_frostwave_damage: float = 65.0
@export var spell_blue_frostwave_freeze: float = 3.0
## Cut from 4.0 on 2026-09-09. Frost Breath already deals damage, freezes every ordinary
## enemy outright, and scales its radius, damage and duration - a full panic button and a
## damage spell in one, which left it competing with White's Wrath and with blue's own
## control kit. The boss clause is the half that was doing too much: a boss slowed for four
## seconds on a repeatable cooldown is a boss that never gets to act. It still buys real
## time, just not a whole phase of one.
@export var spell_blue_frostwave_boss_slow: float = 2.5
## Suction (blue_3). A zone that keeps dragging enemies inward for its whole duration
## rather than pulling once. The pull is slow on purpose: walking out of it is the
## counterplay, and a yank that nothing can escape removes it.
@export var spell_blue_suction_radius: float = 12.0
@export var spell_blue_suction_pull_speed: float = 4.0
## Suction is the one spell whose whole identity is DURATION: a vortex that keeps pulling
## for as long as it stands, rather than a shove. Its rank curve is written out rather than
## riding rank_duration_mult, because the numbers are the design - 10 / 15 / 20 / 25 / 30
## seconds - and a generic multiplier would only approximate them.
##
## Note the cooldown (11s, SpellDatabase) is SHORTER than the duration at every rank past
## the first, so a high-rank Suction can have two or three vortexes running at once. That is
## a deliberate consequence of the curve, not an oversight.
@export var spell_blue_suction_duration: float = 10.0
@export var spell_blue_suction_duration_max: float = 30.0
## Wall of Frost (blue_4). Real collision, plus bonus damage when Unsummon slams an
## enemy into it instead of ordinary terrain.
@export var spell_blue_wall_of_frost_length: float = 8.5
@export var spell_blue_wall_of_frost_duration: float = 10.0
@export var spell_blue_wall_of_frost_unsummon_bonus_damage: float = 120.0
## Displace (blue_5). A short blink to the aimed ground point, capped so it stays a
## mobility tool rather than a cross-lane teleport.
@export var spell_blue_displace_distance: float = 9.0

# --- BLACK: parasitic drain ---
## Doom Blade (black_1). Passes THROUGH - only what the line actually touches is hit,
## which is what makes it a skill shot rather than a cone.
@export var spell_black_doom_blade_damage: float = 115.0
@export var spell_black_doom_blade_length: float = 18.0
@export var spell_black_doom_blade_width: float = 1.6
## Fear (black_2)
@export var spell_black_fear_radius: float = 9.0
@export var spell_black_fear_duration: float = 4.0
## What makes Fear worth casting in a game about keeping enemies CLUSTERED. Scattering the
## pack is actively bad for Suction, Wall of Souls, Rain of Ember, Fireball and every other
## area skill in the roster, so the flee needs to buy something the cluster cannot: everything
## running takes this much more damage for as long as it runs. Fear becomes a damage window
## the player opens deliberately, rather than a button that undoes their own positioning.
##
## Rides the same curse channel as Wall of Souls' mark (EnemyBase.apply_doom_curse), which
## keeps the stronger of the two rather than letting one overwrite the other.
@export var spell_black_fear_vulnerability: float = 1.3
@export var spell_black_fear_vulnerability_max: float = 1.6
## Kill (black_3). The boss clause is what stops an instant delete trivialising the wave
## bosses; the cooldown (spell_database.gd) is the harshest in the game for the same
## reason.
@export var spell_black_kill_range: float = 22.0
@export var spell_black_kill_boss_threshold: float = 0.33
## Wall of Souls (black_4)
@export var spell_black_wall_length: float = 14.0
@export var spell_black_wall_duration: float = 12.0
@export var spell_black_wall_mark_duration: float = 8.0
@export var spell_black_wall_mark_mult: float = 2.0
## Zombify (black_5). Raises corpses that are already lying on the field - a system that
## until now was pure decoration.
@export var spell_black_zombify_count: int = 3
@export var spell_black_zombify_hp: float = 200.0
@export var spell_black_zombify_damage: float = 24.0
@export var spell_black_zombify_duration: float = 20.0

# --- RED: aggression ---
## Fire Dash (red_2). Escape and damage in one, which is why the trail is worth as much
## as the distance.
@export var spell_red_dash_speed: float = 26.0
@export var spell_red_dash_duration: float = 0.38
@export var spell_red_dash_trail_dps: float = 45.0
@export var spell_red_dash_trail_duration: float = 4.0
@export var spell_red_dash_trail_radius: float = 2.2
## Fire Cone (red_4). A refill meter rather than a normal cooldown: hold to spend up to
## this many seconds of flame, then wait for the meter to fill again.
##
## Retuned 2026-09-09 from 145 dps at 9.0 length. At 145 a full 5-second channel was 725
## damage to EVERY enemy in the cone before rank scaling - more than Lightning Bolt's single
## target number, three times Fire Dash's trail and nearly six times Rain of Ember's dps, on
## a spell the player can walk with. Red's four fire skills all wanted the same job; this one
## is now the one that holds a line rather than the one that clears it, which is what the
## slow below is for. Total per enemy at the new numbers: 425 over a full channel.
@export var spell_red_fire_cone_dps: float = 85.0
@export var spell_red_fire_cone_length: float = 7.0
@export var spell_red_fire_cone_dot: float = 0.55
@export var spell_red_fire_cone_max_duration: float = 5.0
## The control half of Fire Cone's new job. Refreshed every frame the enemy is in the cone
## and lapsing shortly after it sweeps off them, so keeping something slowed means keeping
## the flame ON it - which is the sustained-pressure shape the damage no longer provides.
@export var spell_red_fire_cone_slow_mult: float = 0.6
@export var spell_red_fire_cone_slow_duration: float = 0.4
## Lightning Bolt (red_5). Precision against one big target: the smallest area in the
## game and the largest single number.
@export var spell_red_bolt_damage: float = 230.0
@export var spell_red_bolt_radius: float = 2.8
@export var spell_red_bolt_delay: float = 0.55
## What the bolt is FOR. Against a boss or an elite it hits for this much more, which is the
## one thing no other red skill does: Fireball, Rain, Fire Dash and Fire Cone are all area
## damage, and against a single large target they are all mediocre. 230 flat was strictly
## worse than parking a Fire Cone on the same boss; 460 at rank 1 through 598 at rank 5 is a
## number worth rooting yourself and eating the telegraph delay for.
##
## Ordinary enemies feel none of this - the bolt stays a bad way to clear a wave, on purpose.
@export var spell_red_bolt_elite_mult: float = 2.0
@export var spell_red_bolt_elite_mult_max: float = 2.6
## Effectively unlimited: the bolt lands wherever the crosshair meets the ground, however
## far that is. It is the one spell aimed at a POINT rather than around the caster, and a
## 30-unit cap meant the strike silently landed short of what the player was looking at -
## which reads as the spell missing rather than as a range limit.
@export var spell_red_bolt_range: float = 500.0

# --- GREEN: primal vitality ---
## Giant Growth (green_2). The bonus HP is a multiple of player_max_hp, so green's own
## affinity and every other max-HP effect scale it.
@export var spell_green_giant_scale: float = 1.5
@export var spell_green_giant_bonus_hp_mult: float = 1.6
@export var spell_green_giant_duration: float = 12.0
## Fog (green_3). Defensive GROUND rather than an offensive zone - the crystal-defence
## half of green, with Roar.
@export var spell_green_fog_radius: float = 7.0
@export var spell_green_fog_duration: float = 8.0
## Fog's problem was never its strength, it was that suppressed damage is INVISIBLE: the
## player sees enemies swinging and nothing happening, which reads as the spell having failed
## rather than as the spell working. Two answers, both here: the prevented damage is now shown
## as a floating number (Player/EnemyBase), and enemies wade through the cloud rather than
## walking through it - a slow the player can see at a glance without reading numbers.
##
## Milder than frost's 0.3 on purpose. Fog is not a control spell that also blocks damage; it
## is ground the player holds, and the wading is legibility, not the effect.
@export var spell_green_fog_slow_mult: float = 0.65
## Roar (green_4)
@export var spell_green_roar_radius: float = 14.0
@export var spell_green_roar_duration: float = 6.0
## Ironbark (green_5). The only CC immunity in all thirty skills - without it, being
## stunned or frozen has no counter at all.
@export var spell_green_ironbark_reduction: float = 0.6
@export var spell_green_ironbark_duration: float = 6.0

# --- AURAS: THE ORBS ---
# The second half of every colour's aura fork. The Attunements (Fervor, Rhystic
# Study and the rest, above) are flat multipliers; these are presence - something
# visibly fighting alongside the player. All three orbs are ONE implementation.
@export var aura_orb_radius: float = 2.2
@export var aura_orb_height: float = 1.9
@export var aura_orb_speed: float = 2.0
## Winter Orb - blue's Manifestation
@export var aura_orb_of_frost_damage: float = 34.0
@export var aura_orb_of_frost_interval: float = 1.4
@export var aura_orb_of_frost_range: float = 14.0
@export var aura_orb_of_frost_slow: float = 2.5
## Orb of Fire - red's Manifestation
@export var aura_orb_of_fire_damage: float = 42.0
@export var aura_orb_of_fire_interval: float = 1.6
@export var aura_orb_of_fire_range: float = 14.0
@export var aura_orb_of_fire_burn_dps: float = 18.0
@export var aura_orb_of_fire_burn_duration: float = 4.0
## Healing Orb - white's Manifestation. Always picks the LOWEST-health ally in range,
## which is what makes it feel like a healer rather than a regeneration stat. The amount
## is a multiple of player_max_hp, like every white/green HP number.
@export var aura_healing_orb_hp_mult: float = 0.26
@export var aura_healing_orb_interval: float = 2.0
@export var aura_healing_orb_radius: float = 14.0
## Trample - green's Manifestation. Gated on MOVING, so it rewards the colour that
## fights by being physically present.
@export var aura_trample_dps: float = 40.0
@export var aura_trample_radius: float = 3.2
## Grave Pact - black's Manifestation. A stacking bonus that DECAYS is the point: it
## pays a player who keeps killing, and lapses the moment they stop.
@export var aura_grave_pact_radius: float = 12.0
@export var aura_grave_pact_heal: float = 14.0
@export var aura_grave_pact_damage_per_stack: float = 0.04
@export var aura_grave_pact_max_stacks: int = 8
@export var aura_grave_pact_stack_duration: float = 6.0

# --- RANK CEILINGS ---
# The handful of skill numbers the generic curves cannot express, each with the value it
# reaches at rank 5. Fractions and counts, per docs/SKILL_DESIGN.md's "Scales with rank".
## Exalted Strike: charges held, not damage - the damage rides the generic curve.
@export var spell_white_exalted_charges_max: int = 3
## Reprisal Ward: both halves are chances, so both walk to a ceiling.
@export var spell_white_reprisal_reflect_max: float = 0.9
@export var spell_white_reprisal_block_chance_max: float = 0.5
## Rally the Fallen: how many downed teammates one cast can pick up.
@export var spell_white_rally_revives: int = 1
@export var spell_white_rally_revives_max: int = 5
## Kill: the ONLY skill whose cooldown scales, and the only one where a higher rank
## widens the boss window rather than adding damage.
@export var spell_black_kill_cooldown_max_rank_mult: float = 0.6
@export var spell_black_kill_boss_threshold_max: float = 0.5
## Wall of Souls: x2 damage is the headline at rank 1; x4 would eclipse every other
## black skill, so the mark walks to x3.
@export var spell_black_wall_mark_mult_max: float = 3.0
## Zombify: bodies raised per cast.
@export var spell_black_zombify_count_max: int = 7
## Ironbark: reduction is a fraction, and 1.0 would be immunity.
@export var spell_green_ironbark_reduction_max: float = 0.8
## Giant Growth: how much bigger, which is the half of the skill the player sees.
@export var spell_green_giant_scale_max: float = 1.9
## The size also slows the swing - the trade that makes the growth read as weight. Capped
## so a rank-5 giant attacks at most this many times slower; without a ceiling the slow
## would outgrow the damage it is paying for.
@export var spell_green_giant_attack_slow_cap: float = 1.75

# --- NEUTRAL PASSIVES (the guild nodes between the colours) ---
# Five ranks each, one skill point per rank, gated only by team level. Values are the
# rank-1 minimum and the rank-5 ceiling, walked by rank_fraction.
## Vigilance (Selesnya, green/white): spells with a duration last this much longer.
@export var passive_vigilance_duration_min: float = 0.10
@export var passive_vigilance_duration_max: float = 1.0
## Double Strike (Dimir, blue/black): crit chance for ALL player damage, melee and spells.
@export var passive_crit_chance_min: float = 0.10
@export var passive_crit_chance_max: float = 0.50
@export var passive_crit_damage_mult: float = 2.0
## Trample (Gruul, red/green): melee hits add this fraction of the player's max HP.
@export var passive_trample_hp_fraction_min: float = 0.10
@export var passive_trample_hp_fraction_max: float = 0.50
## Haste (Rakdos, black/red): movement speed bonus.
@export var passive_haste_speed_min: float = 0.10
@export var passive_haste_speed_max: float = 0.50
## Flying (Azorius, white/blue): jump height bonus; holding jump while falling glides
## at this fraction of normal gravity.
@export var passive_flight_jump_min: float = 0.5
@export var passive_flight_jump_max: float = 2.5
@export var passive_flight_glide_gravity_mult: float = 0.25
## Doom Blade: "width (barely)" in the design doc, so barely.
@export var spell_black_doom_blade_width_max: float = 1.9

## How fast a feared enemy runs compared with how fast it advances. Slightly quicker,
## so Fear visibly creates space rather than only stopping the attacks.
@export var enemy_flee_speed_mult: float = 1.15


# ============================================================
# SKILL RANKS
# ============================================================
# Every active skill is bought up to five times. Rank 1 is the skill working; ranks 2-5
# scale the two or three numbers its row in docs/SKILL_DESIGN.md lists under "Scales with
# rank". The auras are deliberately NOT rankable - the moment a aura becomes a
# slider it stops being a decision.
#
# The price is flat, one skill point per rank, and the SCARCITY IS THE TEAM LEVEL instead
# - the MOBA shape. A flat price with no gate would make maxing one skill strictly
# correct; a rising price would make it a sums puzzle. A level gate makes it a question of
# WHEN, which is the one form of the question that changes as a run goes on: early you
# take breadth because depth is not available yet, and late you choose what to deepen.
@export var spell_max_rank: int = 5
@export var spell_rank_point_cost: int = 1
## Team level needed for each rank, rank 1 first. Levels are shared across the team
## (docs/ECONOMY.md), so this is the same clock for everybody - nobody is ranked up
## because they got the last hit.
@export var spell_rank_level_requirements: Array[int] = [1, 3, 5, 7, 9]

## Rank 5 is roughly x2 damage, x1.6 area/range, x1.5 duration - the curve suggested in
## the design doc, kept in one place so twenty-five skills cannot each drift from it.
const RANK_DAMAGE_CURVE: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]
const RANK_AREA_CURVE: Array[float] = [1.0, 1.15, 1.3, 1.45, 1.6]
const RANK_DURATION_CURVE: Array[float] = [1.0, 1.125, 1.25, 1.375, 1.5]


func _rank_index(rank: int) -> int:
	return clampi(rank - 1, 0, spell_max_rank - 1)


func rank_damage_mult(rank: int) -> float:
	return RANK_DAMAGE_CURVE[_rank_index(rank)]


func rank_area_mult(rank: int) -> float:
	return RANK_AREA_CURVE[_rank_index(rank)]


func rank_duration_mult(rank: int) -> float:
	return RANK_DURATION_CURVE[_rank_index(rank)]


## For anything that is already a FRACTION - damage reduction, a block chance, a reflect
## share. These cannot be multiplied: x2 on Ironbark's 0.6 reduction is 1.2, which is
## immunity. They walk from their rank-1 value to an explicit ceiling instead, so the
## ceiling is a number a designer chose rather than one the curve happened to produce.
func rank_fraction(base: float, ceiling: float, rank: int) -> float:
	if spell_max_rank <= 1:
		return base
	return lerpf(base, ceiling, float(_rank_index(rank)) / float(spell_max_rank - 1))


## For anything counted in whole things - corpses raised, charges held, allies revived.
## Rounded rather than floored so the middle ranks are not all silently identical.
func rank_count(base: int, top: int, rank: int) -> int:
	return int(roundf(rank_fraction(float(base), float(top), rank)))


## The share of an aura's listed bonus that rank 1 already pays out. Rank 5 always pays
## the full listed number; this is only where the walk to it STARTS.
const AURA_RANK1_SHARE := 0.4

## For a aura aura's MULTIPLIER - Fervor's x1.15 speed, Phyrexian Arena's x1.25 damage,
## Rhystic Study's x0.7 cooldown. `ceiling` is what the aura is documented as giving, and
## rank 5 is what reaches it.
##
## Exists because these were written as `lerpf(1.0, ceiling, rank_damage_mult(rank) - 1.0)`,
## and rank_damage_mult(1) is 1.0 - so the lerp weight at rank 1 was ZERO and the first rank
## of every one of these auras granted nothing at all. Phyrexian Arena rank 1 was the worst
## of them: it drained health for a damage and speed bonus that was still exactly x1.0.
##
## Multiplying by rank_damage_mult() instead would be wrong in the other direction: it would
## take Fervor's x1.15 to x2.3, and Rhystic Study's x0.7 cooldown to x1.4 - a COST. A bonus
## expressed as a multiplier has to walk from a smaller bonus to its listed one, which is
## what rank_fraction already does for every other fraction in the game. This is that, with
## the rank-1 starting point derived from the ceiling rather than written out per aura.
##
## Direction-agnostic on purpose: a ceiling below 1.0 (a cooldown multiplier) walks DOWN to
## it from a weaker discount, exactly as a ceiling above 1.0 walks up.
func aura_bonus_mult(ceiling: float, rank: int) -> float:
	return 1.0 + (ceiling - 1.0) * rank_fraction(AURA_RANK1_SHARE, 1.0, rank)


## The team level this rank needs. Rank 1 is the unlock itself.
## What the colour-investment ladder asks for at tier or rank `step` (1-based). Clamped
## rather than wrapped, so a sixth step - if one is ever added - inherits the last rung
## instead of silently costing nothing.
func color_investment_requirement(step: int) -> int:
	if color_investment_ladder.is_empty():
		return 0
	var index: int = clampi(step - 1, 0, color_investment_ladder.size() - 1)
	return color_investment_ladder[index]


func rank_level_requirement(rank: int) -> int:
	if spell_rank_level_requirements.is_empty():
		return 1
	var index: int = clampi(rank - 1, 0, spell_rank_level_requirements.size() - 1)
	return spell_rank_level_requirements[index]


# ============================================================
# WAVES
# ============================================================
## Pause before the first battle group of a wave lands, which is also how long the player
## has to read its warning banner.
@export var wave_initial_warning_time: float = 2.5
## Superseded by upkeep_duration - kept only as the pause before the very first wave.
@export var wave_rest_period: float = 3.0

# --- Battle groups ---------------------------------------------------------------------
#
# A wave is a handful of BATTLE GROUPS, not a spawn queue. Each group is a run of adjacent
# (which on the colour wheel means ALLIED) colours whose squads spawn simultaneously, in
# formation, converge on a hold line short of the crystal, wait for each other and charge
# together. The per-enemy spawn delays and cluster spacing that used to live here are gone
# with the queue: spacing is now the formation's own business (SquadDoctrine) and a squad
# arrives all at once.

## Gap between one battle group landing and the next. Long enough that two groups are two
## distinct pushes rather than one shapeless mass, short enough that they overlap by the
## time they reach the crystal - a lane is ~180 units and a melee walks it in about a
## minute, so everything deployed inside a wave is fighting at the same time regardless.
##
## This replaces a per-COLOUR delay that was applied after the previous colour had finished
## trickling in, which is how a wave of ten spawn groups ended up spread over more than a
## minute of deployment and was fought colour by colour. A late wave is now two or three
## groups, all on the map inside twenty seconds - the same enemies, arriving as an army.
@export var wave_delay_between_groups: float = 10.0
## From this wave on, ALLIED NEIGHBOURS pair up: two adjacent lanes arrive together, form
## up between their lanes and charge as one. Before it, every colour comes in on its own.
@export var wave_alliance_start_wave: int = 4
## From this wave on, groups can be three adjacent colours - a shard of the wheel.
@export var wave_shard_start_wave: int = 9
## From this wave on, all five colours can arrive in a single push.
@export var wave_grand_alliance_start_wave: int = 16
## How far from the crystal a warband forms up before charging. The lane spawners sit at
## ~180 and the mana wells at ~112, so this puts the hold line just inside the wells -
## close enough that the player can see it happening and go and break it up.
@export var wave_rally_radius: float = 100.0
## How far towards its battle group's centre a squad converges to form up, as a fraction of
## the way from its own lane. 1.0 would be a single shared point on the arc between the
## lanes, which costs each squad a sideways detour about as long as the lane itself - ground
## with nothing on it. At 0.75 two neighbours end up about thirty units apart, which reads
## as one army massing, and the lanes close the rest of the gap during the charge.
@export var wave_rally_convergence: float = 0.75
## Longest a squad will stand at the rendezvous waiting for the rest of its warband. A
## safety net against a partner that is alive but pinned, not a pacing knob.
@export var wave_rally_timeout: float = 12.0
## How fast a formation wheels onto a new heading, in radians per second of blend. Low
## enough that turning towards a rendezvous off the lane's axis reads as a manoeuvre rather
## than as the whole squad's slots teleporting around its anchor.
@export var wave_squad_turn_speed: float = 1.2
## How close a squad's anchor has to get to a waypoint to count as having arrived.
@export var wave_squad_arrive_radius: float = 4.0
## How much faster than the formation's march speed a member may move while catching up to
## its slot. 1.0 would mean anyone who fell behind stays behind forever.
@export var wave_squad_catchup_mult: float = 1.35
## How far short of its break radius a squad starts running. A formation that walked into
## contact at marching pace would make the charge invisible on the one colour that has no
## warband to charge out of a rendezvous with.
@export var wave_squad_charge_lead: float = 18.0
## Below this share of its original size a squad stops being a formation and its survivors
## go and fight. Three enemies walking in rank towards a crystal they cannot threaten only
## makes the wave take longer to finish.
@export var wave_squad_disband_fraction: float = 0.35
## How much bigger a wave gets per player beyond the first. Enemy DAMAGE already scales
## with head count (get_player_scaling_factor), but wave SIZE never did - five players
## against a solo-sized wave shred it without the crystal ever being threatened, and earn
## solo-sized income while doing it. At 0.45 a five-player wave is 2.8x a solo one.
@export var wave_size_per_extra_player: float = 0.45
## Extra enemy health per player beyond the first. 0.15 gives 1.6x at five players.
@export var enemy_health_per_extra_player: float = 0.15
## Extra enemy health per WAVE, linear: wave 20 fights x2.14 the wave-1 health. Linear
## rather than compounding, so late waves get beefier without the curve running away.
@export var enemy_health_per_wave: float = 0.06
@export var wave_dynamic_base_difficulty: int = 5
@export var wave_dynamic_difficulty_per_wave: int = 2
@export var wave_boss_interval: int = 5
@export var wave_boss_delay: float = 2.0
@export var wave_elite_start_wave: int = 2
@export var wave_elite_count_base: int = 1

# --- Minibosses -------------------------------------------------------------------------
#
# A rung above Elite, and deliberately its own separate system rather than a bigger Elite
# tier: Elites only ever change numbers (see EnemyBase.apply_elite_modifier), and a miniboss
# is meant to be SEEN before it's felt - visibly larger, glowing in its colour, and the one
# thing in its squad the melee screen is actually built around. At most one per wave, so it
# reads as a notable arrival rather than a stat roll.
#
## First wave a miniboss may appear. Held back past the opening so the player has already
## seen a plain formation before meeting a reinforced one.
@export var wave_miniboss_start_wave: int = 6
## Chance per wave, from wave_miniboss_start_wave on, that one appears at all.
@export var wave_miniboss_chance: float = 0.35
## Extra melee units added to a miniboss's own squad, on top of the wave's normal
## composition. The formation itself (melee screen in front, see SquadDoctrine) does the
## rest - a denser screen in front of a miniboss reads as an honour guard for free, no new
## formation geometry required.
@export var wave_miniboss_escort_bonus: int = 3
@export var wave_miniboss_health_mult: float = 4.0
@export var wave_miniboss_damage_mult: float = 1.6
## Traded down a little against the health and damage bump, the same bargain Elite's own
## Juggernaut modifier makes - a miniboss that also outran its screen would leave the
## escort behind immediately.
@export var wave_miniboss_speed_mult: float = 0.9
## Visibly larger than its rank-and-file, but well short of a real boss (model_scale 2.1-2.9)
## - a miniboss is still a member of its squad, not a second boss in the same wave.
@export var wave_miniboss_scale_mult: float = 1.35
## Only a Mage miniboss gets a special (see EnemyBase._perform_miniboss_special) - a melee
## or ranged one is a stat-scaled version of the ordinary attack it already has, same swing,
## same bow. A caster gets a telegraphed signature spell instead, on its own long cooldown
## on top of its normal casting - the payoff for finding one in the mage core.
@export var wave_miniboss_special_cooldown_mult: float = 2.6
## Radius/strength multiplier applied to whichever of the five per-colour mage effects the
## special reuses (see perform_mage_spell) - the special is a bigger version of the same
## spell its ordinary cast already throws, not a new mechanic per colour.
@export var wave_miniboss_special_power_mult: float = 2.2
## How long the ground telegraph stands before the special resolves. Not driven off an
## animation clip length the way a real boss's is (BossDatabase.SPECIALS) - the ordinary
## Melee/Ranged/Mage models were never built with a dedicated cast clip to time against, so
## this is a fixed, tunable window instead. Long enough to react to, short enough that the
## mage is not standing rooted through half the fight.
@export var wave_miniboss_special_windup: float = 1.8

# ============================================================
# ENEMIES
# ============================================================
@export var enemy_aggro_radius: float = 12.0
## How much further than its own attack range an enemy may still connect at the
## moment its swing actually lands. Damage now pays out on the clip's measured
## impact frame rather than on the frame the swing started, so a target that walks
## away during the wind-up escapes it - this is the forgiveness on that. Set it very
## high to go back to the old "committed swings always hit" behaviour.
@export var enemy_attack_impact_range_grace: float = 1.35
## How fast an enemy swings its facing around, in lerp weight per second.
@export var enemy_turn_speed: float = 8.0

# --- enemy hit reaction ---
# Every enemy library ships a flinch clip, but until 2026-09-02 it only ever played
# while knockback was still carrying the body - so anything killed at range, which is
# most of what a Mage or Ranged enemy ever takes, never visibly reacted at all.
## A hit only flinches an enemy when it takes at least this fraction of its maximum
## health in one go; chip damage would otherwise leave a wave permanently twitching.
@export var enemy_hit_react_damage_pct: float = 0.08
## Minimum gap between two flinches, so a fast weapon cannot chain them.
@export var enemy_hit_react_cooldown: float = 1.0
## How long the flinch takes; the clip is squeezed into it the same way the player's
## reactions are.
@export var enemy_hit_react_duration: float = 0.4
## Whether a flinch also throws away the swing in flight. True is what "getting hit"
## normally means, and the cooldown above is what keeps it from becoming a stunlock -
## set false to make flinches purely cosmetic and leave the old balance untouched.
@export var enemy_hit_react_interrupts_attack: bool = true
@export var enemy_melee_detection_range: float = 15.0
@export var enemy_ranged_detection_range: float = 35.0
@export var enemy_target_eval_interval: float = 0.5
@export var enemy_path_update_interval: float = 0.3
@export var enemy_mage_spell_cooldown_mult: float = 4.0
@export var enemy_frost_slow_mult: float = 0.3
@export var enemy_white_mage_heal: float = 30.0
@export var enemy_white_mage_range: float = 15.0
@export var enemy_red_mage_range: float = 20.0
@export var enemy_blue_mage_range: float = 20.0
@export var enemy_blue_mage_slow_duration: float = 4.0
@export var enemy_blue_mage_slow_mult: float = 0.6
@export var enemy_green_mage_range: float = 10.0
@export var enemy_green_mage_buff_scale: float = 1.5
@export var enemy_green_mage_buff_damage: float = 1.5
@export var enemy_black_mage_revive_hp_mult: float = 0.5
@export var enemy_elite_haste_speed_mult: float = 1.3
@export var enemy_elite_haste_attack_speed_mult: float = 0.75
@export var enemy_elite_regenerator_health_mult: float = 1.25
@export var enemy_elite_regenerator_heal_pct_per_second: float = 0.025
@export var enemy_elite_juggernaut_health_mult: float = 1.6
@export var enemy_elite_juggernaut_damage_mult: float = 1.25
@export var enemy_elite_juggernaut_speed_mult: float = 0.8
@export var enemy_elite_crystal_hunter_damage_mult: float = 1.35
@export var enemy_max_corpses: int = 100

# ============================================================
# BOSSES
# ============================================================
# Bosses animate slower the bigger they are: a boss whose model_scale equals
# boss_anim_reference_scale plays at 1.0x, larger ones play slower and smaller
# ones faster. boss_anim_scale_strength dials how strongly size matters (0.0
# disables the effect entirely, 1.0 makes playback speed inversely proportional
# to scale). Result is clamped so a very large boss never crawls to a halt.
@export var boss_anim_reference_scale: float = 2.4
@export var boss_anim_scale_strength: float = 1.0
@export var boss_anim_speed_min: float = 0.55
@export var boss_anim_speed_max: float = 1.35

# Special (dodgeable) attacks. Each boss telegraphs a danger zone for
# boss_special_windup_* seconds before the hit lands - that window is the dodge.
@export var boss_special_cooldown: float = 9.0
@export var boss_special_first_delay: float = 5.0
## Unused since each special carries its own `min_range` (BossDatabase.SPECIALS). Kept as the
## documented default a new special should be written against: the big area attacks are all
## held back to this so the melee special owns the point-blank band.
@export var boss_special_min_range: float = 3.0
@export var boss_special_damage_mult: float = 2.0
# Bigger bosses wind up proportionally longer (they also animate slower), so the
# telegraph stays readable instead of the hit landing before the animation reads.
@export var boss_special_windup_scale_with_anim: bool = true

# ============================================================
# COMBAT FEEDBACK
# ============================================================
# Ground decals marking a boss special attack's danger zone during its windup.
# Turning this off removes the visual tell, making specials much harder to dodge.
@export var show_attack_indicators: bool = true
@export var attack_indicator_height: float = 0.08
@export var camera_shake_enabled: bool = true
@export var camera_shake_strength_mult: float = 1.0
# Heavy hits (boss melee and boss specials) shake harder than chip damage.
@export var camera_shake_heavy_strength: float = 0.42
@export var camera_shake_heavy_duration: float = 0.45
@export var camera_shake_light_strength: float = 0.12
@export var camera_shake_light_duration: float = 0.22
@export var camera_shake_frequency: float = 26.0
## The player's own melee connecting. Much smaller than being hit: this fires on every
## landed swing, several times a second through a chain, so anything larger reads as
## the camera being broken rather than as weight.
@export var camera_shake_melee_strength: float = 0.09
## The heavy spin and the chain's third stage, which land far less often.
@export var camera_shake_melee_heavy_strength: float = 0.2
@export var camera_shake_melee_duration: float = 0.16

# ============================================================
# RUN REWARDS
# ============================================================
# ============================================================
# XP, LEVELS AND SKILL POINTS
# ============================================================
## XP is shared by the whole team and every kill feeds one pool, so levels arrive for
## everyone at the same moment. Each level grants every player one skill point.
@export var xp_per_basic: float = 10.0
@export var xp_per_elite: float = 40.0
@export var xp_per_boss: float = 250.0
@export var xp_per_camp: float = 120.0
## Total XP to reach level N is base*(N-1) + growth*(N-1)^2 - superlinear, so early
## levels land every wave or two and late ones take three or four. Target is roughly
## 15-18 levels across a full run.
@export var xp_level_base: float = 90.0
@export var xp_level_growth: float = 26.0

# ============================================================
# TEAM MANA
# ============================================================
## Banked automatically on kill, in the dead enemy's own colour. There is no pickup:
## the pool is shared, so there is nobody for a drop to belong to and no reason to make
## anyone walk to it.
@export var mana_per_basic: int = 1
@export var mana_per_elite: int = 4
@export var mana_per_boss: int = 25
@export var mana_per_camp: int = 12

# ============================================================
# UPKEEP
# ============================================================
## The build phase between waves: the only time mana can be spent, and the one moment
## each wave the whole team is in the same place. Replaces a 3-second rest that was long
## enough for nothing.
## How often the server pushes the economy to clients. Kills arrive far faster than a
## HUD can read, so the pool is flushed at a fixed rate rather than once per enemy.
@export var run_state_sync_interval: float = 0.25
@export var upkeep_duration: float = 30.0
## What the team pays for one skill point FOR EVERY PLAYER, in any colour.
@export var upkeep_skill_point_cost: int = 25
## Crystal repair. The only way to undo leakage, and deliberately a PURCHASE rather than
## an automatic scaling: the crystal is one shared objective whose maximum stays the same
## whether one player is defending it or five, so a team that leaks pays to fix it out of
## the same pool it wanted to spend on enchantments. That trade is the point.
@export var upkeep_crystal_repair_amount: float = 200.0
@export var upkeep_crystal_repair_cost: int = 8

# ============================================================
# ENCHANTMENTS
# ============================================================
## Permanent, stackable, global. Bought at Upkeep in their own colour, which is what
## makes lane choice strategic rather than only tactical.
@export var enchantment_base_cost: int = 8
@export var enchantment_cost_step: int = 6
## Red - Furnace of Rath: every player deals more damage. The benchmark buy.
@export var enchantment_red_damage: float = 0.08
## Blue - Propaganda: enemies attack and cast more slowly. Scales into the late game.
@export var enchantment_blue_attack_slow: float = 0.06
## Black - Exquisite Blood: players heal for a share of the damage they deal. Keeps the
## PLAYERS alive, where white keeps the CRYSTAL alive.
@export var enchantment_black_lifesteal: float = 0.03
## White - Sphere of Safety: enemies near the crystal hurt it less. Does nothing while
## the team is winning; saves the run when they are not.
@export var enchantment_white_reduction: float = 0.08
@export var enchantment_white_radius: float = 2.0
## Green - Overgrowth: all mana income rises. Compounds, so it is a bet on a long run.
@export var enchantment_green_income: float = 0.12

const ENCHANTMENT_NAMES: Dictionary = {
	"White": "Sphere of Safety",
	"Blue": "Propaganda",
	"Black": "Exquisite Blood",
	"Red": "Furnace of Rath",
	"Green": "Overgrowth",
}
const ENCHANTMENT_DESCRIPTIONS: Dictionary = {
	"White": "Enemies near the crystal deal less damage to it",
	"Blue": "All enemies attack and cast more slowly",
	"Black": "Every player heals for a share of the damage they deal",
	"Red": "Every player deals more damage",
	"Green": "All mana income increases",
}


# ============================================================
# MYRS
# ============================================================
@export var myr_max_hp: float = 75.0
@export var myr_speed: float = 2.0
@export var myr_harvest_time: float = 10.0
@export var myr_deposit_time: float = 1.0
@export var myr_mana_cost: int = 2
## How many myrs can exist at once. A hard cap rather than a soft economic one: past this
## the base screen stops being a list anybody reads, and five wells of five slots cannot
## usefully absorb more than this many anyway.
@export var myr_max_count: int = 10
## Levels are bought per myr in the base. Rank 1 is the myr as built.
@export var myr_max_level: int = 5
## Flat health added per level past the first. A levelled myr is meant to SURVIVE a leaked
## enemy, which is the thing that actually costs the player a harvest run.
@export var myr_level_hp_bonus: float = 25.0
## Extra mana carried home per trip, per level. At 1 a level-3 myr brings back three where
## it used to bring one - the levelling is worth more than a second myr long before the
## count cap is reached, which is the point of having a cap at all.
@export var myr_level_carry_bonus: int = 1
## Mana the next level costs, multiplied by the level being bought - so 2, 4, 6, 8.
@export var myr_level_cost: int = 2
## A well has room for this many Myrs standing around it, Warcraft-mine style. More
## than that is what wedged them against the model, so the base UI refuses the sixth.
@export var myr_well_max_slots: int = 5
## How far from the well's centre the harvest slots sit. Far enough that five bodies
## never overlap each other or the well's own collision.
@export var myr_well_slot_radius: float = 2.3

# ============================================================
# PROJECTILES
# ============================================================
@export var projectile_pool_size: int = 20
@export var projectile_base_speed: float = 30.0
@export var projectile_base_damage: float = 50.0
@export var projectile_base_lifetime: float = 2.5
@export var projectile_shock_speed_mult: float = 1.5
@export var projectile_unsummon_speed_mult: float = 0.8
@export var projectile_enemy_speed_mult: float = 0.5
@export var projectile_enemy_damage_mult: float = 0.2

# ============================================================
# MINIMAP
# ============================================================
@export var minimap_update_interval: float = 0.15

# ============================================================
# UI & DEBUG
# ============================================================
@export var show_damage_numbers: bool = true
## Debug: everything in the skill tree is free and ungated. Costs nothing, requires
## no affinity rank, and spends no mana - for trying builds out without farming them.
## Deliberately not persisted: it resets to off every launch, so it cannot be left on
## by accident. Toggled from the in-game options panel.
@export var debug_free_skills: bool = false
@export var damage_number_pool_size: int = 40
@export var show_enemy_health_bars: bool = true
@export var enemy_health_bar_height: float = 2.35
@export var debug_mode: bool = true

# ============================================================
# MULTIPLAYER SCALING
# ============================================================
@export var scale_by_players: bool = true
## Enemy DAMAGE at one player, rising to 100% at five.
##
## Deliberately shallow. Damage is the worst of the three difficulty levers to lean on,
## because it is the only one that changes what a hit COSTS - at 0.2 a Cleric's swing was
## worth 20% solo and 100% in a full team, so a player could never learn what any attack
## is actually worth; it depended on how many friends had logged in. Worse, with five
## players you are usually alone in your own lane, so it punished the individual for the
## team growing.
##
## The solo assist now comes almost entirely from facing FEWER enemies
## (wave_size_per_extra_player), which is the same help without the side effects. This
## keeps a small cushion on top, because one player genuinely cannot cover five lanes and
## some leakage is unavoidable.
@export var min_damage_scale: float = 0.75

## Multiplier on a wave's enemy budget for the number of players present. Counts the
## registry rather than the group, so an avatar mid-spawn cannot briefly inflate a wave.
##
## The PRIMARY difficulty lever, because it is the only one that uses the map: more
## enemies means more lanes under real pressure at once, which is the entire reason a
## five-player team exists. It also leaves every enemy feeling exactly as it does solo.
func get_wave_size_factor(player_count: int) -> float:
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * wave_size_per_extra_player


## Multiplier on an enemy's maximum health for the number of players present.
##
## The correction that wave size alone cannot make. Count scaling assumes players SPREAD
## OUT - one per lane, each fighting alone, killing at solo speed. The moment they group
## up, on a boss or a collapsing lane, five players focus-fire and delete each enemy
## roughly five times faster, and more enemies does not help with that.
##
## Kept modest on purpose: this is the lever that makes things spongy, and melee suffers
## most from sponginess because every swing is a committed animation.
func get_enemy_health_factor(player_count: int) -> float:
	if not scale_by_players:
		return 1.0
	var players: int = clampi(player_count, 1, 5)
	return 1.0 + float(players - 1) * enemy_health_per_extra_player


## Wave scaling, separate from count scaling: the run getting longer is its own
## difficulty axis. Wave 1 (index 0) is exactly base health.
func get_wave_health_factor(wave: int) -> float:
	return 1.0 + float(maxi(wave, 0)) * enemy_health_per_wave


## `tree` is no longer read: PlayerRegistry already keeps the roster this used to
## rebuild. `get_nodes_in_group` allocates a fresh Array on every call, and this is called
## on every enemy attack - once per swing, per arrow, per boss special. The registry
## answers the same question by walking five entries in place. The parameter stays so the
## call sites do not all have to change.
func get_player_scaling_factor(_tree: SceneTree) -> float:
	if not scale_by_players:
		return 1.0
	var player_count = max(1, PlayerRegistry.count())
	var clamp_count = clamp(player_count, 1, 5)
	return lerp(min_damage_scale, 1.0, (clamp_count - 1) / 4.0)

# ============================================================
# BOSSES
# ============================================================
## Animation playback speed for a boss of the given model_scale - bigger bosses
## animate slower. See the boss_anim_* settings for the tunables.
func get_boss_anim_speed(model_scale: float) -> float:
	if boss_anim_scale_strength <= 0.0 or model_scale <= 0.0:
		return 1.0
	var ratio: float = boss_anim_reference_scale / model_scale
	return clampf(pow(ratio, boss_anim_scale_strength), boss_anim_speed_min, boss_anim_speed_max)

# ============================================================
# SKILL UPGRADES
# ============================================================
func get_skill_upgrade_cost(current_level: int) -> int:
	return skill_unlock_cost + (current_level * current_level * 2)

func get_skill_multiplier(current_level: int) -> float:
	return 1.0 + (current_level - 1) * 0.2
