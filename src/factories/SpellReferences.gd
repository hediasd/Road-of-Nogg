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
			"NAME" = "Water Splash",
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
		},
		# --- UTILITY / PLACEHOLDER ---
		{
			"NAME" = "Timeoff",
			"TARGET_TYPE" = "single",
			"RANGE" = 4, "DAMAGE" = 0, "HEALS" = true,
			"INFLICTS_STATUS" = "spd_debuff",
			"ELEMENT" = "wood",
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
pass

static func getReference(name):
	for reference in list:
		if(reference["NAME"] == name):
			return reference
	return list.back()
