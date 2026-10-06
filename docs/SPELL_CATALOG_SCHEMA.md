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
| Strings | `ELEMENT`, `TARGET_TYPE`, `AREA_SHAPE`, `INFLICTS_STATUS`, `REMOVES_STATUS`, `RESONANCE_ELEMENT`, `AOE_TARGETS`, `VFX_PROFILE` (legacy), `DESC` |
| Objects | `VFX` (presentation only; see below) |
| Creator-only | `INNER_DESCRIPTION`: validated and removed at load, never published. See [Inner descriptions](./REFERENCE_CATALOGS.md#inner-descriptions). |

`CAN_TARGET_EMPTY` is explicit on every spell. For non-self spells it controls
whether an empty reachable center is legally confirmable. It does not remove
that center from the player targeting display. Self and healing spells are
currently `false`; offensive non-self spells are `true`.

### `VFX`: the presentation spec

`VFX` is an optional object of presentation-only settings: which effect plays
and how it adapts to the cast. Gameplay never reads it; `SpellReferences`
passes it through untouched. `SpellVfxSpec` (`effects/`)
parses it, fills defaults, and records problems instead of failing. Its
`ASPECTS` table is the vocabulary below, so a later aspect is one row there
plus the effects that read it.

| Key | Values | Default | Meaning |
| --- | --- | --- | --- |
| `PROFILE` | an active catalog profile id | the role fallback below | Which effect plays. |
| `SPREAD` | `centre`, `each_target` | `centre` | One effect at the cast centre (around the unit there, or a default body on an empty cell), or one composition around every affected unit, in one playback. |
| `ANCHOR` | `target`, `caster_front` | `target` | `caster_front` places the effect one cell in front of the caster. Units have no facing: "front" is the direction to the nearest living hostile, ties to the lowest unit id. |
| `AREA_SCALING` | `spread`, `none` | the profile's own: area-bound profiles spread, others do not | `spread` fills the affected cells with the same cubes placed wider; `none` keeps the authored size. Cube sizes never change. |
| `RANGE_SCALING` | `travel`, `fixed` | the profile's own: profiles with travel beats stretch | `travel` lengthens only the travel beats by `clamp(cells / 4, 0.75, 1.5)`; `fixed` keeps one duration at every distance. |
| `ELEMENTS` | array of element names | `ELEMENT`, else the distinct `DAMAGE_LINES` elements, else `none` | The palettes the effect draws in. With two or more, cubes alternate between them. |

```json
"VFX": {
	"PROFILE": "cube_intercepting_guard",
	"SPREAD": "each_target"
}
```

An unknown key, a value outside the vocabulary, a wrong type, or authoring both
`VFX` and the legacy `VFX_PROFILE` is an error the VFX contract probe reports;
presentation keeps the default for that aspect.

### A spell's elements always match its damage lines

A spell's declared element and the elements of its `DAMAGE_LINES` are always
the same set, in both directions. The user set this as an unconditional rule on
2026-09-27, and `SpellReferences` enforces it at load: a spell that breaks it
rejects the whole reload.

- **One element:** author `ELEMENT`. Every damage line must carry that element.
  A spell without `DAMAGE_LINES` gets one line of that element, so it is
  aligned by construction.
- **Two or more elements:** author the top-level `ELEMENTS` array instead of
  `ELEMENT`, listing the elements in the order their damage lines first use
  them. `DAMAGE_LINES` must carry exactly those elements. Such a spell never
  collapses to one element. `Eschatology` (fire/light), `Feather Time`
  (steel/wind), `Magenta Reduction` (water/fire), and `Wicker Man`
  (light/wood) are the current examples.
- A spell that damages in several elements without declaring `ELEMENTS`, or
  declares elements its lines do not carry, is rejected. So is one that authors
  both `ELEMENT` and `ELEMENTS`, lists fewer than two elements in `ELEMENTS`,
  or lists an element there that is repeated or missing from
  `data/elements.json`.

After loading, every reference carries `ELEMENTS` (the full list; empty for an
elementless spell) and `ELEMENT` (the single element, or `none` when there are
several). The top-level `ELEMENTS` is not the presentation-only `VFX.ELEMENTS`
above. That key is still derived from the damage lines by default, so a
multi-element effect shows every element's palette. Resonance follows the same
list: see *Taxonomy and Resonance* in [`GAME_DESIGN.md`](./GAME_DESIGN.md).

`VFX_PROFILE` is the legacy flat form, still read for a spell with no `VFX`
block. No spell carries it today. During the cube-only VFX phase an active cube
profile is preserved; an empty, unknown, or parked value routes by spell role
to Elemental Cube Crownburst (offensive) or Spiral Invocation
(support/utility). None of this ever changes damage, targeting, range, radius,
or any other spell rule. The spells that carry a `VFX` block and their settings
are listed on each cube placeholder family page under
[`effects/`](./effects/README.md).

## Collection fields

- `DAMAGE_LINES` is optional. When present it is an array of objects with
  lowercase `damage` (integer) and `element` (string). When omitted, `Spell`
  synthesizes one line from `DAMAGE` and `ELEMENT`; an explicit empty array is
  preserved.
- `ELEMENTS` is optional and only for spells with two or more elements; see
  *A spell's elements always match its damage lines*. The loader fills it on
  every reference.
- `EFFECTS` is optional and defaults to `[]`. Every entry is an object with a
  non-empty uppercase `NAME`. Integer effect fields (`DURATION`, stat bonuses,
  and `VALUE`), `DAMAGE_MULTIPLIER`, and `NEGATIVE` are coerced before use.

## Editing and validation

Edit `res://data/spells.json` directly. A rejected hot reload leaves the
previous catalog live.

Spell names follow the naming conventions in
[`lore/magic_and_relics.md`](./lore/magic_and_relics.md#spell-names) (a single
word at Level 1, a poetic sentence or niche real-world reference at Level 4).
When a new spell's name carries a reference, document the source in the
spell's `INNER_DESCRIPTION` in the same commit as the catalog entry, following
the authoring rule in [Inner descriptions](./REFERENCE_CATALOGS.md#inner-descriptions).

Gameplay semantics remain owned by `Spell`,
`SpellEffectResolver`, command validation, AI, and presentation; this catalog
only defines authored input. Spell construction, atomic reload behavior, and
integrated battle behavior are validated against those owners, not against this
schema.
