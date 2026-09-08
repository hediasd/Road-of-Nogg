## Compact canonical token used to reject CPU work computed from stale state.
##
## Canonical simulation mutations append history; the extra fields cover RNG,
## allocation, activation, and direct decision inputs so a proposal also goes
## stale if an invariant is violated without a ledger entry. Capturing the token
## is a pure read and avoids serializing the map and complete event history on
## every presentation frame.

class_name BattleStateRevision
extends RefCounted


static func capture(state: BattleState) -> String:
	if state == null:
		return ""
	var monsterIDs: Array = state.monsters.keys()
	monsterIDs.sort()
	var actors: Array = []
	for monsterID in monsterIDs:
		var monster: Monster = state.getMonster(monsterID)
		var position: Vector2i = state.monsterPositions.get(
			monsterID, Vector2i(-1, -1))
		actors.append({
			"id": int(monsterID),
			"position": {"x": position.x, "y": position.y},
			"monster": monster.serialize(),
			"effects": state.getActiveEffects(monsterID).duplicate(true),
			"party": int(state.monsterPartyIDs.get(monsterID, -1)),
			"withdrawn": state.isMonsterWithdrawn(monsterID),
		})
	return JSON.stringify({
		"history_size": state.history.size(),
		"rng_state": state.rng.state,
		"next_monster_id": state.nextMonsterID,
		"round": state.roundCount,
		"turn": state.turnCount,
		"current_monster": state.currentMonsterID,
		"active_party": state.activePartyID,
		"party_order": state.partyOrder,
		"pending_parties": state.pendingPartyIDs,
		"spent_members": state.spentMemberIDs,
		"withdrawn_parties": state.withdrawnPartyIDs,
		"activation": state.activationCount,
		"activation_phase": state.activationPhase,
		"outcome": state.battleOutcome,
		"actors": actors,
	})
