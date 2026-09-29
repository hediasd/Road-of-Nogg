## Typed outcome of BattleSetupConfig.validate().
##
## Setup validation is a runtime boundary, not a serialization edge: the UI, the
## replay runner, and the factory all branch on it, so it is a class rather than
## a Dictionary. The serialized setup snapshot stays a Dictionary — see
## BattleSetupConfig.serialize()/fromDictionary().
class_name BattleSetupValidationResult
extends RefCounted

var success: bool = true
var errors: Array[String] = []


static func ok() -> BattleSetupValidationResult:
	return BattleSetupValidationResult.new()


static func fromErrors(validationErrors: Array[String]) -> BattleSetupValidationResult:
	var result := BattleSetupValidationResult.new()
	result.errors = validationErrors.duplicate()
	result.success = validationErrors.is_empty()
	return result


## Newline-joined errors, the form both the setup UI and assertions want.
func errorText() -> String:
	return "\n".join(errors)
