extends Node
## Regression test: does the Particle Effects setting actually reach the particle systems?
##
## GraphicsSettings sizes every GPUParticles3D as it enters the tree and resizes the ones
## already there when the setting moves. This checks both paths, that Ultra raises the count
## and the lower tiers only thin it out, that switching back and forth never compounds, and
## that a system authored with only a handful of particles keeps a few at Low.
##
## Run with:  godot --headless --path . res://tools/tests/particle_quality.tscn
## Prints "TEST RESULT: PASS" or a FAIL listing what did not hold.

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved: int = GraphicsSettings.particle_quality
	var scales: Array[float] = GameSettings.graphics_particle_quality_scale
	var minimum: int = GameSettings.graphics_particle_min_amount

	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.HIGH)
	var big := GPUParticles3D.new()
	big.amount = 100
	var small := GPUParticles3D.new()
	small.amount = 4
	add_child(big)
	add_child(small)
	_check("High leaves the authored count", big.amount == 100 and is_equal_approx(big.amount_ratio, 1.0),
		"amount %d ratio %.2f" % [big.amount, big.amount_ratio])

	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.LOW)
	_check("Low thins a live system out", big.amount == 100 and is_equal_approx(big.amount_ratio, scales[0]),
		"amount %d ratio %.2f" % [big.amount, big.amount_ratio])
	_check("Low keeps a few in a small system", small.amount_ratio * small.amount >= float(minimum) - 0.01,
		"%.2f of %d" % [small.amount_ratio, small.amount])

	# A system that arrives while the setting is already Low is sized on arrival.
	var late := GPUParticles3D.new()
	late.amount = 50
	add_child(late)
	_check("A new system arrives sized", is_equal_approx(late.amount_ratio, scales[0]),
		"ratio %.2f" % late.amount_ratio)

	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.ULTRA)
	var ultra: int = int(ceil(100.0 * scales[3]))
	_check("Ultra raises the count", big.amount == ultra and is_equal_approx(big.amount_ratio, 1.0),
		"amount %d ratio %.2f" % [big.amount, big.amount_ratio])
	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.ULTRA)
	_check("Applying Ultra twice does not compound", big.amount == ultra, "amount %d" % big.amount)

	# Moved to another parent - node_added fires again - and back to High.
	remove_child(big)
	add_child(big)
	_check("Re-entering the tree does not compound", big.amount == ultra, "amount %d" % big.amount)
	GraphicsSettings.apply_particle_quality(GraphicsSettings.ParticleQuality.HIGH)
	_check("Back to High restores the authored count", big.amount == 100 and is_equal_approx(big.amount_ratio, 1.0),
		"amount %d ratio %.2f" % [big.amount, big.amount_ratio])

	GraphicsSettings.apply_particle_quality(saved)
	if _failures.is_empty():
		print("TEST RESULT: PASS")
	else:
		print("TEST RESULT: FAIL\n  " + "\n  ".join(_failures))
	get_tree().quit()


func _check(what: String, ok: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if ok else "FAIL", what, detail])
	if not ok:
		_failures.append("%s: %s" % [what, detail])
