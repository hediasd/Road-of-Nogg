## PassiveSkillFactory — Creates PassiveSkill instances from the references registry.
## Same pattern as SpellFactory.gd.

class_name PassiveSkillFactory


static func createPassive(passiveName: String) -> PassiveSkill:
	var ref = PassiveSkillReferences.getReference(passiveName)
	if ref.is_empty():
		push_error("PassiveSkillFactory: Cannot create passive '%s' — not found in references." % passiveName)
		return null
	return PassiveSkill.new(ref)
