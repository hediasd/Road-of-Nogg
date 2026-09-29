extends SceneTree

## Diagnostic scenario interventions only; never modifies production data or rules.
## Godot --headless --path . --script tools/investigate_seat_bias.gd --
##   --tag=screen --seeds=4242 --variants=native,swap_rosters,swap_cells,swap_both
## Optional: --policies=tactical_side_v1,legacy_side_v1 --scenarios=<scenario ids>
## A colon pairs different policies, team one first: tactical_side_v1:legacy_side_v1.
## Use a fresh tag for each run. Traces are diagnostics, not replay snapshots.
## Each run writes complete command/event evidence beneath BattleOutputPaths.
const OutputPaths = preload("res://battle/BattleOutputPaths.gd")
const Setup = preload("res://simulation/BattleSetupFactory.gd")
const Config = preload("res://simulation/BattleSetupConfig.gd")
const Simulator = preload("res://simulation/BattleSimulator.gd")
const Identity = preload("res://tools/BuildIdentity.gd")
const Policies = preload("res://ai/PolicyCatalog.gd")
const VARIANTS = ["native", "swap_rosters", "swap_cells", "swap_both", "mirror_a", "mirror_b", "reverse_order", "without_ice_plow"]
const SCENARIOS = ["technical_hxb_contract_cpu_cpu", "proving_ground_cpu_cpu", "hexmap_cpu_cpu"]


func _init() -> void:
	var options := {"tag": "screen", "seeds": "4242", "variants": ",".join(VARIANTS),
		"policies": "tactical_side_v1,legacy_side_v1", "scenarios": ",".join(SCENARIOS)}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2 or not options.has(pair[0]):
			_fail("unknown argument: %s" % argument)
			return
		options[pair[0]] = pair[1]
	if not str(options.tag).is_valid_identifier():
		_fail("tag must be an identifier")
		return
	var root := OutputPaths.pathFor(OutputPaths.TOURNAMENTS, "seat_diagnosis_" + str(options.tag))
	if FileAccess.file_exists(root + "/declaration.json"):
		_fail("output already exists; choose a fresh --tag to preserve evidence")
		return
	var rows: Array = []
	var identity := Identity.capture()
	# The existing identity helper's data root predates the folder flattening.
	# Include the actual catalog, map, scenario and runner bytes independently.
	var sources: Dictionary = {}
	for directory in ["res://data", "res://simulation", "res://content", "res://ai", "res://tools"]:
		_hashSources(directory, sources)
	_write(root + "/declaration.json", {"options": options, "build": identity, "sources": sources,
		"purpose": "diagnostic only; old holdout is inspected, no policy strength claim",
		"round_cap": 30, "decision_cap": 2000,
		"transformations": "roster swaps exchange MONSTER and LEVEL at corresponding party/member slots; cell swaps exchange CELL only; mirror copies MONSTER and LEVEL from original A or B into both sides; reverse_order rebinds TEAM_ID to 3 minus its original value; without_ice_plow removes only that ability from fresh runtime spell sets before simulator configuration; unit/party IDs, commander slots, rules and terrain stay fixed"})
	for scenario_id in str(options.scenarios).split(","):
		if scenario_id not in SCENARIOS:
			_fail("unknown scenario: " + scenario_id)
			return
		var raw: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/%s.json" % scenario_id))
		for variant in str(options.variants).split(","):
			if variant not in VARIANTS:
				_fail("unknown variant: " + variant)
				return
			var transformed := _transform(raw[0], variant)
			var scenario_path := root + "/inputs/%s_%s.json" % [scenario_id, variant]
			_write(scenario_path, [transformed])
			for policy in str(options.policies).split(","):
				for policy_id in policy.split(":"):
					if policy_id not in [Policies.TACTICAL_SIDE, Policies.LEGACY_SIDE] or policy.count(":") > 1:
						_fail("unsupported policy: " + policy)
						return
				for seed_text in str(options.seeds).split(","):
					if not seed_text.is_valid_int() or int(seed_text) < 0:
						_fail("invalid seed")
						return
					var row := _play(scenario_path, policy, int(seed_text), variant)
					row.merge({"scenario": scenario_id, "variant": variant, "policy": policy, "seed": int(seed_text)})
					var file_name := "%s_%s_%s_%s.json" % [scenario_id, variant, policy.replace(":", "_vs_"), seed_text]
					_write(root + "/traces/" + file_name, row)
					var summary := row.duplicate()
					summary.erase("commands")
					summary.erase("events")
					rows.append(summary)
					_write(root + "/results.json", rows)
					print("SEAT_MATCH %s winner=%d rounds=%d decisions=%d error=%s" %
						[file_name, row.winner, row.rounds, row.decisions, row.error])
					if not str(row.error).is_empty():
						_fail(str(row.error))
						return
	var ending_sources: Dictionary = {}
	for directory in ["res://data", "res://simulation", "res://content", "res://ai", "res://tools"]:
		_hashSources(directory, ending_sources)
	if sources != ending_sources:
		_fail("source bytes changed during run; results are diagnostic but cannot be pooled")
		return
	print("SEAT_DIAGNOSIS_OK")
	quit(0)


func _transform(raw: Dictionary, variant: String) -> Dictionary:
	var result := raw.duplicate(true)
	var left: Array = []
	var right: Array = []
	for party: Dictionary in result.PARTIES:
		if int(party.TEAM_ID) == 1:
			left.append_array(party.MEMBERS)
		else:
			right.append_array(party.MEMBERS)
	assert(left.size() == right.size())
	for i in left.size():
		var a: Dictionary = left[i].duplicate(true)
		var b: Dictionary = right[i].duplicate(true)
		if variant in ["swap_rosters", "swap_both"]:
			for key in ["MONSTER", "LEVEL"]:
				left[i][key] = b[key]
				right[i][key] = a[key]
		if variant in ["swap_cells", "swap_both"]:
			left[i].CELL = b.CELL
			right[i].CELL = a.CELL
		if variant in ["mirror_a", "mirror_b"]:
			var source: Dictionary = a if variant == "mirror_a" else b
			for key in ["MONSTER", "LEVEL"]:
				left[i][key] = source[key]
				right[i][key] = source[key]
	if variant == "reverse_order":
		# Preserve every unit, party, position, and commander identity. Rebind team
		# labels so the original right-hand force acts first under approved rules.
		for party: Dictionary in result.PARTIES:
			party.TEAM_ID = 3 - int(party.TEAM_ID)
	return result


func _play(scenario_path: String, policy: String, seed_value: int, variant: String) -> Dictionary:
	var config = Config.new()
	config.scenarioPath = scenario_path
	config.seed = seed_value
	var setup: Dictionary = Setup.createHexState(config)
	var row := {"winner": -1, "rounds": 0, "decisions": 0, "error": "", "commands": [], "events": [], "initial": []}
	if not setup.success:
		row.error = "setup failed: %s" % setup.error
		return row
	if variant == "without_ice_plow":
		for id in setup.state.getAliveMonsterIDs():
			var monster: Monster = setup.state.getMonster(id)
			for spell_set in monster.spellSets:
				for index in range(spell_set.size() - 1, -1, -1):
					if spell_set[index].name == "Ice Plow":
						spell_set.remove_at(index)
	var simulator = Simulator.new(seed_value)
	simulator.configureHexState(setup.state, setup.scenario, config.serialize())
	simulator.setInvariantChecks(true)
	var policy_pair := policy.split(":")
	for id in simulator.state.getAliveMonsterIDs():
		var monster: Monster = simulator.state.getMonster(id)
		var spell_names: Array = []
		for spell_set in monster.spellSets:
			var set_names: Array = []
			for spell: Spell in spell_set:
				set_names.append(spell.name)
			spell_names.append(set_names)
		row.initial.append({"id": id, "name": monster.name, "team": monster.team,
			"position": [monster.position.x, monster.position.y], "hp": monster.hitpoints,
			"atk": monster.atk, "def": monster.def, "move": monster.move,
			"spells": spell_names,
			"commander": simulator.state.parties[simulator.state.monsterPartyIDs[id]].commanderID == id})
	simulator.startBattle()
	while simulator.state.battleOutcome == -1:
		# Complete both sides of the capped round (the tournament loop does not).
		if simulator.state.roundCount >= 30 and simulator.state.activeSideID == -1 and simulator.state.pendingSideIDs.is_empty():
			break
		if int(row.decisions) >= 2000:
			row.error = "decision watchdog"
			break
		if simulator.state.activeSideID == -1:
			var opened: Dictionary = simulator.startNextSideTurn("seat_diagnosis")
			if not opened.success:
				if simulator.state.battleOutcome == -1:
					row.error = "side open failed: %s" % opened
				break
		simulator.sidePolicyID = policy_pair[0] if simulator.state.activeSideID == 1 or policy_pair.size() == 1 else policy_pair[1]
		var deliberation = simulator.beginSideDeliberation()
		var proposal = deliberation.run(64)
		if proposal == null:
			simulator.endSideTurn("no_proposal")
			continue
		var command_row := {"round": simulator.state.roundCount, "side": simulator.state.activeSideID,
			"actor": proposal.actor_id, "command": proposal.command.to_dictionary(), "before": _units(simulator.state)}
		if deliberation.has_method("trace"):
			command_row["policy_trace"] = deliberation.trace()
		if not simulator.selectUnit(proposal.actor_id, "seat_diagnosis").success:
			row.error = "selection rejected"
			break
		var executed = simulator.executeCommand(proposal.actor_id, proposal.command, "seat_diagnosis")
		row.decisions += 1
		command_row["after"] = _units(simulator.state)
		row.commands.append(command_row)
		if not executed.success:
			row.error = "command rejected: " + str(executed.reason)
			break
	row.winner = simulator.state.battleOutcome
	row.rounds = simulator.state.roundCount
	row.events = simulator.state.history.duplicate(true)
	row["invariant_violations"] = simulator.invariantViolations()
	row["final"] = _units(simulator.state)
	if not simulator.invariantViolations().is_empty():
		row.error = "invariant violations"
	return row


func _units(state: BattleState) -> Array:
	var units: Array = []
	for id in state.monsters:
		var monster: Monster = state.getMonster(id)
		units.append({"id": id, "hp": monster.hitpoints, "position": [monster.position.x, monster.position.y],
			"withdrawn": state.withdrawnMonsterIDs.has(id)})
	return units


func _hashSources(root: String, hashes: Dictionary) -> void:
	var directory := DirAccess.open(root)
	assert(directory != null, "source root missing: " + root)
	for file_name in directory.get_files():
		if file_name.ends_with(".gd") or file_name.ends_with(".json"):
			var path := root + "/" + file_name
			hashes[path] = FileAccess.get_sha256(path)
	for child in directory.get_directories():
		_hashSources(root + "/" + child, hashes)


func _write(path: String, value) -> void:
	OutputPaths.ensureParent(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "cannot write: " + path)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()


func _fail(message: String) -> void:
	push_error("SEAT_DIAGNOSIS_FAILED: " + message)
	quit(1)
