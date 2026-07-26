extends SceneTree

const MapReferencesScript = preload("res://src/factories/MapReferences.gd")
const MapFactoryScript = preload("res://src/factories/MapFactory.gd")
const MonsterFactoryScript = preload("res://src/factories/MonsterFactory.gd")
const MonsterStatCalculatorScript = preload("res://src/battle_sim/MonsterStatCalculator.gd")
const StateSerializerScript = preload("res://src/battle_sim/BattleStateSerializer.gd")
const GodotVisualAdapterScript = preload("res://src/presentation/GodotVisualAdapter.gd")
const BattleSetupConfigScript = preload("res://src/battle_sim/BattleSetupConfig.gd")
const BattleSetupFactoryScript = preload("res://src/battle_sim/BattleSetupFactory.gd")
const BattleSetupPresetsScript = preload("res://src/factories/BattleSetupPresets.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for mapName in MapReferencesScript.getNames():
		var reference = MapReferencesScript.getReference(mapName)
		var validation = MapFactoryScript.validateReference(reference)
		if not validation["success"] or int(reference.get("REVISION", 0)) < 3:
			_fail("map height schema failed for %s" % mapName)
			return
		var distinctHeights: Dictionary = {}
		for row in reference["HEIGHTS"]:
			for height in row:
				distinctHeights[int(height)] = true
		if distinctHeights.size() < 3 or not distinctHeights.has(0) or not distinctHeights.has(2):
			_fail("production elevation profile is missing low/mid/high ground for %s" % mapName)
			return

	if MonsterStatCalculatorScript.derive(10, 25, 5) != 11:
		_fail("stat growth hundredths rounding is incorrect")
		return
	if MonsterStatCalculatorScript.derive(10, 33, 4) != 10:
		_fail("stat growth floor boundary is incorrect")
		return

	var state = BattleState.new(77)
	state.setup_board(Vector2i(4, 2))
	state.mapName = "HeightFixture"
	state.mapRevision = 3
	state.heightBoard.set_at(0, Vector2i(0, 0))
	state.heightBoard.set_at(1, Vector2i(1, 0))
	state.heightBoard.set_at(3, Vector2i(2, 0))
	state.heightBoard.set_at(0, Vector2i(3, 0))
	var mover = MonsterFactoryScript.createMonster("Defaultgon", 100)
	mover.jump = 1
	state.addMonster(mover, Vector2i(0, 0), 1)
	var events = BattleEvents.new()
	var movement = MovementResolver.new(state, events)
	var reachable = movement.getReachablePositions(mover.uniqueID)
	if not reachable.has(Vector2i(1, 0)) or reachable.has(Vector2i(2, 0)):
		_fail("jump-limited reachability is incorrect")
		return
	var invalidPath = movement.validateMovePath(
		mover.uniqueID, [Vector2i(1, 0), Vector2i(2, 0)]
	)
	if invalidPath["success"] or invalidPath["reason"] != "height_exceeds_jump":
		_fail("multi-step height validation accepted an excessive jump")
		return

	var serialized = StateSerializerScript.serialize(state)
	if serialized["version"] != 3 or serialized["mapRevision"] != 3:
		_fail("state schema version or map revision was not serialized")
		return
	var restored = StateSerializerScript.deserialize(
		JSON.parse_string(JSON.stringify(serialized))
	)
	if restored.getHeight(Vector2i(2, 0)) != 3 or restored.getMonster(100).jump != 1:
		_fail("height/jump JSON round trip failed")
		return
	var versionTwo = serialized.duplicate(true)
	versionTwo["version"] = 2
	versionTwo.erase("heightBoard")
	versionTwo["monsters"]["100"].erase("level")
	versionTwo["monsters"]["100"].erase("jump")
	var migrated = StateSerializerScript.deserialize(versionTwo)
	if migrated.getHeight(Vector2i(2, 0)) != 0:
		_fail("version-2 flat-height migration failed")
		return
	if migrated.getMonster(100).level != 1 or migrated.getMonster(100).jump != 1:
		_fail("version-2 monster defaults failed")
		return

	var combatState = BattleState.new(5)
	combatState.setup_board(Vector2i(4, 2))
	var attacker = MonsterFactoryScript.createMonster("Gigasaurus", 200)
	var target = MonsterFactoryScript.createMonster("Defaultgon", 201)
	attacker.atk = 20
	target.def = 0
	combatState.addMonster(attacker, Vector2i(0, 0), 1)
	combatState.addMonster(target, Vector2i(1, 0), 2)
	combatState.heightBoard.set_at(1, Vector2i(0, 0))
	combatState.heightBoard.set_at(0, Vector2i(1, 0))
	var combat = CombatResolver.new(combatState, BattleEvents.new())
	if combat.calculateBasicDamage(attacker, target, true) != 22:
		_fail("high-ground direct damage is incorrect")
		return
	combatState.heightBoard.set_at(0, Vector2i(0, 0))
	combatState.heightBoard.set_at(1, Vector2i(1, 0))
	if combat.calculateBasicDamage(attacker, target, true) != 18:
		_fail("low-ground direct damage is incorrect")
		return
	combatState.heightBoard.set_at(3, Vector2i(1, 0))
	if combat.getBasicAttackTargets(attacker.uniqueID).has(target.uniqueID):
		_fail("melee accepted an excessive height delta")
		return

	combatState.moveMonsterTo(target.uniqueID, Vector2i(3, 0))
	combatState.heightBoard.set_at(0, Vector2i(0, 0))
	combatState.heightBoard.set_at(2, Vector2i(1, 0))
	combatState.heightBoard.set_at(0, Vector2i(3, 0))
	if combat._hasLoS(attacker.uniqueID, Vector2i(0, 0), Vector2i(3, 0), target.uniqueID):
		_fail("intervening ridge did not block line of sight")
		return

	var visualState = BattleState.new(9)
	visualState.setup_board(Vector2i(3, 2))
	visualState.heightBoard.set_at(2, Vector2i(1, 0))
	var visualMonster = MonsterFactoryScript.createMonster("Defaultgon", 300)
	var visualTarget = MonsterFactoryScript.createMonster("Gigasaurus", 301)
	visualState.addMonster(visualMonster, Vector2i(0, 0), 1)
	visualState.addMonster(visualTarget, Vector2i(2, 0), 2)
	var visualRoot = Node3D.new()
	root.add_child(visualRoot)
	var adapter = GodotVisualAdapterScript.new(visualState, visualRoot, visualRoot)
	adapter._on_battle_started(visualState.boardSize, [300, 301])
	adapter._on_monster_spawned(300, visualMonster.name, 1, Vector2i(0, 0), {})
	adapter._on_monster_spawned(301, visualTarget.name, 2, Vector2i(2, 0), {})
	if not is_equal_approx(adapter.grid_node.get_child(1).position.y, 2.0):
		_fail("elevated tile visual is misaligned")
		return
	adapter.show_player_cursor(Vector2i(1, 0))
	if not is_equal_approx(adapter._cursor.position.y, 2.21):
		_fail("elevated cursor is misaligned")
		return
	adapter.show_movement_options([Vector2i(1, 0)])
	if not is_equal_approx(adapter.overlay_node.get_child(0).position.y, 2.215):
		_fail("elevated tactical overlay is misaligned")
		return
	var lightGrass = adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(0, 0), 0)
	var darkGrass = adapter.tileColorFor(Color(0.2, 0.8, 0.2), Vector2i(1, 0), 0)
	if lightGrass.is_equal_approx(darkGrass) or lightGrass.v <= darkGrass.v:
		_fail("terrain checker does not alternate light and dark tones")
		return
	var base = adapter._monster_visuals[300].get_child(0) as MeshInstance3D
	var baseMaterial = base.material_override as ShaderMaterial
	var teamColor: Color = baseMaterial.get_shader_parameter("color_a")
	if teamColor.b <= teamColor.r:
		_fail("Team 1 capsule base is not blue")
		return

	visualState.moveMonsterTo(300, Vector2i(1, 0))
	adapter._on_monster_moved(300, [Vector2i(1, 0)])
	adapter._on_monster_attacked(300, 301, 1, visualTarget.hitpoints - 1)
	adapter._on_battle_ended(1)
	# Simulate authoritative state advancing again while the view still owns the
	# earlier movement and attack snapshots.
	visualState.moveMonsterTo(300, Vector2i(0, 0))
	if adapter.activeAnimationKind() != "move" or adapter.queuedAnimationCount() != 2:
		_fail("movement, attack, and victory were not serialized in the visual queue")
		return
	if not is_equal_approx(adapter._monster_visuals[300].position.x, 0.0):
		_fail("queued attack snapped the still-moving model to backend state")
		return
	await create_timer(0.23).timeout
	if adapter.activeAnimationKind() != "bump":
		_fail("attack animation did not wait for movement completion")
		return
	await create_timer(0.35).timeout
	if adapter.isAnimationBusy() or adapter.queuedAnimationCount() != 0:
		_fail("visual animation queue did not drain")
		return
	var queuedFinal: Vector3 = adapter._monster_visuals[300].position
	if not is_equal_approx(queuedFinal.x, 1.0) or not is_equal_approx(queuedFinal.y, 2.2):
		_fail("queued movement read later authoritative position instead of its snapshot")
		return

	adapter._on_monster_moved(300, [Vector2i(0, 0)])
	adapter.anim_tween.pause()
	await create_timer(1.05).timeout
	if adapter.isAnimationBusy() or not is_equal_approx(adapter._monster_visuals[300].position.x, 0.0):
		_fail("visual animation watchdog did not recover a stalled tween")
		return

	visualTarget.hitpoints = 0
	adapter._on_monster_defeated(301, 300)
	await process_frame
	var selection = adapter._monster_visuals[301].get_node("SelectionBody") as StaticBody3D
	if selection.collision_layer != 0:
		_fail("defeat did not disable selection when its queued action began")
		return
	if adapter._monster_visuals[301].get_node_or_null("CapsuleShatter") == null:
		_fail("defeat did not create the capsule shatter effect")
		return
	await create_timer(0.45).timeout
	if adapter.isAnimationBusy() or adapter._monster_visuals.has(301):
		_fail("defeat animation did not finish and release its visual")
		return
	adapter.dispose()
	visualRoot.queue_free()
	await process_frame
	var ai = BattleSimulator.new(13)
	ai.state.setup_board(Vector2i(5, 3))
	var cpu = ai.spawnMonster("Gigasaurus", 1, Vector2i(1, 1))
	var lethalTarget = ai.spawnMonster("Defaultgon", 2, Vector2i(2, 1))
	ai.spawnMonster("Defaultgon", 2, Vector2i(4, 1))
	lethalTarget.hitpoints = 1
	ai.state.currentMonsterID = cpu.uniqueID
	var decisionStart = Time.get_ticks_usec()
	var decision = ai.brains[cpu.uniqueID].decideTurn(cpu.uniqueID)
	var decisionMicros = Time.get_ticks_usec() - decisionStart
	if decision["action"] != "attack" or decision["target_id"] != lethalTarget.uniqueID:
		_fail("CPU did not prioritize a safe lethal action")
		return
	print("CAPSULE_AI_DECISION_US=%d" % decisionMicros)

	var benchmarkConfig = BattleSetupConfigScript.new()
	benchmarkConfig.team1 = BattleSetupPresetsScript.DEFAULT_TEAM_1.duplicate()
	benchmarkConfig.team2 = BattleSetupPresetsScript.DEFAULT_TEAM_2.duplicate()
	var benchmark = BattleSetupFactoryScript.createSimulator(benchmarkConfig)
	var timings: Array[int] = []
	for monsterID in benchmark.state.getAliveMonsterIDs():
		var started = Time.get_ticks_usec()
		benchmark.brains[monsterID].decideTurn(monsterID)
		timings.append(Time.get_ticks_usec() - started)
	timings.sort()
	var percentile95 = timings[mini(timings.size() - 1, ceili(timings.size() * 0.95) - 1)]
	print("CAPSULE_AI_P95_US=%d" % percentile95)
	if percentile95 >= 50000:
		_fail("eight-unit CPU decision p95 exceeded 50 ms")
		return
	print("CAPSULE_FEATURES_OK")
	quit(0)


func _fail(reason: String) -> void:
	push_error("CAPSULE_FEATURES_FAILED: %s" % reason)
	quit(1)
