# Documentation Index

Use this page to find the source of truth instead of searching every document.

| Document | Owns |
|---|---|
| [Project instructions](../AGENTS.md) | Concise operational rules for repository work |
| [Policies](./POLICIES.md) | Engineering guardrails and verification policy |
| [Module map](./MODULE_MAP.md) | Directory ownership, allowed dependencies, and where to make a change |
| [Architecture](./ARCHITECTURE.md) | Current runtime ownership, boundaries, and data flow |
| [Game design](./GAME_DESIGN.md) | Confirmed player-facing mechanics and constraints |
| [UI / UX design](./UI_DESIGN.md) | Battle UI visual language, theme tokens, cursor and input model |
| [VFX design](./VFX_DESIGN.md) | Spell effect contract, authoring conventions, and the debug harness |
| [Backlog](./BACKLOG.md) | Durable future work not in the active task |
| [Learnings](./LEARNINGS.md) | Verified reusable discoveries and review triggers |
| [Development](./DEVELOPMENT.md) | Commands, Windows safeguards, and completion checks |
| [Spell catalog schema](./SPELL_CATALOG_SCHEMA.md) | Authored spell-data shape and normalization boundary |
| [Reference catalogs](./REFERENCE_CATALOGS.md) | JSON ownership and runtime conversion rules for authored catalogs |
| [Game reference index](../gamerefs/tactical_rpg_turn_systems.md) | Comparative research and aspect studies |

## Authority and updates

Current runtime behavior overrides stale prose. When behavior changes,
update the one document that owns that truth and link to it elsewhere. Avoid
copying whole sections between documents.

Consult [`LEARNINGS.md`](./LEARNINGS.md) before work matching its routing table.
Record a new entry only when the finding is verified, likely to recur, and has a
clear rule or review trigger.
