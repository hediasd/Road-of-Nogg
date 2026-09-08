# Road of Nogg

A tactical RPG project built with Godot 4.4.

## Runtime

- Default scene: `scenes/battle/HexBattle.tscn`
- Canonical simulation: `src/battle_sim/BattleSimulator.gd`
- Scene controller: `src/systems/hex_battle/HexBattleController.gd`
- Playable setup: choose an authored scenario and a seed; parties activate in
  turn and their members act in the order you pick
- Headless demo: `godot --headless --script res://scripts/demo_battle.gd` runs a
  full CPU-vs-CPU party battle through the same runtime

## The square battle

The pre-hex square battle is preserved as an independently runnable reference
under `references/square-battle/`, not as live code. It has its own source
package, per-file manifest, reconstruction script and launch instructions; see
`references/square-battle/README.md`. Nothing in the live tree depends on it,
and nothing in it is maintained alongside the hex battle.

## Documentation

Start with the [documentation index](./docs/README.md). It links the current
architecture, game design, active playable-battle plan, development commands,
backlog, durable learnings, and comparative game references.

## Verification

There is no automated test suite or check runner in this repository right now;
the previous suite and its runners were removed to be rebuilt fresh. Verify
changes by running the game manually until a new suite lands — see
[`docs/DEVELOPMENT.md`](./docs/DEVELOPMENT.md) for manual launch notes and
Windows-specific safeguards, and [`docs/POLICIES.md`](./docs/POLICIES.md) for
the current verification policy.
