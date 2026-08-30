# Generic spell-cast aura

`spell_cast_aura` — the default carrier a spell falls back to when it names
no other profile. The contract and conventions this implements live in
[`../VFX_DESIGN.md`](../VFX_DESIGN.md).

Eleven consecutive source frames supersede the earlier still-image
decomposition. They support one evolving footprint aperture/boundary and one
broad changing plume crown; they do not support separated ground waves, a
central glow column, individual lance rods, or rising particles.

The footprint is one world-horizontal alpha-mixed plane. It draws a single
feathered boundary whose radius contracts slightly before expanding late. Two
tightly packed internal striations add early rim texture and disappear as the
opening simplifies. They remain inside the main rim's feather rather than
travelling as separate concentric rings. Camera pitch alone supplies the
apparent ellipse.

The supplied screenshots have a black background and no alpha, so they cannot
prove whether the aperture centre is opaque darkness or transparent negative
space. The terrain A/B was therefore resolved as a deliberate art-direction
choice: runtime uses the approved low-alpha navy aperture by default.
`set_center_darkening()` and the `--spell-aura-transparent-center` debug flag
retain the transparent comparison path without changing geometry or timing.

The vertical field uses two smooth profiled `ArrayMesh` ring shells with
different material jobs. The compact inner shell is low-alpha deep-blue haze;
the taller outer shell is sparse additive ghost rays. Each profile flares
monotonically from the root through its middle to its top. Mesh construction
asserts this ordering, so later tuning cannot silently restore an inward cup.
The ray material rasterizes only one shell hemisphere, leaving the footprint to
close the foreground around the feet. The haze uses a continuous normal mask
to suppress its camera-side contribution. Both meshes remain world-space at
every yaw; neither uses a billboard, camera-relative origin, or camera-driven
transform.

The haze shell uses 0.72/1.05/1.38 root/middle/top radii; the ray shell uses
0.78/1.14/1.52. Those are mean carrier paths, not the alpha boundary of every
individual wisp: a pointed spike may taper locally while its centre continues
outward. Four keyed XZ/Y scale curves translate measured state-to-state
silhouette changes onto the two 3D carriers. The final ray-width sequence is
`1.21, 1.24, 1.22, 1.18, 1.07, 1.16, 1.19, 1.16, 1.22, 1.21, 1.14`; its
height sequence is `0.75, 0.70, 0.68, 0.74, 0.74, 0.85, 0.86, 0.79, 0.86,
0.82, 0.74`. They are driven only by normalized playback progress, never by
camera yaw, pitch, or distance.

The accepted base materials separate mass from highlights. Haze combines 24
overlapping analytic columns, a low root fog, and a restrained sample of the
measured atlas field. It uses alpha mixing at 0.82 authored opacity with a
0.42 alpha ceiling, so it supplies a dark blue connective body on both black
and light terrain. Ghost rays use 24 analytic angular seedsâ€”roughly twelve
visible on the retained far hemisphereâ€”plus broad low-energy shoulders. Their
additive alpha is capped at 0.36, keeping sharp cyan tips without rebuilding an
opaque petal cage. Rays are not grazing-angle attenuated: the single retained
hemisphere already controls overlap, and attenuation measurably narrowed the
source-registered fan.

Cool elements retain the source-locked blue/cyan grading. Red-dominant elements
select a warm luminance-preserving bias so the generic tint contract does not
multiply fire nearly to black. The final cool bias restores the luminance of
the registered material capture while the warm branch remains separately
bounded. No white core is injected into either branch.

`assets/vfx/spell_cast_aura/plume_flow_atlas.png` is original project artwork
generated deterministically by the retained adjacent Python/Pillow source and
the normalized measurements in `source_measurements.json`; source screenshot
pixels are never read or copied. Its eleven 256x256 cells encode angular-U by
height-V fields: red is low continuous haze, green is sparse ghost rays, blue
is close root striation, and alpha is their inspection union. The 360-degree
ray population documents the measured visible group density. Runtime haze and
root detail still sample the atlas as secondary variation. Both plume materials
reconstruct angular U from local 3D position and evaluate their principal
fields analytically per fragment; magnifying the 256-pixel raster ray mask had
exposed its rowwise lean as horizontal terraces. Every atlas cell repeats its
first angular texel at the last column and the generator validates the RGB seam
before saving.

`compare_replica.py` is the convergence gate for this effect. It accepts eleven
ordered source paths and eleven debug-render paths, registers the debug proxy
to the source character's centre, feet, width, and height, and writes a paired
inspection sheet plus a machine-readable report. Source files stay external;
the report retains only names, hashes, dimensions, registration data, and
measurements. The command shape is:

```bash
python assets/vfx/spell_cast_aura/compare_replica.py \
  --source <source-01.png> ... <source-11.png> \
  --render <render-01.png> ... <render-11.png> \
  --report assets/vfx/spell_cast_aura/replica_baseline.json \
  --sheet debug/aura_comparison.png \
  --envelope-plot debug/aura_envelope.png \
  --command-label <capture-contract>
```

Later iterations pass `--baseline=<report>` to classify every shared metric as
closer, unchanged, or worse. `--onset <frames>` plus matching
`--onset-progress <times>` adds zero-pixel, visible-height, energy, and centroid
checks for the uncaptured lead-in without pretending those frames came from the
source sequence.

The report measures faint/dense silhouette bounds, energy centroid, aperture,
angular distribution, palette, body overdraw, registered radial envelopes,
temporal deltas, and several horizontal-edge probes. Those last probes are
supporting signals rather than an automatic stripe detector: legitimate radial
rays in the source also
produce strong row-edge energy, so enlarged tip crops remain mandatory when
judging shell terraces.

`replica_convergence.json` records the retained motion-and-grading pass. Like
the frozen baseline, it contains only hashes, registration data, measurements,
and verdicts; supplied source frames and generated comparison sheets remain
outside version control.

The CPU maps normalized seek onto the eleven measured source positions and
passes an explicit atlas position to both shaders. Motion between authored
states is also derived from this position, so neither shader uses `TIME`.
Haze uses a longer keyed crossfade. Analytic rays reorganize continuously from
the same normalized source-state position. Haze and footprint rotate 0.10 turn
while the ghost rays rotate 0.18 turn over the sequence. Each ray tip samples a
1.15-cycle vertical oscillation with a 0.105 normalized-height amplitude and a
1.731-radian per-ray phase step, so the spikes do not breathe in unison.
`set_plume_state_crossfade()` and
`--spell-aura-crossfade-plume` retain the forced atlas-crossfade inspection path
for haze; analytic rays remain continuous.

The animation is source-keyed rather than a generic charge/decay envelope.
Separate eleven-value curves control plume energy, layer visibility, width,
height, aperture radius, rim width, and striation visibility. Source-relative
plume energy follows
`1.00, 1.13, 1.11, 0.96, 0.79, 0.64, 0.61, 0.76, 0.82, 0.85, 0.70`, preserving
the source's early crest, trough, and smaller secondary swell. Independent haze
and ray visibility grading restores body energy without flattening that rhythm
or lifting every tip equally. The final source
state remains fully visible at normalized time `0.82`; a separate smooth
visibility tail clears every layer by `0.90`. Seed changes apply only a subtle
angular phase offset and cannot replace these curves or their silhouette.

The lead-in is not a global fade of that complete state. At normalized time
`0.0`, footprint and plume root ignition are both zero. The footprint ignites
first; the plume begins at `0.01`, and a world-height reveal front climbs from
the shell root through `0.08`. Its feather sits behind the front, so no plume
pixel can appear above it. The front finishes above UV 1.0, leaving the first
measured state byte-identical to the pre-onset baseline. Root ignition, reveal
height, keyed plume energy, and lifecycle decay remain separate normalized
channels, with no shader `TIME` dependency.

The rejected core cards, crossed ribbons, and `GPUParticles3D` mist have been
removed with their owned shaders. Haze and rays own separate materials and
lower/middle/upper mesh profiles rather than switching roles through a UV phase.
The effect no longer consumes
`VfxTextures.neutralSoftPuff()` or `VfxTextures.lanceStreak()`, reports zero
particles, and returns true from `is_particle_seek_exact()`. The complete
carrier budget is three instances/draw calls: footprint, haze, and ghost rays.
None is a hero-scale billboard.
