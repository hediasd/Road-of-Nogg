# VFX design

Owns the contract, conventions, and authoring workflow for spell visual
effects. Battle UI, theme tokens, and the CRT/retro window layer belong to
[`UI_DESIGN.md`](./UI_DESIGN.md); verified render-isolation findings live in
[`LEARNINGS.md`](./LEARNINGS.md) and are cross-referenced rather than repeated
here.

Current runtime behavior overrides this document. When an effect changes,
update this page rather than adding a second description elsewhere.

---

## 1. How an effect reaches the screen

```
data/spells.json  VFX_PROFILE: "ice_area_storm"
        │
SpellReferences   normalizes the row; VFX_PROFILE defaults to ""
        │
CombatResolver    emits spell_cast_started for every cast
        │
GodotVisualAdapter._on_spell_cast_started
        │         copies VFX_PROFILE, RADIUS, AREA_SHAPE onto a CAST_AREA
        │         VisualAction, derives a deterministic vfx_seed, measures
        │         the footprint's terrain span
        │
GodotVisualAdapter._start_cast_area_animation
        │         resolves the profile, enforces the live cap, spawns,
        │         setFootprint(radius, groundSpan, areaShape), plays, and
        │         holds the visual queue for duration x action_hold_fraction
        │
SpellVfxCatalog   profile id -> factory
        │
VfxPlayback       the effect itself
```

**The adapter is fully profile-driven.** Adding an effect requires no change to
it, to `VisualAction`, or to the event layer. If a new effect seems to need one,
that is a signal the contract is being worked around.

`VFX_PROFILE` is presentation metadata with no gameplay effect. An empty or
unrecognized value falls back to the generic aura. See
[`SPELL_CATALOG_SCHEMA.md`](./SPELL_CATALOG_SCHEMA.md).

---

## 2. The `VfxPlayback` contract

Every effect extends `src/presentation/effects/VfxPlayback.gd` and implements:

| Member | Obligation |
| --- | --- |
| `play(seed, mode)` | Start from zero. `mode` is `MODE_BATTLE` or `MODE_REFERENCE`, selecting which duration applies. |
| `seek_normalized(t)` | Present the exact frame at `t` in 0..1, forwards or backwards. |
| `set_playback_scale(f)` | `0.0` freezes. Drives pause and the game's animation-speed setting. |
| `skip_to_settle()` | Jump to the tail so a skipped action does not cut mid-burst. |
| `dispose()` | Free everything. Safe to call twice, and while playing. |
| `get_layer_names()` / `set_layer_visible()` | Named layers, for isolating one at a time while authoring. |
| `get_live_particle_count()` / `get_live_node_count()` | Honest live figures; the debug HUD and budget checks read them. |
| `is_particle_seek_exact()` | Whether `seek_normalized` reproduces a frame exactly. See §6. |

Optional, discovered by `has_method`:

- `setFootprint(radius, groundSpan, areaShape)` — area effects.
- `setIntensityScale(f)` — lets the adapter dim overlapping effects.

**Registration** is one row in `SpellVfxCatalog.entries()`: `profile_id`,
`display_name`, `factory`, `action_hold_fraction`, `max_live`.

---

## 3. Determinism is the load-bearing property

Effects derive their motion from `INDEX` and an explicit `playback_time`
uniform, never from `TIME` and never from frame-accumulated state.

This is not a purity exercise. It buys three things:

- **Scrubbing.** A paused frame is a real frame, not an approximation.
- **Reproducible captures**, which golden-frame regression depends on.
- **Replay.** The same cast looks the same, because `vfx_seed` is derived from
  spell name, caster, and position rather than from a random source.

**A shader driven by `TIME` keeps animating while its GDScript timeline is
paused**, so Play, Pause, scrub, and screenshots disagree by layer. This is a
verified finding recorded in `LEARNINGS.md` — give every effect one local
elapsed-time source and drive companion shaders from that same uniform.

**The limit, measured 2026-08-04:** the GDScript timeline is deterministic, but
`GPUParticles3D` is not entirely. `restart()` and `request_particles_process()`
are serviced on the rendering server, and identical runs produce slightly
different frames for the same timestamp (mean per-channel difference
0.00–0.03). Replaying from zero before each seek removes most of it; additional
settle frames remove none, which identifies the residue as scheduling rather
than a race that waiting fixes. Hence tolerance-based golden comparison (§5),
not byte comparison.

---

## 4. Conventions for a new effect

### Fork, don't abstract — until the third

`IceStormEffect` and `FireStormEffect` are separate files with near-identical
lifecycle code. That is deliberate: profile constants are `const` on a class
rather than an injectable resource, so there is no seam to subclass against, and
extracting one for two effects costs more than it saves.

**The third elemental effect is the trigger to reconsider.** At three copies the
shared shape is proven, and the payoff — a `SpellVfxProfile` resource, after
which a new element is a `.tres` rather than a forked file — is real. Doing it
at two is speculative; doing it at four is late.

### Provenance labels

Constants carry a label stating where the number came from, so a later session
can tell a measurement from a guess:

| Label | Meaning |
| --- | --- |
| `MEASURED` | Taken from reference material, with that material identified. |
| `ESTIMATED` | Inferred from reference material but not frame-measured. |
| `AUTHORED` | Chosen by eye. No external source claimed. |
| `DERIVED` | Carried from another profile, inheriting its provenance. |

**Do not upgrade a label without recording the evidence.** `IceStormProfile`'s
`MEASURED` values mean something; diluting them costs more than the labels are
worth.

**Reference-footage decomposition was the ice storm's single most expensive
activity, and it does not transfer.** The fire storm is `AUTHORED`/`DERIVED`
throughout and cost a fraction as much with no visible deficit. Default to
authoring by eye; spend on measurement only when a specific effect earns it.

### Budgets, asserted at build time

Each profile carries `MAX_EFFECT_NODES`, `MAX_DRAW_CALLS`, and
`MAX_LIVE_PARTICLES`, asserted in `_buildLayers()` so a violation fails loudly
at construction rather than being noticed as a frame-rate problem later.

### Additive material conventions

Layers blend additively via `VfxTextures._createMaterial`. Two traps:

- **`vertex_color_use_as_albedo` multiplies.** A draw material with a baked tint
  will multiply against a per-particle colour the shader writes to `COLOR`. An
  effect whose shader owns its palette must neutralise the material's albedo and
  emission to white first, or the gradient is skewed toward the baked tint.
- **`emission` is baked once at construction.** A caller varying a layer's
  colour per frame must set `emission` alongside `albedo_color`, or the tint
  appears only in unlit albedo and not in the glow that actually reads as
  brightness.

### Density is a function of volume, not count

The most transferable lesson from building the second effect. The ice storm
spreads 180 particles across a flat field; the fire storm concentrates its
particles into a narrow column. **At the same count the column was an
unreadable haze in which no individual ember — and therefore no spiral — was
legible, and its additive core clipped to flat white, hiding the entire palette
gradient.** It needed 104 particles and roughly half the per-particle alpha.

When adapting an effect to new geometry, retune **count** and **alpha** first,
from the new volume, rather than starting from the donor's numbers. Both are
readability constraints, not performance ones — worth stating in the profile so
nobody later "restores" them toward the budget.

### Footprint shape

Gameplay area shapes come from `ShapeCaster` via
`CombatResolver._spellAffectedPositions`. Only `cross` and `line` are
special-cased; **everything else, including `circle`, is a Manhattan diamond**
(`|x| + |z| <= radius`), not a Euclidean circle.

An effect that claims tiles the spell does not hit is a real defect — it misinforms
the player about the area. Two useful facts:

- The diamond boundary has an exact polar form, `r_max(t) = R / (|cos t| + |sin t|)`,
  which a radial effect can clamp to so it traces the true footprint.
- A square sampled uniformly and rotated 45 degrees **is** that diamond, so a
  particle field can fill it with no rejection and no density loss.

A radius-`R` footprint reaches `R + 0.5` in world units, because the outermost
tile contributes its own half-width. Effects and the debug guide both use that,
so they agree by construction.

Current gap, tracked in `BACKLOG_LONGTERM.md`: ground washes carry every shape,
but particle layers still do not handle `cross` or `line`.

---

## 5. The debug harness

`scenes/debug/VFXDebugScene.tscn` renders through the real retro pipeline and is
the acceptance surface for VFX work. Interactive keys are listed in
`VFXDebugController.gd`'s header.

**Every interactive control has a CLI equivalent**, so a validation pass is
scriptable. That parity is not a convenience — it is the thing that keeps a
validation item from stalling.

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --effect=fire_area_storm --shape=cross --radius=1 --seed=7 --hide-hud \
  --capture-at=0.15,0.35,0.55,0.85 --capture-sheet --resolution 1400x900
```

- `--capture-at` accepts a **list**, captured in one process. The engine boot
  dominates a single capture, so a phase sweep costs one launch instead of one
  per frame.
- `--capture-sheet` tiles the series into a single image, so phases are compared
  side by side rather than from memory.
- `--golden=<dir>` compares each capture against a stored reference and exits
  non-zero on failure; `--golden-write` records new references.

Golden comparison is **tolerance-based** for the reason in §3. It defends
structure — palette, layer presence, footprint shape — not individual pixels.
Its weakness is dilution: the mean is taken over the whole frame, so an effect
occupying a small share of it produces a small mean even when it changes a lot.
Frame goldens so the effect fills a decent portion of the image, and treat a
diff merely *near* tolerance as worth a look rather than as a pass.

Goldens currently have no committed home: `/debug/` is gitignored, so references
are local to a machine. Committing a set is worth doing when there is a runner
to compare against; until then they catch regressions within a working session.

**A scene launch does not parse new scripts.** Running the debug scene does not
rescan the filesystem, so a new `class_name` file is never loaded and a probe
can print clean while proving nothing. Use `--import --headless` as the parse
gate; it also generates the `.uid` sidecars that must be committed alongside new
`.gd` and `.gdshader` files. Its progress-dialog errors are known harness noise
(see [`DEVELOPMENT.md`](./DEVELOPMENT.md)).

---

## 6. Checklist for a new effect

1. **Confirm the carrier.** Which spell selects this profile, and what are its
   `RADIUS` and `AREA_SHAPE`? Design to that, not to a hypothetical.
2. **Fork** the closest existing effect and profile. Rename; change only what
   the new look requires.
3. **Author the shader** as a pure function of `INDEX` and `playback_time`.
4. **Set the layer roster.** Drop inherited layers with no equivalent — that is
   what frees node budget for new ones.
5. **Label every constant** `AUTHORED` or `DERIVED` unless measurement was
   actually performed.
6. **Retune count and alpha** for the new geometry before anything else.
7. **Register** one catalog row; add `VFX_PROFILE` to the carrier spell.
8. **`--import --headless`** to parse and generate `.uid` sidecars.
9. **Sweep phases** with one multi-capture command plus `--capture-sheet`.
10. **Validate the carrier's real shape and radius**, not just the defaults.
11. **Check the donor effect still renders** — forks share `VfxTextures`.
12. **Record goldens** once the look is settled.

**When planning the work, check whether the validation item names any
observation the harness cannot produce.** If it does, that is item zero. This
has been learned twice: both the ice and fire cycles stalled on a missing
harness capability that was plainly visible in the plan text before execution
began.
