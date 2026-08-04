# Spell Catalog Schema

Status: current as of the spell-catalog migration to JSON.

The spell catalog lives at `res://data/spells.json`. Its root is an array of
spell reference objects. `SpellReferences` loads it through `JsonCatalogLoader`,
normalizes spell-domain values, and exposes `list`, `getReference()`,
`hasReference()`, and `getNames()`. `reloadCatalog()` commits the replacement
only after the full file is parsed, normalized, and indexed successfully.

## Required field

| Key | Type | Notes |
|---|---|---|
| `NAME` | string | Unique primary key. Empty or duplicate names reject the reload. |

## Normalized scalar fields

`SpellReferences` supplies the same defaults the runtime spell constructor used
before the JSON migration. Authored values are coerced at the catalog boundary:

| Group | Keys |
|---|---|
| Integers | `RADIUS`, `MIN_RANGE`, `RANGE`, `MAX_HEIGHT_DELTA`, `DAMAGE`, `BUFFS_ATK`, `BUFF_DURATION`, `COOLDOWN`, `SEQUENCE_LEVEL`, `SELF_RADIUS`, `HEAL_AMOUNT` |
| Booleans | `HEALS`, `CAN_TARGET_EMPTY`, `BYPASS_LOS`, `REVERTS_DAMAGE` |
| Strings | `ELEMENT`, `TARGET_TYPE`, `AREA_SHAPE`, `INFLICTS_STATUS`, `REMOVES_STATUS`, `RESONANCE_ELEMENT`, `AOE_TARGETS`, `VFX_PROFILE`, `DESC` |

`CAN_TARGET_EMPTY` is explicit on every spell. For non-self spells it controls
whether an empty reachable center is legally confirmable. It does not remove
that center from the player targeting display. Self and healing spells are
currently `false`; offensive non-self spells are `true`.

`VFX_PROFILE` is optional presentation metadata with no gameplay effect. An
empty or unknown value falls back to the generic spell aura; a recognized value
selects a registered presentation effect without changing damage, targeting,
range, radius, or any other spell rule.

## Collection fields

- `DAMAGE_LINES` is optional. When present it is an array of objects with
  lowercase `damage` (integer) and `element` (string). When omitted, `Spell`
  synthesizes one line from `DAMAGE` and `ELEMENT`; an explicit empty array is
  preserved.
- `EFFECTS` is optional and defaults to `[]`. Every entry is an object with a
  non-empty uppercase `NAME`. Integer effect fields (`DURATION`, stat bonuses,
  and `VALUE`), `DAMAGE_MULTIPLIER`, and `NEGATIVE` are coerced before use.

## Editing and validation

Edit `res://data/spells.json` directly. A rejected hot reload leaves the
previous catalog live. Gameplay semantics remain owned by `Spell`,
`SpellEffectResolver`, command validation, AI, and presentation; this catalog
only defines authored input. Spell construction, atomic reload behavior, and
integrated battle behavior are validated against those owners, not against this
schema.