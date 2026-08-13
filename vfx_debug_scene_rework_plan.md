# VFX Debug Scene Rework

**Opened 2026-08-12.** Held in its own file rather than `implementation_plan.md`
because that file is the Spell Cast Aura spiritual-vortex cycle's active plan
and carries uncommitted work on `vfx/magenta-reduction`. This plan does not
depend on that cycle closing, but items touching
`src/presentation/effects/SpellCastAura.gd` do, and say so.

---

## 1. Goal

Turn `scenes/debug/VFXDebugScene.tscn` from a floating overlay panel over a
fixed camera into an authoring tool: **a fixed menu column on the left, a
navigable 3D pane on the right, and live control of every parameter an effect
exposes** rather than only the footprint radius.

Three properties of the current scene are load-bearing and must survive intact:

- **CLI parity.** Every interactive control has a command-line equivalent, so a
  validation pass is scriptable rather than a sequence of clicks
  (`docs/VFX_DESIGN.md` §5). New controls carry new flags.
- **Determinism.** A given effect, seed, and timestamp reproduce across
  processes; this is what makes golden comparison meaningful, and it is also
  what makes live re-tuning viable — see §3.
- **Shipping-pipeline fidelity.** The scene renders through the real
  `RetroRenderController`, not a lookalike. Anything it shows must be something
  the game can actually produce.

## 2. Current state

Audited 2026-08-12 against `src/presentation/debug/VFXDebugController.gd`
(1,644 lines), `scenes/debug/VFXDebugScene.tscn`, and
`src/presentation/RetroRenderController.gd`.

**The 3D view is already a texture.** `RetroRenderController._build_render_target()`
renders the world into a `SubViewport` and displays it as a `TextureRect` at
`PRESET_FULL_RECT` on its own `CanvasLayer`, behind a black letterbox `ColorRect`
and under a full-rect CRT overlay. Confining the world to a pane is a matter of
giving those three rects a sub-rect and sizing the viewport to match — no
restructuring of the render stack.

**`get_display_rect()` is the coupling point.** `screen_to_world()`,
`world_to_screen()`, and `screen_motion_scale()` all derive from it, and it
assumes the display fills the screen. Re-anchoring the rects from the debug
scene alone would leave all three silently wrong. See VDS-1.

**The camera the scene wants already exists.** `BattleCameraController` is a
`Camera3D` subclass with orbit, pan, wheel zoom, and double-middle-click reset
behind `handle_input(event, motionScale)`; `BattlePresentationController` drives
it with `retro_renderer.screen_motion_scale()`. The debug scene uses a plain
`Camera3D` with a yaw `SpinBox` and CLI-only size/focus overrides.

**Menu audit.** Verdicts settled with the user on 2026-08-12:

| Control | Verdict |
| --- | --- |
| Effect, element tint, timing mode, playback scale, seed pin/+1, play/pause/settle/overlap, scrub | Keep. Core loop, sound. |
| Layer toggles | Keep; populate on effect selection, not only after `Play`. |
| Footprint radius | Keep. The only parameter with a runtime path today (`setFootprint`). |
| Area shape | **Missing from the UI**, CLI-only, though it drives both effect and guide. Promote. |
| Target body preset, source distance | Keep. |
| Camera yaw `SpinBox` | Superseded by the orbit camera; becomes a bound readout plus Reset. |
| Camera size / focus | CLI-only; folds into the camera block. |
| Resolution + retro toggle | Keep, but **decouple**: `_onResolutionSelected` force-flips retro from the resolution index, so picking Native silently disables retro. Source the list from `RenderPresetCatalog` instead of the local four-entry copy, which can drift from what ships. |
| CRT pass | Keep. |
| Canvas stretch presets | Settles a UI-text question already settled (`project.godot` is native; `NoggTheme.UI_SCALE` is the answer). Not a VFX control. Moves into the collapsed text section. |
| Text specimen block | Orthogonal to VFX. **Stays in this scene as a collapsed section** — user's call, taken to avoid moving the documented `--text-*` flags and `docs/UI_DESIGN.md` §319. |
| Capture once | One-per-process lock is a leftover of the quit-after-capture path; interactively the button is dead after first use. Number interactive captures; leave the CLI path untouched, goldens depend on it. |
| Status label | Twelve values in one five-line format string. Becomes a labelled grid. |

**Two structural problems.** `_input()` binds bare letters with no focus guard,
so typing into a `SpinBox` already fires hotkeys — a latent bug that a permanent
panel makes constant. And the controller does world building, HUD wiring,
capture, golden comparison, CLI parsing, and the text specimen in one file;
adding a generated parameter editor without splitting it first lands it near
2,500 lines.

## 3. Established facts and design decisions

### The pane letterboxes to the game's aspect

A three-quarter-width pane is a shape the game never renders, and this scene's
value is fidelity to the shipping look. The pane shows the shipping window's
aspect with bars, with a `fill pane` toggle for close inspection. Existing
goldens in `debug/vfx_golden/` are invalidated by the reframing and are
rewritten, not reinterpreted; they are gitignored and local, so this is cheap.

### Camera parity comes from the class, not from a copy

The scene's camera becomes a `BattleCameraController`. A second implementation
of orbit and pan would drift from the one the game ships, and the drift would be
invisible precisely where this scene is supposed to be trustworthy.

### Effect parameters are constants, and that is the whole problem

Every effect's parameters are `const` on a `*Profile.gd` class —
`SpellCastAuraProfile` alone has roughly seventy — read directly at build time.
Constants cannot be changed at runtime. Radius is in the UI only because it
already has a runtime path.

The chosen approach is a **tunable descriptor plus an override dictionary**.
Each effect declares its tunable parameters as data; the panel builds controls
generically and holds no per-effect UI code, which is the "data handled by
general resolvers" rule in `AGENTS.md`. Profiles keep their `AUTHORED` /
`DERIVED` labels and remain the documented source of truth, now serving as
defaults rather than as the only possible values.

Rejected: making profiles `Resource` with `@export`. It buys the Godot
inspector and saveable `.tres` presets, but converts compile-time constants into
instance state across shipping code paths and puts the constant-labelling
discipline of `docs/VFX_DESIGN.md` §4 at risk of drifting from its source.

### Tuning means rebuild and replay, not mutate in place

Most parameters shape geometry inside `play()`. Changing one rebuilds the
effect, replays at the pinned seed, and re-seeks to the current normalized time.
Determinism is what makes that stable rather than jarring. Parameters that can
be applied live — alpha, emission energy — are marked as such in the descriptor
rather than discovered by trial.

### Tuned values must be able to leave the tool

A tuning session that ends with the user transcribing numbers off sliders will
rot the profiles. The tuning section exports changed values as GDScript `const`
lines ready to paste, and saves/loads a tuning set as JSON for A/B.

## 4. Proof checkpoints

| Checkpoint | Required proof | Owner |
| --- | --- | --- |
| Framing unchanged | New pane framing captured beside a pre-rework golden of the same effect, seed, and timestamp. A framing regression must not hide inside a layout change. | VDS-2 |
| Camera parity | One capture per orbit extreme (default, yawed, pitched, zoomed in, zoomed out) proving the pane letterbox holds and nothing clips. | VDS-3 |
| Panel legibility | Full-window capture of the reorganized menu at the project's smallest supported window height, every section expanded, then collapsed. | VDS-7 |
| Tuning round trip | One effect tuned live, exported as `const` lines, pasted into its profile, and re-captured — the pasted result must match the tuned frame. | VDS-9 |

## 5. Items

### VDS-1 — Optional display-rect override on `RetroRenderController`

**Model:** Opus 5 / GPT Sol

**Depends on:** nothing.

**Files:** `src/presentation/RetroRenderController.gd`, `docs/ARCHITECTURE.md`
or `docs/VFX_DESIGN.md` as the ownership note requires.

**End state:**

- A `display_rect_override: Rect2` field, zero-size by default, meaning "fill
  the host viewport" — the exact behaviour every current caller gets today.
- `get_display_rect()` honours it, letterboxing the world aspect *within* the
  override rather than within the screen. `screen_to_world()`,
  `world_to_screen()`, and `screen_motion_scale()` inherit correctness for free
  because all three already derive from it.
- The letterbox `ColorRect`, `world_texture`, and `crt_overlay` are positioned
  from the same rect instead of `PRESET_FULL_RECT`, so the CRT pass distorts the
  world pane and not the surrounding UI.
- `_resize_world_viewport()` sizes from the override when one is set, so a
  native-resolution pane renders at pane resolution rather than window
  resolution and is then letterboxed twice.
- Window resize re-applies the override; a host that never sets one is
  bit-identical to today.

**Risk:** this is a shared compatibility surface per `AGENTS.md`. Both callers —
`BattlePresentationController` and the debug controller — are in the validation
scope, and Battle25D's cursor picking is the specific behaviour that would break
if `screen_to_world()` drifted.

**Resolution target:** implemented; pending end-of-plan validation. Confirm
Battle25D still picks tiles correctly under the untouched default path.

### VDS-2 — Split layout: fixed left menu, letterboxed right pane

**Model:** Sonnet 5 / GPT Terra

**Depends on:** VDS-1, VDS-6.

**Files:** `scenes/debug/VFXDebugScene.tscn`, the extracted HUD and world units
from VDS-6.

**End state:**

- Menu panel anchored to the left quarter of the window, full height, no longer
  a floating overlay; the world pane takes the remaining three quarters via
  `display_rect_override`.
- Pane letterboxes to the shipping window aspect by default, with a `fill pane`
  toggle and a `--pane-aspect=<game|fill>` flag.
- Pane rect and viewport size recomputed on window resize.
- `H` still hides the menu; hiding it expands the pane to full width so
  `--hide-hud` captures are framed as they are today.
- `REPRESENTATIVE_CAMERA_SIZE` and `CAMERA_OFFSET` re-checked against the new
  pane and adjusted only if the framing proof requires it.

**Proof checkpoint:** framing unchanged.

### VDS-3 — Real orbit camera in the pane

**Model:** Sonnet 5 / GPT Terra

**Depends on:** VDS-2.

**Files:** `scenes/debug/VFXDebugScene.tscn`, the extracted camera/world unit,
`docs/VFX_DESIGN.md` §5 flag list.

**End state:**

- The scene's `Camera3D` is a `BattleCameraController`, driven with
  `retro_renderer.screen_motion_scale()` exactly as
  `BattlePresentationController` drives it.
- Camera input is claimed only while the pointer is over the pane; an in-flight
  drag keeps ownership when the pointer crosses the menu, matching the shipping
  rule.
- `--camera-yaw` and `--camera-focus` keep working; `--camera-pitch` and
  `--camera-zoom` join them, and `--camera-size` remains an alias for zoom.
- The menu's camera block shows live yaw, pitch, and size as two-way bound
  fields, plus a Reset that shares the double-middle-click path.

**Proof checkpoint:** camera parity.

### VDS-4 — Hotkey focus guard

**Model:** Sonnet 5 / GPT Terra

**Depends on:** VDS-6.

**Files:** the extracted input unit.

**End state:** `_input()` ignores its bare-letter bindings while a `Control`
owns focus, so typing into any field cannot fire playback or capture. Behaviour
with nothing focused is unchanged.

### VDS-5 — Reframe and rewrite goldens

**Model:** Sonnet 5 / GPT Terra

**Depends on:** VDS-2, VDS-3.

**Files:** `debug/vfx_golden/` (untracked), `docs/VFX_DESIGN.md` §5.

**End state:** every stored golden regenerated under the new framing with
`--golden-write`, and a `--golden` run over the fresh set reporting all MATCH.
The doc note about goldens having no committed home stays accurate.

### VDS-6 — Extract `VFXDebugController`

**Model:** Opus 5 / GPT Sol

**Depends on:** nothing. Sequenced before VDS-2 so layout work lands on the
split files rather than being redone.

**Files:** `src/presentation/debug/VFXDebugController.gd` and new siblings under
`src/presentation/debug/`, plus generated `.uid` sidecars.

**End state:**

- The controller becomes a host that owns lifecycle and wiring only.
- Extracted units, each with one job: the debug world (terrain samples,
  anchors, footprint guide, cast context), the HUD (control construction,
  binding, status readout), capture and golden comparison, and CLI argument
  parsing.
- Behaviour is byte-identical: the same capture, golden, and CLI paths produce
  the same output before and after. This item changes structure only.
- The header's documentation of flags and keys stays with the surface that owns
  each, rather than remaining one 75-line block.

**Risk:** the golden and capture paths carry hard-won determinism notes about
replay-before-seek and settle frames. Those comments move with their code
verbatim; none is a candidate for condensing.

**Resolution target:** implemented; pending end-of-plan validation. Prove with a
`--capture-at` series and a `--golden` run matching pre-extraction output.

### VDS-7 — Menu reorganization and audit fixes

**Model:** Sonnet 5 / GPT Terra

**Depends on:** VDS-6.

**Files:** `scenes/debug/VFXDebugScene.tscn`, the extracted HUD unit.

**End state:**

- Collapsible sections: Playback, Cast context, Camera, Render, Tuning, Text
  specimen (collapsed by default, carrying the canvas-stretch presets),
  Diagnostics.
- Status becomes a labelled grid, grouped playback / budget / context / render,
  rather than one format string.
- Area shape promoted to a UI control alongside radius.
- Resolution and retro decoupled into independent controls; the resolution list
  sourced from `RenderPresetCatalog`.
- Layer toggles populate on effect selection.
- Interactive captures numbered instead of locked to one per process; the CLI
  capture path is untouched.

**Proof checkpoint:** panel legibility.

### VDS-8 — Tunable contract and generated editor

**Model:** Opus 5 / GPT Sol

**Depends on:** VDS-6, VDS-7.

**Files:** `src/presentation/effects/VfxPlayback.gd`, the extracted HUD unit, a
new tunable-editor unit, `docs/VFX_DESIGN.md`.

**End state:**

- `VfxPlayback` gains `static func tunables() -> Array[Dictionary]` and
  `apply_tunables(Dictionary)`, defaulting to an empty roster so an effect that
  declares nothing behaves exactly as it does now.
- Each descriptor row carries id, label, group, min, max, step, default, and
  whether the parameter is applied live or requires a rebuild.
- The panel builds its controls purely from the descriptor and contains no
  effect-specific code; a new effect gets an editor by declaring one.
- A rebuild-class change rebuilds, replays at the pinned seed, and re-seeks to
  the current normalized time.
- `--tune=NAME=value,...` for CLI parity, applied before any capture.
- Export of changed values as `const` lines, and JSON save/load of a tuning set
  under `debug/`.

**Risk:** an override read landing in a per-particle or per-frame path would
cost real performance in a tool used to judge performance. Hot reads cache to
locals at build time; the descriptor lookup happens once per rebuild.

**Proof checkpoint:** tuning round trip.

### VDS-9 — Per-effect tunable rollout

**Model:** Sonnet 5 / GPT Terra, one item per effect.

**Depends on:** VDS-8. The `SpellCastAura` row additionally depends on the
spiritual-vortex cycle in `implementation_plan.md` closing.

**Files:** one effect and its profile per item.

**End state, per effect:** a curated tunable roster covering the parameters
worth authoring against — counts, dimensions, alphas, emission energies, timing
windows — reading through the override accessor with the profile constant as
default. Order: `SpellCastAura`, `IceStormEffect`, `FireStormEffect`,
`MagentaReductionEffect`, `IceTargetEncasementEffect`.

**Proof checkpoint:** tuning round trip, per effect.

## 6. Final validation

Runs once, after VDS-9's last row.

- Battle25D launches, picks tiles, orbits, and pans exactly as before — the
  `display_rect_override` default path proven untouched.
- The debug scene at default and at the harshest render preset, menu expanded
  and hidden.
- A `--golden` run over the regenerated set reporting all MATCH.
- One scripted capture per catalog effect proving CLI parity for every control
  added by this plan.
- `--import --headless` as the parse gate, with `.uid` sidecars committed
  alongside every new script.

## 7. Resolution log

### VDS-1 — implemented; pending end-of-plan validation

`display_rect_override` added to `RetroRenderController` with the full stack —
`get_display_rect()`, the letterbox, the world texture, the CRT overlay, and
`_resize_world_viewport()` — reading it, plus `set_display_rect_override()` /
`clear_display_rect_override()`. Zero size means fill, which is what both
shipping callers use.

**Equivalence proved by measurement, not inspection.** The file was temporarily
reverted to `HEAD` to establish a baseline, and the same capture command run on
both sides:

```
Godot_v4.4-stable_win64.exe --path . scenes/debug/VFXDebugScene.tscn \
  --resolution 900x600 --effect=ice_area_storm --seed=7 --hide-hud \
  --capture-at=0.2,0.45,0.75 --capture-out=user://ice --golden=debug/vfx_golden
```

Both produced `diff=11.65 / 13.05 / 12.83` against the stored goldens —
identical to the digit across three frames, which places the change well below
the 0.00–0.03 repeat-run noise floor.

**The stored goldens are stale, and that predates this plan.** All three exceed
tolerance identically at `HEAD`, and a diff near 12 is roughly four times the
score of comparing two entirely different effects, so the references were
captured under flags or effect code that no longer match. VDS-5 regenerates
them; until then `--golden` reports on this effect are not usable as a gate.

### VDS-6 — implemented; pending end-of-plan validation

`VFXDebugController.gd` reduced from 1,644 to 1,077 lines, with four new
siblings: `VfxDebugArguments` (68), `VfxDebugHud` (189), `VfxDebugCapture`
(276), and `VfxDebugWorld` (336). The determinism notes on replay-before-seek,
settle frames, and golden tolerance moved verbatim with their code.

The capture/golden boundary landed at output rather than at orchestration:
driving the timeline to a timestamp stays in the controller because it is
playback sequencing, while everything downstream of the read-back — naming,
writing, contact sheets, comparison — belongs to `VfxDebugCapture`.

Proved with the same command as VDS-1, producing the same `11.65 / 13.05 /
12.83`, plus a full-flag smoke run (`--element --shape --radius --scale
--target-body --source-distance --camera-yaw --camera-focus --camera-size
--stretch --render-resolution --crt --text --text-sample --text-backdrop
--capture-sheet`) with no warnings, and a HUD-visible capture with `--layers`
isolation confirming panel construction, control population, the status
readout, and layer toggles.

**One deliberate behavioural change.** `_captureOnce`'s `quitAfter` parameter
was removed. Both call sites passed `false`, so its three quit paths were
unreachable; preserving a dead branch whose exit codes could not be exercised
would have been carrying an untested claim forward. The interactive capture
never quits; `--capture-at` owns exit codes.

### VDS-2 — implemented; pending end-of-plan validation

Menu anchored to the left quarter, full height; world in the remaining pane,
letterboxed to the window's own aspect, with `--pane-aspect=<game|fill>`. Pane
and render target recomputed on window resize and whenever the menu is toggled.

**A latent trap in the shared controller surfaced here and is worth recording.**
`Control.set_anchors_preset()` changes anchors and leaves offsets untouched, so
restoring `PRESET_FULL_RECT` after an override reinterpreted the pane's offsets
against full-rect anchors and left the world pane-sized and displaced. It looked
exactly like a framing bug in the new pane code. `set_anchors_and_offsets_preset()`
is the call that actually resets a rect. `RetroRenderController` only worked
before because it set the preset once, on controls whose offsets were still
zero.

Diagnosis was by measurement: a `--probe-no-pane` flag that forced the override
empty reproduced the pre-rework numbers exactly, which located the fault in the
override path rather than in the scene or the extraction.

Framing proof: `--hide-hud` gives the world the whole window, and the three-frame
ice capture returns `11.66 / 13.06 / 12.85` against a pre-rework baseline of
`11.65 / 13.05 / 12.83` — inside the documented 0.00–0.03 repeat-run noise
floor. Every documented capture command frames as it always has.

`RetroRenderController`'s letterbox now tracks the world rect rather than the
screen, so the scene owns a black backdrop plate below `CRT_LAYER` for the area
around the pane.

### VDS-3 — implemented; pending end-of-plan validation

The scene's camera *is* a `BattleCameraController` now, script-attached in the
scene rather than reimplemented: middle-drag orbit, right-drag pan, wheel zoom,
double-middle-click reset, driven with `retro_renderer.screen_motion_scale()`
exactly as `BattlePresentationController` drives it. Camera input is claimed
only over the pane; `_input` continues an in-flight drag across the menu.

**Camera authorship is now split the way the shipping camera splits it.**
Changing separation or target body moves `focus_point` only — it can no longer
rotate or zoom a view the user has set. Taking authorship happens in exactly
three places: initial framing, the `--camera-*` flags, and Reset.

Yaw, pitch, and zoom are two-way bound: `_process` mirrors the live orbit into
the fields, so dragging updates them and the next separation change does not
snap the view back to a stale number. New flags `--camera-pitch` and
`--camera-zoom` (an alias of `--camera-size`, which keeps precedence).

**`SpinBox.step` quantises assigned values, not just arrow clicks.** The pitch
field at `step = 5.0` snapped the representative 44.5° framing to 46° and
shifted every capture by a consistent ~0.2 diff. Pitch uses `step = 0.5` and
zoom `step = 0.05` so the default framing is exactly representable.

### VDS-4 — implemented; pending end-of-plan validation

`_input` ignores its bare-letter bindings while a `LineEdit` or `TextEdit` owns
focus. Deliberately narrower than "any focused control": a focused *button*
must still allow `P`, or the hotkeys would die the moment Play was clicked.

### VDS-7 — implemented; pending end-of-plan validation

Panel restructured into collapsible sections (Playback, Layers, Cast context,
Camera, Render, Tuning, and Text specimen collapsed by default, carrying the
canvas-stretch presets). Headers are generated from a list rather than authored
per section, so the sections cannot drift apart in the scene file.

Status is a labelled grid keyed by id, replacing a five-line format string with
twenty-odd positional arguments — the shape where a new field silently lands in
the wrong column.

Audit fixes: area shape promoted from CLI-only to a control; **resolution and
retro decoupled**, so selecting Native no longer silently disables the retro
viewport and "native render, retro materials" is reachable; interactive
captures numbered instead of locked to one per process; pane aspect exposed.

Layer toggles and the tuning roster now follow the *selected* effect rather than
the last one played, via a probe playback built and disposed purely to read its
layer names. Both used to appear only after `Play` — backwards for deciding what
to run.

**One plan item was wrong and is corrected here.** The plan said to source the
resolution list from `RenderPresetCatalog`. That catalog holds shipping *look
presets*, which bundle resolution with colour and CRT settings; it is not a
resolution list. The panel gained a **Look preset** dropdown fed by the catalog
(with `--preset=`), sitting alongside the independent resolution override rather
than replacing it.

### VDS-8 — implemented; pending end-of-plan validation

`VfxPlayback` gained `tunables()`, `apply_tunables()`, and the `tunable()` /
`tunable_int()` accessors, all defaulting so that an effect declaring nothing
behaves exactly as before. `VfxDebugTuning` builds the panel entirely from a
descriptor and holds no per-effect knowledge.

Overrides store only what differs from a descriptor default, so "what did I
change" is the dictionary itself rather than a diff computed later — which is
also what makes the export honest. Export prints paste-ready `const` lines,
emitting integers for whole-number tunables so a blade count does not paste as
`18.0` into an `int` constant.

A rebuild-class change replays at the pinned seed and re-seeks to the current
normalized time. `--tune=` and `--tune-load=` give CLI parity, applied in
load-then-override order so a saved set and individual flags compose the way an
interactive session would.

### VDS-9 — SpellCastAura implemented; four effects outstanding

`SpellCastAura` declares a 19-parameter roster across three groups (inner plume,
outer plume, aperture) and reads every one through `tunable()`. Verified with
`--tune=PLUME_OUTER_TOP_RADIUS_U=2.6,PLUME_OUTER_EMISSION_ENERGY=4.0`, which the
status readout reports as "19 parameters, 2 changed".

`_createFootprintAperture` stopped being static so it can read instance
overrides — its uniforms are the effect's most-authored surface.

**`IceStormEffect`, `FireStormEffect`, `MagentaReductionEffect`, and
`IceTargetEncasementEffect` remain on empty rosters and behave exactly as
before.** Unlike the aura, whose values flow through one contained build, these
four read their constants across scattered per-frame update paths; picking which
are safely build-time needs per-effect reading rather than pattern-matching, and
a roster whose rows silently fail to take effect would be worse than none. The
panel already reports "This effect exposes no tunables" for them. One item each,
as this plan's VDS-9 always specified.

### VDS-5 — implemented

Goldens regenerated for ice, fire, and magenta at three timestamps each, and a
verification run reports MATCH at `diff=0.00` for all three ice frames.

**The previous set's real defect was undocumented provenance**, not age: nothing
recorded the flags that produced it, so its uniform ~12 failure was
indistinguishable from a regression. `docs/VFX_DESIGN.md` now carries the exact
regeneration command, including why `--hide-hud` is load-bearing — the menu
column otherwise takes a quarter of the window and changes the framing.
