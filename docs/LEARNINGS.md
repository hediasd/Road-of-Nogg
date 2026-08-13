# Durable Engineering Learnings

Purpose: retain verified findings that prevent repeated investigation. This is
not a session log, policy copy, or backlog.

## When to consult

| Before working on… | Read… |
|---|---|
| Determinism, replay, RNG, or identity | Deterministic state |
| Commands, action results, or reactive passives | Command acceptance and resolution |
| Turn order, movement, or pathfinding | Ordering and pathing |
| Godot classes, loads, or factory paths | GDScript loading |
| Console maps or diagnostic output | Text rendering |
| Running Godot scripts reliably on Windows | Process behavior |
| Tween-based UI animation | UI animation |
| Cursor ownership or tile intent | Cursor event semantics |
| Presentation event sequencing or animation cancellation | Visual action playback |
| Elevation rendering or map geometry | Elevation presentation |
| SubViewports, render scaling, shaders, or picking | Render isolation |
| VFX textures, materials, factories, or effect reuse | Shared visual resources |

When adding a learning, include the verified observation, the reusable rule,
and a review trigger. Move commands to [`DEVELOPMENT.md`](./DEVELOPMENT.md),
actionable future work to [`BACKLOG.md`](./BACKLOG.md), and architectural truth
to [`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Shared visual resources

### A neutral factory is a compatibility surface

- **Verified observation:** Magenta Reduction built its core and halo from the
  same `VfxTextures` factories used by Ice Storm. Replacing the factories'
  radial disc and continuous puff with Ice-specific posterized silhouettes made
  Magenta's core disappear and exposed the debug target marker, even though no
  Magenta file changed. Fire Storm was also a caller and therefore shared the
  regression risk.
- **Reusable rule:** Keep neutral primitives white, semantically named, and
  visually stable. An effect-specific silhouette, blend mode, filter, or palette
  gets an effect-owned texture/material factory. Before changing any shared
  visual resource, enumerate its callers and make their carrier captures part
  of the same validation surface.
- **Review when:** editing `VfxTextures`, a shared material/texture factory,
  render/theme tokens, or any presentation resource consumed by more than one
  effect.

### Hero-scale billboards do not survive an orbiting camera

- **Verified observation:** A spell-cast aura built from full camera-facing
  quads also shifted its billboard origin along the camera forward vector. It
  looked acceptable from its authoring angle, but the same view-space plane
  followed camera yaw and read as a tall sheet rising behind the caster.
- **Reusable rule:** Keep large spatial aura layers in world space. Arrange
  short cards around world up for soft volume, and use crossed world-space
  ribbons when a directional streak must retain a face from arbitrary yaw.
  Reserve billboard rendering for small local particles whose position, scale,
  and envelope cannot masquerade as the effect's spatial volume.
- **Review when:** adding `INV_VIEW_MATRIX`, writing `MODELVIEW_MATRIX`, enabling
  billboards on a hero-scale mesh, or authoring an effect for a moving camera.
  Capture at 0, 90, and 180 degrees before accepting the geometry.

## Deterministic state

### Stable identity and RNG

- **Verified observation:** Runtime entities use project-owned `uniqueID`
  values, and battle randomness is routed through `BattleState.rng`.
- **Reusable rule:** Never derive gameplay identity from `get_instance_id()` or
  use global RNG in simulation. Persist the seed and command/event inputs needed
  to reproduce a battle.
- **Review when:** adding an entity type, random outcome, snapshot field, or
  replay continuation path.

### Coordinated position mirrors

- **Verified observation:** `BattleState.moveMonsterTo()` updates the occupancy
  board, `monsterPositions`, and `Monster.position` together. Fast consecutive
  commands can reuse a vacated tile before its previous visual tween finishes.
- **Reusable rule:** One live entity per tile is a hard invariant. Assert the
  board/position bijection after mutations, restore, and replay. Views serialize
  event-time position snapshots; they must not synchronize a follow-up action
  from newer authoritative state while an older position animation is playing.
- **Review when:** adding movement, forced displacement, teleportation, load,
  replay playback, or animation timing changes.

## Command acceptance and resolution

### Spell radius does not select area semantics

- **Verified observation:** Ice Plow carried radius 2 and an area-sized visual
  profile while its omitted `TARGET_TYPE` normalized to `single`.
  `CombatResolver._spellAffectedPositions()` consequently returned only the
  selected centre; radius is consulted only for spells explicitly authored as
  `area` (or for a self spell with `SELF_RADIUS`).
- **Reusable rule:** Do not infer multi-target gameplay from `RADIUS`, targetable
  empty cells, or a presentation footprint. When a feature expects several
  affected units, verify `TARGET_TYPE: "area"` in the catalog and exercise the
  real resolver with several occupants before accepting the carrier.
- **Review when:** assigning an area VFX profile, selecting a carrier spell,
  changing spell schema defaults, or changing spell-target previews.

### A valid command can still fizzle during resolution

- **Verified observation:** A command can pass authoritative target/range
  validation, then a reactive passive can defeat or invalidate its actor before
  the requested action resolves.
- **Reusable rule:** Treat validation acceptance and action resolution as
  separate outcomes. Record an accepted command once with `success=true`; use
  `resolved` and `actionResult` for a later fizzle. Do not relabel it as rejected
  or generate a fallback command.
- **Review when:** adding reactions, interrupts, counterattacks, movement
  triggers, new action types, replay logic, or network command handling.

### Height is a shared edge rule

- **Verified observation:** Passing only a destination into BFS/A* cannot decide
  jump legality because traversal depends on both the current and next heights.
- **Reusable rule:** Search callbacks receive `(current, next)` and delegate to
  `MovementResolver.canTraverse()`; previews, validation, and CPU planning must
  not reimplement height edges.
- **Review when:** adding terrain costs, special traversal, teleportation, or
  moving/destructible surfaces.
## Ordering and pathing

### Stable turn ties

- **Verified observation:** Speed-only sorting leaves equal-speed ordering
  dependent on insertion details.
- **Reusable rule:** Sort by speed first and deterministic `uniqueID` second so
  snapshots and replays agree across runs.
- **Review when:** changing initiative, haste/slow, summons, or queue rebuilds.

### Grid heuristics

- **Verified observation:** Current orthogonal grid pathing uses Manhattan
  distance and dictionary-backed open/closed membership.
- **Reusable rule:** Keep heuristic and movement topology aligned. Re-evaluate
  the heuristic before enabling diagonals, variable edge costs, or portals.
- **Review when:** changing allowed movement directions or terrain costs.

### Line-of-sight endpoints are never tested as blockers

- **Verified observation:** `LineOfSight.hasLoS()` documents and implements
  "source and target cells are never passed to isBlocker" — only strictly
  intervening cells (plus diagonal corner-check cells) are evaluated. A prior
  audit theorized that `CombatResolver.canSpellReachPositionFrom()` passing
  `targetID = -1` to `_hasLoS()` let the target's own occupant block its own
  tile; that specific mechanism is impossible given this traversal rule — the
  endpoint is never sampled regardless of which ID is passed. The `-1` vs. real
  `targetID` argument only matters if a *different*, bystander entity occupies
  a strictly-intervening cell and happens to share an ID with whatever is
  passed — a narrower and rarer case than originally described. The fix
  applied (passing the real occupant ID instead of `-1`) is still correct and
  harmless; the stated root cause in the audit was not.
- **Reusable rule:** Before shipping a LoS/geometry bug fix, verify the
  root-cause theory against the algorithm's actual documented traversal —
  which cells get sampled, which are explicitly skipped — rather than reasoning
  from the symptom alone. A theory that sounds mechanically plausible can still
  describe a code path the algorithm never executes. Write the regression test
  first if possible: constructing a concrete failing scenario forces the same
  verification a pure read-through can skip.
- **Review when:** touching `LineOfSight.gd`, `CombatResolver`'s LoS call
  sites, or diagnosing a spell-targeting/preview mismatch.

## GDScript loading

### Global names do not repair invalid paths

- **Verified observation:** `class_name` exposes a global type name, while
  `preload()` still resolves its explicit resource path independently.
- **Reusable rule:** Prefer one mechanism intentionally and keep every explicit
  resource path valid. Never assume a global class makes a bad preload safe.
- **Review when:** moving scripts, changing factory dependencies, or exporting.

### Pure classes can own custom signals

- **Verified observation:** A non-`Node` GDScript class can declare and emit
  custom signals in memory.
- **Reusable rule:** `BattleEvents` can stay headless; scene-tree lifecycle
  behavior belongs in presentation code.
- **Review when:** adding event ownership, connection lifetimes, or adapters.

### A brand-new `class_name` is not a usable bare type until the project rescans it

- **Verified observation:** A freshly created script's `class_name` fails with
  `Could not find type "X" in the current scope` the first time another script
  both defines and uses it as a static type (`var w: NoggWindow`) in the same
  session — even though `load("res://.../NoggWindow.gd").new()` on the exact
  same class works fine. The difference is a `.gd.uid` sidecar: an
  already-registered class (`NoggTheme.gd`, which had one from an earlier
  session) resolved as a bare type immediately; two classes created moments
  earlier in the same session (`NoggWindow.gd`, `MenuCursor.gd`) did not, until
  a project-wide scan generated their `.uid` files. Neither `--headless -s
  script.gd` nor `--path . scene.tscn` reliably triggers that scan for a file
  created in the same session; `--headless --editor --quit-after 200` does.
- **Reusable rule:** After adding a new `class_name`, either run `--headless
  --editor --quit-after 200` once before relying on it as a bare static type
  elsewhere, or check for its `.gd.uid` sidecar first. Typing the reference as
  `Control`/`Node`/`RefCounted` instead avoids the error but only defers it —
  a caller of that reference that itself needs static inference (e.g. `var row
  := window.add_row(...)`) will hit a *different* error (`Cannot infer the
  type of "row"`) the first time it's typed against the workaround value
  instead of the real class.
- **Review when:** adding a new `class_name` and using it as a static type
  (not just via `preload().new()`) in the same session it was created.

## Text rendering

### Terminal width is not portable for emoji

- **Verified observation:** Emoji and box-drawing glyphs occupy inconsistent
  terminal widths across fonts and Windows hosts.
- **Reusable rule:** Use single-column ASCII symbols for alignment-sensitive
  tactical grids; put descriptive names in a separate legend.
- **Review when:** changing console board output or CI diagnostics.

## Process behavior

### Bound native diagnostics

- **Verified observation:** Direct PowerShell invocation of the bundled
  non-console Godot binary returned before its detached process completed, so a
  stale exit code hid parser errors and left the failed `SceneTree` alive.
- **Reusable rule:** Launch the Godot binary as a bounded, waited process (e.g.
  `System.Diagnostics.Process` with `WaitForExit` and a timeout), capture
  stdout/stderr to a fresh log rather than relying on console output, and check
  for an explicit expected marker in that log rather than trusting the exit
  code alone. On timeout, terminate only the exact process object launched.
- **Review when:** the execution host or sandbox tooling changes, or when
  building a new check/test runner against this Godot binary.

### Stop retrying a broken patch boundary

- **Verified observation:** The workspace patch helper repeatedly failed with
  `windows sandbox failed: helper_unknown_error` before reading the target.
  Attempts to synthesize a fallback with `git diff --no-index` then introduced
  separate Windows absolute-path and patch-context failures. None of those
  retries produced new evidence about the requested code change.
- **Reusable rule:** After the same patch-infrastructure failure recurs, inspect
  the target and stop retrying equivalent helper/temp variants. If the target
  is unchanged, make one exact, asserted workspace-scoped replacement, inspect
  its focused diff immediately, and continue. Keep fallback temp files beside
  the target; a no-index diff against an external Windows temp path can encode
  a drive-qualified filename that `git apply` rejects.
- **Review when:** the patch helper, filesystem sandbox, Git runtime, or Windows
  temp-path behavior changes.

### Nested command layers consume each other's escapes

- **Verified observation:** Source passed through JavaScript into PowerShell and
  then Python/GDScript lost inner `\"` and `\n` intent before reaching the
  final language. That produced invalid quoted GDScript diagnostics and an
  unterminated Python string. Separately, Windows newline translation rewrote
  generated JSON to CRLF, and `git diff --check` reported every added line as
  trailing whitespace.
- **Reusable rule:** Avoid inline multi-language payloads for nontrivial source.
  Prefer a short workspace-scoped helper file, use single-quoted diagnostics
  where supported, express control characters with `[char]10` / `chr(10)`, and
  open generated text with an explicit LF newline policy. Always inspect a
  small output sample and run `git diff --check` after a mechanical rewrite.
- **Review when:** generating JSON/code through more than one command language,
  changing shells, or changing repository line-ending policy.

### `--import --headless` can silently rewrite `project.godot`

- **Verified observation:** Running the parse gate
  (`Godot_v4.4-stable_win64.exe --path . --import --headless`) repeatedly
  during a VFX authoring session left `project.godot` modified on disk: its
  entire `[display]` section, including `window/stretch/mode="disabled"` and
  the comment explaining why, was gone. No code in this repository writes
  that file; the only thing that touched it was the import/parse pass itself.
- **Reusable rule:** `git status`/`git diff project.godot` after any
  `--import --headless` run and before staging, the same way a broad `git add`
  is reviewed. Revert an unrelated `project.godot` change with
  `git checkout -- project.godot` rather than committing it, since it is
  editor-side reformatting, not an intended settings change.
- **Review when:** running the headless import/parse gate repeatedly in one
  session, or seeing an unexplained `project.godot` diff in `git status`.

### Prove the execution environment before diagnosing Godot

- **Verified observation:** Sandboxed Godot editor/checker launches could not
  create their AppData cache/log directories and sometimes detached or exited
  with an access-violation code. Those environment failures obscured the real
  project error. Once Godot ran with normal AppData access, its application log
  identified the originating `RaceReferences.gd:27` parse error immediately.
- **Reusable rule:** Separate environment evidence from code evidence. If Godot
  reports AppData denial, detaches, or lacks an expected completion marker,
  rerun the same bounded command with the needed permission and inspect its
  captured output/application log before editing project code. Never interpret
  a blank launch or zero exit code as a successful check.
- **Review when:** sandbox permissions, Godot executable type, AppData location,
  or process-launch tooling changes.

### Capturing a second screenshot in one running process returns a stale image

- **Verified observation:** `root.get_texture().get_image().save_png(...)`
  called a second time in the same `SceneTree` process — after a genuine state
  change (a `CanvasLayer.visible` flip, confirmed correct by reading the
  property directly) and after `await RenderingServer.frame_post_draw` plus
  several `await process_frame`s — returned an image byte-identical to the
  first capture. Sampling fixed opaque button pixels confirmed it: the second
  "before/after" pair was pixel-for-pixel the same PNG. A single capture per
  process, immediately after the state change, was correct every time.
- **Reusable rule:** A windowed before/after screenshot harness needs one
  process per captured state, not one process capturing several states in
  sequence. Do not "fix" a stale second capture by awaiting more frames or more
  post-draw signals — it does not go away with more waiting.
- **Review when:** writing or extending a `debug/verify_*.gd` harness that
  captures more than one visual state.

### A node's `_ready()` is not synchronous within `add_child()` before the tree's first frame

- **Verified observation:** `NoggWindowScript.new(); parent.add_child(window);
  window.add_row(...)` — a sequence that works correctly everywhere in the
  actual game (`BattleUIBuilder.gd`, `PlayerCommandMenu.gd`, all called deep
  into an already-running scene tree) — threw `Cannot call method 'add_child'
  on a null value` inside `NoggWindow.add_row()` when the identical sequence
  ran at the very start of a fresh `SceneTree` script's `_initialize()`, before
  any frame had been awaited. `_content` (built in `_ready()`) was still null;
  `add_child()` had not yet triggered it.
- **Reusable rule:** `_ready()` fires synchronously within `add_child()` once
  the tree is already several frames into its main loop, but not reliably
  before the very first frame. A minimal verification harness that builds
  scene-tree nodes at the top of `_initialize()` needs at least one `await
  process_frame` before treating a freshly `add_child()`-ed custom node as
  fully constructed.
- **Review when:** writing a `debug/verify_*.gd`/`probe_*.gd` script that
  builds nodes immediately in `_initialize()` with no prior `await`.

## Cursor event semantics

### Camera drags own their complete gesture

- **Verified observation:** Inferring camera dragging from global mouse-button
  state during each motion event allowed a gesture to stop when event delivery
  changed as animated models or UI passed beneath the pointer.
- **Reusable rule:** Acquire orbit/pan ownership on an unhandled press, route an
  active drag before hit-tested controls, and release only on the matching
  button-up, focus loss, or battle lifecycle change.
- **Review when:** changing camera controls, viewport input forwarding, modal UI,
  model picking, or mouse capture behavior.

### Events communicate discrete tactical intent

- **Verified observation:** Following a moving model caused the cursor to land on
  transient or stale tiles when movement and action events overlapped.
- **Reusable rule:** Cursor events describe stable grid intent: movement points
  to the destination; attacks, spells, and heals point to the action target.
  Cursor ownership prevents older AI activity from overriding player intent.
- **Review when:** implementing player control, queued animations, cancellation,
  keyboard navigation, or replay playback.

## Visual action playback

### Follow-up actions must not resynchronize active movement

- **Verified observation:** Starting the attack bump called the global visual
  occupancy synchronizer, which killed the active movement tween and snapped the
  attacker to its newer authoritative tile before the move animation completed.
- **Reusable rule:** Queue movement, targeting, action, and defeat presentation
  in event order using coordinates and text captured when the event is emitted.
  Simulation never waits for this queue. Each movement step starts from the
  current rendered transform and animates to the shared terrain-surface query;
  its arc and duration include the vertical delta rather than snapping Y from
  authoritative state. Bound every tween with an idempotent completion callback
  plus a watchdog, and invalidate both on adapter disposal.
- **Review when:** adding a visual event, changing action timing, accelerating
  simulation playback, replay visualization, or implementing skip/fast-forward.

### An effect cannot `free()` itself at teardown

- **Verified observation:** `SpellCastAura.dispose()` called `free()` on itself
  whenever it was already out of the tree, which is exactly the state disposal
  reaches during scene and process teardown. The engine has the object locked
  for the duration of the call or notification that triggered the disposal, so
  the free was refused with `Object is locked and can't be freed` /
  `Attempted to free a locked object`. It printed only at teardown, never
  during play, which is why it survived for months as harmless noise.
- **Reusable rule:** An effect's `dispose()` must never call `free()` directly.
  Use `queue_free()` while inside the tree and `call_deferred("free")` outside
  it, so the deletion runs after the lock is released, and return early when
  `is_queued_for_deletion()` is already true.
- **Review when:** writing or changing a `VfxPlayback.dispose()`, or seeing a
  locked-object error at scene exit or application quit.

### A delayed cleanup callback must not strongly capture its earlier owner

- **Verified observation:** `DamageNumberBillboard` normally freed itself from
  its animation tween, but its later safety timer held an anonymous-function
  capture of that billboard. When the timer eventually fired, Godot attempted
  to restore the already-freed capture and logged `Lambda capture at index 0
  was freed` once per damage number during a long battle.
- **Reusable rule:** When a delayed callback may outlive the node it cleans up,
  bind a `WeakRef` into a named/static callback and resolve it at callback time.
  Do not close over the node strongly and rely on `is_instance_valid()` inside
  the closure—the failure occurs while reconstructing the capture, before that
  guard can run.
- **Review when:** adding cleanup timers, watchdogs, deferred callbacks, or
  fire-and-forget UI/VFX nodes whose normal animation can free them first.

## Elevation presentation

### A logical surface needs visible supporting volume

- **Verified observation:** Moving one thin tile mesh directly to logical height
  made raised terrain appear to float, even though monsters and overlays were
  numerically aligned with its top surface.
- **Reusable rule:** Render height `N` as a contiguous column of `N + 1` exact
  `1 x 0.5 x 1` blocks. Keep logical heights integer-based, map every level to
  0.5 world units, and derive movement, cursor, overlay, and picking anchors
  from the same top-surface query.
- **Review when:** changing elevation units, tile mesh dimensions, terrain
  deformation, ramps, cliffs, water depth, or map rendering hierarchy.

## Render isolation

### Previewable GPU effects need one effect-local clock

- **Verified observation:** In Godot 4.4, `GPUParticles3D.use_fixed_seed`,
  `seed`, `restart(true)`, and `request_particles_process(t)` reproduce a
  particle system at a requested timeline position, while `speed_scale = 0`
  pauses it. A spatial shader using global `TIME` continues animating even
  while that particle system and its GDScript timeline are paused. See the
  [Godot 4.4 GPUParticles3D contract](https://docs.godotengine.org/en/4.4/classes/class_gpuparticles3d.html).
- **Reusable rule:** Give every previewable effect one local elapsed-time
  source. Seek fixed-seed GPU particles by restarting with the seed preserved
  and requesting the target process time; pause them with zero speed. Drive
  companion shaders from that same elapsed-time uniform rather than `TIME`, so
  Play, Pause, Resume, scrub, and screenshot frames cannot disagree by layer.
- **Review when:** adding a previewable GPU particle layer, timeline scrub,
  pause/resume, deterministic replay visuals, or checkpoint capture.

### Standalone SubViewports need explicit display and input mapping

- **Verified observation:** A standalone `SubViewport` does not display itself
  or automatically receive main-viewport input. Its isolated 3D world also owns
  the physics space used by picking.
- **Reusable rule:** Display its `ViewportTexture` explicitly, keep native UI
  outside the low-resolution viewport, and map coordinates through the actual
  aspect-preserving display rectangle. Forward camera input deliberately and
  query physics through the isolated world root. A shader that writes
  POSITION must assign a valid clip-space value on every path.
- **Verified observation:** Per-mesh vertex coordinates restart for every part
  of a procedural model, so a local-coordinate color split repeats separately
  across the head, stem, collar, and base.
- **Reusable rule:** Multi-part visual effects that represent one model must use
  a shared model-space transform and shared complete-model bounds. Per-instance
  shader transforms preserve that space while materials remain shared.
- **Verified observation:** Affine UV interpolation has no visible result on
  flat-colored geometry under an orthographic camera because there is neither
  textured UV detail nor perspective depth to distort.
- **Reusable rule:** Do not present an affine/perspective choice as a useful
  player-facing control until the active content visibly demonstrates it. Use
  directly observable controls such as upscale filtering for current content.
- **Verified observation:** Screen-space vertex snapping also ran during the
  directional-light shadow pass and produced broad diagonal bands across the
  battlefield.
- **Reusable rule:** Keep real-time shadow casting disabled for snapped world
  materials unless a separate shadow-safe pass is implemented and visually
  verified.
- **Verified observation:** Rendering preset values can be edited independently
  during battle, so the originating preset name no longer describes the active
  configuration after the first manual change.
- **Reusable rule:** Treat presets as complete recipes and immediately label any
  manual rendering change as `Custom`; persist the complete Custom state. Keep
  `None` as the neutral reset baseline and migrate legacy preset identifiers.
- **Verified observation:** A strict parity checker with one coordinated light
  tone and one dark tone makes terrain categories visibly tile-based; mottled
  multi-step variation read as accidental inconsistency instead.
- **Reusable rule:** Derive presentation-only terrain alternation from `(x+y)%2`
  and a terrain base color. Keep it outside simulation RNG so grass, water, and
  future sand/rock/lava palettes inherit the same deterministic two-tone rule.
- **Verified observation:** CPU estimates made from a candidate destination can
  disagree with resolution if elevation arithmetic reads the actor's current
  state position instead of the proposed command position.
- **Reusable rule:** Pure planning queries accept explicit source positions and
  share the same damage/height arithmetic as resolution; never mutate state to
  simulate a candidate.
- **Review when:** changing viewport resolution, letterboxing, camera controls,
  mouse picking, world shaders, shadows, or the UI/world composition.

## UI animation

### A killed `Tween` never emits `finished`, and a live one keeps animating regardless of who created it

- **Verified observation, twice, in the same session.** `NoggWindow.close()`
  originally awaited `_open_tween.finished`; an `open()` call arriving while a
  `close()` was still in flight killed that tween to start its own, which
  meant the waiting `close()` coroutine — awaiting a signal that a killed tween
  never sends — would have hung forever. Caught before shipping and fixed with
  a `SceneTree` timer plus a generation counter instead. The *same* class of
  bug then shipped anyway in the row-marquee feature: the scroll tween created
  inside the marquee loop was never stored anywhere, so when a row lost focus
  and `set_focused_row()` set `label.position.x = 0.0` to reset it, the
  still-running, un-killed tween overwrote that reset on the very next frame,
  since nothing had ever told it to stop. Confirmed on screen — a row
  refocused away mid-scroll stayed visibly scrolled instead of snapping back —
  not caught by reading the code, because the reset call was right there and
  looked correct.
- **Reusable rule:** Any `Tween` that can be superseded (a new open/close, a
  new focus target, a new selection) must be stored in a member variable and
  explicitly `.kill()`ed at the point of supersession, even if nothing appears
  to await it. Never `await tween.finished` on a tween that can be killed by
  something other than its own natural completion — use a `SceneTree` timer of
  matching duration instead, guarded by a generation counter so a
  now-irrelevant wakeup can cleanly no-op.
- **Review when:** adding or modifying any tweened UI state (open/close,
  focus/dim, cursor movement, marquee/scroll) that a later call can interrupt
  before it finishes.

## Retro render parameters

### `RetroRenderController` has two setters and the wrong one fails silently

**Consult when:** changing any CRT or look parameter at runtime, from a debug
harness or from game code.

`set_look_parameter()` and `set_crt_parameter()` have separate `match`
statements over separate name constants. Neither has a fallback arm, so passing
a `CRT_*` name to `set_look_parameter()` matches nothing, changes nothing, and
reports nothing. The call compiles, runs, and is a no-op.

This is indistinguishable from a shader that ignored the value, and it produced
a confidently wrong measurement before being caught: two captures taken to
compare scanline pitch differed by a mean of 0.009 with a peak of 1, which reads
as "the parameter does nothing" rather than "the parameter was never set."
Routing the same call through `set_crt_parameter()` produced mean 1.383, peak 31.

The general lesson is worth more than the specific trap: **when a visual
parameter appears to have no effect, diff the two frames numerically before
concluding anything about the effect.** A near-zero peak difference means the
input never arrived; a real but subtle difference looks completely different in
the numbers even when it is hard to see by eye.
