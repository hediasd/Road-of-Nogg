# Inner Descriptions

2026-10-02, revised the same day. **Proposal: do not execute INNER-3 until the
user confirms its spell list (see "Blocking decision").** The user wants every
authored content object (spells, elements and element combinations, items, and
similar) to carry an inner description. It is a free-text field for the creator
alone, recording the real-world source of an object rooted in a real concept,
plus any other trivia. No player-facing screen ever shows it. It replaces the
lore Reference Register, which the user does not trust. The proof of concept is
a new fire/darkness spell, *Blood Meridian*, named after Cormac McCarthy's
novel. This cycle does not build an items catalog (none exists yet), add new
VFX, or write lore, flavour text, or any explanation of how a source links to an
object.

## Outcome

- Every JSON content catalog accepts an optional string `INNER_DESCRIPTION` on
  each entry. A wrong type rejects the reload, and no player-facing code reads
  it. A future catalog (items included) inherits the rule, because it lives at
  the shared loader boundary.
- `data/elements.json` is the one element catalog. It holds single elements,
  all 45 two-element combinations, and three placeholder three-element
  combinations, each with an `INNER_DESCRIPTION` slot.
- The Reference Register is gone, and spell sources live in
  `INNER_DESCRIPTION`.
- `data/spells.json` has *Blood Meridian*, a Level 4 fire/darkness spell whose
  `INNER_DESCRIPTION` documents the novel.
- A standing authoring rule, recorded in `AGENTS.md` and
  `docs/REFERENCE_CATALOGS.md`, governs every inner description from now on.

## The authoring rule (user, 2026-10-02)

An inner description documents **the source only**. When the object is rooted
in a real-world concept, base the entry on its English Wikipedia article
whenever a good one exists, and end with that article's URL. Never explain how
the source links to the object: why a spell is fire/darkness, what its
mechanics evoke, or any reading of the name. If Wikipedia cannot be reached,
write only the source the user stated, add no URL, and say in the commit body
that Wikipedia was not checked.

Format: one plain string. Write the source as one or two sentences in your own
words based on the article's lead, then `Wikipedia: <url>`. Any trivia the user
adds later follows as further sentences.

## Blocking decision (user)

**Which existing spells get a sourced inner description in INNER-3?** The
register is not trusted, so INNER-3 does not copy it. It sources only the spells
the user lists. Candidates whose names are recognisable real-world references
are *Roses at Summers End*, *Wicker Man*, *Insatiable Famine*, *Eschatology*,
*Holy Cross*, *Aurora Veil*, *Solar Storm*, and *Corallitic Acid Reflux*. Any
spell the user does not name keeps no inner description.

## Defaults taken (the user may overrule)

- The field is named `INNER_DESCRIPTION`, because every catalog key is
  UPPER_SNAKE.
- The field is covered on elements (combinations included), spells, status
  effects, passives, archetypes, monsters, and taxonomy (races, families,
  species). Maps, scenarios, and tilesets are excluded.
- The three placeholder triples are `fire+darkness+light`, `ice+water+wind`,
  and `wood+earth+thunder`. They were chosen only so that the triples, between
  them, cover nine of the ten elements.

## Present-state facts an executing agent must not "fix"

- There is no items catalog. Only a placeholder Item plate exists in the HUD.
- *Corallitic Acid Reflux* has no `DESC`, and that is deliberate: the user
  writes descriptions. *Blood Meridian* ships without a `DESC` too.
- `ElementReferences` has exactly two consumers: `SpellReferences` calls
  `isValid()`, and `ui/HexUnitFacts.gd` calls `code()`. Both mean a single
  element. A combination must never satisfy either. `effects/SpellVfxSpec.gd`
  validates against its own `KNOWN_ELEMENTS` and is out of scope.
- No tool writes the content catalogs back to disk, so the new field cannot be
  dropped by a round-trip save.
- `docs/plans/berserk-status.md` (not started as of 2026-10-02) tells BERSERK-2
  to add a register row for *Summit Fever*. INNER-3 removes that instruction
  only if that cycle still has no commits; see INNER-3.

## Items

### INNER-1 — Make `INNER_DESCRIPTION` a creator-only field at the catalog boundary

**Model:** Opus 5 / GPT Sol

**Model rationale:** This item sets a contract on the shared loader that every
current and future catalog inherits. It has to settle how "never shown" is
enforced, and that choice reaches probes it does not own. The taxonomy's nested
families and species also do not pass through the named-catalog path the way
other entries do. Those are boundary judgements, not mechanical edits.

**Depends on:** —

**Touches:**
- `content/JsonCatalogLoader.gd`
- `content/RaceReferences.gd`, `content/MonsterReferences.gd` (only if
  families, species or monsters need wrapper-level handling)
- `checks/content/probe_inner_description.gd` (new, with `.uid`)
- `checks/manifests/content.json` (new)
- `docs/REFERENCE_CATALOGS.md` (new section "Inner descriptions")
- `docs/SPELL_CATALOG_SCHEMA.md`, `docs/MONSTER_CATALOG_SCHEMA.md` (one row
  each pointing at that section)
- `AGENTS.md` (one bullet under "Working safely")

**End state:** Every catalog under "Defaults taken" accepts `INNER_DESCRIPTION`
as a string. A non-string value rejects the reload with a message naming the
entry, and the previous catalog stays live. No player-facing code can read the
field. `docs/REFERENCE_CATALOGS.md` states the contract and the authoring rule
above, word for word. `AGENTS.md` gains one bullet: inner descriptions document
only the source, are based on Wikipedia where a good article exists, and never
explain the link. The bullet points to `docs/REFERENCE_CATALOGS.md`.

**Implementation (brief):** The tension is between *enforcing* "never shown"
and *keeping the field reachable*. One option strips the field from the runtime
reference after validation. That guarantees no HUD or AI code can read it, and
reference-dictionary snapshots stay unchanged. Its cost is that a future
in-editor viewer would have to read the JSON itself. The other option keeps the
field and relies on a grep audit. Choose one and record why in the commit body.
Either way, validation lives once, in the shared loader, not in each wrapper.
These invariants must survive: a failed reload preserves the live catalog; a
catalog without the field behaves exactly as before; wrappers keep owning only
domain coercion.

**Risk:** Stripping a key could disturb a probe that snapshots a reference
dictionary. Run the targeted probes for any wrapper you change.

**Validation:**
- Self-contained: the new probe loads each covered catalog with the field
  present, absent, and wrong-typed, and checks that a rejection preserves the
  live catalog. A grep audit confirms `INNER_DESCRIPTION` appears nowhere under
  `ui/`, `battle/`, `effects/`, `ai/`, `simulation/`, or `worldmap/`. The
  headless load check from `AGENTS.md` passes.

### INNER-2 — Hold single, paired and tripled elements in one element catalog

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The data shape, the generation rule, the API and the
exact list of rejections are all stated below, and the only consumers are
named. What is left is careful mechanical work in two files, with a contract
whose breakage a probe catches literally.

**Depends on:** INNER-1.

**Touches:**
- `data/elements.json`
- `content/ElementReferences.gd`
- `checks/content/probe_element_catalog.gd` (new, with `.uid`)
- `checks/manifests/content.json`
- `docs/REFERENCE_CATALOGS.md` (the Elements row only)

**End state:**
- The existing 11 single-element entries keep their `NAME`, `CODE` and order.
  Each gains `"INNER_DESCRIPTION": ""`.
- 45 pair entries follow them, one per unordered pair of the ten elements other
  than `none`. Then come the three placeholder triples from "Defaults taken".
  A combination entry has exactly `NAME`, `ELEMENTS`, and
  `"INNER_DESCRIPTION": ""`, with no `CODE`. Example:
  `{"NAME": "fire+darkness", "ELEMENTS": ["fire", "darkness"], "INNER_DESCRIPTION": ""}`.
- The canonical order is the order of the single elements in the file (fire,
  ice, wood, steel, darkness, light, earth, water, thunder, wind). A
  combination's `ELEMENTS` is in that order, and its `NAME` is those elements
  joined with `+`. Pairs are listed in that order too: `fire+ice`,
  `fire+wood`, …, `thunder+wind`.
- `ElementReferences`:
  - `list`, `STANDARD`, `CODES`, `code()` and `isValid()` stay single-element
    only, with unchanged behaviour. `isValid("fire+darkness")` returns false.
  - New `static var COMBINATIONS: Array` holds the combination entries.
  - New `static func getCombination(elements: Array) -> Dictionary` is
    order-insensitive and case-insensitive, and returns `{}` when no entry
    exists.
- The reload is rejected, and the previous catalog stays live, when a
  combination has fewer than 2 or more than 3 elements, names an unknown
  element or `none`, repeats an element, carries a `CODE`, has a `NAME` that is
  not its canonical key, or duplicates another entry's set. It is also
  rejected when a single element appears after the first combination.

**Implementation:** An entry with an `ELEMENTS` key is a combination; one
without is a single element. Generate the 45 pairs with a throwaway script, not
by hand. Do not touch `SpellReferences.gd`, `ui/HexUnitFacts.gd`,
`effects/SpellVfxSpec.gd`, or the spell-level `ELEMENTS` ordering contract. No
gameplay code calls `getCombination` yet.

**Risk:** If a combination leaks into `STANDARD`, every spell validation and
HUD element code changes meaning. The probe asserts that `STANDARD` is exactly
the 11 single elements.

**Validation:**
- Self-contained: the new probe asserts `STANDARD.size() == 11`,
  `COMBINATIONS.size() == 48`, and order-insensitive lookup, and hits every
  rejection case. The headless load check passes, which proves
  `SpellReferences` still accepts every spell.

### INNER-3 — Retire the Reference Register and source the confirmed spells

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** Once the user lists the spells, each entry follows the
authoring rule mechanically: read the article, then write a source sentence and
the URL. It involves no interpretation (the rule forbids explanation), and the
doc edits are deletions plus one pointer.

**Depends on:** INNER-1, the blocking decision. **Must not run while BERSERK-2
runs:** both write `data/spells.json`.

**Touches:**
- `data/spells.json`
- `docs/lore/magic_and_relics.md` (delete the "Reference Register" section;
  keep "Naming by Level")
- `docs/SPELL_CATALOG_SCHEMA.md` (the paragraph that sends new spells to the
  register)
- `docs/plans/berserk-status.md` (only the sentence asking BERSERK-2 for a
  register row, and only if `git log --grep="Plan-Item: BERSERK"` is empty;
  otherwise leave the file alone and tell the user)

**End state:**
- Each spell the user listed carries an `INNER_DESCRIPTION` written under the
  authoring rule.
- The register section no longer exists.
- `docs/SPELL_CATALOG_SCHEMA.md` tells authors to document a referenced name's
  source in the spell's `INNER_DESCRIPTION`, and links to the authoring rule.
- `grep -rn "Reference Register" docs .claude AGENTS.md` finds nothing outside
  `docs/plans/`.

**Implementation:** Do not copy register text, because it is untrusted. Do not
add an element link or any interpretation. Touch no other spell field.

**Risk:** JSON formatting churn. Keep the tab indentation and key order.

**Validation:**
- Self-contained: `python3 -m json.tool data/spells.json` parses the file, the
  headless load check passes, and the grep above is clean. The commit body
  lists each spell with the article it used, or says Wikipedia was not reached.

### INNER-4 — Add *Blood Meridian*

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The gameplay values copy the existing Level 4 benchmark,
and the inner description follows the fixed rule, so there is no balance or
design judgement left. It is one catalog entry.

**Depends on:** INNER-3 (same file; run as one lane).

**Touches:** `data/spells.json`

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
	"INNER_DESCRIPTION": "<per the authoring rule>",
	"MAX_HEIGHT_DELTA": 1,
	"NAME": "Blood Meridian",
	"RADIUS": 2,
	"RANGE": 4,
	"SEQUENCE_LEVEL": 4,
	"TARGET_TYPE": "area"
}
```

The `INNER_DESCRIPTION` names the novel's full title (*Blood Meridian, or the
Evening Redness in the West*), Cormac McCarthy, and 1985, plus at most one
further sentence drawn from the article's lead. It ends with
`Wikipedia: https://en.wikipedia.org/wiki/Blood_Meridian`. If Wikipedia is
unreachable, it is only `Source: Blood Meridian, or the Evening Redness in the
West, a 1985 novel by Cormac McCarthy.`, and the commit body says Wikipedia was
not checked.

**Implementation:** The spell has no `DESC`, no `VFX` block (the default cube
fallback draws fire and darkness palettes from the damage lines), and no
status. It goes into no monster's kit. Write no element link and no flavour
text.

**Risk:** The spell is unreachable in play until a kit carries it, and that is
intended.

**Validation:**
- Self-contained: the headless load check passes, so `SpellReferences` accepts
  the multi-element alignment. A grep shows the entry with
  `ELEMENTS == ["fire", "darkness"]`.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | INNER-1 | boundary item; everything depends on it |
| 2 | INNER-2, INNER-3 + INNER-4 (lane) | element catalog and its wrapper vs. spell catalog and spell/lore docs; no shared path. The lane must not overlap BERSERK-2 on `data/spells.json`. |
| — | validation: inline, no deferred checks | |

## Deliberately excluded

- **An items catalog.** The loader-level rule means a future items catalog
  carries `INNER_DESCRIPTION` without extra work.
- **Stripping the field from exported builds.** `data/*.json` ships inside the
  export, so the text is in the build even though no screen shows it. This
  belongs in the backlog before a public release.
- **A kit for *Blood Meridian*.** Smoke Cloud (race Terrorugon, family Smoke
  Fiend) is the only fire+darkness monster. Its one spell set is fire-only, so
  its darkness bar never charges and it could never cast a Level 4
  fire/darkness spell. A kit needs a darkness set first, which is a separate
  design decision.
- **All 120 triples, and gameplay use of combinations.** The triples are
  placeholders. Nothing reads combinations yet.
- **Backfilling inner descriptions beyond the INNER-3 list.** The user adds the
  rest as they go.
