extends Node

var pool_size: int
var pool: Array[DamageNumber] = []

func _ready() -> void:
	pool_size = GameSettings.damage_number_pool_size
	for i in range(pool_size):
		var dn := DamageNumber.new()
		dn.active = false
		dn.visible = false
		dn.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(dn)
		pool.append(dn)

func get_damage_number() -> DamageNumber:
	for dn in pool:
		if not dn.active:
			return dn

	# Pool exhausted — reuse the oldest one. Fine for a purely cosmetic effect:
	# worst case a very old, about-to-fade number gets cut short and replaced.
	return pool[0]
