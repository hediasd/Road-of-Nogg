# Monster Catalog Schema

Status: current. Introduced in Stage 1 of the MonsterReferences JSON migration.

The monster catalog lives at `res://data/monsters.json`, a JSON array of
monster reference objects. `MonsterReferences.gd` loads it at `_static_init()`
and exposes it through `list`, `getReference()`, `hasReference()`, and
`getNames()` — the same API the catalog exposed when it was a hardcoded
GDScript array. `reloadCatalog(path: String = JSON_PATH)` re-reads the file at
runtime (bound to **Ctrl+R** during a battle); a failed reload leaves the
previously loaded catalog untouched.

## Field reference

| Key | Type | Required | Notes |
|---|---|---|---|
| `NAME` | string | yes | Unique across the catalog. Primary key for `getReference()`/`hasReference()`. |
| `HP`, `ATK`, `DEF`, `SPD`, `MOVE` | int | yes | Level 1 base stats. JSON numbers parse as float in Godot; the loader casts these to `int` before exposing them — see "Numeric coercion" below. |
| `LUCK` | int | no (defaults to 0) | Drives critical hit chance only: `min(luck * 1%, 15%)`. No design contract restricts which monsters may carry it (see [GAME_DESIGN.md](GAME_DESIGN.md)). |
| `ELEMENTS` | array of string | yes | Must be valid per `ElementReferences.isValid()` and not `"none"`. A monster can only cast spells whose required elements are all present here. |
| `RACE` | string | yes | Must exist in `RaceReferences`. Determines elemental resistance/weakness multipliers. |
| `FAMILY` | string | no (defaults to `"none"`) | Flavor/grouping label, not mechanically enforced. |
| `BRAIN` | string | yes | CPU behavior controller name (e.g. `TacticalBrain`, `MageBrain`, `SupportBrain`, `BerserkBrain`). |
| `SPELLS` | array of array of string | yes | Each inner array is a "vertical set": at most one spell per sequence Level 1-4, staying on a single element. Max 4 sets per monster. `[]` is valid (no spells). |
| `PASSIVES` | array of string | no (defaults to none) | Must exist in `PassiveSkillReferences`. |
| `ASCENDS_FROM` | string | no (defaults to `""`) | Name of the monster this one ascends from. Validated against the full catalog name set, order-independent (a parent declared later in the file still resolves). |
| `DESCRIPTION` | string | no | Free-text flavor, not validated. |

### Derived fields (do not author these)

`BASE_HP`, `BASE_ATK`, `BASE_DEF`, `HP_GROWTH`, `ATK_GROWTH`, `DEF_GROWTH`,
and `JUMP` are set by the loader from `HP`/`ATK`/`DEF` (or explicit overrides)
and default to `0`/`1` when absent. They exist for the level-growth system
described in `GAME_DESIGN.md`, which is designed but not yet live — every
`*_GROWTH` should stay `0` until that system ships.

## Numeric coercion

Godot's `JSON.parse_string()` returns **every** number as a `float`, including
integer-looking literals like `30`. `MonsterReferences.reloadCatalog()` explicitly
casts `HP`, `ATK`, `DEF`, `SPD`, `MOVE`, and `LUCK` back to `int` immediately
after parsing, before any consumer sees the reference. If you extend the
schema with a new integer stat field, add it to that coercion list in
`MonsterReferences.gd` — omitting it means every reader downstream silently
receives a float where an int is expected.

## Validation

There is no automated catalog validator right now. The previous single
authority on catalog correctness (name uniqueness, race/element/spell/passive
references, spell-set shape, spell-element compatibility, `ASCENDS_FROM`
resolution), `CatalogValidator.gd`, was removed along with the test suite that
was its only caller. Malformed catalog entries currently fail at runtime,
where the consuming code happens to notice, rather than being rejected up
front. Rebuilding this validation is tracked in
[`BACKLOG.md`](./BACKLOG.md).

## Editing the catalog

Edit `res://data/monsters.json` directly, or use the browser-based catalog
panel (Stage 3) to generate a replacement file. After editing:

1. Manually confirm the roster loads and plays correctly — there is no
   automated check to catch unknown races/elements/spells/passives or
   malformed spell sets.
2. In a running build, press **Ctrl+R** to hot-reload without restarting.
3. Exported builds bundle `data/*.json` via `export_presets.cfg`'s
   `include_filter` — a `.json` file is not a Godot resource by default, so
   it must be explicitly included even though `export_filter="all_resources"`
   is set.
