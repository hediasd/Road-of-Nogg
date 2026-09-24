# Backlog

Reviewed 2026-09-22 against the current hex battle, catalogs, probe manifests,
recent commits, and active cycles. This file holds actionable work that has no
current implementation owner. Active work belongs in its frozen cycle under
`docs/plans/`; verified findings belong in the owning design document or commit.
Order within a section is a suggested priority, not a commitment to new rules
or art. When taking an item, check the current code and claim its write paths.

## Improve the playable battle

### Explain non-damage spells before confirmation

The hex aim prompt reports `Heals; no damage forecast.` for healing and `Deals
no damage.` for pure buffs, debuffs, and statuses. Use the already authored
effects and resolved targets to state the expected healing, stat change, status,
and duration where they are knowable. Keep simulator eligibility and resolution
authoritative; do not invent a numerical prediction for a random effect.
Acceptance: a player can distinguish the benefits of two legal support spells
before choosing one, including spells aimed at empty cells or several targets.

### Make the whole team's condition readable

The selected-unit readout and STATUS sheet show detailed HP, but comparison
across a full 4v4 still requires inspecting units one at a time. Find a compact
team-level view of HP and ready/spent state, and check it at the battle camera's
normal and awkward angles. Do not restore the health-and-level plates under
every unit; the user rejected and reverted that presentation. Acceptance: the
player can identify the wounded and still-available units in one glance without
obscuring board clicks. Include a live check that critical hits, elemental
weakness, and Resonance changes are noticed at the moment they occur.

### Give existing spells useful homes

`Blue Crowned Pidgeon` still has no spells, while many authored Level 1 spells
are unused. Assign suitable existing spells and validate each kit against its
element and tier rules. Review `Mage Dragon`'s `Think`/`Thought` entries with the
content owner: they read as placeholder self casts and should either gain a
clear purpose or leave the production kit. Then author a small number of
additional complete elemental ladders so more than Wood can reach Resonance
tiers 2-3 and a Level 4 finisher. Acceptance: several distinct roster choices
can build and spend Resonance in a normal battle, with catalog checks passing.
Spell roles and balance values require a deliberate content decision.

### Make levels playable

Every roster slot still enters battle at level 1 and all 28 monster growth
triples are zero. Add per-slot level selection to battle setup and preserve it
through save/reconstruction, defaulting old setup data to level 1. Agree on a
bounded range and role-shaped growth, then author the catalog values. Acceptance:
mixed-level battles show the correct HP/ATK/DEF in setup, simulation, STATUS,
and restored state; existing level-1 numbers stay unchanged. The range and
growth values are balance decisions for the user.

### Review the cube placeholder settings per spell

Every spell that casts a cube placeholder effect carries a presentation-only
`VFX` block (`data/spells.json`, vocabulary in `docs/SPELL_CATALOG_SCHEMA.md`).
The 25 carriers and their settings were proposed and approved in the cycle
that built the library, on the understanding that the user reviews them once
it shipped. Review each with `--spell=<Name>` in the VFX debug scene and in a
live battle. Points noticed during validation to decide on:

- **Magenta Reduction** has no `ELEMENT` and water and fire damage lines, so
  the default rule shows both palettes. Author `ELEMENTS` if one colour is
  wanted.
- **Cube scale against battle pawns.** Body-bound shapes (frost, cage) scale to
  the body bounds the adapter measures; next to the small pawn models they
  read chunky. Decide whether the world unit (1.6 per sketch unit) or the body
  measurement should change.
- **Single-cell area casts** (Ice Plume, Earth Spike) squeeze their area
  studies into one hex, which keeps them truthful but tight. Decide whether a
  single-target spell should play an area study at all.
- **Range scaling** is provisional: travel beats stretch by
  `clamp(cells / 4, 0.75, 1.5)`. Adjacent casts hit the 0.75 floor.
- **The final validation was not independent.** The session that built the
  library also validated it, at the user's instruction to proceed without
  stopping. A fresh-eyes look at the 24 against the retained sketch is still
  owed.

Acceptance: each carrier's settings are confirmed or changed by the user, and
any change keeps `scripts/hex_battle/probe_vfx_contract.gd`'s carrier table and
the cube placeholder manifest in step.

### Prove existing VFX in real battles

Only once these effects are restored: as of the cube placeholder library, no
spell carries `Fire Storm`, the ice target encasement or the generic
spell-cast aura (`Smoke Tower` and `Ice Statue` now play cube placeholders).
`Fire Storm`, `Ice Statue`'s encasement, and the generic spell-cast aura have
extensive debug-harness evidence but incomplete integrated battle acceptance.
Cast them through the real event/adapter path. Retain the checks particular to
each:

- **Fire Storm (`Smoke Tower`):** test live terrain and units through CRT and
  queue playback; cover overlap/cap, pause, skip, speed, and exit. Extend the
  harness radius sweep beyond 1-2 to radius 3. Capture closely spaced motion
  frames so winding, taper, shrink, and lean can be judged in motion.
- **Ice Statue (Snowzilla):** cast at short and long legal range onto two
  visibly different bodies, including elevated terrain. Check event-time
  placement, cyan readability through CRT, damage-number separation, defeat,
  retrigger, oldest-effect disposal at the live cap, pause, skip, 0.5x/2x
  speed, and exit without a surviving shell.
- **Generic spell-cast aura:** prove true time-zero emergence, several seeds and
  elemental tints, native and retro rendering, camera motion, forward/backward
  seek, identical frames at identical normalized time and seed, pause, skip,
  overlap, replay, disposal, and a real cast. Its longer lifecycle and adapter
  hold fraction need a separate motion judgement; 1.8-2.2 seconds was an
  initial range to test, not an approved duration.

Compare existing caller goldens before touching a shared VFX primitive. Record
the tested revision, visible result, gameplay result, and clean teardown for
each effect. The shutdown reproducer below is a distinct stress case.

## Make authoring and verification dependable

### Accept the world-map editor end to end

The editor implements paint, history, recovery, save/reopen, and battle export,
but its fresh-eyes interactive pass is still pending. Author one representative
region through the UI, including height and objects; save, reopen, export, and
play the exported battle. Check larger-map responsiveness after the redraw
optimization. Acceptance: no lost edits or manual file repair, and the battle
matches the authored terrain and walkability. Record any observed failure at its
own narrow write path rather than reviving the older broad editor plan.

### Restore trustworthy probe coverage

The registered probe manifests under `scripts/checks/probes/` own the current
quarantine list and failure notes. The active AI cycle owns the old battle
corpus and round-cap probes. Investigate the world-map and editor probes still
marked `gate: false`; a failure may be an obsolete assertion or a product
defect, so establish which before changing the gate. The sweep currently skips
renderer-bound probes: add a renderer-capable run path. Until then, perform and
record explicit non-interactive window checks; do not count `SKIP` as a pass.
Give the unregistered renderer-bound foundation acceptance probe a success
marker and register it only when the sweep can actually run it. Acceptance:
each repaired probe passes in its required environment and is gated, or is
replaced with a current-rule check that proves the same useful contract. Keep
the manifest as the single source for exact probe names and status.

### Diagnose the synthetic VFX shutdown fault

Shipped hex paths previously exited cleanly, including completed battles, but
`scripts/hex_battle/probe_shutdown.gd` still reproduces an exit-time access
violation when a particular mix of hex and donor effects is loaded in one
process. A single effect and larger mixes can exit cleanly, so volume alone is
not the cause. Capture the retained-object/resource graph before cleanup loses
the report, identify the ownership cycle, and prove repeated exit code 0 with
no leak reports. Keep the probe quarantined until that proof exists.

## Later, when a concrete use calls for them

### Make area VFX match resolved hex footprints

Ground washes and particle fields do not consistently depict non-disc areas;
`cross` and `line` need exact cast direction/affected cells, and some effects
still assume a fixed radius. Before introducing runtime radius modifiers,
define modifier ownership and snapshot behavior. Then carry the resolved hex
footprint through presentation and verify edges, shape, and effect budgets for
each area carrier. This is one feature; avoid separate radius and particle
shape work that would change the same interface twice.

### Repair the v1 technique-aura tuning controls

Several `TechniqueChargeAuraV1Effect` sliders labelled live update only their
override dictionary; their shader uniforms change only after rebuild. Mirror
the proven v2 live-update path and verify an interactive slider drag at a fixed
seed and time. Keep the debug-only effect's production telegraph decision out
of this bug fix.

### Give CPU-versus-CPU scenarios a fair second seat

Across the declared evaluation experiment -- three scenarios, six seeds, both
side assignments, 36 matches -- **side one won every single match**. Every
position split, so the run produced eighteen decided positions and zero decisive
ones, and could say nothing at all about which policy plays better. Whoever
moves first wins these boards.

That is a scenario and turn-order question, not an AI one, and it blocks any
future policy comparison on these maps: a league run here measures the seat.
Worth establishing whether the advantage is starting positions, the side order
itself, or a first-strike threshold in the combat numbers, and then either
balancing the scenarios or adding ones that do not resolve on move one.
Acceptance: a scenario set where the same policy on both sides does not win by
seat, so a paired comparison can produce decisive positions.

### Improve battle input access

Validate keyboard and gamepad navigation, focus indicators, and all six
camera-relative hex directions in an actual battle. Add user-facing remapping
only after the concrete navigation gaps are known. Acceptance: every available
command and legal target can be reached and confirmed without a mouse.
