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
| Elements | `elements.json` | Ordered normalized element-name list. |
| Archetypes | `archetypes.json` | Optional integer stat-band values. |
| Passives | `passives.json` | Trigger/effect fields, value, and radius. |
| Status effects | `status_effects.json` | Duration, damage-per-turn, and negative flag. |
| Maps | `maps.json` | Integer heights and JSON coordinate pairs converted to `Vector2i`. |

## Map coordinates

JSON has no Godot vector type. `maps.json` represents `SIZE` and deployment
slots as `[x, y]` pairs. `MapReferences` converts them to `Vector2i` before
publishing references, so `MapFactory` and setup validation retain their
existing runtime contract.

## Editing rules

- Catalog roots are arrays of named objects; names must be unique.
- A failed hot reload preserves the previously live catalog.
- Do not put authored arrays back into GDScript reference classes. Behavior
  registries and resolvers may remain code when they represent executable
  strategy rather than content.
- Exported builds include `data/*.json` through `export_presets.cfg`.
- Cross-catalog gameplay acceptance belongs to the final validation item in the
  active implementation plan.
