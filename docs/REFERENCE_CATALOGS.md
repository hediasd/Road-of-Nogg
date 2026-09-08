# Reference Catalogs

Status: current as of the reference-catalog migration to JSON.

Authored gameplay content belongs in JSON under `res://data/`. Each catalog is
loaded through `JsonCatalogLoader`, which owns file access, parse diagnostics,
entry shape, unique non-empty names, deep copies, and constant-time name
indexing. The small GDScript wrapper for each catalog owns only domain coercion
and runtime representation conversion.

| Catalog | JSON file | Wrapper responsibility |
|---|---|---|
| Monsters | `monsters.json` | Nested `STATS` coercion and monster metadata defaults. |
| Races | `taxonomy.json` (`races`) | Resistance multiplier coercion. |
| Spells | `spells.json` | Spell scalars, damage lines, and effect definitions. |
| Elements | `elements.json` | Ordered normalized names plus a required, unique two-character uppercase `CODE`; includes the `none` sentinel. |
| Archetypes | `archetypes.json` | Optional integer stat-band values. |
| Passives | `passives.json` | Trigger/effect fields, value, and radius. |
| Status effects | `status_effects.json` | Duration, damage-per-turn, and negative flag. |
| Maps | `maps.json` | Integer heights and JSON coordinate pairs converted to `Vector2i`. |
| Hex battle maps | `battle/maps/<map-id>.json` | Strict tactical topology, mask, semantic terrain, elevation, source identity, and cell metrics. |
| Hex battle scenarios | `battle/scenarios/<scenario-id>.json` | Exact map identity, deterministic parties, controllers, members, and deployment. |

## Map coordinates

JSON has no Godot vector type. `maps.json` represents `SIZE` and deployment
slots as `[x, y]` pairs. `MapReferences` converts them to `Vector2i` before
publishing references, so `MapFactory` and setup validation retain their
existing runtime contract.

## Hex battle resources

Hex battle map and scenario files each contain a one-entry named array so they
retain the shared `JsonCatalogLoader` file and index boundary while remaining
independently addressable resources. Both formats start at `FORMAT_VERSION: 1`.

A map declares `GRID_KIND: "hex_flat"`, `COORDINATES: "odd_q_offset"`, and
`SURFACE_MODEL: "single"`. `SIZE` is the rectangular storage extent;
`VALID_MASK` is one `0`/`1` string per row and owns the actual cells. The map
also declares positive `CELL_METRICS` (`WIDTH`, `HEIGHT`, `HEIGHT_STEP`), exact
source identity, semantic `TERRAIN_DEFINITIONS`, one `DEFAULT_SURFACE`, and
unique `CELL_OVERRIDES`. Terrain definitions separate enter, pass-through,
stop, movement cost, movement termination, line-of-sight blocking, and the
legacy matrix state code. Art and tileset identifiers do not belong in these
terrain IDs. Version 1 supports one standable surface per valid cell.

A scenario declares its own revision and seed, then identifies the map by
resource path, map ID, map revision, and source fingerprint. `PARTIES` carry
positive deterministic party/team/commander IDs, a `player` or `cpu`
controller, and one or more members. Each member carries a globally unique
positive ID, an existing monster catalog name, positive level, and `[x, y]`
deployment cell. Factories reject missing resources, mismatched identity,
unknown content, duplicate membership, invalid commanders, masked or blocked
deployment, and overlap before state construction.

Files whose names begin with `technical_` may set `SOURCE.HEADLESS_ONLY` to
true and leave `VISUAL_SCENE_PATH` empty. Production resources require a
loadable visual scene tied to the same source identity.

## Editing rules

- Catalog roots are arrays of named objects; names must be unique.
- A failed hot reload preserves the previously live catalog.
- Do not put authored arrays back into GDScript reference classes. Behavior
  registries and resolvers may remain code when they represent executable
  strategy rather than content.
- Exported builds currently include `data/*.json` through `export_presets.cfg`;
  nested `data/battle/**` inclusion is verified before the hex runtime ships.
- Cross-catalog gameplay acceptance belongs to the final validation item in the
  active implementation plan.
