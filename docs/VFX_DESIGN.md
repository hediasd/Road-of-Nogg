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
CombatResolver    resolves ordered target IDs and the live spell footprint,
        │         then emits spell_cast_started for every cast
        │
GodotVisualAdapter._on_spell_cast_started
        │         reads only VFX_PROFILE from the catalog; copies the event's
        │         resolved radius, shape, and event-time source/target snapshot
        │         onto a CAST_AREA VisualAction; derives a deterministic seed
        │
GodotVisualAdapter._start_cast_area_animation
        │         resolves the profile, enforces the live cap, spawns,
        │         configures VfxCastContext and the optional footprint, plays,
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

**The cast event owns the resolved footprint.** Gameplay uses the mutable
`Spell` instance attached to the caster, so a transient `radius += 2` must reach
presentation from `CombatResolver`; presentation must not re-read the immutable
catalog radius. A single-target cast reports radius 0. An area cast and a
self-area cast report the same radius and shape used by `ShapeCaster`.

**The cast context owns target-bound presentation geometry.** Every profile
receives a `VfxCastContext` before `play()`, containing the source and impact
world positions plus stable target IDs, event-time target positions, and
body-only local bounds. It may also carry a generic event-time world-space
surface path for ground-bound presentation; this is adapter-owned terrain data,
not a VFX-specific simulation event or a lazy playback query. Effects that do
not need those values inherit the default no-op. The simulation never imports
this context or any visual node.
When a target visual is missing or already defeated, the adapter supplies a
standard authored body box centered at the event impact.

---

## 2. The `VfxPlayback` contract

Every effect extends `src/presentation/effects/VfxPlayback.gd` and implements:

| Member | Obligation |
| --- | --- |
| `configure_cast_context(context)` | Receive the standard target/source snapshot before `play()`. The base implementation is a no-op. |
| `play(seed, mode)` | Start from zero. `mode` is `MODE_BATTLE` or `MODE_REFERENCE`, selecting which duration applies. |
| `seek_normalized(t)` | Present the exact frame at `t` in 0..1, forwards or backwards. |
| `set_playback_scale(f)` | `0.0` freezes. Drives pause and the game's animation-speed setting. |
| `skip_to_settle()` | Jump to the tail so a skipped action does not cut mid-burst. |
| `dispose()` | Free everything. Safe to call twice, and while playing. |
| `get_layer_names()` / `set_layer_visible()` | Named layers, for isolating one at a time while authoring. |
| `get_live_particle_count()` / `get_live_instance_count()` / `get_live_node_count()` | Honest live figures; the debug HUD and budget checks read them. |
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

Each profile carries `MAX_EFFECT_NODES`, `MAX_DRAW_CALLS`, and the relevant
particle or geometry-instance ceiling, asserted while its layers are built so a
violation fails loudly at construction rather than being noticed as a
frame-rate problem later.

### Target-bound volumetric shells

`ice_target_encasement` is the first profile driven by `VfxCastContext` body
bounds rather than by an area footprint. It uses three effect-owned low-poly
meshes—block, wedge, and irregular crystal—distributed into explicit
`shell_rear`, `shell_sides`, `shell_front`, and `shell_cap` layers. Eleven
authored hero forms replace a regular front/rear grid: broad lower/front slabs,
uneven side walls, rear silhouette masses, and two unequal cap pieces scale
against the supplied body bounds. Small seeded position/rotation/scale jitter
does not erase that size hierarchy.

The shell uses true transparent-cyan alpha, an alpha depth prepass, and explicit
rear/side/front/cap render priorities. Pale front and cap faces build toward
white-cyan where the volume overlaps, while darker blue facets keep adjoining
pieces readable. This avoids modern refraction and also avoids screen-door
dither: a 4×4 Bayer experiment was rejected because the shipping retro upscale
collapsed it into horizontal moiré. A small `ice_core` remains independently
toggleable, and shell-only captures must read without it.

Formation begins at the caster-facing lower contact point derived from the
event-time source position and target body bounds. The broad lower slab erupts
there while the last ground spike is still visible. Later chunks begin from a
progressively wider lower footprint, rise along their own final spatial role,
overshoot slightly, and settle into the authored shell: lower/side masses first,
rear and upper shards next, unequal cap pieces last. Initial forms retain broad
horizontal dimensions instead of expanding uniformly from the target centre.
All eruption and settle transforms are pure normalized-time functions.

Every chunk records its intact transform plus seeded linear velocity, angular
axis/speed, and a slight launch delay when the shell is built, then keeps one
stable MultiMesh slot for its full lifetime. Breakup is analytic projectile
motion: `p = p0 + velocity * time + 0.5 * gravity * time squared`. Position is
never eased toward an endpoint, and piece scale remains constant. Lower slabs
receive shallow trajectories, side pieces move laterally, and upper/cap shards
receive higher arcs; size slows both launch and spin so large slabs retain
weight. No rigid bodies, accumulated integration, or random sampling occurs
after shell construction. Seeking backward or forward therefore recomputes the
same transform, and skip lands late in the same ballistic motion instead of
cutting away a closed statue.

The effect does not mutate the target model. If a future target-bound profile
needs pose hold or tint, `GodotVisualAdapter` must own a reversible lease and
restore prior state on completion, skip, disposal, and battle exit; an effect
must never reach through its context to edit arbitrary target materials.

Timeline code must not replace instances at fracture time: the large pieces
visible in the closed statue are the pieces that leave it.

Three effect-local supporting layers establish delivery without competing with
the shell. `delivery_trail` uses 8–12 irregular low-poly ground spikes planted
along the context's event-time surface path. Their bases never translate: each
spike grows in source-to-target order, then recedes after impact. Missing path
samples fall back to a two-point source/target path rather than silently
querying mutable terrain during playback. `contact_accents` uses eight small
deep-blue square prisms clustered at the same lower caster-facing contact point.
They pop rapidly to a stable readable size, drift only a short distance, and
clear before closure. They remain in a single MultiMesh; applying a standard
billboard material here is forbidden because Godot replaces the per-instance
basis and defeats the scale used to hide their endpoints. `impact_flash` is one
compact low-alpha, depth-independent pulse at that contact point, synchronized
with the final spike and first lower slab.
Each layer is independently toggleable, and all three are gone before the
completed enclosure.

The complete build contains 11 large shell chunks, 8–12 delivery spikes, eight
contact instances, and one core instance. Each shell mesh has a broad inner
seat and a pointed exterior ridge or apex; layer orientation makes that edge
face away from the target on every side. Per-face UVs select deterministic
16×16 cells from `ice_strip.png`, with half-texel atlas insets and nearest
sampling preserving pixel-art facets under the retro renderer. The build stays
within 32 geometry instances, 26 effect nodes, and 16 draw calls. The
delivery/contact population is capped at 20 so later tuning cannot turn the
supporting cues into replacement debris.

The debug catalog and production spell data use the same profile id. `Ice Statue`
is the single-target production carrier: it copies Ice Punch's damage, element,
radius, empty-target behavior, and height constraint, but has an authored
minimum range of 1 and maximum range of 5. `VFX_PROFILE` changes only its
presentation; target-bound effects continue to consume the generic cast context
without a spell-name branch in the adapter.

### Resource ownership and donor-effect guardrails

Anything returned by a shared texture or material factory is a compatibility
surface. A local visual experiment must not silently redefine that surface for
every caller. The ownership rule is encoded in names:

| Factory family | Contract | Current consumers |
| --- | --- | --- |
| `neutralSoftDisc()`, `createNeutralSoftDiscMaterial()` | white radial falloff; additive; stable silhouette | Fire particles, Magenta core |
| `neutralSoftPuff()`, `createNeutralSoftPuffMaterial()` | white continuous noisy puff; additive and linear-filtered | Fire crown, Magenta halo |
| `snowParticleFrames*`, `iceCanopy*` | Ice-owned authored/posterized pixel art | Ice Storm only |

When one effect needs a different silhouette, filter, blend mode, or palette,
add an explicitly owned factory and migrate that effect. Do not modify a
neutral factory in place merely because its first or most visible consumer is
the effect currently being tuned. Neutral resources remain white so consumers
own their palettes without inheriting an element tint.

`VfxTextures` asserts pixel fingerprints for the neutral disc and puff and
asserts their white/additive/filter material contracts when they are first
built. A mismatch is intentionally loud. Updating a fingerprint is not the fix
for a spell-specific request; it is reserved for an intentional neutral-contract
migration after the complete consumer sweep below has been accepted.

Before changing any shared VFX resource:

1. Search for every caller of the texture and material factory.
2. Classify the change as a neutral-contract correction or effect-specific
   tuning. Effect-specific tuning gets a new owned variant.
3. Put every caller—not only the commissioned spell—into final validation.
4. Compare stored goldens where present and capture the carrier timeline where
   no golden exists.

This is a completion gate. A clean target-effect sheet does not validate a
shared factory change. The regression that established the rule changed Ice's
shared radial disc and puff into pixelated Ice silhouettes; Magenta's unchanged
core disappeared and the cyan debug target marker underneath was mistaken for
the effect's centre. The code-level split prevents Ice tuning from reaching
Magenta or Fire, while the donor sweep catches any future shared-contract edit.

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
  sprites — `neutralSoftDisc()` above all — are radial gradients, opaque at the centre
  and zero at the rim. Scaling one onto a long thin quad puts that opaque centre
  in the middle of the streak and fades both ends out, so the best it can
  produce is a soft blob where a line was wanted. **Pick the sprite for the
  silhouette you want**, and add one rather than stretching a wrong one:

  | Sprite | For |
  | --- | --- |
  | `neutralSoftDisc()` | Round specks and compact neutral cores. |
  | `lanceStreak()` | A single tapered streak with a pointed head. |
  | `boltSegment()` | One link of a chained path — uniform along its length, so joints do not pinch. |
  | `sparkleFrames()` | Hand-drawn four-frame sparkle animation. |
  | `pixelDot()` | Small hard dots, for a field that must be *countable*. |

### Sharp lines need the camera's plane, not the world's

"Pixel-perfect" only means something relative to a pixel grid, and a quad
rotated to an arbitrary angle in world space sits on no grid at all. It either
reads soft (wide enough to see, with a ramped cross-section) or drops out into
dashes (thin enough to be sharp, below the raster's reach). No texture fixes
this; it is geometry.

What does fix it, as built for the magenta implosion's discharge:

- **Build the layer in the camera's plane.** Pass the camera's right and up axes
  in as uniforms — a particles process shader has no access to the camera matrix
  — and lay the geometry out in the 2D coordinates they span. A heading in that
  plane *is* a screen heading.
- **Quantize headings to 8 or 16 notches.** Axis-aligned and 45-degree runs are
  what hand-drawn pixel lightning is made of. Quantizing in world space and then
  projecting through an isometric camera does not work: a world 45 is not a
  screen 45.
- **Turn in whole notches, never by snapping a continuous angle.** Snapping the
  result of a ±31-degree random kink against a 22.5-degree half-step rounded
  ~70% of turns back to their original heading, and the bolts rendered as
  straight rays with the jag apparently missing.
- **Pull each turn back toward the launch heading.** An unbiased walk over
  notches does not preserve direction — bolts curled and folded instead of
  radiating. The roll supplies the jag; the restoring pull supplies the heading.
- **Binary alpha.** A partial-alpha sheath under additive blending is a glow,
  and a glow is the opposite of a sharp line.
- **Fix the width in world units, not as a footprint fraction.** A sharp line is
  defined in pixels, so scaling thickness with the footprint means only one
  radius is ever the crisp one.

Two consequences to accept up front: the layer stops being spatially grounded —
it no longer crawls over terrain — and it needs `no_depth_test`, because
geometry heading *downward on screen* passes below the board and gets
depth-tested away by whatever terrain happens to stand in front, which ate close
to half the burst asymmetrically. Depth testing buys nothing for a layer with no
spatial grounding.

At the project's native render this yields **crisp**, not pixelated: there is no
chunky grid to align to at 1400x900. True pixel-art lightning needs the effect
seen through the retro viewport.

**World up is the one exception.** Both cameras are orthographic
(`BattlePresentationController._setup_camera_and_lighting`,
`VFXDebugController._configureBattleWorld`) and both re-derive their transform
with `look_at(focus, Vector3.UP)` every frame, so neither ever rolls. Under an
orthographic projection with zero roll, world up maps to screen up exactly, and
a world-vertical edge is a vertical raster line anywhere in frame, at any yaw or
pitch. Geometry that stands on the world's up axis — such as target-encasement
spikes — is therefore sharp without any camera-plane construction, and it
keeps the spatial grounding the camera-plane layer gives up. Only *arbitrary*
world angles need the camera's plane. Confirm the projection before relying on
this: a perspective camera would converge those verticals toward a vanishing
point, and only the geometry through the screen centre would stay vertical.

If a layer built this way is a flat quad rather than a closed shell, it also
has to face the viewer, and that must be a Y-axis billboard — spin it around
world up using the camera's right axis (`INV_VIEW_MATRIX[0]`, flattened onto
the horizontal plane), never a full billboard, which would tilt it off vertical
and forfeit the sharpness.

### Generic spell-cast aura: reference-locked rebuild

Eleven consecutive source frames supersede the earlier still-image
decomposition. They support one evolving footprint aperture/boundary and one
broad changing plume crown; they do not support separated ground waves, a
central glow column, individual lance rods, or rising particles.

At the current committed implementation boundary the generic aura deliberately
renders only the footprint aperture. One world-horizontal alpha-mixed plane
draws a single feathered boundary whose radius contracts slightly before
expanding late. Two tightly packed internal striations add early rim texture
and disappear as the opening simplifies. They remain inside the main rim's
feather rather than travelling as separate concentric rings. Camera pitch alone
supplies the apparent ellipse.

The supplied screenshots have a black background and no alpha, so they cannot
prove whether the aperture centre is opaque darkness or transparent negative
space. Runtime therefore defaults to transparent. `set_center_darkening()` and
the `--spell-aura-dark-center` debug flag select a low-alpha navy variant for
the required terrain comparison without changing geometry, timing, or the
one-draw-call budget.

The rejected core cards, crossed ribbons, and `GPUParticles3D` mist have been
removed with their owned shaders. The effect no longer consumes
`VfxTextures.neutralSoftPuff()` or `VfxTextures.lanceStreak()`, reports zero
particles, and returns true from `is_particle_seek_exact()`. The remaining
source-authoritative plume crown is open build work; it must use continuous
world-space carriers and retain the clean character silhouette without
restoring a hero-scale billboard.

### Authored textures and frame animation

`VfxTextures` generates scalable silhouettes procedurally and preserves two
authored pixel-art sources: `sparkleFrames()` and Ice Storm's
`snow_strip.png`. The rule that earns an authored source is worth keeping —
**generate what has to scale with a footprint or vary per seed; draw what
carries shading or silhouette choices a formula would only approximate.** The
sparkle's palette and the snow particles' four distinct silhouettes are the
reason to use their art at all.

An authored source does not have to arrive as a regular animation strip. Ice
Storm's four flakes occupy irregular positions in an 80x32 canvas, so
`snowParticleFrames()` copies four exact 8x8 regions into a 4x1 runtime atlas.
`Image.blit_rect()` copies texels one-for-one: the source stays untouched,
nearest filtering stays meaningful, and the particle shader can select frames
without per-particle materials. Do not crop, resize, or regenerate authored
pixels merely to make their packing convenient.

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

Static frame selection needs a declared distribution, not a uniform random
roll by accident. Ice Storm packs its atlas smallest-to-largest and uses
52/30/14/4 percent weights. The one-pixel and four-pixel flakes therefore form
the field; the six- and eight-pixel flakes provide sparse punctuation without
turning an expanded storm into a wall of repeated icons.

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

An effect does not choose its radius. The live resolved radius arrives through
the cast event and `setFootprint()`, and the same profile has to hold from a
single tile to a wide field — including transient buffs that never change
`data/spells.json`.

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

For precipitation, use one vertical envelope rather than independently scaling
the cloud and the falling particles. Ice Storm first derives a `snowCeiling`
from radius with a sublinear power (`height proportional to radius^0.65`, with
profile clamps), starts every flake at or below that ceiling, and then positions
each cloud puff so its lower opaque half straddles the same value. Cloud height,
frost height, particle descent speed, and the visibility AABB all derive from
that contract. Expanding the footprint can therefore raise the storm without
allowing snow to originate above a cloud authored for a smaller radius.

Do not make one billboard as wide and tall as the full footprint. Under an
isometric camera that becomes a translucent horizontal slab. Ice Storm uses
five smaller puffs distributed by golden-angle coverage across the footprint;
the deck grows through coverage and shared height, not one stretched rectangle.

Where a value genuinely should not scale — a core sprite that must stay a
readable size at every radius, say — that is a decision worth one line of
comment on the constant, not a silent literal. Note that this can split within
one layer: the implosion's core keeps a near-fixed *size* for readability while
its *height* scales, and both halves of that need saying.

Counts should normally scale more slowly than occupied area. For a Manhattan
diamond, `A(R) = 1 + 2R(R + 1)`. Ice Storm uses
`N(R) = clamp(N0 * sqrt(A(R) / A(R0)), Nmin, Nmax)`: radius 4 occupies 41 tiles
and radius 6 occupies 85, but the flurry grows from 120 to about 173 particles
rather than doubling to 249. This keeps presence while preserving negative
space and the 220-particle ceiling.

### Mathematical design grammar

Use constants for a job they are mathematically suited to, then judge the
result. They are not hidden quality multipliers.

| Family | Owns | Good VFX uses | Do not use it for |
| --- | --- | --- | --- |
| `PI` / `TAU` | angular and periodic structure | headings, arcs, orbit phase, waves, radial boundaries | arbitrary damage, counts, or timings |
| `exp()` / e | energy changing through time | attack/release envelopes, decay, drag, frame-rate-independent response | a generic replacement for every easing curve |
| `PHI` / golden angle | progressive low-discrepancy distribution | particle positions, shard directions, non-repeating stagger, sphere sampling | claiming a rectangle or duration is automatically beautiful |

Godot exposes `PI` and `TAU` directly; `TAU` is one full turn and therefore the
clearer constant for headings and periodic phase ([Godot `@GDScript`
constants](https://docs.godotengine.org/en/stable/classes/class_%40gdscript.html)).
Ice Storm uses `TAU` for shard rotation and periodic canopy motion, then snaps
those continuous angles to an eight-heading PS1 vocabulary.

Use an exponential half-life when an energy should lose the same *fraction*
over equal time intervals:

```gdscript
var remaining := exp(-log(2.0) * elapsed / halfLife)
var responseWeight := 1.0 - exp(-responseRate * delta)
```

The first is a readable decay contract; the second makes smoothing independent
of frame rate. Godot provides `exp()` in global scope ([Godot
`exp`](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html)).
Ice Storm uses exponential charge/reveal and settle envelopes, then samples
motion at 15 Hz so the energy arc stays natural while its display reads retro.

The golden ratio is `PHI = (1 + sqrt(5)) / 2`. Its practical graphics tool is
usually the **golden angle**, `TAU / PHI²` (about 137.508 degrees): adding one
sample at a time tends to fill the largest remaining gaps. Schretter, Kobbelt,
and Dehaye describe golden-ratio sequences for progressive low-discrepancy
sampling on squares and discs ([paper and
download](https://www.graphics.rwth-aachen.de/publication/032/)); spherical
Fibonacci mapping applies the related construction to nearly uniform sphere
samples ([Keinert et al., 2015](https://cris.fau.de/publications/116802224/?lang=en_GB)).

Ice Storm starts flake and hero-shard directions from the golden angle, adds a
small deterministic seeded jitter so no sunflower spiral becomes visible, and
then applies footprint masking and PS1 quantization. The effect is expected to
survive a count change without entirely re-clumping.

The aesthetic claim is deliberately weaker than the sampling claim. Controlled
studies have found no special preference for the golden section over nearby
ratios ([Boselie,
1992](https://journals.sagepub.com/doi/abs/10.2190/QB14-NK7B-ARYT-W5QT);
[Russell,
2000](https://journals.sagepub.com/doi/abs/10.1068/p3037)). Therefore:

- do not force Fibonacci counts, golden rectangles, or `PHI`-sized timing
  windows into every effect;
- compare golden-angle placement against seeded random placement at identical
  count, alpha, radius, retro, and CRT settings;
- keep it only when it measurably reduces clumping without exposing a spiral.

A golden spiral combines all three families:
`r(theta) = r0 * exp((log(PHI) / (PI / 2)) * theta)`, growing by `PHI` each
quarter turn. It suits deliberately ordered magic such as summoning, healing,
growth, or an implosion. It is too orderly to be Ice Storm's dominant motion;
there the golden angle is only the invisible distribution substrate.

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

Target-bound effects use explicit caster and target anchors in this scene. The
harness creates their `VfxCastContext` through the same factory battle playback
uses, so previewed source/impact positions, stable target identity, and
body-only bounds cannot drift into a harness-only convention. The target body
control offers `standard`, `wide`, and `tall` bounds; source separation and
camera yaw are both inspectable through the HUD and controllable with
`--source-distance=<units>` and `--camera-yaw=<degrees>`. Use
`--target-body=<standard|wide|tall>` in scripted captures. The retro viewport
is enabled by default, and the status readout includes the selected bounds,
separation, yaw, live node/particle totals, and a mesh/particle draw-call
estimate.

The proxies stand on opposing 3×3 terrain islands with the middle corridor
empty, matching the harness's original composition. The caster is centred on
the flat green island and the target on the height-2 centre of the uneven blue
island. Both use the original capsule proxy silhouette; the target capsule
scales to the selected body-bound preset. Source separation moves the complete
islands symmetrically rather than sliding models across fixed terrain. Its
minimum is 4 world units, which preserves at least the original one-cell empty
corridor.

Three controls exist for judging one effect rather than a delivery path.
`--element=<name>` picks the tint from `BattleMeshFactory`'s palette, which is
what makes an element sweep reproducible for any effect whose colours all
derive from that one argument. `--camera-size=<units>` overrides the
distance-derived orthographic size, and `--camera-focus=<midpoint|caster|target>`
chooses what the camera looks at. The default wide two-island framing is right
for a caster-to-target path and far too wide to judge geometry standing on one
tile; `--camera-size=5 --camera-focus=target` frames that case.

The retro viewport starts enabled. Scripted comparisons use
`--render-resolution=<native|640x480|480x360|320x240>` with `--retro`, or
`--no-retro` for the matched native-render frame; capture commands never need
an interactive resolution or render-mode toggle to produce either side.

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

**Record the command that wrote a golden.** A set whose flags are unknown is
worse than no set: a stale reference fails identically at every commit, and the
failure looks like a regression rather than like a reference nobody can
reproduce. That is exactly what happened to the previous set — every frame
failed by roughly 12, four times the score of comparing two entirely different
effects. Regenerate with:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --resolution 900x600 --effect=<profile> --seed=7 --radius=4 --element=ice \
  --hide-hud --capture-at=0.2,0.45,0.75 --capture-out=user://<name> \
  --golden=debug/vfx_golden --golden-write
```

`--hide-hud` matters: the menu column otherwise takes a quarter of the window
and the world is letterboxed into the rest, so a golden written with the panel
visible frames differently from one written without it.

### Panel, camera, and live tuning

The scene is a fixed menu column on the left and a navigable world pane on the
right. The pane letterboxes to the window's own aspect so framing judgements
transfer to the game; `--pane-aspect=fill` spends the whole pane on pixels
instead. Hiding the menu (`H`, `--hide-hud`) gives the world the whole window.

The pane's camera is `BattleCameraController` — the same class the battle scene
uses, not a copy — so orbit, pan, and zoom behave identically. Changing source
distance or target body moves the focus point only; yaw, pitch, and zoom are
taken over solely by initial framing, the `--camera-*` flags, and Reset.

Effects expose parameters for live authoring by declaring a `tunables()` roster
on their playback. The debug panel builds its controls from that descriptor and
holds no effect-specific code, so declaring a roster is the whole cost of
getting an editor. Profiles keep their `AUTHORED` / `DERIVED` labels and supply
the defaults — they remain the source of truth, and the panel carries only the
differences. `--tune=NAME=value,...` and `--tune-load=<path>` give the same
reach from the command line, and **Export** prints paste-ready `const` lines for
exactly the constants that changed, which is what keeps a tuning session from
ending in hand-transcribed numbers.

Changing a rebuild-class parameter replays the effect at the pinned seed and
re-seeks to the current timestamp. Determinism is what makes that watchable
rather than jarring.

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
