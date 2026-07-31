class_name BattleCommandResult
extends RefCounted

## Typed outcome for command validation/execution. Resolver-specific details
## remain in action_result because their shape varies by action and effect.

var success: bool = false
var reason: String = ""
var command: BattleCommand
var resolved: bool = false
var acted: bool = false
var skipped: bool = false
var action_result: Dictionary = {}


static func rejected(_reason: String) -> BattleCommandResult:
	var result = BattleCommandResult.new()
	result.reason = _reason
	return result


static func accepted(_command: BattleCommand) -> BattleCommandResult:
	var result = BattleCommandResult.new()
	result.success = true
	result.command = _command
	return result


static func from_dictionary(data: Dictionary) -> BattleCommandResult:
	var result = BattleCommandResult.new()
	result.success = bool(data.get("success", false))
	result.reason = str(data.get("reason", ""))
	var command_data = data.get("command", {})
	if command_data is Dictionary and not command_data.is_empty():
		result.command = BattleCommand.from_dictionary(command_data)
	result.resolved = bool(data.get("resolved", false))
	result.acted = bool(data.get("acted", false))
	result.skipped = bool(data.get("skipped", false))
	result.action_result = data.get("actionResult", {}).duplicate(true)
	return result


func to_dictionary() -> Dictionary:
	var data := {"success": success}
	if not reason.is_empty():
		data["reason"] = reason
	if command != null:
		data["command"] = command.to_dictionary()
	# An accepted validation result has a command but no action payload yet.
	# Execution results always carry one, even for Wait.
	if success and not action_result.is_empty():
		data["resolved"] = resolved
		data["acted"] = acted
		data["skipped"] = skipped
		data["actionResult"] = action_result.duplicate(true)
	return data