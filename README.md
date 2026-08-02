# Road of Nogg

A tactical RPG project built with Godot 4.4.

## Runtime

- Default scene: `scenes/Battle25D.tscn`
- Canonical simulation: `src/battle_sim/BattleSimulator.gd`
- Presentation controller: `src/systems/BattlePresentationController.gd`
- Playable setup: CPU vs CPU or Player vs CPU, map/team dropdowns, seeded defaults

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
