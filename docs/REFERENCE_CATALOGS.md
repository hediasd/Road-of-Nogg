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
| Elements | `elements.json` | Single elements first: ordered normalized names plus a required, unique two-character uppercase `CODE`, including the `none` sentinel; `list`, `STANDARD`, `CODES`, `code()` and `isValid()` see only these. Then two- and three-element combinations: an entry with `ELEMENTS` and no `CODE`, named by its elements in single-element order joined with `+` (`fire+darkness`), reached through `COMBINATIONS` and the order-insensitive `getCombination()`. |
| Archetypes | `archetypes.json` | Optional integer stat-band values. |
| Passives | `passives.json` | Trigger/effect fields, value, and radius. |
| Status effects | `status_effects.json` | Duration, damage-per-turn, and negative flag. |
| Maps | `maps.json` | Integer heights and JSON coordinate pairs converted to `Vector2i`. |
| Hex battle maps | `battle/maps/<map-id>.json` | Strict tactical topology, mask, semantic terrain, elevation, source identity, and cell metrics. |
| Hex battle scenarios | `battle/scenarios/<scenario-id>.json` | Exact map identity, deterministic parties, controllers, members, and deployment. |

## Inner descriptions

Any entry in a JSON catalog may carry `INNER_DESCRIPTION`: a string for the
creator alone, recording the real-world source of an object rooted in a real
concept, plus any other trivia. The game never shows it.

`JsonCatalogLoader.loadNamedCatalog` enforces this once, for every catalog. A
string is accepted and removed before the entry reaches its wrapper, so no
runtime reference, screen, AI decision or save ever holds it. Any other type
(a number, `null`, an array, an object) rejects the whole reload with a message
naming the entry, and the previous catalog stays live. A new catalog that loads
through `loadNamedCatalog`, an items catalog included, inherits the rule with
no code of its own. To read an inner description, open the JSON file: it is
deliberately not available at runtime.

Taxonomy families and species have no runtime loader, so nothing checks them
at load. `checks/content/probe_inner_description.gd` proves the rule on them,
and on every wrapped catalog, directly.

### Authoring rule (user, 2026-10-02)

An inner description documents **the source only**. When the object is rooted
in a real-world concept, base the entry on its English Wikipedia article
whenever a good one exists, and end with that article's URL. Never explain how
the source links to the object: why a spell is fire/darkness, what its
mechanics evoke, or any reading of the name.

Format: one plain string. Write the source as one or two sentences in your own
words based on the article's lead, then `Wikipedia: <url>`. Any trivia the user
adds later follows as further sentences.

**Pending entries.** When an inner description is owed but cannot be written
now (Wikipedia is unreachable, or the user asked for it to be left pending),
the field holds an instruction for whoever fills it, never an empty string or a
guess:

`PENDING: write the source from English Wikipedia (topic: <topic>). Source only; do not explain the link.`

`<topic>` is the real-world concept the user named, taken from their own words
or the object's existing text. User-written text may come before the
`PENDING:` sentence. A session that reaches a `PENDING:` entry while it can
reach Wikipedia may replace that sentence under the rule above, keeping any
text before it, and lists each replacement in its commit body. An empty
`INNER_DESCRIPTION` means nothing is owed (for example, an element combination
nobody has written about yet); it is not pending.

## Race descriptions

Race sits above family (race → family → species). Every race in
`taxonomy.json` carries a short `DESCRIPTION`, which may be empty; a family
carries one only in the rare case the creator gives it. No code reads the
field. It records what belongs in each race, so a session choosing a default
race has the creator's intent to go on. Race descriptions match the race lines
in `docs/lore/bestiary.md`; keep the two in step when either changes. Look for
pending descriptions on races, not families.

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
- `INNER_DESCRIPTION` is creator-only; see *Inner descriptions* above.
- A failed hot reload preserves the previously live catalog.
- Do not put authored arrays back into GDScript reference classes. Behavior
  registries and resolvers may remain code when they represent executable
  strategy rather than content.
- Exported builds currently include `data/*.json` through `export_presets.cfg`;
  nested `data/maps/**` and `data/scenarios/**` inclusion is verified before the hex runtime ships.
- Cross-catalog gameplay acceptance belongs to the final validation item in the
  active implementation plan.
