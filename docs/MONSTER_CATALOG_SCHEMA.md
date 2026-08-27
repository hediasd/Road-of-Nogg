# Monster Catalog Schema

Status: current as of the monster-catalog migration to JSON.

The monster catalog lives at res://data/monsters.json. Its root is an array of
monster reference objects. MonsterReferences loads it through the shared
JsonCatalogLoader and exposes list, getReference(), hasReference(), and
getNames(). reloadCatalog() commits a new catalog only after the entire file
has parsed, normalized, and indexed successfully; failure preserves the last
working catalog.

## Field reference

| Key | Type | Required | Notes |
|---|---|---|---|
| NAME | string | yes | Unique primary key. Empty or duplicate names reject the full reload. |
| STATS | dictionary | yes | Owns every authored base, movement, luck, jump, and growth value. See below. |
| ELEMENTS | array of string | yes | May be empty; each present value must be a supported element other than none. |
| RACE | string | yes | Determines elemental resistance and weakness multipliers. |
| FAMILY | string | no | Defaults to none. |
| SPECIES | string | no | Defaults to none. |
| ARCHETYPE | string | no | Tactical role used by AI scoring where supported. |
| BRAIN | string | yes | CPU controller name. |
| SPELLS | array of arrays of string | yes | Each inner array is a vertical spell set. An empty array is valid. |
| PASSIVES | array of string | no | Passive names owned by the monster. |
| ASCENDS_FROM | string | no | Defaults to an empty string. |
| DESCRIPTION | string | no | Free-text flavor. |

### STATS dictionary

The following integer keys are authored inside STATS:

| Key | Required | Default | Meaning |
|---|---|---:|---|
| HP, ATK, DEF, SPD, MOVE | yes | n/a | Required Level 1 combat and movement values. |
| LUCK | no | 0 | Critical-hit chance input, capped by combat rules. |
| JUMP | no | 1 | Maximum supported elevation step. |
| HP_GROWTH, ATK_GROWTH, DEF_GROWTH | no | 0 | Hundredths of one point gained per level after Level 1. |

All ten keys are written explicitly in the production catalog for easy
authoring and diff review. The loader still supplies the optional defaults for
fixtures and future content tools.

Old top-level stat keys, including BASE_HP, BASE_ATK, and BASE_DEF, are
rejected. There is one schema only: consumers read STATS, while runtime replay
serialization continues to store resolved monster state independently.

## Numeric coercion

Godot JSON numbers do not preserve an integer-specific schema. During reload,
MonsterReferences casts every recognized STATS value to int before publishing
the new catalog. Add future authored integer stats to STAT_DEFAULTS in
MonsterReferences so coercion and defaults remain centralized.

## Validation boundary

JsonCatalogLoader owns file access, JSON parse diagnostics, root/entry shape,
unique non-empty NAME validation, deep copying, and construction of the
constant-time name index. MonsterReferences owns the monster-specific STATS
schema and normalization. RaceReferences uses the same loader and owns
resistance coercion.

Broader cross-catalog semantic validation is not currently automated.
Rebuilding it is tracked in `BACKLOG_LONGTERM.md` under "Build a fresh test
suite".

## Editing the catalog

1. Edit res://data/monsters.json and keep all monster stats under STATS.
2. Launch the game and exercise catalog loading plus affected battle behavior.
3. In a running battle, Ctrl+R hot-reloads the catalog; a rejected reload leaves
   the previous data active.
4. Exported builds include data/*.json through export_presets.cfg.
