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
any change keeps `checks/battle/probe_vfx_contract.gd`'s carrier table and
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

### Let a spell declare several elements without damage lines

The spell catalog enforces that a multi-element spell's `ELEMENTS` match its
damage lines, and rejects `ELEMENTS` on a spell with no damage lines. At
runtime, `Spell.getElements()` derives elements from `ELEMENT` and the damage
lines, so a non-damaging spell has no way to be multi-element. Carpet of
Flowers (light/wood) and Area Denial (steel/water) below are both
non-damaging and multi-element. When the spell has damage lines, the declared
elements must still match them exactly. When it has none, they must stand on
their own. Acceptance: a spell with `ELEMENTS` and no damage lines loads.
Casting it requires every declared element, and it charges each of their
Resonance bars. `probe_spell_elements.gd`'s "ELEMENTS with no damage lines"
fixture flips from rejected to accepted, and every other alignment check
still holds.

### Add ground effects, for Carpet of Flowers and Area Denial

Nothing in the battle lasts on a cell: statuses live on units, and no spell
leaves anything on the board. Two designed spells need a ground-effect
mechanic: cells that carry an effect for a number of turns, trigger for units
standing on them, and can be removed.

- **Carpet of Flowers:** Level 2, light/wood. Creates flowers over a radius-3
  area. At the start of the turn of each unit standing there, it heals the
  caster's allies.
- **Area Denial:** Level 2, steel/water. Removes every ground effect within
  radius 3 of the caster.

The creator gave the above. Defaults to confirm when this is built: Carpet of
Flowers targets a cell up to range 3, lasts 3 turns, and heals 2 HP per trigger
(only allies of the caster, never enemies). Area Denial removes effects of both
sides. Both break the Level 2 tier shape (single target). Record them as
exceptions in `docs/GAME_DESIGN.md`, or change the shape, per the creator's
call. This needs the item above first. Acceptance: both spells exist in the
catalog. The flowers heal only allies standing in
the area at their turn start, and expire. Area Denial clears them. All of this
is visible on the board, serialized, and deterministic under replay.

### Port the lost turn-boundary and window-scaling work

Three commits from 2026-09-20 (`f529879`, `f17b59f`, `77cb0ea`) never reached
`main`. They sit on `claude/turn-auto-end-darkening-rk687y`, which is also
meant to be archived as the tag `archive/turn-auto-end-darkening`. That branch
predates the 2026-09-18 re-import and the flat layout, so it cannot be merged.
Re-implement on current code what `main` still lacks:

- **Window scaling.** A fixed 1280x720 canvas stretched to the window, opening
  at 1600x900, with `aspect = expand`, and UI scale derived from the canvas so
  the engine's scaling is not applied twice. The commit body argues for
  `viewport` over `canvas_items` stretch: the baked game fonts lose their glyph
  cache when oversampling changes. Re-check that against today's font code.
- **Turn announcement.** "NEXT TURN" then "TURN #n" across the screen at each
  side turn. It ignores the mouse and never blocks playback.
- **Instant turn-end controls.** Clear the action arc, forecasts and End turn
  on `side_turn_ended`, instead of waiting for the next side to open.
- **Petrified player side.** Check whether a player side whose only ready units
  are petrified can still get stuck. If it can, end that side automatically.

Do not port the branch's shader-based two-shade darkening: `main` rebuilt it
(`73b2f0d`). Its playback timing, where a unit darkens when the animation queue
reaches its action, and undo brightening, are worth comparing against `main`'s
turn-phase approach. Acceptance: each ported behaviour works on the current
layout, passes `checks/battle/probe_ui_guardrails.gd` and the hex-battle probes,
and leaves `main`'s darkening unchanged.

### Build the berserk status and Summit Fever

On 2026-09-28 the user asked for Summit Fever, a Level 3 fire/ice spell that
puts its target into a berserk state, and chose what berserk means: the target
**loses control**. For a few turns it acts on its own, charging and attacking
the nearest unit, friend or foe, the way the aggressive BerserkBrain plays. It
is not a stat buff or debuff. Nothing like it exists today: statuses only shift
stats or deal damage over time, a basic attack cannot target an ally, and the
controller chooses every action.

- **Status.** A negative `berserk` status (so cleanse removes it) with a default
  duration. Its unit leaves its controller's choices and takes one
  deterministic automatic action per side turn against the nearest living unit
  of either team, ties broken by the lowest `uniqueID`. Friendly fire is legal
  for that unit only; `CombatResolver`'s refusal to attack allies stays for
  everyone else, and existing BerserkBrain monsters play exactly as before.
  Calls left to the implementer: basic attack only or spells too; when in the
  side turn it acts and whether it spends its activation; how the CPU values
  inflicting a pure control effect, which its evaluator scores at zero today.
- **Summit Fever.** `ELEMENTS` fire then ice, damage lines 3 fire and 3 ice,
  single target, range 4, minimum range 1, cooldown 4, Level 3, can target an
  empty cell, maximum height delta 1, inflicts berserk. No `DESC` and no `VFX`
  block. Single target breaks the Level 3 area shape by the user's choice:
  record it as an exception in `docs/GAME_DESIGN.md`. No fire/ice monster
  exists, so like Heat Drift it has no caster yet.
- **Hex battle UI.** Show the state, and keep a berserk unit out of the
  player's command flow.

Acceptance: a registered probe proves control loss, ally targeting,
determinism, expiry, cleanse and replay. The battle, hex_battle, ai_rework,
invariants and fuzz sweeps match a baseline taken before the change. The HUD
passes `checks/battle/probe_ui_guardrails.gd`.

### Direct the hex battle camera

`HexBattleCamera` orbits, zooms and frames the whole map, but nothing directs it
during a battle: `focusOn` and `orbit` have no callers outside the camera, and
every battle opens at the default yaw and pitch. The square battle's
never-enabled `BattleCameraDirector` left with the square runtime; do not revive
it. The goals the user set on 2026-08-30 still stand: frame the acting unit,
follow the cursor without turning the board into a treadmill, follow a piece
while it moves, orbit slowly while a CPU thinks, pull back for a wide spell,
settle before aiming, and give everything up the instant the player takes the
camera. No cinematics: no establishing shot, KO camera or second camera.
Build the setup-screen preview first: the configured board orbiting behind
the menu, rebuilt as the dropdowns change. It is the only place to judge the
opening angle under the real renderer. The behaviour table is in
`docs/sketches/2026-08-29-battle-camera-behaviour-and-opening-framing.html`.
Acceptance: each behaviour is observable in a player-vs-CPU battle and yields
to manual control at once. The user picks the opening pitch and the orbit rate
by watching the preview. Cursor directions stay correct after every camera
move.

### Close the CPU deliberation frame-time tail

CPU deliberation is paced by a 4 ms wall-clock budget per frame. A single
enumeration slice (one actor) can still overshoot it on its own, which leaves a
17 to 20 ms tail: up to one dropped frame per side decision, as measured on
2026-09-22. Closing it means subdividing enumeration below one actor.
Candidates must keep accumulating in a fixed order so that the decision does
not depend on where a slice falls. Acceptance: no deliberating frame exceeds
16.7 ms in `tools/capture_ai_session.gd` on the same machine class, and the
slice-equivalence and side-policy probes pass unchanged.

## Make authoring and verification dependable

### Accept the world-map editor end to end

The editor implements paint, history, recovery, save/reopen, and battle export,
but its fresh-eyes interactive pass is still pending. Author one representative
region through the UI, including height and objects; save, reopen, export, and
play the exported battle. Check larger-map responsiveness after the redraw
optimization. Acceptance: no lost edits or manual file repair, and the battle
matches the authored terrain and walkability. Record any observed failure at its
own narrow write path rather than reviving the older broad editor plan.

### Give the world-map editor its missing tools

The hex authoring validation of 2026-09-07
(`docs/plans/reviews/worldmap-hex-validation.md`) left these gaps. Check each
against current code before starting:

- Water and bridges have no editor tool, so they can only be placed by script.
- Authored water has no editor preview: `buildWater` runs only on export.
- Water is not fogged, while the ground is.
- Rectangle and Stamp are square-map only on a hex document.
- Relief is invisible at pitch 60: a dry hill reads flat.

Acceptance: water and bridges can be placed and undone with the mouse, and
water is visible while editing and fogged like the ground. Rectangle and Stamp
either gain a hex behaviour or are disabled on hex documents. Relief
readability goes to the user as a design question; don't silently retune it.

### Record the playtests the closed cycles never passed

On 2026-10-02 the user dissolved every implementation cycle except Inner
Descriptions. Their code appears built, but this was spot-checked, not checked
item by item: the 2026-09-18 re-import dropped the commit trailers that
recorded each item. These interactive acceptances were never recorded as
passed:

- **Action pacing.** At 1x, movement, settling, contact and recovery read as
  distinct beats without feeling sluggish. Pause, 2x and skip still treat a
  paced sequence as one action.
- **Hex battle as a whole.** This covers side turns, the playability
  restoration, the first hex battle, and the Brigandine HUD. A full
  player-vs-CPU battle reads correctly: side-turn cues, ordered combat
  consequences, status badges, inspection, the party HUD, round-cap endings,
  and resuming after a pause.
- **Folder layout.** Appearance, timing and lifecycle match the evidence from
  before the move, and the Windows export with the existing preset works. Run
  `tools/folder_layout.ps1 -Mode Verify` against the migration revision
  `32a2232`, not HEAD.
- **World-map props and daylight.** Shadows look painted and hold still while
  the sun moves and the camera pans. Lamps after dark leave the ground its
  daytime colours.

The editor's own feel check is "Accept the world-map editor end to end"
above. Acceptance: the user observes each one, and each either passes or
becomes its own narrow backlog item.

### Restore trustworthy probe coverage

The registered probe manifests under `checks/manifests/` own the current
quarantine list and failure notes. The old battle corpus and round-cap probes
lost their owner when the AI rework cycle closed; include them here. Investigate the world-map and editor probes still
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
`checks/battle/probe_shutdown.gd` still reproduces an exit-time access
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

### Build a fresh policy-comparison corpus

Mirroring the two existing kits across three maps separated some roster effects
from seat effects, but the technical A kit favoured legacy at every seed,
Proving Ground A favoured tactical at every seed, and both B kits stayed fully
seat split. Repeating seeds on these inspected maps is not a new holdout.
Author new map, deployment and roster combinations without looking at their
policy outcomes first. Screen development cases with same-policy play from
both seats, then reserve distinct, uninspected cases for the final paired run.
Acceptance: the manifest declares independent held-out cases and both policy
assignments in advance; the report shows seat balance, decisive pairs,
failures and caps by fixture, with no claim based on a viewed development set.

### Define paired draw and cap scoring before another strength claim

The mirrored run included a tactical win paired with a draw, which the current
analyzer counts as a tactical-favouring position even though its estimand says
the policy wins outright from both seats. `PairedOutcomes` can also count a
win paired with a round cap, contrary to the report's claim that capped matches
stay out of the strength tally. Decide the exact pair categories and update the
analyzer, prose and hand-checked probe cases together. Acceptance: win/draw and
win/cap pairs have explicit, tested classifications, and the reported
estimand matches the code before a fresh holdout is evaluated.

### Improve battle input access

Validate keyboard and gamepad navigation, focus indicators, and all six
camera-relative hex directions in an actual battle. Add user-facing remapping
only after the concrete navigation gaps are known. Acceptance: every available
command and legal target can be reached and confirmed without a mouse.
