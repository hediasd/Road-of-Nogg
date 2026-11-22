# Cross-filter sparkles

Profile `cross_filter_sparkles`. Pink four-ray stars twinkling round a body's
outline on a held 12 fps clock. It plays once per cast.

**Carrier: Shine**, as a placeholder (since 2026-11-22). Shine is a light
self buff that also reaches allies within radius 2, so the sparkles surround
every unit it buffs. Its spec is just `{"PROFILE": "cross_filter_sparkles"}`.
The profile reaches the active set through `SpellVfxCatalog.AUTHORED_CATALOGS`,
the one non-cube exception to the cube-only catalog. Preview it in the debug
scene with:

```bash
Godot_v4.4-stable_win64.exe --path . scenes/VFXDebugScene.tscn \
  --effect=cross_filter_sparkles --seed=7 --camera-size=5 --camera-focus=target
```

Files: `effects/CrossFilterSparkleEffect.gd`, `CrossFilterSparkleProfile.gd`,
`CrossFilterSparkleCatalog.gd`, `assets/shaders/cross_filter_sparkle.gdshader`.

## The reading behind it

Studied on 2026-11-19 from three frames of a 1994 TV cel. Every sparkle in
those frames, dots included, turned out to be the same element: a soft core
with four thin rays, all at one diagonal angle, with ray length tracking
brightness. That is what a cross-screen camera filter does to every light in a
frame. So the effect has one sparkle type and one brightness value per
sparkle, which drives the core and the rays together; the rays grow faster than
the core, so dim sparkles read as dots.

The palette stops at energy 0.30 and 1.00 and the 3 px ring colour are
`MEASURED` from six stars on black in the second frame. Everything else is
`AUTHORED`. An interactive HTML sketch settled the motion; the user picked
12 fps held drawings over 8 fps and smooth.

## How it is built

- **One MultiMesh, one draw call.** Slots are grouped. Each group has two
  lanes, and each lane has a leader plus up to three followers that pop in one
  after another along the edge, spaced so neighbouring rays cross.
- **Pure function of slot, seed and clock.** The shader derives every sparkle
  from `INSTANCE_ID`, the seed and `playback_time`, and the GDScript floors that
  clock to `FRAME_RATE` before handing it over. Seeks are exact and the held
  frames survive scrubbing.
- **Entrance over idle.** Every group's first cycle starts within 0.35 s and
  gets a brightness boost, which gives the opening burst. Group periods differ,
  so the idle that follows has no readable beat. Nothing is born in the last
  `SETTLE_SECONDS` and the field fades out over them.
- **Camera plane.** Quads are laid out in view space and the rays sit at a
  fixed screen angle, so every star shares one orientation, as the reference
  does. Placement is an ellipse round each target's body in the camera's
  plane. Depth testing is off: the sparkles overlay the body as in the
  reference.
- **Widths have a pixel floor.** Ray and core widths never drop below a set
  fraction of a screen pixel, measured with screen-space derivatives.
- The factory's element colour is ignored; the palette belongs to the profile.

## Findings

- **One lane per group emptied the idle.** A slot's period had to hold a whole
  chain plus the longest life (2.15 s), so every group fired once in a 2.6 s
  playback. Alternating two lanes halves the minimum period.
- **"Only spawn what finishes in time" is the wrong settle.** It cut every
  long-lived sparkle from about 1.2 s on. A spawn cutoff plus a field fade
  replaced it.
- **Additive pink nearly vanishes over a bright body**, just as the reference's
  sparkles go pale on light fur. The outward bias keeps most of them outside
  the outline.

## Open questions

- **Retro presets.** At 320x240 the rays fall below a pixel and the stars read
  as soft pink dots. Thicker rays everywhere, a pixel-art star for retro, or
  accepting the dots is a look decision for the user.
- **Sizing for Shine.** Duration (2.6 s) and density were set before Shine
  carried it and have not been retuned against a real cast.
- **Colour.** The palette is fixed pink even though Shine is a light spell.
  Whether it should follow the element is open.
