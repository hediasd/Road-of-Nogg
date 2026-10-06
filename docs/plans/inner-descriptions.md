# Inner Descriptions

2026-10-02, revised twice the same day. The user wants every authored content
object (spells, elements and element combinations, items, and similar) to carry
an inner description: a free-text field for the creator alone, recording the
real-world source of an object rooted in a real concept, plus any other trivia.
No player-facing screen ever shows it. It replaces the lore Reference Register,
which the user does not trust. The proof of concept is a new fire/darkness
spell, *Blood Meridian*, named after Cormac McCarthy's novel. On the same day
the user dissolved every other cycle. Their medium and large unbuilt work went
to `BACKLOG.md`, and the one small leftover, the damage-number arc's last two
steps, is folded in here as INNER-5. This cycle does not build an items catalog
(none exists), add new VFX, or write lore, flavour text, or any explanation of
how a source links to an object.

## Outcome

- Every JSON content catalog accepts an optional string `INNER_DESCRIPTION` on
  each entry. A wrong type rejects the reload, and no player-facing code reads
  it. A future catalog (items included) inherits the rule, because it lives at
  the shared loader boundary.
- `data/elements.json` is the one element catalog. It holds single elements,
  all 45 two-element combinations, and three placeholder three-element
  combinations, each with an `INNER_DESCRIPTION` slot.
- The Reference Register is gone. *Wicker Man*, *Eschatology*, *Solar Storm*,
  and *Insatiable Famine* carry pending inner descriptions.
- `data/spells.json` has *Blood Meridian*, a Level 3 fire/darkness spell with a
  sourced or pending inner description.
- A standing authoring rule, recorded in `AGENTS.md` and
  `docs/REFERENCE_CATALOGS.md`, governs every inner description from now on.
- A damage number answers the impact flash instead of arriving with it, and a
  multi-hit attack's numbers either overlap in rhythm or are recorded as
  something the queue cannot express.

## The authoring rule (user, 2026-10-02)

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
text before it, and lists each replacement in its commit body. An empty `INNER_DESCRIPTION` means nothing is
owed (for example, the element slots below); it is not pending.

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
- *Insatiable Famine*'s player-facing `DESC` begins "Inspired by the curse of
  Erysichthon." That is source text in a visible field. On 2026-10-03 the user
  asked for it to move into the inner description; INNER-3 does that and
  changes no other `DESC`.
- `ElementReferences` has exactly two consumers: `SpellReferences` calls
  `isValid()`, and `ui/HexUnitFacts.gd` calls `code()`. Both mean a single
  element. A combination must never satisfy either. `effects/SpellVfxSpec.gd`
  validates against its own `KNOWN_ELEMENTS` and is out of scope.
- No tool writes the content catalogs back to disk, so the new field cannot be
  dropped by a round-trip save.
- `effects/DamageNumberBillboard.gd` already implements the arc's ballistic
  travel and flash-out, and `checks/battle/probe_damage_number.gd` proves them.
  `SPAWN_HEIGHT` is still 0.85, and `_spawnNumber` still fires in the same
  frame as the strike.

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
above, including the pending convention, word for word. `AGENTS.md` gains one
bullet: inner descriptions document only the source, are based on Wikipedia
where a good article exists, never explain the link, and use the `PENDING:`
form when they cannot be written yet. The bullet points to
`docs/REFERENCE_CATALOGS.md`.

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

### INNER-3 — Retire the Reference Register and mark the user's four spells pending

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The four strings and the one `DESC` change are fixed
below, and the doc edits are a deletion plus one pointer. It needs no research and no interpretation.

**Depends on:** INNER-1.

**Touches:**
- `data/spells.json`
- `docs/lore/magic_and_relics.md` (delete the "Reference Register" section;
  keep "Naming by Level")
- `docs/SPELL_CATALOG_SCHEMA.md` (the paragraph that sends new spells to the
  register)

**End state:**
- These four spells carry exactly these strings, and no other spell gains an
  `INNER_DESCRIPTION`. *Insatiable Famine*'s first sentence is the user's own,
  moved out of its `DESC`:

  | Spell | `INNER_DESCRIPTION` |
  |---|---|
  | Wicker Man | `PENDING: write the source from English Wikipedia (topic: wicker man). Source only; do not explain the link.` |
  | Eschatology | `PENDING: write the source from English Wikipedia (topic: eschatology). Source only; do not explain the link.` |
  | Solar Storm | `PENDING: write the source from English Wikipedia (topic: solar storm). Source only; do not explain the link.` |
  | Insatiable Famine | `Inspired by the curse of Erysichthon. PENDING: write the source from English Wikipedia (topic: the curse of Erysichthon). Source only; do not explain the link.` |

- *Insatiable Famine*'s `DESC` is exactly
  `Single target ranged attack that inflicts poison.`
- The register section no longer exists.
- `docs/SPELL_CATALOG_SCHEMA.md` tells authors to document a referenced name's
  source in the spell's `INNER_DESCRIPTION`, and links to the authoring rule.
- `grep -rn "Reference Register" docs .claude AGENTS.md BACKLOG.md` finds
  nothing outside `docs/plans/`.

**Implementation:** These stay pending even if Wikipedia is reachable: the user
asked for them to be pending. Do not copy register text, because it is
untrusted. Apart from *Insatiable Famine*'s `DESC`, touch no other spell
field.

**Risk:** JSON formatting churn. Keep the tab indentation and key order.

**Validation:**
- Self-contained: `python3 -m json.tool data/spells.json` parses the file, the
  headless load check passes, and the grep above is clean.

### INNER-4 — Add *Blood Meridian*

**Model:** Sonnet 5 / GPT Terra

**Model rationale:** The gameplay values copy *Wicker Man*, the existing
two-element Level 3 spell, and the inner description follows the fixed rule,
so there is no balance or design judgement left. It is one catalog entry.

**Depends on:** INNER-3 (same file; run as one lane).

**Touches:** `data/spells.json`

**End state:** `data/spells.json` contains:

```json
{
	"CAN_TARGET_EMPTY": true,
	"COOLDOWN": 6,
	"DAMAGE_LINES": [
		{"damage": 5, "element": "fire"},
		{"damage": 5, "element": "darkness"}
	],
	"ELEMENTS": ["fire", "darkness"],
	"INNER_DESCRIPTION": "<see below>",
	"MAX_HEIGHT_DELTA": 1,
	"NAME": "Blood Meridian",
	"RADIUS": 2,
	"RANGE": 4,
	"SEQUENCE_LEVEL": 3,
	"TARGET_TYPE": "area"
}
```

If `https://en.wikipedia.org/wiki/Blood_Meridian` is reachable, the
`INNER_DESCRIPTION` follows the authoring rule. It names the full title
(*Blood Meridian, or the Evening Redness in the West*), Cormac McCarthy and
1985, adds at most one further sentence drawn from the article's lead, and
ends with `Wikipedia: https://en.wikipedia.org/wiki/Blood_Meridian`. Otherwise
it is exactly
`PENDING: write the source from English Wikipedia (topic: Blood Meridian, the 1985 novel by Cormac McCarthy). Source only; do not explain the link.`,
and the commit body says Wikipedia was unreachable.

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

### INNER-5 — Finish the damage-number arc: impact frame and multi-hit cadence

**Model:** Opus 5 / GPT Sol

**Model rationale:** Half of this is a one-frame delay, but the other half
needs a judgement about whether the visual action queue models a multi-hit
attack at all, and how a per-number stagger interacts with an action's hold.
That shape cannot be known from one file. Inventing a queue feature here would
be the wrong call, and telling when to stop is the judgement being paid for.

**Depends on:** —

**Touches:**
- `battle/HexBattleCombatFeedback.gd`
- `battle/VisualAction.gd`
- `effects/DamageNumberBillboard.gd` (`SPAWN_HEIGHT` only)
- `checks/battle/probe_damage_number.gd`

**End state:** The number spawns one frame after the impact flash begins, so
the flash reads first. `SPAWN_HEIGHT` is re-checked now that the number climbs
4.76 glyph heights on its own, and lowered if a full arc overshoots the unit's
head. The multi-hit outcome is either two numbers from one attack overlapping
0.34 s apart, each on its own full 0.58 s arc (the gap is a constant on the
feedback layer, not the billboard), or a commit body stating that the queue
cannot express it, with no queue feature invented.

**Implementation (brief):** The reference figures are in the removed
`docs/plans/battle-damage-number-arc.md` (read it from git history). The
single-hit arc already implemented must not change: rise, fall, drift,
outline and flash constants stay as they are. Pacing in `_startNumber` and
`_startStrike` must keep its total.

**Risk:** A spawn delay that makes the queue's hold end before the number is
visible; a stagger that stretches every attack's action time.

**Validation:**
- Self-contained: `checks/battle/probe_damage_number.gd` still passes; extend
  it to assert the one-frame spawn delay. Run the headless load check.
- Deferred: the user watches a basic attack and, if one exists, a multi-hit
  attack at 1x, and judges whether the number answers the flash and clears
  the unit's head.

### INNER-V — Watch the damage numbers

**Model:** Opus 5 / GPT Sol

**Model rationale:** The only deferred check is a visual judgement about
INNER-5's work, which its implementing session cannot fairly make about
itself. The user observes; the session prepares exact steps, records the
result, and tunes only `SPAWN_HEIGHT` or the multi-hit gap if the user asks.

**Depends on:** INNER-5.

**Touches:** `effects/DamageNumberBillboard.gd` (`SPAWN_HEIGHT` only),
`battle/HexBattleCombatFeedback.gd` (the multi-hit gap constant only),
`docs/plans/inner-descriptions.md` (deletion at closure).

**End state:** The user has watched the steps and accepted them, or the
correction is committed with the observation. The cycle closes and this file
is deleted.

**Validation:**
- Deferred: INNER-5's deferred line, observed by the user at the INNER-5
  revision, noting any unrelated in-flight changes.

## Waves

| Wave | Items | Why disjoint |
|------|-------|--------------|
| 1 | INNER-1, INNER-5 | catalog loader, content probes and docs vs. battle feedback and damage-number billboard; no shared path |
| 2 | INNER-2, INNER-3 + INNER-4 (lane) | element catalog and its wrapper vs. spell catalog and spell/lore docs; no shared path |
| 3 | INNER-V | validation, alone; the user observes |

Five implementation items: the convergence review falls after the second,
which is the end of wave 1.

## Deliberately excluded

- **An items catalog.** The loader-level rule means a future items catalog
  carries `INNER_DESCRIPTION` without extra work.
- **Stripping the field from exported builds.** `data/*.json` ships inside the
  export, so the text is in the build even though no screen shows it. This
  belongs in the backlog before a public release.
- **A kit for *Blood Meridian*.** Smoke Cloud (race Terrorugon, family Smoke
  Fiend) is the only fire+darkness monster, and at Level 3 it could legally
  carry the spell in its fire set beside Smoke Tower. It is left out because
  Smoke Cloud fights in nine scenarios, including the AI evaluation mirrors,
  so a new spell would change CPU behaviour and evaluation baselines. That is
  the user's call, not a side effect of this cycle.
- **All 120 triples, and gameplay use of combinations.** The triples are
  placeholders. Nothing reads combinations yet.
- **Inner descriptions for *Roses at Summers End*, *Holy Cross*, *Aurora
  Veil*, *Corallitic Acid Reflux*, or any other object.** The user listed four
  spells, and adds the rest as they go.
- **Everything from the dissolved cycles except INNER-5.** It is in
  `BACKLOG.md`.
