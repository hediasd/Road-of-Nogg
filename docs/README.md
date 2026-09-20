# Documentation Index

Use this page to find the source of truth instead of searching every document.

| Document | Owns |
|---|---|
| [Project instructions](../AGENTS.md) | Concise operational rules for repository work |
| [Policies](./POLICIES.md) | Engineering guardrails and verification policy |
| [Module map](./MODULE_MAP.md) | Directory ownership, allowed dependencies, and where to make a change |
| [Architecture](./ARCHITECTURE.md) | Current runtime ownership, boundaries, and data flow |
| [Nogg AI architecture](./AI_ARCHITECTURE.md) | AI structure, algorithms, state/forecast contracts, determinism, extension points, and experiment semantics; current behavior and intended changes are labeled separately |
| [Game design](./GAME_DESIGN.md) | Confirmed player-facing mechanics and constraints |
| [UI / UX design](./UI_DESIGN.md) | Battle UI visual language, theme tokens, cursor and input model |
| [VFX design](./VFX_DESIGN.md) | Spell effect contract, authoring conventions, the house motion style for any animation, and the debug harness |
| [Effects](./effects/README.md) | One page per effect profile: what each one does, its constants, and the measurements behind them |
| [Sketches](./sketches/README.md) | Kept design sketches: the few debug artifacts that stayed useful after their work shipped |
| [Critical backlog](../BACKLOG_CRITICAL.md) | Incomplete work that materially affects current gameplay, correctness, or readiness |
| [Long-term backlog](../BACKLOG_LONGTERM.md) | Deferred design, tooling, and maintenance work |
| [Learnings](./LEARNINGS.md) | Verified reusable discoveries and review triggers |
| [Development](./DEVELOPMENT.md) | Commands, Windows safeguards, and completion checks |
| [Spell catalog schema](./SPELL_CATALOG_SCHEMA.md) | Authored spell-data shape and normalization boundary |
| [Reference catalogs](./REFERENCE_CATALOGS.md) | JSON ownership and runtime conversion rules for authored catalogs |
| [World map editor](./WORLDMAP_EDITOR.md) | World-map authoring workflow, document safety, and export boundaries |
| [Hex tileset authoring](./HEX_TILESET_AUTHORING.md) | Starter tilesheet layout and reproducible hex palette recipe |
| [Hex map format](./HEX_MAP_FORMAT.md) | Versioned `.noggmap.json` source envelope, identity, and compatibility contract |
| [Game reference index](../gamerefs/tactical_rpg_turn_systems.md) | Comparative research and aspect studies |
| [Lore](./LORE.md) | World, factions, and narrative canon; see also `lore/` |
| [Monster catalog schema](./MONSTER_CATALOG_SCHEMA.md) | Authored monster-data shape and validation rules |
| [Implementation cycles](./plans/) | Active cycles, each frozen during execution; item findings live in commit messages |

## Authority and updates

Current runtime behavior overrides stale prose. When behavior changes,
update the one document that owns that truth and link to it elsewhere. Avoid
copying whole sections between documents.

Consult [`LEARNINGS.md`](./LEARNINGS.md) before work matching its routing table.
Record a new entry only when the finding is verified, likely to recur, and has a
clear rule or review trigger.
