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
		},
		# --- NEW SPELLS ---
		{
			"NAME" = "Eschatology",
			"RANGE" = 3, "DAMAGE" = 6,
			"ELEMENT" = "fire",
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
		},
		# --- UTILITY / PLACEHOLDER ---
		{
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
