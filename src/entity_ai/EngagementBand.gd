## Where a unit actually wants to stand, read off what it can do.
##
## A blunt "close on the nearest enemy" rule suits a unit whose damage is a
## sword and nothing else. It is wrong for everyone else: it walks an archer
## into melee, and it walks a healer into a crossfire. The distance a unit wants
## is not a personality that someone types in per role -- it falls out of the
## abilities the unit is actually carrying, so a unit that is handed a new spell
## starts wanting a new distance without anyone editing a table.
##
## For each way a unit can deal damage, this records the distance band it works
## at and what it is worth there: melee at distance one for `atk`, and each
## castable damaging spell across its own range band. The preferred band is the
## most valuable one, and ties go to the **longer** band, because reaching from
## further costs less to hold.
##
## `fitValue()` then says what standing at some distance is worth per turn: full
## value inside the band, falling off outside it. That is the positional value a
## one-decision horizon cannot otherwise see -- closing to melee is worth
## nothing this turn and everything next turn, and without this term a unit that
## can only reach for three damage today will always rather stand still.

class_name EngagementBand
extends RefCounted


## `{"min": int, "max": int, "value": int, "kind": String}` for every way this
## unit can deal damage, best first.
static func bandsFor(state: BattleState, monsterID: int) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	var monster: Monster = state.getMonster(monsterID)
	if monster == null or not monster.is_alive():
		return bands
	if monster.atk > 0:
		bands.append({"min": 1, "max": 1, "value": monster.atk, "kind": "melee"})
	for setIndex in range(monster.spellSets.size()):
		for spellIndex in range(monster.spellSets[setIndex].size()):
			var spell: Spell = monster.spellSets[setIndex][spellIndex]
			if spell.heals or not monster.can_cast(spell):
				continue
			var damage := spell.damage
			for line in spell.damage_lines:
				damage = maxi(damage, int(line.get("damage", 0)))
			if damage <= 0:
				continue
			bands.append({
				"min": maxi(0, spell.min_range),
				"max": maxi(spell.min_range, spell.range),
				"value": damage,
				"kind": "spell",
			})
	bands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["value"]) != int(b["value"]):
			return int(a["value"]) > int(b["value"])
		if int(a["max"]) != int(b["max"]):
			return int(a["max"]) > int(b["max"])
		return int(a["min"]) < int(b["min"])
	)
	return bands


## The band this unit would rather fight from. Empty when it cannot damage
## anything at all, in which case position has no offensive meaning for it.
static func preferredBand(state: BattleState, monsterID: int) -> Dictionary:
	var bands := bandsFor(state, monsterID)
	return {} if bands.is_empty() else bands[0]


## What standing `distance` from the nearest enemy is worth per turn. Inside the
## band it is the band's full value; outside, it falls by one step per hex of
## error and **is not clamped at zero**.
##
## The clamp was the whole problem. With it, everywhere past a few hexes scored
## the same nothing, so a unit that started far from the fight saw a flat
## landscape, found no reason to prefer one tile over another, and swung at
## empty air instead of walking in. Letting the value go negative keeps a
## gradient everywhere on the board, which is what "move to the best position
## for this unit" actually requires.
static func fitValue(band: Dictionary, distance: int) -> int:
	if band.is_empty():
		return 0
	var low := int(band["min"])
	var high := int(band["max"])
	var value := int(band["value"])
	if distance >= low and distance <= high:
		return value
	var error := low - distance if distance < low else distance - high
	var step := maxi(1, int(round(float(value) / 4.0)))
	return value - error * step


## The best any of this unit's bands scores at `distance`. A unit with a sword
## and a spell is not confined to one of them, and a tile that suits either is
## a good tile.
static func bestFitValue(bands: Array[Dictionary], distance: int) -> int:
	if bands.is_empty():
		return 0
	var best := fitValue(bands[0], distance)
	for band: Dictionary in bands:
		best = maxi(best, fitValue(band, distance))
	return best
