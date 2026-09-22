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

### Prove existing VFX in real battles

`Fire Storm`, `Ice Statue`, and the generic spell-cast aura have extensive
debug-harness evidence but incomplete integrated battle acceptance. Cast them
through the real event/adapter path, on contrasting bodies and terrain, and
check targeting, camera motion, readability, overlap, pause, skip, speed,
defeat, and scene exit. Compare existing caller goldens before touching any
shared VFX primitive. The generic aura's longer lifecycle is a separate motion
decision: judge its timing in a live action before retuning it. Acceptance:
record the tested revision, visible result, gameplay result, and clean teardown
for each effect. The shutdown reproducer below is a distinct stress case.

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
quarantine list and failure notes. Reconcile old battle corpus/round-cap probes
with side turns where the active AI cycle does not already do so; investigate
the world-map and editor probes still marked `gate: false`; and add a marker to
the unregistered renderer-bound foundation acceptance probe. A failure may be
an obsolete assertion or a product defect: establish which before changing the
gate. Acceptance: each repaired probe passes and is gated, or is replaced with
a current-rule check that proves the same useful contract. Keep the manifest as
the single source for exact probe names and status.

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

### Improve battle input access

Validate keyboard and gamepad navigation, focus indicators, and all six
camera-relative hex directions in an actual battle. Add user-facing remapping
only after the concrete navigation gaps are known. Acceptance: every available
command and legal target can be reached and confirmed without a mouse.

### Polish world-map presentation after authoring acceptance

At close framing, a single cloud can dominate the view; its shadow can end at
the region edge as a hard rectangle. No current preset exposes standing
structures and their lighting. Judge these together on an authored map, then
choose a preset and shadow/scale behavior from captured gameplay views. The
ground rig's broader camera and region-width decisions belong to world-map
design rather than a standing implementation task.
