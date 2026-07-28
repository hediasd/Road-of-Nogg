class_name SpellReferences

static var list

static func _static_init():
	list = [
		# --- ICE ---
		{
			"NAME" = "Ice Punch",
			"RADIUS" = 1, "RANGE" = 1, "DAMAGE" = 3, "ELEMENT" = "ice"
		},{
			"NAME" = "Ice Plume",
			"RADIUS" = 1, "RANGE" = 5, "DAMAGE" = 5, "ELEMENT" = "ice"
		},{
			"NAME" = "Ice Plow",
			"RADIUS" = 2, "RANGE" = 3, "DAMAGE" = 4, "ELEMENT" = "ice"
		},{
			"NAME" = "Dark Bolt",
			"RANGE" = 4, "DAMAGE" = 4,
			"ELEMENT" = "darkness",
			"DESC" = "Fires a dark bolt from afar."
		},{
			"NAME" = "Dark Nova",
			"RANGE" = 3, "DAMAGE" = 6,
			"TARGET_TYPE" = "area",
			"ELEMENT" = "darkness",
			"DESC" = "A burst of darkness in an area."
		},{
			"NAME" = "Mending",
			"RANGE" = 5, "HEALS" = true, "DAMAGE" = 5,
			"TARGET_TYPE" = "single",
			"ELEMENT" = "light",
			"BYPASS_LOS" = true,
			"DESC" = "Restores HP to an ally."
		},{
			"NAME" = "Ember Strike",
			"RANGE" = 2, "DAMAGE" = 3,
			"ELEMENT" = "fire",
			"INFLICTS_STATUS" = "burn",
			"DESC" = "A fiery blow that inflicts burn."
		},{
			"NAME" = "Pyre Blast",
			"RANGE" = 3, "DAMAGE" = 4,
			"ELEMENT" = "fire",
			"INFLICTS_STATUS" = "burn",
			"DESC" = "A blast of fire that inflicts burn."
		},{
			"NAME" = "Earth Spike",
			"RANGE" = 3, "DAMAGE" = 4, "ELEMENT" = "earth"
		},{
			"NAME" = "Steel Blade",
			"RANGE" = 1, "DAMAGE" = 5, "ELEMENT" = "steel"
		},{
			"NAME" = "Splash",
			"RANGE" = 4, "DAMAGE" = 3, "ELEMENT" = "water"
		},{
			"NAME" = "Wood Splinter",
			"RANGE" = 3, "DAMAGE" = 3, "ELEMENT" = "wood"
		},{
			"NAME" = "Empower",
			"RANGE" = 0, "DAMAGE" = 0, "ELEMENT" = "wood",
			"TARGET_TYPE" = "self",
			"BUFFS_ATK" = 3, "BUFF_DURATION" = 2,
			"BYPASS_LOS" = true,
			"DAMAGE_LINES" = [],
			"DESC" = "Channels wood energy to temporarily empower the caster's strength (+3 ATK for 2 turns)."
		},
		# --- LEVEL 1 SELF SPELLS ---
		{
			"NAME" = "Anticipate", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "darkness", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "guard", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 0.75}]
		},{
			"NAME" = "Plot", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "darkness", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "focus", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 1.25}]
		},{
			"NAME" = "Pillar", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "earth", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "def_buff", "DURATION" = 3, "DEF_BONUS" = 2}]
		},{
			"NAME" = "Stand", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "earth", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [
				{"NAME" = "def_buff", "DURATION" = 4, "DEF_BONUS" = 1},
				{"NAME" = "guard", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 0.75}
			]
		},{
			"NAME" = "Enrage", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "fire", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "atk_buff", "DURATION" = 3, "ATK_BONUS" = 2}]
		},{
			"NAME" = "Predict", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "fire", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "focus", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 1.25}]
		},{
			"NAME" = "Lantern", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "fire", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "spd_buff", "DURATION" = 4, "SPD_BONUS" = 1}]
		},{
			"NAME" = "Triage", "RANGE" = 0, "DAMAGE" = 0, "HEALS" = true, "HEAL_AMOUNT" = 3,
			"TARGET_TYPE" = "self", "ELEMENT" = "ice", "SEQUENCE_LEVEL" = 1
		},{
			"NAME" = "Chill", "RANGE" = 0, "DAMAGE" = 1,
			"TARGET_TYPE" = "self", "SELF_RADIUS" = 1, "AOE_TARGETS" = "enemies",
			"ELEMENT" = "ice", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "chill", "DURATION" = 3, "SPD_BONUS" = -1, "NEGATIVE" = true}]
		},{
			"NAME" = "Dutiful", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "ice", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "guard", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 0.75}]
		},{
			"NAME" = "Prelude", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "light", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "focus", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 1.25}]
		},{
			"NAME" = "Elucidate", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "light", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "cleanse"}]
		},{
			"NAME" = "Shine", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "SELF_RADIUS" = 2, "AOE_TARGETS" = "allies",
			"ELEMENT" = "light", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "def_buff", "DURATION" = 3, "DEF_BONUS" = 1}]
		},{
			"NAME" = "Prayer", "RANGE" = 0, "DAMAGE" = 0, "HEALS" = true, "HEAL_AMOUNT" = 3,
			"TARGET_TYPE" = "self", "ELEMENT" = "light", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "cleanse"}]
		},{
			"NAME" = "Iterate", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "steel", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "cooldown_reduction", "VALUE" = 1}]
		},{
			"NAME" = "Cheers", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "SELF_RADIUS" = 2, "AOE_TARGETS" = "allies",
			"ELEMENT" = "thunder", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "atk_buff", "DURATION" = 3, "ATK_BONUS" = 1}]
		},{
			"NAME" = "Ponder", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "water", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "def_buff", "DURATION" = 4, "DEF_BONUS" = 1}]
		},{
			"NAME" = "Dissolve", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "water", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "cleanse"}]
		},{
			"NAME" = "Moderation", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "water", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [
				{"NAME" = "guard", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 0.75},
				{"NAME" = "def_buff", "DURATION" = 4, "DEF_BONUS" = 1}
			]
		},{
			"NAME" = "Breeze", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "wind", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "move_buff", "DURATION" = 4, "MOVE_BONUS" = 1}]
		},{
			"NAME" = "Stroll", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "wind", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "spd_buff", "DURATION" = 4, "SPD_BONUS" = 1}]
		},{
			"NAME" = "Follow Up", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "wind", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "focus", "DURATION" = 4, "DAMAGE_MULTIPLIER" = 1.25}]
		},{
			"NAME" = "Flow", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "wind", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [
				{"NAME" = "cleanse"},
				{"NAME" = "move_buff", "DURATION" = 4, "MOVE_BONUS" = 1}
			]
		},{
			"NAME" = "Barricade", "RANGE" = 0, "DAMAGE" = 0,
			"TARGET_TYPE" = "self", "ELEMENT" = "wood", "SEQUENCE_LEVEL" = 1,
			"EFFECTS" = [{"NAME" = "def_buff", "DURATION" = 3, "DEF_BONUS" = 2}]
		},{
			"NAME" = "Gather", "RANGE" = 0, "DAMAGE" = 0, "HEALS" = true, "HEAL_AMOUNT" = 2,
			"TARGET_TYPE" = "self", "SELF_RADIUS" = 2, "AOE_TARGETS" = "allies",
			"ELEMENT" = "wood", "SEQUENCE_LEVEL" = 1
		},
		# --- WOOD TIER LADDER (P4-3 pilot) ---
		# The first complete Level 1-4 vertical set in the catalog, and the
		# reference implementation of the tier contract documented in
		# docs/GAME_DESIGN.md: L1 self-target setup, L2 single-target engage,
		# L3 committed area with a cooldown, L4 ultimate that spends three
		# Resonance charge. Level 1 of this set is the existing "Gather".
		{
			"NAME" = "Thornlash",
			"TARGET_TYPE" = "single",
			"RANGE" = 3, "DAMAGE" = 4,
			"ELEMENT" = "wood", "SEQUENCE_LEVEL" = 2,
			"DESC" = "Lashes a single foe with a barbed vine."
		},{
			"NAME" = "Bramble Crown",
			"TARGET_TYPE" = "area",
			"RADIUS" = 2, "RANGE" = 3, "DAMAGE" = 5,
			"INFLICTS_STATUS" = "poison",
			"COOLDOWN" = 4,
			"ELEMENT" = "wood", "SEQUENCE_LEVEL" = 3,
			"DESC" = "Erupts a ring of thorned briar that poisons everything it encircles."
		},{
			"NAME" = "Roses at Summers End",
			"TARGET_TYPE" = "area",
			"RADIUS" = 2, "RANGE" = 4, "DAMAGE" = 7,
			"INFLICTS_STATUS" = "poison",
			"COOLDOWN" = 8,
			"ELEMENT" = "wood", "SEQUENCE_LEVEL" = 4,
			"DESC" = "The last bloom of the season opens in full glory and withers all it touches."
		},
		# --- NEW SPELLS ---
		{
			"NAME" = "Eschatology",
			"MIN_RANGE" = 2,
			"RANGE" = 3,
			"DAMAGE_LINES" = [
				{"damage": 4, "element": "fire"},
				{"damage": 4, "element": "light"}
			],
			"DESC" = "A medium-close range fire/light damage spell."
		},{
			"NAME" = "Closing of the Third Sanctuary",
			"TARGET_TYPE" = "area",
			"RADIUS" = 3, "RANGE" = 5, "DAMAGE" = 0,
			"INFLICTS_STATUS" = "petrify",
			"COOLDOWN" = 5,
			"ELEMENT" = "darkness",
			"DESC" = "Applies petrification to enemies in a 3-cell radius."
		},{
			"NAME" = "Opening of the Third Sanctuary",
			"TARGET_TYPE" = "area",
			"RADIUS" = 3, "RANGE" = 5, "DAMAGE" = 2, "HEALS" = true,
			"REMOVES_STATUS" = "petrify",
			"ELEMENT" = "light",
			"DESC" = "Removes petrification and heals allies in a 3-cell radius."
		},{
			"NAME" = "Holy Cross",
			"TARGET_TYPE" = "area",
			"AREA_SHAPE" = "cross",
			"RADIUS" = 2, "RANGE" = 4, "DAMAGE" = 4,
			"ELEMENT" = "light",
			"DESC" = "A cross-shaped burst of holy energy."
		},{
			"NAME" = "Smoke Tower",
			"TARGET_TYPE" = "area",
			"AREA_SHAPE" = "cross",
			"RADIUS" = 1, "RANGE" = 4, "DAMAGE" = 4,
			"ELEMENT" = "fire",
			"INFLICTS_STATUS" = "burn",
			"DESC" = "A cross-shaped pillar of smoke and fire that inflicts burn."
		},{
			"NAME" = "Peck",
			"RANGE" = 1, "DAMAGE" = 3, "ELEMENT" = "wind",
			"DESC" = "A sharp, quick beak attack infused with wind."
		},{
			"NAME" = "Feather Time",
			"RANGE" = 4, "DAMAGE_LINES" = [{"damage": 3, "element": "steel"}, {"damage": 3, "element": "wind"}],
			"DESC" = "Unleashes a flurry of metallic feathers, striking with both steel and wind."
		},{
			"NAME" = "Sudden Storm",
			"TARGET_TYPE" = "area", "RADIUS" = 2, "RANGE" = 4, "DAMAGE" = 5, "ELEMENT" = "wind",
			"DESC" = "Conjures a violent, localized windstorm to batter enemies."
		},{
			"NAME" = "Ooze Shield",
			"TARGET_TYPE" = "self", "SELF_RADIUS" = 2, "AOE_TARGETS" = "allies", "DAMAGE" = 0, "ELEMENT" = "water",
			"EFFECTS" = [{"NAME" = "def_buff", "DURATION" = 3, "DEF_BONUS" = 2}],
			"DESC" = "Coats nearby allies in a resilient layer of gel, increasing their defense."
		},{
			"NAME" = "Corrupting Splatter",
			"TARGET_TYPE" = "area", "RADIUS" = 1, "RANGE" = 3, "DAMAGE" = 3, "ELEMENT" = "darkness",
			"INFLICTS_STATUS" = "poison",
			"DESC" = "Lobs a chunk of dark, toxic slime that poisons enemies in a small area."
		},{
			"NAME" = "Flourish",
			"TARGET_TYPE" = "single", "RANGE" = 4, "DAMAGE" = 0, "HEALS" = true, "HEAL_AMOUNT" = 4, "ELEMENT" = "wood",
			"EFFECTS" = [{"NAME" = "atk_buff", "DURATION" = 3, "ATK_BONUS" = 1}],
			"DESC" = "A potent single-target ally buff/heal. Heals target for 4 HP and grants +1 ATK for 3 turns."
		},{
			"NAME" = "Insatiable Famine",
			"TARGET_TYPE" = "single", "RANGE" = 4, "DAMAGE" = 2, "ELEMENT" = "wood",
			"INFLICTS_STATUS" = "poison",
			"DESC" = "Inspired by the curse of Erysichthon. Single target ranged attack that inflicts poison."
		},
		# --- UTILITY / PLACEHOLDER ---
		{
			"NAME" = "Timeoff",
			"TARGET_TYPE" = "single",
			"RANGE" = 4, "DAMAGE" = 0, "HEALS" = true,
			"ELEMENT" = "wood",
			# DURATION 999 stands in for "permanent": no battle runs that long.
			"EFFECTS" = [{"NAME" = "spd_debuff", "DURATION" = 999, "SPD_BONUS" = -2, "NEGATIVE" = true}],
			"DESC" = "Heals the target but permanently reduces their speed."
		},{
			"NAME" = "Lightningbolt",
			"TARGET_TYPE" = "single",
			"RANGE" = 6, "DAMAGE" = 2,
			"ELEMENT" = "thunder",
			"DESC" = "Strikes the target with lightning from a long range."
		},{
			"NAME" = "Ages Ago",
			"TARGET_TYPE" = "single",
			"RANGE" = 4, "DAMAGE" = 0,
			"REVERTS_DAMAGE" = true,
			"COOLDOWN" = 8,
			"ELEMENT" = "steel",
			"DESC" = "Reverts the damage dealt by the target on their last turn. Cooldown: 8 turns."
		},{
			"NAME" = "Think",
			"RADIUS" = 0, "RANGE" = 0, "DAMAGE" = 0, "ELEMENT" = "none"
		},{
			"NAME" = "Thought",
			"RADIUS" = 0, "RANGE" = 0, "DAMAGE" = 0, "ELEMENT" = "none"
		},{
			"NAME" = "Dump",
			"RADIUS" = 0, "RANGE" = 0, "DAMAGE" = 0, "ELEMENT" = "none"
		}
	]
	for reference in list:
		reference["MAX_HEIGHT_DELTA"] = int(reference.get("MAX_HEIGHT_DELTA", 1))

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	push_error("SpellReferences: Unknown spell '%s'." % name)
	return {}


static func hasReference(name: String) -> bool:
	for reference in list:
		if reference["NAME"] == name:
			return true
	return false
