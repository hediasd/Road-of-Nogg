## Typed data returned by a one-command detached forecast.
extends RefCounted

var actor_id: int = -1
var sample_id: int = 0
var rng_mode: String = ""
var horizon: String = "one_command"
var accepted: bool = false
var resolved: bool = false
var reason: String = ""
var command_result: Dictionary = {}
var changes: Array[Dictionary] = []
var events: Array[Dictionary] = []
var cost: Dictionary = {}
