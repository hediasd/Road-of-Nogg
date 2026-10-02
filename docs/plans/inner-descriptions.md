# Inner Descriptions

2026-10-02. **Proposal: do not execute until the user settles the decisions
under "Blocking decisions".** The user wants every authored content object
(spells, elements, two- and three-element combinations, items, and similar) to
carry an inner description: a free-text field for the creator alone. It
records real-world sources when an object is rooted in a real concept, plus
any other trivia. No player-facing screen ever shows it. The proof of concept
is a new fire/darkness spell, *Blood Meridian*, named after Cormac McCarthy's
novel. This cycle does not build an items catalog (none exists yet), does not
add new VFX, and does not write any lore, flavour text, or interpretation the
user has not confirmed.

## Outcome

- Every JSON content catalog accepts an optional string `INNER_DESCRIPTION` on
  each entry. A wrong type rejects the reload. No gameplay, AI, or presentation
  code can read it. A future catalog (items included) gets this for free,
  because the rule lives at the shared loader boundary.
- Element combinations of two and three elements have a catalog of their own,
  so each one can carry an inner description.
- The spells the lore Reference Register already sources carry those sources
  in `INNER_DESCRIPTION`.
- `data/spells.json` has *Blood Meridian*, a Level 4 fire/darkness spell whose
  `INNER_DESCRIPTION` cites the novel.

## Blocking decisions (user)

1. **Field name.** Proposed: `INNER_DESCRIPTION`. Every catalog key is
   UPPER_SNAKE (`DESC`, `DESCRIPTION`), so `InnerDescription` would be the only
   camel-case key.
2. **Combination catalog shape.** Proposed: **sparse**. An entry exists only
   once there is something to record, and a missing entry means "no inner
   description yet". The ten real elements make 45 pairs and 120 triples, so a
   dense catalog is 165 mostly empty entries. Combinations are unordered:
   fire+darkness and darkness+fire are one entry. `none` never takes part.
3. **Reference Register vs. the new field.** `docs/lore/magic_and_relics.md`
   already keeps a "Reference Register" of spell-name sources. Proposed: the
   catalog field becomes the canonical home for sources and trivia. The register
   keeps its rows as the lore-facing index, so the lore tools still find them,
   and its Reference column stays a one-line citation. The alternative is to
   retire the register entirely.
4. **Which catalogs.** Proposed: elements, element combinations, spells, status
   effects, passives, archetypes, monsters, and taxonomy (races, families,
   species). Maps, scenarios, and tilesets are excluded: they are authored
   geometry, and the world map files already have a `DESCRIPTION`.

## Present-state facts an executing agent must not "fix"

- There is no items catalog. Only a placeholder Item plate exists in the HUD.
  Do not create one to have somewhere to put the field.
- *Corallitic Acid Reflux* has no `DESC`, and that is deliberate: the user
  writes descriptions. *Blood Meridian* also ships without a `DESC`.
- `data/elements.json` includes the `none` sentinel. It gets the field like any
  other entry, but never takes part in a combination.
- No tool writes the content catalogs back to disk (checked 2026-10-02: the
  only JSON writers are VFX debug, map editor, and tournament tools). So the
  field cannot be dropped by a round-trip save.

## Items

### INNER-1 — Make `INNER_DESCRIPTION` a creator-only field at the catalog boundary

**Model:** Opus 5 / GPT Sol

**Model rationale:** This item sets a contract on the shared loader that every
current and future catalog inherits. The session has to make two boundary
calls (described below) whose consequences reach probes it does not own, and
the taxonomy's nested families and species do not pass through the named
catalog path the way other entries do. Those are judgement calls on an
architectural boundary, not a mechanical edit.

**Depends on:** user decisions 1 and 4.

**Touches:**
- `content/JsonCatalogLoader.gd`
- `content/RaceReferences.gd`, `content/MonsterReferences.gd` (only if taxonomy
  families/species or monster entries need wrapper-level handling)
- `checks/content/probe_inner_description.gd` (new)
- `checks/manifests/content.json` (new)
- `docs/REFERENCE_CATALOGS.md` (new section "Inner descriptions")
- `docs/SPELL_CATALOG_SCHEMA.md`, `docs/MONSTER_CATALOG_SCHEMA.md` (one row
  each pointing at that section)

**End state:** On every catalog in decision 4, an entry can carry
`INNER_DESCRIPTION` as a string. A non-string value rejects the reload with a
message naming the catalog entry, and the previous catalog stays live. Nothing
outside `content/` and `checks/` mentions the key. `docs/REFERENCE_CATALOGS.md`
states the rule, including that a new catalog inherits it.

**Implementation (brief):** The tension is between *enforcing* "never shown"
and *keeping the field reachable*. One option strips the field from the
runtime reference after validation. That guarantees no HUD or AI code can
ever read it, and it leaves existing probes that compare reference
dictionaries untouched. But any future in-editor viewer would then have to
read the JSON itself. The other option keeps the field in the reference and
relies on a grep audit. Choose one, and record the choice and its reasoning
in the commit body. Whichever you choose, the validation must live once, in
the shared loader, not be copied into each wrapper. Taxonomy families and
species may need explicit coverage. The invariants that must survive are
these: a failed reload preserves the live catalog, a valid catalog with no
`INNER_DESCRIPTION` behaves exactly as before, and wrappers keep owning only
domain coercion.

**Risk:** Stripping a key could disturb a probe that snapshots a reference
dictionary. Run the targeted probes for any wrapper you change.

**Validation:**
- Self-contained: the new probe loads every covered catalog with the field
  present, absent, and wrong-typed, and checks that a rejection preserves the
  live catalog. Run a grep audit that `INNER_DESCRIPTION` appears nowhere under
  `ui/`, `battle/`, `effects/`, `ai/`, `simulation/`, or `worldmap/`. Run the
  headless load check from `AGENTS.md`.

### INNER-2 — Add the element-combination catalog

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Once user decision 2 is settled, the shape is fully
specified: one new JSON file and one new wrapper that mirrors an existing
one. Nothing is left open, and the risk is confined to new files.

**Depends on:** INNER-1, user decision 2.

**Touches:**
- `data/element_combinations.json` (new)
- `content/ElementCombinationReferences.gd` (new, plus its `.uid`)
- `checks/content/probe_element_combinations.gd` (new)
- `checks/manifests/content.json`
- `docs/REFERENCE_CATALOGS.md` (one table row)

**End state:**
- `data/element_combinations.json` is a JSON array. It ships with exactly one
  entry, which is enough to prove the format:
  `{"NAME": "fire+darkness", "ELEMENTS": ["fire", "darkness"], "INNER_DESCRIPTION": ""}`.
- `NAME` is the canonical key: the `ELEMENTS` sorted into `data/elements.json`
  order and joined with `+`.
- `ElementCombinationReferences` mirrors `content/ElementReferences.gd`
  (`list`, `reloadCatalog()`, `_static_init()`). It adds
  `getReference(elements: Array) -> Dictionary`, which is order-insensitive
  and returns `{}` when no entry exists.
- A reload is rejected when an entry has fewer than two or more than three
  elements, an unknown element, `none`, a repeated element, a `NAME` that does
  not equal its canonical key, or the same set as another entry.

**Implementation:** Load through `JsonCatalogLoader.loadNamedCatalog`. Do not
touch `ElementReferences.gd`, `data/elements.json`, `SpellReferences.gd`, or
spell `ELEMENTS` ordering: the order of a spell's elements is a separate
contract and stays as it is. No gameplay code calls the new wrapper.

**Risk:** Low. These are new files only.

**Validation:**
- Self-contained: the new probe covers every rejection case above and checks
  that the lookup is order-insensitive. Run the headless load check.

### INNER-3 — Move the Reference Register's spell sources into `INNER_DESCRIPTION`

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** This copies existing, user-confirmed text from four
register rows into four catalog entries. It needs no invention, and the end
state can be checked against the register literally.

**Depends on:** INNER-1, user decision 3. **Must not run while BERSERK-2 runs:**
both items write `data/spells.json`.

**Touches:**
- `data/spells.json`
- `docs/lore/magic_and_relics.md` (Reference Register section only)

**End state:** *Roses at Summers End*, *Wicker Man*, and *Insatiable Famine*
each carry an `INNER_DESCRIPTION` containing their register Reference text,
plus the Element link where it is not "TBC" or "Not yet recorded". A link
marked *(reading)* keeps that marker. *Corallitic Acid Reflux* gets nothing,
because its source is still TBC. The register's preamble says the catalog
field is the canonical home (per decision 3).

**Implementation:** Copy verbatim. Do not reword, do not add trivia, and do not
fill any TBC. Touch no other spell field.

**Risk:** JSON formatting churn. Keep the file's tab indentation and key order.

**Validation:**
- Self-contained: `python3 -m json.tool data/spells.json` parses the file, and
  the headless load check passes, so `SpellReferences` accepts the reload.
  Diff the three strings against the register.

### INNER-4 — Add *Blood Meridian*

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The gameplay values below copy the existing Level 4
benchmark, so nothing about balance or design is left for the session to
judge. It is one catalog entry plus one register row.

**Depends on:** INNER-3 (same files; run as one lane).

**Touches:**
- `data/spells.json`
- `docs/lore/magic_and_relics.md` (one register row)

**End state:** `data/spells.json` contains:

```json
{
	"CAN_TARGET_EMPTY": true,
	"COOLDOWN": 8,
	"DAMAGE_LINES": [
		{"damage": 4, "element": "fire"},
		{"damage": 3, "element": "darkness"}
	],
	"ELEMENTS": ["fire", "darkness"],
	"INNER_DESCRIPTION": "Source: Cormac McCarthy's novel Blood Meridian, or the Evening Redness in the West (1985).",
	"MAX_HEIGHT_DELTA": 1,
	"NAME": "Blood Meridian",
	"RADIUS": 2,
	"RANGE": 4,
	"SEQUENCE_LEVEL": 4,
	"TARGET_TYPE": "area"
}
```

The Reference Register gains a row:
`| Blood Meridian | FIRE / DARKNESS | 4 | Cormac McCarthy's novel *Blood Meridian, or the Evening Redness in the West* (1985). | TBC |`.

**Implementation:** The spell has no `DESC`, no `VFX` block (the default cube
fallback draws fire and darkness palettes from the damage lines), and no
status. It goes into no monster's kit. Do not invent an element link,
description, or flavour text.

**Risk:** The spell is unreachable in play until a kit carries it, and that is
intended.

**Validation:**
- Self-contained: the headless load check passes, so `SpellReferences`
  accepts the multi-element alignment. A one-line probe or grep shows
  `Blood Meridian` in the catalog with `ELEMENTS == ["fire", "darkness"]` and
  `ELEMENT == "none"`.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | INNER-1 | boundary item; everything depends on it |
| 2 | INNER-2, INNER-3 + INNER-4 (lane) | combination catalog vs. spell catalog and lore register; no shared path. The lane must not overlap BERSERK-2 on `data/spells.json`. |
| — | validation: inline, no deferred checks | |

## Deliberately excluded

- **An items catalog.** The loader-level rule means a future items catalog
  carries `INNER_DESCRIPTION` without extra work.
- **Stripping the field from exported builds.** `data/*.json` ships inside the
  export, so the text is in the build even though no screen shows it. This
  belongs in the backlog before a public release, not here.
- **A kit for *Blood Meridian*.** Smoke Cloud (race Terrorugon, family Smoke
  Fiend) is the only fire+darkness monster. Its one spell set is fire-only, so
  its darkness bar never charges and it could never cast a Level 4
  fire/darkness spell. Giving it a kit needs a darkness set first, which is a
  separate design decision.
- **Backfilling inner descriptions for every existing object.** The user
  writes those as they go.
