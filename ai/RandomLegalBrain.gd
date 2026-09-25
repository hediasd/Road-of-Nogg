## Plays a legal move chosen at random. A fuzzer, never an opponent.
##
## Why it exists: every shipped brain is deterministic and the only random draw in a battle is the
## critical-hit roll, so a championship over twenty seeds replayed one fight with five decision
## sequences, and five seeds under the current rules replayed it with one (`docs/DEVELOPMENT.md`).
## A corpus like that says almost nothing about whether the rules hold -- it says one path through
## them holds. Random legal play walks the rest: withdrawing commanders, spells cast from odd
## tiles, units that wait with an enemy in reach, sides that empty in an unusual order.
##
## It is not a difficulty setting and not a baseline to measure brains against. A random policy
## loses to every real one, and win rates against it measure nothing about balance.
##
## Determinism is preserved: the draw comes from `BattleState.rng`, the same seeded generator the
## crit roll uses, so a random battle at one seed replays byte for byte. That also means this brain
## consumes RNG draws, so a run with it and a run without it diverge after the first decision --
## which is the point, and why a random corpus must never be pooled with a policy corpus. The
## corpus records the brain that drove each member, so it always says which it is.

class_name RandomLegalBrain
extends EntityBrain


## Lets the side deliberation recognise a fuzzing brain without importing this class. Scoring one
## unit's random pick against another's is meaningless -- and worse than meaningless, because a
## wait scores 0 while a random real move often scores below it, so the best-scored proposal of a
## side playing at random is a wait almost every time. The side picks its actor at random instead.
func playsAtRandom() -> bool:
	return true


## The evaluator still enumerates what is legal -- that is the part worth reusing, because it asks
## the simulator rather than guessing -- and the choice among those candidates becomes a draw.
func beginDeliberation(monsterID: int) -> CommandDeliberation:
	var deliberation := super.beginDeliberation(monsterID)
	if deliberation != null:
		deliberation.useUniformRandomChoice(rngFor(state, monsterID))
	return deliberation


## A generator seeded out of the state itself, NOT `state.rng`.
##
## Deliberation is a pure query -- `CommandDeliberation` says so at the top of the file, and
## `StateRevision` enforces it by treating `rng.state` as part of the state. Drawing from
## `state.rng` therefore invalidated the very deliberation making the draw: the side threw the
## proposal away as stale and waited instead. That is how the first version of this brain came to
## play 24,000 consecutive waits.
##
## Seeding from `battleSeed`, the unit and the length of the history makes each draw a pure
## function of the position, so a replay at one seed reproduces it exactly while nothing observable
## changes. The history length is what keeps successive decisions from drawing the same index.
static func rngFor(battleState: BattleState, monsterID: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([battleState.battleSeed, monsterID, battleState.history.size()])
	return rng
