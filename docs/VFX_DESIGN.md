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
| `is_particle_seek_exact()` | Whether `seek_normalized` reproduces a frame exactly. See §3. |

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

**Connected geometry is still possible under this rule.** `INDEX` addresses a
particle, but nothing stops a shader deriving a *structure* from it: the magenta
implosion's lightning splits `INDEX` into a bolt and a segment along it, then
walks that bolt's path from the origin in a compile-time-bounded loop,
accumulating each kink. Every particle recomputes the same prefix of the same
path, so segment N always begins exactly where N-1 ended — a connected polyline
with no shared state between particles and nothing carried across frames. The
same trick places branches, by walking a parent's path to the fork point first.
Chained, branching, or otherwise interdependent geometry is not a reason to
reach for frame-accumulated state.

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

**Reconsidered at the third, 2026-08-08, and declined — the trigger was
counting the wrong thing.** `MagentaReductionEffect` was the third elemental
effect, and it was forked anyway. What the first two share is not "an effect",
it is the structure of a *storm*: ground wash, an outward and upward particle
field, a crown above it, one continuous arc from onset to settle. The implosion
has none of that — it pulls inward, it runs a four-beat timeline whose third
beat holds before anything is released, and it carries a core and a discharge
while dropping the crown. A resource abstracted from three files where the third
only barely fits would have fixed the wrong shape for everything after it.

**Restated trigger: the next effect that is structurally a storm**, counting
shapes rather than files. Tracked in `BACKLOG_LONGTERM.md`, which also records
that `IceStormProfile`'s `MEASURED` labels have to survive any migration. The
general lesson is worth keeping: *a "do it at the third" rule needs to say the
third **what**.*

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
- **A radial sprite cannot be stretched into a streak.** `VfxTextures`'
  sprites — `softFlake()` above all — are radial gradients, opaque at the centre
  and zero at the rim. Scaling one onto a long thin quad puts that opaque centre
  in the middle of the streak and fades both ends out, so the best it can
  produce is a soft blob where a line was wanted. **Pick the sprite for the
  silhouette you want**, and add one rather than stretching a wrong one:

  | Sprite | For |
  | --- | --- |
  | `softFlake()` | Round specks; the default particle. |
  | `lanceStreak()` | A single tapered streak with a pointed head. |
  | `boltSegment()` | One link of a chained path — uniform along its length, so joints do not pinch. |
  | `sparkleFrames()` | Hand-drawn four-frame sparkle. The one authored texture here. |
  | `pixelDot()` | Small hard dots, for a field that must be *countable*. |

### Authored textures and frame animation

`VfxTextures` generates everything procedurally, with one exception:
`sparkleFrames()` is drawn pixel art. The rule that earned the exception is
worth keeping — **generate what has to scale with a footprint or vary per seed;
draw what carries shading choices a formula would only approximate.** A sparkle
does neither of the first two, and its white-core/warm-mid/cool-rim palette is
the reason to use art at all.

Three things that bite when an authored sprite is animated over particles:

- **`detect_3d/compress_to` defaults to 1**, which silently re-imports any
  texture used in 3D as VRAM-compressed. Block compression through a handful of
  flat colours is visible ruin. Set it to `0`, along with
  `process/fix_alpha_border=false`, for any pixel-art source.
- **`BILLBOARD_PARTICLES` is not optional.** It is the only billboard mode whose
  generated shader reads `INSTANCE_CUSTOM.z` and offsets `UV` into the
  `particles_anim_h_frames` grid. Writing `CUSTOM.z` under any other mode
  animates nothing and reports nothing.
- **Drive the frame from the effect's own clock, never `TIME`.** §3's rule
  applies to animation phase exactly as it does to motion: the implosion's
  sparks take their frame from each spark's `age`, so they scrub and freeze with
  everything else. A `TIME`-driven strip keeps animating on a paused frame and
  breaks golden capture.

An authored sprite also inverts the palette convention: the shader **multiplies**
it rather than owning it, so the tint constant is white by default and exists
only as a later escape hatch.
- **A shader-built basis that is left-handed gets the whole layer culled.** An
  effect that writes its own `TRANSFORM` basis — to point a quad along a travel
  direction, say — must keep `cross(X, Y)` pointing the same way as the `Z` it
  assigns, or the quad's winding flips and `CULL_BACK` discards it from the side
  the camera is actually on. Nothing warns: positions, colours, alpha, and
  particle counts are all correct and the layer is simply absent. The magenta
  implosion's discharge lost two capture cycles to this, and the first cycle was
  misattributed to the texture trap above, which was *also* present and made a
  plausible-looking culprit. Set `cull_mode = CULL_DISABLED` on any additive
  shader-oriented layer; it writes no depth and lights nothing, so culling buys
  it nothing and costs an invisible layer the next time the basis is edited.

  The general lesson: **when a layer renders nothing, suspect the basis before
  the texture.** A wrong texture usually produces something faint and wrong; a
  flipped winding produces exactly zero pixels, which is what a blank frame
  actually looks like.

### Pixel-art sprites: posterize first, filter second

An effect that should show its pixels needs **both** halves, and the texture
half matters more:

- **`TEXTURE_FILTER_NEAREST`.** Bilinear resamples every texel boundary into a
  gradient, so a hard source arrives smoothed back out.
- **Posterized alpha.** A `smoothstep` falloff spends most of its range at very
  low alpha, spreading a long dim tail over many texels; under additive blending
  that tail *is* the soft halo hiding the grid. `VfxTextures._posterizeAlpha()`
  snaps to a few levels and cuts the tail.
- **A coarse source.** A texel has to cover more than a screen pixel, so these
  sprites are authored at 8–16px rather than 32–64.

Two traps, both hit while building the magenta implosion:

- **The cutoff must sit below the lowest non-zero level.** At a cutoff of 0.34
  against three levels, everything at 1/3 was discarded — which erased
  `sparkleStar()`'s spikes and left a bare core. The stars rendered as plain
  squares with nothing in the code looking wrong.
- **A hard-edged sprite reads as larger and heavier than a soft one of the same
  nominal size**, because its edge is where you think it is. Every size and
  alpha tuned against a radial sprite needs re-tuning downward after the switch;
  the implosion's motes merged into a solid mass until they came down by a third.

Filtering is a property of the **material**, and the shared factories in
`VfxTextures` are used by the storms too. Set `texture_filter` on the effect's
own duplicate rather than changing the factory, or a pixel-art effect quietly
restyles every effect that shares the material.

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

### Everything is a parameter

**Standing rule, applying to every new effect unless the item commissioning it
says otherwise in writing:** no timing, colour, count, size, speed, or geometry
value may sit as a literal in effect code or in a shader body. Every one is a
labelled constant on that effect's profile class, forwarded to the shader as a
uniform.

The test is blunt: *can a later session change the look by editing profile
constants alone?* If retuning the palette or the swirl rate means reading the
shader, the effect is under-parameterized and the next session pays for it.

This is also what makes the debug harness's layer isolation worth anything —
`swirl_enabled` and `flicker_enabled` on `fire_storm_vortex.gdshader` exist so a
motion component can be switched off and looked at, not because the game ever
sets them to zero.

### Radius 1 to many is a correctness test

An effect does not choose its radius. The carrier's `RADIUS` arrives at runtime
through `setFootprint()`, and the same profile has to hold from a single tile to
a wide field — `Smoke Tower` alone moved from radius 1 to 3 in one editing pass.

**Author every dimension as a function of the footprint, and validate at radius
1, at the carrier's real radius, and at something large (4+).** A constant
offset tuned at radius 2 spills outside the footprint at radius 1 and reads as a
speck in an empty field at radius 5. Both are the same bug, and neither shows up
if the only capture ever taken is at the default.

**A jagged path is shorter than it looks.** A chained path whose segments kink
spends much of its arc length moving sideways, so its *radial* reach is well
under its nominal length — the magenta implosion's bolts reached about half the
field at a length nominally equal to it. If an effect builds a wandering path,
it needs an explicit overshoot multiplier, and that multiplier is a function of
the jag: raise one and the other has to follow.

**Heights are the offset this catches most often.** Both instances so far have
been vertical: a particle band authored in world units at the carrier's radius
projects clear of the footprint at radius 1, because the tile shrinks and the
hover does not. The magenta implosion's motes were authored at 0.14–0.86 u for
radius 3 and read as a cloud floating beside a radius-1 target — the horizontal
clamp was never violated, only the height. Express hover heights as a fraction
of the footprint's world half-extent, and the radius-1 capture stops finding
this.

Where a value genuinely should not scale — a core sprite that must stay a
readable size at every radius, say — that is a decision worth one line of
comment on the constant, not a silent literal. Note that this can split within
one layer: the implosion's core keeps a near-fixed *size* for readability while
its *height* scales, and both halves of that need saying.

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

## 6. Show the work before it is finished

**Standing rule: VFX work reports visually, mid-flight, not just at the end.**
An effect is judged by eye and by nobody else, so a session that writes an
entire effect and only then produces its first image has bet the whole budget on
one guess. The two effects built so far both showed that the expensive mistakes
— density, alpha, palette clipping — are the ones a single early frame would
have caught.

Any plan that commissions an effect names its **proof checkpoints** up front:
the points at which the session stops, captures, and shows the user something
before continuing.

A workable default for a new effect:

| Checkpoint | Proof | Roughly |
| --- | --- | --- |
| Skeleton renders | One capture at mid-timeline, any radius. Layers present, footprint right, nothing else claimed. | after registration |
| Phase structure | `--capture-sheet` across the phase boundaries the design names. | after the shader's motion is in |
| Radius sweep | One sheet per radius: 1, the carrier's, and a large one. | before tuning |
| Final look | Sheet at the carrier's real radius and shape, plus the donor effect still rendering. | before goldens |

Cheapest form, one launch per checkpoint:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --effect=<profile> --radius=<r> --seed=7 --hide-hud \
  --capture-at=0.12,0.30,0.50,0.70,0.90 --capture-sheet --resolution 1400x900
```

**Stop at a checkpoint that looks wrong rather than pressing on to the next
item.** Continuing past a bad frame is how a session ends with a lot of
committed code and a look nobody wants; the sheet is there so that the
conversation about it happens while it is still cheap to change.

---

## 7. Checklist for a new effect

1. **Confirm the carrier.** Which spell selects this profile, and what are its
   `RADIUS` and `AREA_SHAPE`? Design to that, not to a hypothetical.
2. **Fork** the closest existing effect and profile. Rename; change only what
   the new look requires.
3. **Author the shader** as a pure function of `INDEX` and `playback_time`.
4. **Set the layer roster.** Drop inherited layers with no equivalent — that is
   what frees node budget for new ones.
5. **Label every constant** `AUTHORED` or `DERIVED` unless measurement was
   actually performed. Nothing stays a literal in code or shader — see §4.
6. **Retune count and alpha** for the new geometry before anything else.
7. **Register** one catalog row; add `VFX_PROFILE` to the carrier spell.
8. **`--import --headless`** to parse and generate `.uid` sidecars.
9. **Sweep phases** with one multi-capture command plus `--capture-sheet`, and
   **show it** — that is a proof checkpoint, not a private check (§6).
10. **Sweep radius** 1 / carrier / large, and validate the carrier's real
    shape, not just the defaults.
11. **Check the donor effect still renders** — forks share `VfxTextures`.
12. **Record goldens** once the look is settled.

**When planning the work, check whether the validation item names any
observation the harness cannot produce.** If it does, that is item zero. This
has been learned twice: both the ice and fire cycles stalled on a missing
harness capability that was plainly visible in the plan text before execution
began.
