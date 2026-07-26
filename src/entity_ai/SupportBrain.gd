## SupportBrain — Healing AI.
## Values casting heal/support spells highly. Avoids threat heavily.

class_name SupportBrain
extends EntityBrain


func _evaluationWeights() -> Dictionary:
	return {"damage": 45, "utility": 180, "threat": 8, "distance": 0, "wait_penalty": 4}

func _evaluateTile(monsterID: int, pos: Vector2i) -> Dictionary:
	var tile_score = -9999
	var tile_decision = { "action": "wait", "target_id": -1 }
	var mon = state.getMonster(monsterID)
	
	var support_score = 0
	
	# 1. Healing Spells (Highest priority)
	var healDecision = _findBestHealSpell(monsterID, pos, 0.75)
	if healDecision != null:
		# If it's a damage-revert or a low HP heal, score is massive
		support_score = 150
		tile_decision = { 
			"action": "spell", 
			"target_id": healDecision.target_id, 
			"spell_set_index": healDecision.spell_set_index, 
			"spell_index": healDecision.spell_index 
		}
	else:
		# 2. Self Buff
		var buffDecision = _findBestSelfBuff(monsterID)
		if buffDecision != null:
			support_score = 60
			tile_decision = buffDecision
		else:
			# 3. Offensive Spell (Desperation)
			var spellDecision = _findBestOffensiveSpell(monsterID, pos)
			if spellDecision != null:
				support_score = 50 + spellDecision.score
				tile_decision = { 
					"action": "spell", 
					"target_id": spellDecision.target_id, 
					"spell_set_index": spellDecision.spell_set_index, 
					"spell_index": spellDecision.spell_index 
				}
				
	# 4. Kiting/Avoidance modifier
	var threatMap = ThreatMap.generate(state, mon.team)
	var threat_at_pos = threatMap.get(pos, 0)
	
	if tile_decision.action == "wait":
		# Prefer staying near the lowest HP ally
		var lowestAllyID = _findLowestHPAlly(monsterID)
		if lowestAllyID != -1 and lowestAllyID != monsterID:
			var allyPos = state.getMonsterPosition(lowestAllyID)
			var distToAlly = abs(pos.x - allyPos.x) + abs(pos.y - allyPos.y)
			support_score = 40 - distToAlly
		else:
			support_score = 0
			
	# Heavy penalty for being in threat zones
	tile_score = support_score - (threat_at_pos * 6)
			
	return { "score": tile_score, "decision": tile_decision }
