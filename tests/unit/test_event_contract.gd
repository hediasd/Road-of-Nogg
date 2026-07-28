## Mechanically enforces the rule in docs/ARCHITECTURE.md: "Add or change events
## by updating BattleEvents, IBattleVisualAdapter, every active adapter, and
## focused event-contract checks together." Reflects over every BattleEvents
## signal and asserts IBattleVisualAdapter declares a matching _on_<signal>
## handler, connects it in connectToEvents(), and disconnects it symmetrically
## in disconnectFromEvents().
##
## This check caught a real gap when written: BattleEvents.resonance_changed
## had no adapter handler and was never connected or disconnected (see
## AUDIT_REMEDIATION_PLAN.md P2-1, wired minimally alongside this test so a
## real gap does not leave this check permanently red).
extends "res://tests/TestCase.gd"


func describe() -> String:
	return "every BattleEvents signal has a symmetrically connected IBattleVisualAdapter handler"


func run() -> void:
	var events = BattleEvents.new()
	var adapter = IBattleVisualAdapter.new()

	## get_signal_list() also returns inherited engine signals (script_changed,
	## property_list_changed, ...); get_script_signal_list() is scoped to the
	## ones BattleEvents itself declares.
	var signalNames: Array[String] = []
	for signalInfo in events.get_script().get_script_signal_list():
		signalNames.append(signalInfo["name"])

	for signalName in signalNames:
		var handlerName := "_on_%s" % signalName
		if not adapter.has_method(handlerName):
			fail("BattleEvents.%s has no matching IBattleVisualAdapter.%s handler" % [signalName, handlerName])

	adapter.connectToEvents(events)
	for signalName in signalNames:
		var handlerName := "_on_%s" % signalName
		if not adapter.has_method(handlerName):
			continue  # Already reported above; avoid a second misleading failure.
		var handler := Callable(adapter, handlerName)
		if not Signal(events, signalName).is_connected(handler):
			fail("connectToEvents() did not connect BattleEvents.%s to %s" % [signalName, handlerName])

	adapter.disconnectFromEvents()
	for signalName in signalNames:
		var handlerName := "_on_%s" % signalName
		if not adapter.has_method(handlerName):
			continue
		var handler := Callable(adapter, handlerName)
		if Signal(events, signalName).is_connected(handler):
			fail("disconnectFromEvents() left BattleEvents.%s connected to %s" % [signalName, handlerName])
