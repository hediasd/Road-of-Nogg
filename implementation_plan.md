================================================================================
ACTIVE STORM GUST IMPLEMENTATION PLAN
Road of Nogg - clean-room recreation of classic Ragnarok Online "Storm Gust"
Drafted and installed 2026-08-03 - see section 1.
================================================================================

STATUS: Active. On 2026-08-03 the user explicitly directed execution to proceed
despite the unfinished battle-window cycle. Its still-open preview-harness and
integrated visual-acceptance work was moved to BACKLOG_CRITICAL.md in durable
prose. The displaced plan remains recoverable with
git show 3b16f4b:implementation_plan.md.


--------------------------------------------------------------------------------
1. LIFECYCLE PREAMBLE
--------------------------------------------------------------------------------

    Opened 2026-08-03. The previous battle-window/XenoText restyle cycle was
    displaced at the user's explicit direction before its preview-harness and
    integrated visual-acceptance work ran. Those open outcomes were moved to
    BACKLOG_CRITICAL.md; recover the full displaced plan with
    git show 3b16f4b:implementation_plan.md. This file now holds one new cycle:
    a clean-room, high-similarity recreation of the classic Ragnarok Online
    "Storm Gust" visual language as a dedicated, data-selected area-spell
    effect, integrated through spell_cast_started.

    The untracked vfx_plan.md remains user-owned. It was audited on 2026-08-03
    and NOT adopted: several of its premises are stale or contradicted by the
    current references (see 5.4). This cycle does not edit, rename, or delete
    it, and cites none of its identifiers.

    Execute one item per session in file order, committing at each boundary.
    Implementation items stop after focused diff review, git diff --check,
    backlog maintenance, and their commit. Only SG-VALIDATE performs the
    combined gameplay, integration, and visual-acceptance pass.

Installation was explicitly authorized by the user despite the displaced
cycle's unfinished validation; the durable backlog now owns that remaining
work.


--------------------------------------------------------------------------------
2. GOAL AND PLAYER-VISIBLE END STATE
--------------------------------------------------------------------------------

When a unit casts the carrier ice-area spell, the battlefield shows ONE
sustained, ground-targeted ice storm centred on the selected area - not a
caster-centred aura, not a single explosion.

A pale, broad cloud canopy hangs above the footprint and flickers brighter on a
repeating beat. Beneath it a dense but gappy flurry of small cold-white flakes
crosses the volume at several depths and speeds, organised into visible lateral
gust bands so the field reads as WIND, not snowfall. A handful of much larger,
hard-edged white ice shards tumble through, sparse enough to count. A soft cold
wash sits on the ground. The storm pulses several times, then the canopy,
flurry, shards, and ground wash fade out on staggered schedules rather than
together.

Throughout, units remain readable as silhouettes, terrain and elevation stay
legible, and damage numbers stay fully readable (structurally guaranteed - see
5.3). A viewer familiar with classic Ragnarok should recognise the reference
before reading the spell name.

The effect is selected by an AUTHORED DATA FIELD, not by a spell-name
conditional, so any future spell can adopt it. Spells without that field keep
the existing generic aura.


--------------------------------------------------------------------------------
3. NON-GOALS
--------------------------------------------------------------------------------

- No change to spell damage, range, radius, hit count, status effects,
  knockback, freeze rules, balance, targeting legality, or turn logic.
- No renaming of the carrier spell and no new spell added. Adding a spell named
  after Ragnarok's is OUT OF SCOPE and would require explicit user
  authorisation.
- No Ragnarok lore, naming, or mechanics imported into Road of Nogg content.
  The profile identifier is `ice_area_storm`, deliberately generic.
- No sound design.
- No general rebuild of every spell effect, and no general spell-VFX framework
  beyond what this integration provably needs.
- NO global glow, tonemapping, or environment change. See 7.4 - this is a
  deliberate reversal of an assumption in vfx_plan.md.
- No download, extraction, decompilation, tracing, or reuse of any Ragnarok
  client asset, GRF content, texture, sprite, sound, or shader. Every texture
  is procedural or newly authored in-repo.
- Visual gust pulses are cosmetic only. They must never emit gameplay events,
  damage, knockback, or state changes.


--------------------------------------------------------------------------------
4. REFERENCE TARGET AND SOURCE / PROVENANCE RECORD
--------------------------------------------------------------------------------

4.1 PRIMARY SOURCES (directly analysed in the planning session)

  S1  codex-clipboard-34168e1d-...40.png  (1280x720)
      Role: supporting close-up.
      Authoritative for: canopy shape, flake density/distribution, shard
      silhouettes, cold white/blue luminosity, vertical volume.

  S2  codex-clipboard-a301d773-...76.png  (approx 640x360)
      Role: PRIMARY AUTHORITY.
      Authoritative for: scale vs characters and tiles, battlefield
      compositing, opacity, 2000s rendering character, acceptable clutter.

  Both files existed and were read directly. The analysis in section 6 is
  derived from those pixels.


4.2 A REAL CONFLICT BETWEEN S1 AND S2, AND ITS RESOLUTION

  S1 IS NOT A CLASSIC-CLIENT CAPTURE AT CLASSIC RESOLUTION. It is 1280x720
  with soft, high-fidelity gradients and a black background - either a much
  later client, an upscaled capture, or a dark/night map. Its apparent
  brightness and contrast are massively exaggerated by the black backdrop
  relative to S2's lit dungeon floor.

  RESOLUTION: S1 is authoritative for STRUCTURE (what layers exist, silhouette
  shapes, relative sizes, distribution) and NOT for LUMINOSITY, SOFTNESS, or
  RESOLUTION CHARACTER. Every brightness, alpha, and softness decision defers
  to S2. Where S1 suggests a bloomy, soft, high-detail look, that is an
  artefact of its capture conditions and must not be transplanted.

  This is the single most important interpretive call in the plan and it is
  why 7.4 rejects global glow.


4.3 EXTERNAL SOURCES

  MECHANICAL TIMING - corroborated across three independent wikis, HIGH
  CONFIDENCE:

    Storm Gust summons a blizzard on a targeted location lasting 4.5 SECONDS,
    dealing Water-property damage EVERY 0.5 SECONDS (approx 10 HITS), pushing
    targets 2 cells in random directions, with a level-scaled freeze chance.
    Two simultaneous instances in one location have no more effect than one.

    - iRO Wiki Classic - Storm Gust
      https://irowiki.org/classic/Storm_Gust
      Classic/pre-renewal authority.
      LIMITATION: returned HTTP 403 to direct fetch; content reached via
      search-engine extraction of that page.

    - Ragnarok Wiki (Fandom) - Storm Gust
      https://ragnarok.fandom.com/wiki/Storm_Gust
      Corroborates 10 hits and random-direction push.
      LIMITATION: HTTP 402 on direct fetch; content via search extraction.

    - Ragnarok Project Zero wiki - Storm Gust
      https://wiki.playragnarokzero.com/wiki/Storm_Gust
      Pre-renewal-faithful server; corroborates 4.5 s / 0.5 s independently.

    - Divine Pride - Skill 89
      https://www.divine-pride.net/database/skill/89
      Raw client skill DB; useful as a fourth check.

    - RateMyServer skill DB
      https://ratemyserver.net/index.php?page=skill_db&skid=89

  Area of effect is reported as base 9x9 cells with each affected cell
  splashing 3x3, giving an effective 11x11. LOWER CONFIDENCE - single
  search-summary source, primary page unreachable.

  IMPORTANT: This is GAMEPLAY timing, not ANIMATION timing. Inferring that the
  visual pulse cadence tracks the 0.5 s damage interval is an INFERENCE,
  flagged as such in section 6 - a well-supported one, because the pulse is
  what tells the player a hit landed, but it is not a frame-level measurement.


  CANDIDATE MOTION FOOTAGE - INSPECTED; NONE QUALIFIES AS PRIMARY

    https://www.youtube.com/watch?v=F9oZbhb_k5c
      "Nostalgia RO", 2014. The captured character is a level 137 Shadow
      Chaser, so this is post-Renewal gameplay. Secondary structure only;
      server/client version remains unidentified. A visible cast around
      1:58-2:06 shows repeated bright flake-and-shard pulses.

    https://www.youtube.com/watch?v=ryg8wuHkzPo
      Same series, part 02. The captured character is a level 140 Shadow
      Chaser, so this is also post-Renewal and secondary only.

    https://www.youtube.com/watch?v=jHKJrPdqZr0
      RagnarokZero, 2018, Firewall + Storm Gust AoE. The source identifies
      itself as Zero and remains secondary under this plan's source hierarchy.

    https://www.youtube.com/watch?v=r337MHlbw3w
      A 5.96 s sound-effect sample using static channel artwork. It contains no
      Storm Gust animation frames and cannot establish visual timing.

  Frame access closed the discovery gap but did not produce a qualifying
  classic/pre-Renewal stock source. Every timing claim therefore remains either
  wiki-sourced mechanical timing or an explicit inference/estimate. No later
  item may treat section 6's timing column as measured until a qualifying
  source is supplied or the user explicitly changes the evidence requirement.


  THE CLIENT'S INTERNAL RENDERING MODEL IS NOT ADEQUATELY DOCUMENTED

    The STR effect-file format - which would reveal the client's actual
    layer/blend/keyframe model - has no usable public specification.

    - https://github.com/rdw-archive/RagnarokFileFormats
      Describes STR only as "compiled (binary) effects format".
    - https://ragnarokresearchlab.github.io/file-formats/str/
      An empty placeholder page.
    - https://github.com/skardach/ro-str-viewer
      Publishes no spec.
    - https://www.robrowser.com/blog/welcome-effects
      Announces an STR loader; no technical detail.

    THIS PLAN THEREFORE MAKES NO CLAIM ABOUT THE CLIENT'S INTERNAL RENDERING
    MODEL and derives its "2.5D sprite character" entirely from what S2
    visibly shows. (Consulting format documentation would in any case be
    research, not asset extraction; no client file is touched either way.)


--------------------------------------------------------------------------------
5. VERIFIED CURRENT-STATE FINDINGS
--------------------------------------------------------------------------------

Every line number below was read during the planning session.
THREE OF THE ORIGINAL BRIEF'S PREMISES WERE WRONG OR IMPRECISE - corrections
are marked [!].


5.1 THE CURRENT EFFECT

  src/presentation/effects/SpellCastAura.gd:25
    VISIBLE_DURATION := 1.1
  src/presentation/effects/SpellCastAura.gd:29
    _CLEANUP_DELAY := 1.4
    CONFIRMED "~1.1 s".

  SpellCastAura.gd:38
    static func spawn(parent: Node3D, world_pos: Vector3,
                      element_color: Color) -> void
    CONFIRMED.

  SpellCastAura.gd:97-127   ground decal: 2x2 PlaneMesh at y = 0.025,
                            spell_aura.gdshader, one lifetime_progress tween
                            0 -> 1.
  SpellCastAura.gd:134-201  rising wisps, amount = 7 (line 137).
    CONFIRMED "noisy expanding plane plus seven wisps".

  [!] LATENT DEFECT: cleanup at SpellCastAura.gd:49 uses
      get_tree().create_timer(). Pause and skip reach NEITHER. The aura
      already survives a paused queue. The replacement must not repeat this.

  assets/shaders/spell_aura.gdshader:58
    ring centre expands 0.04 -> 0.42
  spell_aura.gdshader:67-68
    centre glow decays by progress 0.45
  spell_aura.gdshader:71
    fade smoothstep(0.65, 1.0)
  spell_aura.gdshader:92
    EMISSION = color * brightness, with intensity 6.0 (line 23)

    THE EXPANDING RING IS WRONG FOR THIS REFERENCE - see section 6, row 8.


5.2 EVENT FLOW

  src/battle_sim/BattleEvents.gd:20
    signal spell_cast_started(casterID, centerPos, spellName, element,
                              targetsHit)
    CONFIRMED.

  src/battle_sim/CombatResolver.gd:486-488
    Emitted EXACTLY ONCE per accepted cast, BEFORE any per-target effect,
    synchronously inside executeCastSpell. Carries NO radius.

  [!] CORRECTION: src/presentation/GodotVisualAdapter.gd:688-704 does NOT
      ignore spell_cast_started. It early-returns when targetsHit > 0
      (lines 694-695) and otherwise enqueues a caster-centred BUMP carrying
      log_text "no units are affected". So the zero-target path already exists
      and already works; only the >=1-target path falls through to per-target
      events.

  GodotVisualAdapter.gd:707-736
    _on_monster_cast_spell enqueues one BUMP per target,
    action.coord = state.getMonsterPosition(targetID).

  GodotVisualAdapter.gd:881-927   _start_bump_animation
  GodotVisualAdapter.gd:907-910   spawns the aura at originalPos (THE CASTER)
                                  whenever action.element is non-empty, and
                                  sets holdDuration =
                                  VISIBLE_DURATION * ACTION_HOLD_FRACTION
                                  = 1.1 * 0.6 = 0.66 s (line 213).
    CONFIRMS the duplicate-caster-aura bug for multi-target spells.


5.3 QUEUE, PACING, AND RENDERING

  src/presentation/VisualAction.gd:8
    enum Kind { FOCUS, MESSAGE, MOVE, BUMP, DEFEAT }
    No cast-area kind, no VFX snapshot.
  VisualAction.gd:39-59
    clone() enumerates every field explicitly and MUST BE EXTENDED IN LOCKSTEP
    with any new field - an omitted field is silently dropped.

  GodotVisualAdapter.gd:241-257   _activateScaled()
    The hold is appended to the action's own tween via
    tween.chain().tween_interval(), so pause, set_speed_scale, and
    skipActive()'s kill() all reach it for free.
    ANY NEW EFFECT MUST HOOK THIS SAME MECHANISM, NOT A PARALLEL SceneTree
    TIMER.

  src/presentation/VisualActionQueue.gd
    activate()            line 138
    setPaused()           line 85   (deliberately does NOT bump _serial)
    skipActive()          line 152
    recover()             line 172
    dispose()             line 188
    MAX_QUEUED_ACTIONS    line 30   := 4096
    WATCHDOG_MARGIN       line 31   := 0.75

  src/systems/BattlePresentationController.gd:126-131
    camera PROJECTION_ORTHOGONAL, size = 14.0, position = Vector3(6, 15, 14).
    NOTE line 465 OVERRIDES size per map to
    max(w,h) * 0.95 + highestElevation * 0.35, so 14.0 is a construction
    default, not the shipping framing.

  BattlePresentationController.gd:113-123
    environment BG_CANVAS, ambient 0.8, SSAO/SSIL off, TONE_MAPPER_LINEAR.
    GLOW IS NOT ENABLED. CONFIRMED.

  [!] CORRECTION (IMPORTANT):
      src/presentation/RetroRenderController.gd:50-51
        render_size defaults to Vector2i(640, 480)
        BUT retro_enabled defaults to FALSE
      RetroRenderController.gd:450-457
        _resize_world_viewport() uses host.get_window().size whenever retro is
        off.

      THE SHIPPING DEFAULT IS A NATIVE-RESOLUTION VIEWPORT, NOT 640x480.
      Low-res only applies under a preset:
        SATURATED_CRT     = 640x480 + CRT   (lines 333-347)
        TACTICAL_SOFT     = 480x360
        FOGGY_SURVIVAL    = 480x360
        TROPICAL_COLOR    = 480x360
        four further presets at 320x240 - HARSHER THAN EITHER RESOLUTION THE
        ORIGINAL BRIEF NAMED.

      The effect must be judged at native, 640x480, 480x360, AND 320x240.

  RetroRenderController.gd:84     world_viewport.own_world_3d = true
  RetroRenderController.gd:86-87  MSAA and screen-space AA disabled

  DAMAGE-NUMBER READABILITY IS STRUCTURAL, NOT A TUNING PROBLEM.
    GodotVisualAdapter.gd:72-80
      damage_number_layer is a CanvasLayer at NoggTheme.WORLD_EFFECT_LAYER (9),
      parented to root_node - OUTSIDE THE BATTLE SubViewport ENTIRELY.
    GodotVisualAdapter.gd:986-1007
      _spawn_damage_number() projects via camera.unproject_position() then
      renderer.world_to_screen().
    Corroborated by docs/ARCHITECTURE.md:298.

    NO WORLD-SPACE EFFECT CAN EVER OCCLUDE A DAMAGE NUMBER. The readability
    budget therefore spends entirely on unit silhouettes and terrain.

  docs/ARCHITECTURE.md:293-296
    The queue plays exactly one action at a time, so two damage numbers from
    one multi-target spell are never simultaneous. A settled contract the new
    flow must preserve.


5.4 DEBUG HARNESS, DATA, AND SCALE

  scenes/debug/VFXDebugScene.tscn
    perspective Camera3D, fov = 55, at (0, 2.8, 3.2)   lines 40-42
    its own Environment (ambient 0.1, energy 0.5)      lines 5-7
    20x20 PlaneMesh; SpawnAnchor; HUD/PanelContainer/Label
    NO RetroRenderController.  CONFIRMED UNTRUTHFUL.

  src/presentation/debug/VFXDebugController.gd
    66 lines; arrows cycle 11 elements, Space retriggers, via _input.

  project.godot HAS NO [input] SECTION AT ALL.
    No custom InputMap actions exist project-wide; only Godot's built-in ui_*
    defaults. Key-collision risk is confined to arrows / Enter / Escape /
    Space.
    Also: textures/canvas_textures/default_texture_filter=0 (Nearest) is
    CANVAS-ONLY; 3D MATERIALS DO NOT INHERIT IT and must set filtering
    explicitly.

  data/spells.json - carrier candidates:
    Ice Plow    ice, RADIUS 2, RANGE 3, CAN_TARGET_EMPTY true, DAMAGE 4
                BEST FIT: largest ice radius, ground-targetable, hits empty
                tiles.
    Ice Plume   ice, RADIUS 1, RANGE 5   (secondary)
    Ice Punch   ice, RADIUS 1, RANGE 1   (secondary)

  src/factories/SpellReferences.gd:24-32   STRING_DEFAULTS
  src/factories/SpellReferences.gd:68-74   normalisation
    The one correct place to add a VFX_PROFILE default.

  SCALE ANCHORS:
    src/presentation/BattleMeshFactory.gd:9
      TERRAIN_CELL_SIZE = Vector3(1.0, 0.5, 1.0)
      => ONE TILE = 1.0 WORLD UNIT, one elevation step = 0.5
    BattleMeshFactory.gd:15     BASE_TOTAL_HEIGHT := 0.2
    BattleMeshFactory.gd:140-152 bodies approx 0.7-0.8 tall
      => A UNIT IS approx 1.0 WORLD UNIT TALL - the same as one tile is wide.
    GodotVisualAdapter.gd:20-22, 126-137
      _surface_y() / _coord_to_surface_pos3d() is the shared surface query.

  src/presentation/theme/NoggTheme.gd:21-36
    CRT_LAYER                     -20
    CRT_OVERLAY_LAYER_DEFAULT     -10
    WORLD_EFFECT_LAYER              9
    GAME_LAYER                     10
    CRT_OVERLAY_LAYER_THROUGH_UI   11
    DEV_LAYER                      20
    DEV_LAYER SITS ABOVE EVERYTHING including the through-UI CRT pass - the
    correct home for the debug panel.

  docs/MODULE_MAP.md:24
    src/presentation/effects/ owns transient effects, may use the Godot 3D
    API, must not be imported by simulation.
  docs/MODULE_MAP.md:22
    presentation may read simulation directories read-only.


5.5 AUDIT OF vfx_plan.md - NOT ADOPTED

  ACCURATE in that file:
    - the render-pipeline facts
    - the current-effect anatomy
    - the single call site
    - the "seven wisps cannot read as an effect" diagnosis
    - the debug-scene-is-untruthful finding

  REJECTED OR SUPERSEDED:
    - Its "no glow is the single largest contributor" thesis and its
      glow-enabling item. Section 7.4 rejects this on reference grounds and on
      whole-game risk.
    - Its shard_burst design using BoxMesh fragments - the references show
      FLAT HARD-EDGED POLYGONS, not lit 3D chunks (section 6, row 5).
    - Its "hard constraint - do not change the public signature" on
      SpellCastAura.spawn. This plan deliberately supersedes that; the
      caster-position call site is the bug.
    - Its ground-ring shader rework (concentric expanding rings, radial
      streaks). THE REFERENCES SHOW NO EXPANDING RING AT ALL (section 6,
      row 8).
    - Its uncommitted-work warning is stale: `git status --short` shows only
      `?? vfx_plan.md`.


--------------------------------------------------------------------------------
6. REFERENCE DECOMPOSITION
--------------------------------------------------------------------------------

Observation vs inference is marked per row. THE TIMING FIELD IS THE WEAKEST -
entries marked (INFERENCE) are derived from wiki mechanics or reasoned from
structure, NOT measured from classic footage. The user-authorized secondary-
source calibration records them as estimates in IceStormProfile.gd.

Scale reference throughout: unit height approx 1.0u, tile width = 1.0u.


ROW 1 - CAST ONSET
  Observation : S2 shows no anticipation ring or charge-up; the storm is
                simply present and dense.
  Source      : S2
  Timing      : onset short; storm at near-full density early (INFERENCE)
  Motion      : downward establishment
  Scale       : full footprint immediately
  Colour      : bright from the start
  Confidence  : LOW
  Translation : Short 8-12% onset - canopy and ground wash fade in, flurry
                ramps to full. NO CHARGE-UP RING; that is generic-spell
                language, not this reference.

ROW 2 - UPPER CLOUD CANOPY
  Observation : S1 - broad pale mass across the top ~20% of the effect,
                brilliant near-white core upper-centre, soft grey feathered
                edges spreading horizontally.
                S2 - bright white puffy mass clearly above unit heads, roughly
                as wide as the storm.
  Source      : S1 (shape), S2 (scale/opacity)
  Timing      : persists whole storm; brightens on the pulse beat (INFERENCE)
  Motion      : slow lateral drift + gentle scale breathing
  Scale       : sits approx 2.5-3.5u above ground; width approx full footprint
  Density     : 2-3 overlapping masses
  Colour      : near-white core -> pale grey-blue edges; ADDITIVE, moderate
                alpha
  Depth       : above everything, behind nothing
  Blending    : additive; never occludes units (it is above them)
  Confidence  : HIGH (structure), MED (timing)
  Translation : 2-3 large camera-facing quads, FBM-masked soft texture,
                additive, slow drift/scale, brightness pulse driven by the
                shared clock.

ROW 3 - FROST-VEIN / CRACKLE BACKDROP
  Observation : S1 - distinct deep blue-violet BRANCHING FILAMENT patterns
                behind the flakes, like frost cracks or lightning.
                S2 - reads only as a diffuse cold blue wash behind the units.
  Source      : S1 (structure), S2 (how it survives low-res)
  Timing      : static-ish; flickers with pulses (INFERENCE)
  Motion      : little to none; intensity modulates
  Scale       : fills the storm volume
  Density     : 1 layer
  Colour      : deep blue-violet, LOW ALPHA
  Depth       : behind the flurry
  Blending    : additive
  Confidence  : MED
  Translation : One additive backdrop quad with a procedural branching/vein
                mask, low intensity. EXPECT IT TO READ ONLY AS A COLD BLUE
                BACKING WASH AT 320x240 - that is correct, not a failure.
                A frequently-missed layer that carries much of the "cold"
                reading.

ROW 4 - DENSE SMALL FLURRY
  Observation : S1 - dozens of small soft-edged white blobs, varied sizes,
                distributed through the volume, densest centre-right.
                S2 - chunky 2-5 px white specks and short streaks.
  Source      : S1 (distribution), S2 (HOW MANY IS ACCEPTABLE)
  Timing      : continuous throughout
  Motion      : predominantly DOWNWARD WITH STRONG LATERAL BIAS, varied speeds
  Scale       : individual flakes much smaller than a unit; volume fills the
                footprint
  Density     : high but GAPPY - S2 shows clear floor between flakes
  Colour      : white / cold-blue, additive, individually semi-transparent
  Depth       : interleaved at many depths - S2 shows flakes BOTH IN FRONT OF
                AND BEHIND units
  Blending    : additive; must NOT merge into solid white
  Confidence  : HIGH
  Translation : GPUParticles3D, soft-dot billboards, additive, distributed
                across the footprint at varied Z so units interleave. Density
                tuned against S2, not S1.

ROW 5 - HERO ICE SHARDS
  Observation : S1 - approx 6-10 HARD-EDGED FLAT WHITE POLYGONS: irregular
                quads and triangles, crisp straight edges, NO GLOW, some pure
                white, some faintly blue, one with a visible gradient.
                Roughly 4-8x a flake.
  Source      : S1
  Timing      : sparse and continuous; individually short-lived
  Motion      : TUMBLE - in-plane rotation while descending
  Scale       : each approx 0.15-0.3u; conspicuously larger than flakes
  Density     : SPARSE - countable
  Colour      : near-opaque white, slight blue variation
  Depth       : through the volume at varied depth
  Blending    : ALPHA-BLENDED, NOT ADDITIVE
  Confidence  : HIGH
  Translation : Flat quads with irregular hard-alpha masks, unshaded,
                near-opaque, in-plane roll animating.
                THE BLEND SPLIT IS THE POINT: soft additive flakes beside hard
                alpha silhouettes is what produces the reference's texture
                contrast. vfx_plan.md's BoxMesh fragments would read as lit 3D
                debris and are rejected.

ROW 6 - GUST STRUCTURE / CIRCULATION
  Observation : S1 - flake distribution is banded and curved rather than
                uniform. S2 - horizontal smearing through the mass.
  Source      : S1, S2
  Timing      : bands sweep across during pulses (INFERENCE)
  Motion      : LATERAL / CURVED SWEEP
  Scale       : bands span the footprint
  Density     : modulates the flurry
  Colour      : same palette as flurry
  Depth       : within the flurry volume
  Blending    : additive
  Confidence  : MED
  Translation : NOT a separate emitter - a LATERAL VELOCITY FIELD plus a
                TRAVELLING DENSITY MASK applied to the flurry, so the field
                reads as wind. Cheaper and more coherent than a second
                particle system.

ROW 7 - CENTRAL BRIGHTNESS / WHITE FLASH
  Observation : S1 - brilliant blowout at the canopy core; centre notably
                brighter than periphery.
                S2 - bright core, BUT FAR LESS EXTREME; clearly the black
                backdrop exaggerates S1.
  Source      : S2 GOVERNS
  Timing      : peaks on each pulse
  Scale       : core approx 1/3 of footprint
  Colour      : white-blue; S2'S RESTRAINT IS AUTHORITATIVE
  Depth       : canopy + upper volume
  Blending    : additive
  Confidence  : MED (S1 misleads)
  Translation : Effect-local brightness ramp on the canopy and flurry near
                centre. NO GLOBAL BLOOM. Peak brightness calibrated against
                S2.

ROW 8 - GROUND RESPONSE
  Observation : S2 - soft white-blue wash on the floor around the units; TILE
                EDGES REMAIN CLEARLY VISIBLE THROUGH IT.
                NEITHER IMAGE SHOWS AN EXPANDING RING, SHOCKWAVE, OR HARD
                DISC.
  Source      : S2
  Timing      : present throughout; fades late
  Motion      : static
  Scale       : covers the footprint
  Density     : 1 layer
  Colour      : cold white-blue, LOW ALPHA
  Depth       : ground plane
  Blending    : additive, depth_draw_never
  Confidence  : HIGH (including the negative finding)
  Translation : Soft low-alpha cold wash disc. EXPLICITLY NOT AN EXPANDING
                RING - this reverses both the current shader's central
                behaviour and vfx_plan.md's ring rework.

ROW 9 - PULSE CADENCE
  Observation : NOT OBSERVABLE IN STILLS
  Source      : wiki mechanics + inference
  Timing      : 10 hits at 0.5 s over 4.5 s
  Motion      : brightness/density surge
  Confidence  : MED-LOW AS ANIMATION TIMING
  Translation : Repeating brightness + density accent on a fixed interval.
                Authorized secondary footage supports a repeating beat but
                cannot prove exact classic timing. Cosmetic only - emits nothing.

ROW 10 - FADE-OUT / SETTLE
  Observation : NOT OBSERVABLE IN STILLS
  Source      : inference
  Timing      : staggered
  Confidence  : LOW
  Translation : Canopy, flurry, shards, and ground wash fade on STAGGERED
                schedules. Shards stop spawning first; flurry thins; canopy
                dissipates last.

ROW 11 - CONTINUOUS VS BURST
  Observation : S2 shows a sustained field, not a detonation.
  Source      : S2 + wiki
  Timing      : sustained 4.5 s
  Confidence  : HIGH
  Translation : SUSTAINED HYBRID - a continuous field with periodic accents.
                Not a burst.

ROW 12 - FOOTPRINT AND VERTICAL VOLUME
  Observation : S2 - the effect spans roughly 4 character-heights vertically
                and approx 4 character-widths horizontally; volume is roughly
                as tall as it is wide.
  Source      : S2
  Scale       : approx 4x unit height => approx 4u tall; width from spell
                radius
  Confidence  : MED
  Translation : Width = (RADIUS * 2 + 1) tiles, approx 5.0u for the RADIUS 2
                carrier. Height approx 3.5-4.0u, canopy topping out around
                3.0-3.5u. (ESTIMATES recorded in IceStormProfile.gd.)

ROW 13 - SILHOUETTE READABILITY
  Observation : S2 - units are fully readable black/white silhouettes; HP
                bars, names, and the yellow "404" all legible through the
                storm.
  Source      : S2
  Density     : storm covers maybe 40-60% with real gaps
  Confidence  : HIGH
  Translation : Hard acceptance criterion. Controlled negative space is a
                FEATURE, not leftover budget.

ROW 14 - LOW-RES / SPRITE CHARACTER
  Observation : S2 - chunky aliased specks, limited colour count, obvious
                billboard flatness, no soft volumetrics.
  Source      : S2
  Confidence  : HIGH
  Translation : Nearest filtering, low source resolutions, limited palette,
                hard alpha where the reference is hard. DELIBERATELY AVOID
                smooth volumetrics, soft shadows, and global bloom.


COMPARISON CHECKPOINTS (normalised t, for matched captures):
  t = 0.08   onset settled
  t = 0.25   pulse 2 peak
  t = 0.50   mid-storm, full density
  t = 0.75   late pulse
  t = 0.95   staggered fade
These remain estimated checkpoints under the user-authorized secondary-source
calibration.


--------------------------------------------------------------------------------
7. TECHNICAL APPROACH COMPARISON AND CHOSEN ARCHITECTURE
--------------------------------------------------------------------------------

7.1 OPTION 1 - MOSTLY GPUParticles3D

  Classic 2.5D similarity  MEDIUM-POOR. Simulated particles read as modern;
                           classic effects are authored keyframed layers.
  Temporal control/pulses  POOR. Ten discrete pulses need either ten emitters
                           or `emitting` toggling that breaks continuity.
  Pause / exact frames     PARTIAL - speed_scale = 0 freezes, but no backward
                           scrub.
  Low-res pipeline         POOR - many small additive quads dissolve into
                           undifferentiated noise at 320x240.
  Depth sorting            GOOD - genuine 3D interleaving with units.
  Reproducible captures    POOR without a verified fixed-seed path.
  Performance              GOOD.
  Tuning / maintainability MEDIUM - process-material tuning is opaque.
  Provenance               CLEAN.
  Simultaneous casts       GOOD.

  VERDICT: fails on pulse cadence and frame control - the two most
  recognisable Storm Gust traits.


7.2 OPTION 2 - PURE FLIPBOOK ON CAMERA-FACING QUADS

  Classic 2.5D similarity  HIGHEST IN PRINCIPLE - the period-correct
                           technique.
  Temporal control/pulses  PERFECT - frame index is an integer.
  Pause / exact frames     PERFECT.
  Low-res pipeline         EXCELLENT.
  Depth sorting            DISQUALIFYING. A flat quad is entirely in front of
                           or behind a unit. S2 shows flakes on BOTH sides of
                           the units.
  Reproducible captures    PERFECT.
  Performance              EXCELLENT.
  Tuning                   POOR - every change means regenerating the sheet.
  Provenance               CLEAN but expensive: a convincing 4.5 s turbulent
                           blizzard sheet is a large procedural authoring job.
  Simultaneous casts       GOOD.

  VERDICT: perfect control, wrong volume. Cannot interleave with unit depth,
  which S2 requires.


7.3 OPTION 3 - HYBRID, DETERMINISTIC-CLOCK DRIVEN  ***SELECTED***

  The two references jointly demand characteristics neither pure option
  provides:

    1. S1's BLEND SPLIT (soft additive flakes beside hard alpha-blended shard
       silhouettes) is cheap with two draw materials and awkward to bake into
       one sheet.
    2. S2's DEPTH INTERLEAVING (flakes in front of AND behind units) requires
       real 3D distribution - ruling out Option 2.
    3. THE PULSE CADENCE requires deterministic temporal authority - ruling
       out Option 1.

  THE LOAD-BEARING ARCHITECTURAL RULE: NO LAYER OWNS ITS OWN TIME.

  Every layer animates as a function of a single normalised t in [0,1] that an
  effect-local clock writes each frame:

    - SHADERS read a `uniform float phase` the controller writes. THEY MUST
      NEVER USE `TIME` - TIME cannot be paused, scrubbed, or made
      deterministic.
    - THE CANOPY FLIPBOOK frame is int(t * frames) % frames - scrubs exactly,
      both directions.
    - SHARDS are controller-transformed: position and roll are pure functions
      of t and a per-shard seed - scrub exactly, both directions.
    - THE PARTICLE FLURRY is the one honest exception (7.5).

  This yields Option 2's temporal precision for everything except the flurry,
  Option 1's depth behaviour, and the reference's blend contrast - while
  keeping every texture procedural.


7.4 REJECTED AS A PREREQUISITE: GLOBAL GLOW

  vfx_plan.md treats enabling Environment glow as the single biggest win.
  THIS PLAN REJECTS THAT, on three grounds:

    1. REFERENCE GROUNDS. S1's bloom is largely an artefact of its black
       backdrop and non-classic capture (4.2). S2 - the authority for
       rendering character - shows crisp, aliased, limited-palette
       compositing, NOT a bloomed image. Global bloom actively moves the
       result AWAY from the target.

    2. WHOLE-GAME RISK. BattlePresentationController.gd:113-123 builds one
       shared Environment. Glow restyles terrain, monsters, and UI-through-CRT
       at once - explicitly excluded by scope.

    3. A CHEAPER LOCAL ALTERNATIVE EXISTS. Effect-local brightness ramps and a
       soft additive canopy produce the reference's luminosity without
       touching the environment.

  If SG-VALIDATE shows the effect reads flat SPECIFICALLY BECAUSE OF MISSING
  BLOOM, that becomes a separate, user-approved cycle - not a dependency
  buried in this one.


7.5 THE HONEST LIMIT: GPU PARTICLE SCRUBBING

  GPUParticles3D simulates on the GPU and CANNOT BE SCRUBBED BACKWARD. This
  plan therefore promises exactly this and no more:

    PAUSE             speed_scale = 0 freezes the flurry with everything else.
                      Coherent and exact.
    FORWARD STEPPING  Exact.
    BACKWARD SCRUB    The canopy, shards, veins, ground wash, and all shader
                      phase are EXACT. The flurry is RESTART-APPROXIMATE - it
                      restarts under its fixed seed and fast-forwards to the
                      target t.

  SG-3 must VERIFY whether Godot 4.4's GPUParticles3D fixed-seed properties
  and `preprocess` permit an exact restart-to-time. If they do, backward scrub
  is exact everywhere. If not, THE HUD MUST DISPLAY `flurry: approx` whenever
  the paused frame was reached by backward scrub, so a debug frame never
  silently lies.

  NO CONTROL IS OFFERED THAT PRODUCES AN INACCURATE FRAME WITHOUT SAYING SO.


--------------------------------------------------------------------------------
8. PROPOSED RUNTIME / DATA FLOW
--------------------------------------------------------------------------------

  CombatResolver.executeCastSpell()                    [headless, unchanged]
    |
    +-- events.spell_cast_started.emit(casterID, centerPos, spellName,
    |                                  element, targetsHit)
    |     CombatResolver.gd:486
    v
  IBattleVisualAdapter._on_spell_cast_started()        [port, unchanged]
    |
    v
  GodotVisualAdapter._on_spell_cast_started()          [MODIFIED]
    |
    +-- profile <- SpellVfxCatalog.resolve(
    |                SpellReferences.getReference(spellName))
    |
    +-- builds ONE VisualAction(Kind.CAST_AREA), snapshotting:
    |     coord, element, monster_id(caster), log_text,
    |     origin = _coord_to_surface_pos3d(centerPos), has_origin,
    |     vfx_profile, vfx_radius, vfx_seed, vfx_ground_span
    |
    +-- _queue.enqueue(action)          -> clones the snapshot
    v
  VisualActionQueue
    -> _start_queued_animation()
    -> _start_cast_area_animation()                    [NEW]
         |
         +-- effect <- SpellVfxCatalog.spawn(profile, visual_parent, action)
         +-- registers effect in _live_effects for pause / speed / dispose
         +-- _activateScaled(tween, action, 0.0, holdDuration)
               hold approx onset + 2 pulses
         v
  IceStormEffect (Node3D, src/presentation/effects/)   [NEW]
    +-- effect-local clock: t in [0,1], scale-aware, pausable
    +-- canopy quads / vein backdrop / flurry particles / gust mask /
    |   shards / ground wash
    +-- self-frees on completion  (NOT a SceneTree timer - see 5.1)

  Per-target monster_cast_spell -> BUMP actions play OVER the running storm,
  each carrying its own damage number, exactly as today.


RESOLUTIONS TO THE FIFTEEN ARCHITECTURE QUESTIONS

Q1 - EXACTLY ONE VISUAL PER CAST.
  CombatResolver.gd:486 already emits spell_cast_started exactly once per
  accepted cast, before any per-target effect. Remove the `targetsHit > 0`
  early return at GodotVisualAdapter.gd:694-695 and always enqueue one
  CAST_AREA action. Zero-target casts keep their existing log_text.

Q2 - NO DUPLICATE STORMS.
  MOVE ALL CAST VFX TO spell_cast_started AND DELETE THE AURA SPAWN FROM
  _start_bump_animation (lines 907-910). Per-target BUMP actions keep the
  lunge and damage number and spawn no effect.

  This deliberately avoids the alternative - tracking a "cast in progress"
  flag consumed by later events - which would be fragile:
  passiveSkillResolver.fireOnTargeted (CombatResolver.gd:490-494) and
  _handleDefeat run BETWEEN the emissions and could nest another cast.
  REMOVING THE STATE IS BETTER THAN SYNCHRONISING IT.

  CONSEQUENCE TO STATE PLAINLY: EVERY SPELL'S AURA MOVES FROM THE CASTER TO
  THE TARGET CENTRE. For ranged AoE that is a bug fix; it is still a
  user-visible change to all spells and belongs in validation, not in silence.

Q3 - DEDICATED Kind: YES.
  VisualAction.Kind.CAST_AREA.
  Immutable fields: existing coord, element, monster_id, left_monster_id /
  has_left_monster, log_text, origin / has_origin; NEW vfx_profile: String,
  vfx_radius: int, vfx_seed: int, vfx_ground_span: float.
  clone() (VisualAction.gd:39-59) MUST BE EXTENDED FOR EVERY ONE - it
  enumerates fields explicitly and silently drops anything omitted.

Q4 - WORLD-SPACE CENTRE.
  _coord_to_surface_pos3d(centerPos) (GodotVisualAdapter.gd:136-137), the same
  shared surface query movement, cursor, and overlays use. Computed AT ENQUEUE
  TIME and frozen on the snapshot, honouring ARCHITECTURE.md:280.

Q5 - RADIUS WITHOUT MUTABLE STATE.
  spell_cast_started carries no radius, and extending the signal would touch
  BattleEvents, IBattleVisualAdapter, CombatResolver, and ConsoleVisualAdapter.
  Instead presentation reads the authored catalog:
  SpellReferences.getReference(spellName) -> RADIUS, snapshotted onto the
  action at enqueue. MODULE_MAP.md:22 permits presentation to read simulation
  directories read-only, and NAME is the catalog's documented primary key
  (SPELL_CATALOG_SCHEMA.md). No event change, no headless change, no
  dependence on later mutable state.

Q6 - SELECTION WITHOUT NAME BRANCHING.
  Looking a spell up BY PRIMARY KEY is not branching on a display name;
  `if spellName == "Ice Plow"` would be. Selection reads the authored
  VFX_PROFILE field. A presentation-only SpellVfxCatalog maps profile id ->
  factory. No spell-name conditional appears anywhere.

Q7 - VFX PROFILE FIELD: YES.
  VFX_PROFILE, normalised at the existing catalog boundary in
  SpellReferences.STRING_DEFAULTS (lines 24-32, applied 73-74), default "".
  Presentation metadata, not gameplay - it changes no damage, radius, or
  targeting.

Q8 - SPELLS WITHOUT A PROFILE.
  "" resolves to the existing SpellCastAura, now spawned once at the target
  centre instead of N times at the caster. Its spawn() signature is superseded
  by the registry's uniform contract (SG-3); the original brief authorises
  this and the old signature is exactly what encodes the bug.

Q9 - PAUSE / SPEED / SKIP / WATCHDOG / DISPOSE / TEARDOWN.
  SPEED     the adapter passes _animation_speed_scale (lines 199-206) into the
            effect's clock at spawn.
  PAUSE     the adapter holds _live_effects: Array[WeakRef] and forwards pause
            by setting each effect's playback scale to 0. Required because the
            storm outlives its queue slot; the tween-appended hold alone
            cannot cover it.
  SKIP      skipActive() kills the tween; the adapter calls
            effect.skip_to_settle() so the storm resolves gracefully instead
            of vanishing.
  WATCHDOG  unaffected - the hold is short and tween-bound, so activate()'s
            duration remains truthful.
  DISPOSE   dispose() (line 1115) frees every live effect.
  THE EFFECT MUST NOT USE get_tree().create_timer() FOR CLEANUP - the current
  aura's mistake at SpellCastAura.gd:49, which pause and skip cannot reach.

Q10 - HOLD DURATION.
  Hold the CAST_AREA action for ONSET + THE FIRST TWO PULSES (approx 0.45 of
  battle duration, approx 1.0 s), then advance. The tail overlaps the
  per-target damage numbers deliberately: the numbers SHOULD appear while the
  storm still rages, which is both better-looking and better-paced than gating
  the full duration. Holding all approx 2.2 s would worsen the known "visual
  playback can no longer keep up with an unpaced simulation" backlog entry.

Q11 - NO WHITE-OUT.
  Classic Storm Gust does not stack with itself, and this mirrors that: the
  adapter caps live storms at TWO; a third replaces the oldest. Overlapping
  storms scale their additive intensity by 1 / live_count. Simple, measurable,
  reference-faithful.

Q12 - REPEATABLE RANDOMNESS, NEVER TOUCHING BattleState.rng.
  vfx_seed is derived at enqueue from data already in the event:
    hash(spellName) ^ (casterID * 73856093)
                    ^ (centerPos.x * 19349663)
                    ^ (centerPos.y * 83492791)
  Deterministic, replay-stable, presentation-only. The harness can pin or
  cycle it. AGENTS.md's rule that GAMEPLAY randomness routes through
  BattleState.rng is preserved precisely because this is not gameplay
  randomness.

Q13 - UNEVEN TERRAIN / MULTI-TILE FOOTPRINTS.
  The storm anchors at the centre tile's surface. vfx_ground_span - sampled at
  enqueue as max(_surface_y) - min(_surface_y) across the footprint - lets the
  ground wash thicken vertically so it does not float above lower tiles or
  sink into higher ones. One extra float; no per-tile decal machinery.

Q14 - READABILITY.
  Damage numbers are structurally safe (5.3). Unit silhouettes are protected
  by budget, not luck: capped flurry density, the canopy sitting above head
  height, and enforced negative space (section 10), verified by screenshot at
  every resolution.

Q15 - LAYER OWNERSHIP.
  Everything new lives in src/presentation/ - effects/ for the effect,
  textures, and profile constants; debug/ for the harness. The only files
  touched outside presentation are data/spells.json (an authored field),
  src/factories/SpellReferences.gd (its normalisation), src/entities/Spell.gd
  (carrying it), and docs/SPELL_CATALOG_SCHEMA.md.
  NO PRESENTATION NODE, TYPE, OR IMPORT ENTERS src/battle_sim/, AND NO
  SIMULATION FILE IMPORTS PRESENTATION.


--------------------------------------------------------------------------------
9. TIMING MODEL
--------------------------------------------------------------------------------

One normalised timeline t in [0,1] drives both modes. Only two constants
differ.

                        REFERENCE-SPEED          BATTLE-SPEED
  Total duration        4.5 s (wiki-sourced)     approx 2.2 s (ESTIMATE -
                                                 user-approved at SG-VALIDATE)
  Pulse interval        0.45 s                   0.44 s
  Pulse count           10                       approx 5
  Onset/sustain/settle  8% / 74% / 18%           identical proportions
                        (ESTIMATE)

THE PRESERVED QUANTITY IS THE PULSE INTERVAL, NOT THE PULSE COUNT.
Compressing ten pulses into 2.2 s would produce flicker; holding the interval
and letting the count fall out of the duration keeps the rhythm identical and
simply makes the storm shorter. Phase proportions are fractions of t, so they
are automatically preserved.

Both modes are the same code path with different total_duration and
pulse_interval. Reference-speed exists ONLY IN THE HARNESS; battle-speed
ships. Road of Nogg is never silently given Ragnarok's gameplay duration -
that is the entire point of the split, and SG-VALIDATE requires explicit user
approval of the battle-speed number.


--------------------------------------------------------------------------------
10. PERFORMANCE AND READABILITY BUDGETS
--------------------------------------------------------------------------------

Measured via Performance.get_monitor() in the harness HUD and re-measured in
battle.

  Live particles, one storm      <= 220
    S2's density is achievable well under this; more merges into white noise.

  Live particles, cap (2 storms) <= 440
    The Q11 cap makes this a hard ceiling.

  Draw calls added, one storm    <= 14
    2-3 canopy + 1 vein + 1 ground + 1 flurry pass + 1 shard pass + slack.

  Effect node count, one storm   <= 12
    Flat structure; deep trees complicate cleanup.

  Node count after 20 casts      EXACT BASELINE
    Any drift is a leak.

  Frame time added               <= 3 ms at 640x480
    Idle frames already reach approx 21 ms (BACKLOG_LONGTERM.md), so headroom
    is genuinely tight.

  FILL RATE
    Large additive quads dominate at low res - PREFER MANY SMALL QUADS TO FEW
    LARGE ONES. The real cost at 320x240.

READABILITY BUDGET

  Footprint pixels fully obscured        <= 60% at peak (S2-derived)
  Unit silhouette recognisable @320x240  REQUIRED AT EVERY t
  Terrain elevation readable through     REQUIRED
  Damage numbers                         structurally guaranteed (5.3)
  Hero shards on screen at once          <= 8, individually countable


--------------------------------------------------------------------------------
11. ORDERED IMPLEMENTATION ITEMS
--------------------------------------------------------------------------------

================================================================================
SG-1 - ESTABLISH THE REFERENCE DECOMPOSITION AND CALIBRATION CONSTANTS
================================================================================

MODEL:        Opus 5 / GPT Sol
DEPENDS ON:   none

RISK: High. Every later item is authored against these numbers. Worse,
section 6's timing column is currently INFERENCE, NOT MEASUREMENT - if this
item rubber-stamps it, the whole cycle inherits unverified timing.

MITIGATION / ROLLBACK BOUNDARY: produces exactly one new file of constants and
comments. Wrong values are corrected by editing that file; no other item is
invalidated structurally.

ADDS TO VALIDATION COVERAGE: the shipping effect's proportions, cadence, and
palette trace to a recorded, sourced decomposition rather than to taste.

END STATE: src/presentation/effects/IceStormProfile.gd holds every calibrated
constant with its source and confidence recorded in comments. The reference
decomposition is settled and no later item re-derives it.

WORK
  1. WATCH THE CANDIDATE FOOTAGE IN 4.3. Record for each: resolved
     server/client version where discoverable, useful timestamps, and whether
     the effect is stock or modified. DISCARD ANY SOURCE THAT CANNOT BE SHOWN
     TO BE CLASSIC/PRE-RENEWAL STOCK, OR LABEL IT SECONDARY.
  2. From that footage, CONFIRM OR CORRECT every section 6 row marked
     (INFERENCE): pulse cadence and whether the visual beat tracks the 0.5 s
     damage beat; onset length; settle stagger; shard spawn rate; gust-band
     sweep direction and period.
  3. Re-measure section 6's scale estimates (row 12) against S2 and record
     them in world units, keyed to tile = 1.0u, unit height approx 1.0u.
  4. Settle the palette: canopy core/edge, flake, vein, shard, and ground-wash
     colours, sampled from S2 for luminosity and S1 only for hue relationships
     (4.2).
  5. Write IceStormProfile.gd as a pure constants script - durations, pulse
     interval, phase fractions, layer counts, densities, sizes, colours,
     alphas, comparison checkpoints. EVERY CONSTANT CARRIES A COMMENT NAMING
     ITS SOURCE AND MARKING IT MEASURED OR ESTIMATED.
  6. Record the 4.2 S1/S2 conflict resolution in the file header so no later
     session re-litigates it.
  7. Review the backlogs.

FILES: src/presentation/effects/IceStormProfile.gd (+ .uid)

BLOCKING USER DECISION: Resolved 2026-08-03. The user explicitly authorized
calibration from the inspected post-Renewal/Zero footage after the candidate
set failed to prove classic-stock motion.

RESOLUTION: Implemented; pending end-of-plan validation.

Added IceStormProfile.gd as a presentation-only constants script. It records
the S1/S2 authority split in its header and labels every duration, cadence,
phase, scale, density, motion, palette, alpha, checkpoint, readability target,
and performance cap with its source and measured/estimated status. The profile
uses the wiki-sourced 4.5 s reference duration, an estimated 2.2 s battle mode,
0.45/0.44 s pulse intervals, 8/74/18 percent phases, a measured five-tile
carrier footprint, an estimated 3.8 u vertical volume, 180 gappy flurry
particles, and at most eight alpha-blended hero shards. The inspected secondary
footage informs motion estimates only; the file makes no classic-client frame
measurement claim. No runtime effect or gameplay behavior exists yet, and
vfx_plan.md remains untouched. Backlog review found no additional unresolved
work beyond the already-preserved battle-window validation. A bounded Godot
editor/import smoke probe exited 0 and generated the script UID; it emitted only
the documented headless-editor progress-dialog noise, with no parse error. A
separate bounded load probe then emitted ICE_STORM_PROFILE_LOAD_OK with the
expected 4.5 s reference duration.

================================================================================
SG-2 - MAKE VFXDebugScene RENDER THROUGH THE REAL BATTLE PIPELINE
================================================================================

MODEL:        Sonnet 5 / GPT Terra
DEPENDS ON:   none (parallel with SG-1)

RISK: Medium. RetroRenderController._init() adds children to its host and
connects host.get_viewport().size_changed (lines 88, 97, 123, 134). Standalone
instantiation from a Node3D root should work but is unproven.

MITIGATION / ROLLBACK BOUNDARY: debug-only; touches no battle file. If
standalone instantiation proves invasive, FALL BACK to matching the battle
camera and environment exactly and driving a SubViewport manually - and record
why. Do not restructure RetroRenderController to make this work.

ADDS TO VALIDATION COVERAGE: the debug scene renders through the real
retro/CRT path at real resolutions with battle-matched orthographic framing;
battle rendering is unchanged.

END STATE: what an author sees in VFXDebugScene is what ships.

WORK
  1. In VFXDebugController._ready(), instantiate RetroRenderController.new(self)
     and REPARENT the existing Camera3D, DirectionalLight, Ground, and
     SpawnAnchor into retro_renderer.world_root. Reparent at runtime rather
     than restructuring the .tscn, so the scene stays editable.
  2. Replace the perspective camera settings with the battle's:
     PROJECTION_ORTHOGONAL, and THE SAME RELATIVE OFFSET AND ANGLE as
     Vector3(6, 15, 14) looking at the board - computed from the anchor, since
     the anchor is at origin and the battle camera is not. Use a
     representative `size` reflecting the per-map override at
     BattlePresentationController.gd:465, not the raw 14.0 default.
  3. Build the debug Environment from the SAME CODE PATH as the battle's
     (lines 113-123). If that requires extracting a small static factory
     returning a configured Environment, do that as composition. DO NOT make
     the debug scene depend on BattlePresentationController or anything in
     src/battle_sim/.
  4. Add a resolution control covering NATIVE, 640x480, 480x360, AND 320x240,
     plus retro on/off and CRT on/off, driven through RetroRenderController's
     existing preset and parameter API. Record in the Resolution that the
     shipping default is native (5.3 [!]).
  5. Add DUMMY UNITS AT REAL GAMEPLAY SCALE - bodies approx 0.7-0.8u on a 0.2u
     base, per BattleMeshFactory.gd:15, 140-152 - built through
     BattleMeshFactory so they use the real retro materials, not debug
     stand-ins.
  6. Add a FLAT and an UNEVEN terrain sample using real TERRAIN_CELL_SIZE
     blocks, so multi-tile footprint behaviour is inspectable.
  7. Add a TARGET-CENTRE MARKER and FOOTPRINT GUIDE ring sized from a radius
     setting.
  8. Review the backlogs.

FILES: scenes/debug/VFXDebugScene.tscn,
       src/presentation/debug/VFXDebugController.gd,
       src/presentation/BattleEnvironmentFactory.gd,
       src/systems/BattlePresentationController.gd
       (environment-factory extraction only)

RESOLUTION: Implemented; pending end-of-plan validation. VFXDebugScene now
constructs RetroRenderController against its Node3D host and reparents the
editable camera, light, ground, and spawn anchor into the isolated world at
runtime. Its orthographic camera uses the shipping Vector3(6, 15, 14) relative
offset and the 15.55 size produced by the default 16-cell maps' camera formula.
A shared presentation factory now supplies the exact battle Environment to both
the battle controller and debug scene without introducing a battle-simulation
dependency. Native (the shipping default), 640x480, 480x360, and 320x240
controls refresh through RetroRenderController's existing look-parameter path;
retro and CRT toggles remain independently inspectable. The scene includes real
BattleMeshFactory terrain blocks, 0.2 u model bases with gameplay-scale bodies,
flat and uneven samples, a target-centre marker, and a radius-driven footprint
ring. The ignored debug paths are deliberately task-owned artifacts and will be
force-added at this boundary. A bounded editor/import probe and a five-frame
headless scene run both exited 0 with no parse or runtime errors. This is an
intermediate smoke check, not manual visual acceptance. Backlogs were reviewed;
no new unresolved work was found.


================================================================================
SG-3 - PLAYBACK CONTRACT, EFFECT REGISTRY, AND THE DEBUG UI PANEL
================================================================================

MODEL:        Sonnet 5 / GPT Terra
DEPENDS ON:   SG-2

RISK: High. This defines the pause/scrub contract every layer must obey. A
contract that cannot actually freeze GPU particles coherently would produce
debug frames that LIE, and every subsequent tuning decision would be made
against a false image.

MITIGATION / ROLLBACK BOUNDARY: verify the particle behaviour BEFORE building
the UI on top of it. If exact restart-to-time is unavailable, ship the
approximate path WITH A VISIBLE `flurry: approx` HUD MARKER (7.5) rather than
a silent inaccuracy.

ADDS TO VALIDATION COVERAGE: effect selection, Play, Pause/Resume, and status
readout work; repeated use leaks nothing; a paused frame is coherent across
every layer or is explicitly labelled approximate.

END STATE: "Choose effect -> Play -> Pause/Resume" works in a sharp,
responsive panel outside the low-res viewport.

WORK
  1. Define src/presentation/effects/VfxPlayback.gd - the interface every
     previewable effect implements:
       play(seed, mode)
       set_playback_scale(f)
       seek_normalized(t)
       skip_to_settle()
       get_normalized_time()
       is_finished()
       dispose()
  2. Create src/presentation/effects/SpellVfxCatalog.gd - a presentation-only
     registry mapping profile id -> display name + factory Callable. Register
     "" -> SpellCastAura initially. NO SPELL-NAME CONDITIONALS, here or in the
     controller. Adapt SpellCastAura behind the uniform contract.
  3. VERIFY whether Godot 4.4's GPUParticles3D fixed-seed properties and
     `preprocess` support exact deterministic restart-to-time. Record the
     finding in the Resolution - SG-5 depends on it.
  4. Build the debug panel on a CanvasLayer at NoggTheme.DEV_LAYER (20), ABOVE
     CRT_OVERLAY_LAYER_THROUGH_UI (11), so it stays sharp and clickable while
     the preview is paused:

       "Effect" OptionButton - populated from the registry. Changing selection
         chooses the next effect and does NOT trigger it.

       "Play" - disposes any active instance, then starts the selection from
         its first frame at the anchor. While paused, Play RESTARTS FROM THE
         BEGINNING, never resumes ambiguously.

       "Pause" / "Resume" - freezes at the current frame; label toggles;
         resume continues from that exact frame without changing the seed.
         IMPLEMENTED VIA set_playback_scale(0.0) ON THE EFFECT.
         NEVER Engine.time_scale - the panel must stay responsive.

       STATUS READOUT: selected effect / playing-paused-stopped /
         reference-vs-battle speed / normalised t and elapsed-total /
         active seed / live particle and node counts /
         `flurry: exact|approx`.

  5. Add supplementary controls that do not complicate the core flow: mode
     toggle, slow-motion scale, scrub, seed pin/cycle, per-layer visibility
     toggles, overlapping-cast trigger, and single-shot screenshot capture.
  6. SCREENSHOT CAPTURE MUST BE ONE CAPTURE PER PROCESS.
     docs/LEARNINGS.md:230-245 records that a second capture in one SceneTree
     returns a byte-identical STALE image and that awaiting more frames does
     not fix it. Provide a single-capture key AND a command-line
     `--capture-at=<t>` mode that launches, seeks, captures once, and quits.
     DO NOT PROMISE AUTOMATED MULTI-CHECKPOINT CAPTURE IN ONE RUN.
  7. Keyboard shortcuts are supplementary only. project.godot defines NO
     [input] section, so only Godot's built-in ui_* defaults exist; avoid
     Enter, Escape, Space, and the arrows. Use letter keys.
  8. Verify repeated select/play/pause/restart cycles leak no nodes,
     particles, tweens, timers, or signal connections.
  9. Review the backlogs.

FILES: src/presentation/effects/VfxPlayback.gd (+ .uid),
       src/presentation/effects/SpellVfxCatalog.gd (+ .uid),
       src/presentation/debug/VFXDebugController.gd,
       scenes/debug/VFXDebugScene.tscn,
       src/presentation/effects/SpellCastAura.gd

RESOLUTION: Not started.


================================================================================
SG-4 - PROCEDURAL TEXTURE LIBRARY AND SHARED MATERIAL CONVENTIONS
================================================================================

MODEL:        Sonnet 5 / GPT Terra
DEPENDS ON:   SG-1 (palette and sizes)

RISK: Low individually, but load-bearing. Wrong filtering or blend defaults
here would be re-litigated in every layer of SG-5.

MITIGATION / ROLLBACK BOUNDARY: each texture must be independently previewable
through SG-3's layer toggles so a bad one can be bisected.

ADDS TO VALIDATION COVERAGE: every texture is procedural, built once and
cached, and survives 320x240 without dissolving; no VFX art asset is imported.

END STATE: src/presentation/effects/VfxTextures.gd provides cached procedural
textures and correct shared materials.

WORK
  1. Implement cached static getters, extending the _ensure_shared_resources()
     pattern at SpellCastAura.gd:60. ALL GENERATED AT RUNTIME - no image file
     is imported, so there are no .import settings and no provenance question.

     GETTER          SRC RES   ALPHA TREATMENT          WHY IT SURVIVES LOW RES
     -------------------------------------------------------------------------
     soft_flake()    16^2      radial, soft edge        Small enough that
                                                        320x240 downsampling
                                                        cannot dissolve it
                                                        further.
     shard_mask(i)   32^2 x4   HARD ALPHA, straight     Hard edges stay hard at
                               edges                    any resolution - the
                                                        row 5 silhouette.
     canopy_puff()   64^2      FBM-masked radial, soft  Large and
                                                        low-frequency;
                                                        downsampling harmless.
     frost_vein()    128^2     branching filament mask, Degrades gracefully to
                               low alpha                a blue wash (row 3).
     ground_wash()   64^2      soft radial, very low    Broad and low-contrast
                               alpha                    by design.

  2. Set filtering explicitly per material:
     TEXTURE_FILTER_NEAREST on flake and shard draw materials (hard,
     pixelated, period-correct); linear acceptable on canopy, vein, and ground
     wash (broad soft masses where nearest only adds aliasing).
     project.godot's default_texture_filter=0 is CANVAS-ONLY AND DOES NOT
     REACH 3D MATERIALS (5.4) - every 3D material must set it.

  3. Shared material conventions, fixed once here:
     - ADDITIVE (BLEND_MODE_ADD) for canopy, flurry, veins, ground wash.
     - ALPHA-BLENDED (TRANSPARENCY_ALPHA, default blend) for HERO SHARDS -
       row 5's blend split is the reference's signature contrast and must not
       be collapsed.
     - SHADING_MODE_UNSHADED, disable_receive_shadows = true, depth_draw_never
       on all.
     - vertex_color_use_as_albedo = true so ramps drive fade.
     - EMISSION ENERGY AT OR NEAR 1.0. With glow deliberately disabled (7.4),
       values above 1.0 merely clip to white - the existing shader's
       intensity = 6.0 (spell_aura.gdshader:23) is wasted work, not
       brightness.

  4. Verify each texture at 320x240 through SG-3's toggles before committing.
  5. Review the backlogs.

FILES: src/presentation/effects/VfxTextures.gd (+ .uid)

RESOLUTION: Not started.


================================================================================
SG-5 - COMPOSE THE ICE STORM EFFECT
================================================================================

MODEL:        Opus 5 / GPT Sol
DEPENDS ON:   SG-1, SG-3, SG-4

RISK: HIGHEST IN THE PLAN. Overlapping additive layers saturate to a white
blob - the failure the current effect already has, and this version has far
more layers with which to have it. It is also where "reads as classic RO" is
won or lost.

MITIGATION / ROLLBACK BOUNDARY: build layers IN THE ORDER BELOW, inspecting
each through SG-3's pause and layer toggles before adding the next. If it
saturates, REDUCE LAYER COUNT OR ALPHA BEFORE REDUCING BRIGHTNESS - the
reference's restraint comes from negative space, not from dimness. Each layer
is independently toggleable, so a bad one is bisectable. The effect is one
self-contained file; rollback is reverting it.

ADDS TO VALIDATION COVERAGE: canopy, flurry, gust motion, hero shards, veins,
ground wash, and pulse accents are each separately legible; the storm is
sustained, not a burst; staggered fade; budgets met.

END STATE: IceStormEffect implements VfxPlayback, registers as
`ice_area_storm`, and is selectable in the harness.

WORK
  1. EFFECT-LOCAL CLOCK FIRST. _process(delta) advances t by
     delta * playback_scale / total_duration. Every layer reads t.
     NO LAYER MAY READ `TIME` OR CREATE ITS OWN TIMER - this is what makes
     pause, scrub, speed scaling, and determinism work at all, and what avoids
     SpellCastAura.gd:49's unreachable cleanup timer.
  2. Seed every stochastic choice from vfx_seed via a local
     RandomNumberGenerator. NEVER BattleState.rng.
  3. Build layers in this order, verifying each:
       a. GROUND WASH - soft low-alpha cold disc, footprint-sized, thickened
          vertically by vfx_ground_span. NOT AN EXPANDING RING (row 8).
       b. FROST-VEIN BACKDROP - one additive quad, low intensity, brightness
          modulated by the pulse.
       c. CANOPY - 2-3 large camera-facing quads at approx 2.5-3.5u, slow
          lateral drift and scale breathing, brightness pulsing on the beat.
       d. FLURRY - GPUParticles3D, soft-dot billboards, additive, distributed
          across the footprint AT VARIED Z SO UNITS INTERLEAVE (row 4). Fixed
          seed. Density from IceStormProfile, tuned against S2.
       e. GUST STRUCTURE - a lateral velocity field plus a travelling density
          mask over the flurry, NOT a second emitter (row 6).
       f. HERO SHARDS - flat quads with shard_mask variants, alpha-blended,
          near-opaque, in-plane roll and descent as PURE FUNCTIONS OF t AND A
          PER-SHARD SEED so they scrub exactly. Sparse and countable, <= 8 on
          screen.
  4. PULSE ACCENTS: at each pulse boundary, a short brightness ramp on the
     canopy plus a density surge in the flurry. COSMETIC ONLY - emits no
     signal, event, or state change.
  5. STAGGERED SETTLE: shards stop spawning first, flurry thins, ground wash
     fades, canopy dissipates last. NOTHING DISAPPEARS ON THE SAME FRAME
     (row 10).
  6. Implement skip_to_settle() and self-free at completion WITHOUT A
     SceneTree TIMER.
  7. Support the live-storm intensity scaling from Q11.
  8. Verify against section 10's budgets using the harness HUD, at NATIVE,
     640x480, 480x360, AND 320x240, retro and CRT on and off.
  9. Capture the section 6 checkpoint frames (t = 0.08, 0.25, 0.50, 0.75,
     0.95) in reference-speed mode for SG-VALIDATE, ONE CAPTURE PER PROCESS
     per SG-3 step 6.
 10. Review the backlogs.

FILES: src/presentation/effects/IceStormEffect.gd (+ .uid),
       assets/shaders/ice_storm_*.gdshader as needed (+ .uid),
       src/presentation/effects/SpellVfxCatalog.gd (registration)

RESOLUTION: Not started.


================================================================================
SG-6 - AUTHOR THE VFX PROFILE FIELD THROUGH THE CATALOG BOUNDARY
================================================================================

MODEL:        Sonnet 5 / GPT Terra
DEPENDS ON:   SG-5

RISK: Medium. A malformed data/spells.json edit REJECTS THE WHOLE CATALOG
RELOAD, which would break every spell at once, not just the carrier.

MITIGATION / ROLLBACK BOUNDARY: a narrow parse/load probe is justified here -
the file is a single point of failure for all spell data. Run it and record it
as a smoke check, not acceptance. Rollback is reverting one field on one entry
plus one normalisation line.

ADDS TO VALIDATION COVERAGE: Ice Plow resolves to the storm profile; every
other spell keeps the generic aura; the catalog loads.

END STATE: VFX_PROFILE is a normalised, documented, optional presentation
field, and Ice Plow carries `ice_area_storm`.

WORK
  1. Add "VFX_PROFILE": "" to SpellReferences.STRING_DEFAULTS (lines 24-32).
     Normalisation at lines 73-74 then applies with no further change.
  2. Carry it through src/entities/Spell.gd alongside area_shape (line 62), if
     the runtime object needs it. IF ONLY PRESENTATION READS IT, PREFER
     READING THE REFERENCE DIRECTLY AND LEAVE Spell UNTOUCHED - do not widen
     the runtime object without need.
  3. Set "VFX_PROFILE": "ice_area_storm" on ICE PLOW in data/spells.json.
     CHANGE NOTHING ELSE ON THAT ENTRY - not NAME, DAMAGE, RADIUS, RANGE,
     ELEMENT, or CAN_TARGET_EMPTY.
  4. Document the field in docs/SPELL_CATALOG_SCHEMA.md under normalized
     strings, stating plainly that it is PRESENTATION METADATA WITH NO
     GAMEPLAY EFFECT and that an unknown or empty value falls back to the
     generic aura.
  5. Run a narrow catalog load probe confirming the reload succeeds and Ice
     Plow resolves. Record as a smoke check.
  6. Review the backlogs.

FILES: src/factories/SpellReferences.gd,
       data/spells.json,
       docs/SPELL_CATALOG_SCHEMA.md,
       possibly src/entities/Spell.gd

BLOCKING USER DECISION - CARRIER CONFIRMATION.
  This plan selects ICE PLOW (ice, RADIUS 2, RANGE 3, ground-targetable) as
  the temporary carrier and changes none of its gameplay. IF THE USER WANTS A
  DIFFERENTLY-NAMED OR NEWLY-ADDED SPELL INSTEAD, THAT IS A CONTENT DECISION
  REQUIRING EXPLICIT AUTHORISATION - STOP AND ASK RATHER THAN ADDING ONE.

RESOLUTION: Not started.


================================================================================
SG-7 - ROUTE ONE AREA EFFECT PER CAST THROUGH THE VISUAL QUEUE
================================================================================

MODEL:        Opus 5 / GPT Sol
DEPENDS ON:   SG-5, SG-6

RISK: High. This changes event handling, adds a VisualAction.Kind, and alters
aura placement for EVERY spell in the game. VisualAction.clone() enumerates
fields explicitly, so a missed field is silently dropped and only shows as a
wrong-looking effect much later.

MITIGATION / ROLLBACK BOUNDARY: the change is confined to three presentation
files and is revertible as a unit. Extend clone() IN THE SAME EDIT as each new
field, never afterwards.

ADDS TO VALIDATION COVERAGE: exactly one storm per cast at zero, one, and
several targets; per-target damage numbers intact; pause, skip, speed,
dispose, and teardown all reach the storm; no stranded nodes.

END STATE: one area-centred effect per cast, no duplicate caster auras, every
queue invariant preserved.

WORK
  1. Add CAST_AREA to VisualAction.Kind (line 8) and the fields from Q3.
     EXTEND clone() (lines 39-59) FOR EVERY ONE.
  2. Rewrite GodotVisualAdapter._on_spell_cast_started() (lines 688-704):
     remove the `targetsHit > 0` early return (lines 694-695); always enqueue
     one CAST_AREA; snapshot profile, radius, seed, ground span, and
     origin = _coord_to_surface_pos3d(centerPos). Preserve the existing
     zero-target log_text.
  3. DELETE THE AURA SPAWN FROM _start_bump_animation() (lines 907-910).
     Per-target BUMP keeps its lunge and damage number.
     STATE PLAINLY IN THE RESOLUTION THAT THIS MOVES EVERY SPELL'S AURA FROM
     THE CASTER TO THE TARGET CENTRE, so a later session does not "restore"
     it.
  4. Add _start_cast_area_animation() and its _start_queued_animation() branch
     (lines 264-281). Spawn through SpellVfxCatalog; hold via _activateScaled()
     per Q10.
  5. Add _live_effects tracking and forward pause, speed scale, skip, and
     dispose() (line 1115) to live effects (Q9). Enforce the two-storm cap and
     intensity scaling (Q11).
  6. Extend _finalize_animation() (lines 284-298) for CAST_AREA - it must NOT
     touch monster visuals, since there is no monster to snap.
  7. Confirm ConsoleVisualAdapter still satisfies IBattleVisualAdapter.
     NO SIGNAL SIGNATURE CHANGES, SO NO HEADLESS FILE IS TOUCHED.
  8. Review the backlogs.

FILES: src/presentation/VisualAction.gd,
       src/presentation/GodotVisualAdapter.gd,
       src/presentation/effects/SpellVfxCatalog.gd

RESOLUTION: Not started.


--------------------------------------------------------------------------------
12. SG-VALIDATE - INTEGRATED GAMEPLAY, PERFORMANCE, AND VISUAL ACCEPTANCE
--------------------------------------------------------------------------------

MODEL:        Opus 5 / GPT Sol
DEPENDS ON:   SG-1, SG-2, SG-3, SG-4, SG-5, SG-6, SG-7

RISK: Medium. The result is primarily visual; no parse or load check can
establish similarity, readability, or pacing.

MITIGATION / ROLLBACK BOUNDARY: defects are fixed in this session; only the
relevant consolidated checks are rerun. Prior items are not reopened.

ADDS TO VALIDATION COVERAGE: nothing new - consolidates and runs the whole
cycle's coverage.

END STATE: the effect is accepted in a real battle, all items are marked done,
and this plan is cleared in the same session.

PRECONDITIONS: every implementation item committed; working tree clean.

WORK
  1. HARNESS PASS. Launch scenes/debug/VFXDebugScene.tscn bounded and waited
     per docs/DEVELOPMENT.md "Windows execution safeguards" (repository root,
     --path ., waited process, known output marker). Exercise
     "Choose effect -> Play -> Pause/Resume" for both the generic aura and the
     storm. Verify Play restarts cleanly from paused; Resume continues without
     seed change or drift; the status readout is accurate; and
     `flurry: exact|approx` is honest.

  2. REFERENCE-SPEED COMPARISON. In reference-speed mode, capture the
     section 6 checkpoints (t = 0.08, 0.25, 0.50, 0.75, 0.95), ONE CAPTURE PER
     PROCESS (docs/LEARNINGS.md:230). Compare against the reference material
     and confirm the canopy, flurry, gust motion, hero shards, veins, ground
     wash, and pulse accents are each separately legible.

  3. RESOLUTION AND CRT MATRIX. Verify at NATIVE, 640x480, 480x360, AND
     320x240, retro on and off, CRT on and off, and ui_through_crt both ways.
     Confirm the effect retains a 2.5D sprite character and does not read as a
     modern volumetric blizzard.

  4. BATTLE INTEGRATION. Launch Battle25D bounded and waited. Cast the carrier
     at: AN EMPTY AREA (ZERO TARGETS), A SINGLE TARGET, AND SEVERAL TARGETS.
     Confirm EXACTLY ONE STORM PER CAST in all three, centred on the selected
     area and covering the intended footprint, with per-target damage numbers
     intact and readable.

  5. REGRESSION ON OTHER SPELLS. Cast several non-carrier spells of different
     elements. Confirm each shows the generic aura ONCE, AT THE TARGET CENTRE,
     correctly tinted - and confirm this relocation is acceptable to the user,
     since it is a deliberate change to every spell.

  6. PACING AND CONTROL. Test normal speed, slow speed, pause mid-storm, skip,
     and consecutive casts in one AI turn. Confirm the battle-speed duration
     and cadence are acceptable and that overlapping storms do not white out.

  7. CLEANUP AND PERFORMANCE. Cast 20+ TIMES; confirm node and particle counts
     return to baseline. Verify section 10's budgets. Test battle teardown and
     return-to-setup (adapter dispose()) mid-storm and confirm nothing is
     stranded.

  8. READABILITY. Confirm unit silhouettes, terrain elevation, targeting
     information, and damage numbers remain readable at every resolution.

  9. BLOCKING USER VISUAL APPROVAL. Present representative reference-speed,
     harness, and live-battle screenshots. EXPLICITLY OBTAIN APPROVAL OF:
       (a) the overall reference match,
       (b) the battle-speed duration and cadence,
       (c) the relocation of every spell's aura to the target centre.
     This is BLOCKING; the plan is not complete without it.

 10. Confirm NO GAMEPLAY STATE OR BALANCE CHANGE and NO COPYRIGHTED RAGNAROK
     ASSET anywhere in the diff.

 11. Run `git diff --check`; confirm only task-owned files are staged.

 12. Update owning documentation and the backlogs (BACKLOG_CRITICAL.md,
     BACKLOG_LONGTERM.md, docs/BACKLOG.md) for any verified durable finding.
     Record durable discoveries in docs/LEARNINGS.md with a reuse trigger.

 13. GREP THE REPOSITORY FOR "SG-" AND REWRITE ANY HIT OUTSIDE
     implementation_plan.md AS DURABLE PROSE (AGENTS.md "Nothing persistent
     may cite a plan item").

 14. Mark SG-1 ... SG-7 done, CLEAR THIS FILE, and commit validation results
     and fixes together. Note that prior contents are recoverable via
     `git show <ref>:implementation_plan.md`.

FILES: implementation_plan.md, BACKLOG_CRITICAL.md, BACKLOG_LONGTERM.md,
       docs/BACKLOG.md, docs/LEARNINGS.md, plus only files requiring a
       validation fix.

RESOLUTION: Not started.


--------------------------------------------------------------------------------
13. RESOLUTION PLACEHOLDERS
--------------------------------------------------------------------------------

  SG-1         - Implemented; pending end-of-plan validation
  SG-2         - Implemented; pending end-of-plan validation
  SG-3         - Not started
  SG-4         - Not started
  SG-5         - Not started
  SG-6         - Not started
  SG-7         - Not started
  SG-VALIDATE  - Not started


--------------------------------------------------------------------------------
CLOSING STATEMENT
--------------------------------------------------------------------------------

SELECTED TECHNICAL DIRECTION
  A hybrid, deterministic-clock effect: one effect-local normalised timeline t
  drives every layer, with billboard canopy and vein quads, a GPU-particle
  flurry shaped by a lateral gust field, and flat alpha-blended hero shards
  whose motion is a pure function of t. The reference's signature is the BLEND
  CONTRAST - soft additive flakes beside hard-edged opaque shard silhouettes -
  and its ground response is a soft cold wash, NOT an expanding ring.
  Selection is data-driven via an authored VFX_PROFILE field; all cast VFX
  moves to spell_cast_started, which fixes the duplicate-caster-aura bug by
  REMOVING state rather than synchronising it. GLOBAL GLOW IS DELIBERATELY
  REJECTED, on reference grounds and whole-game risk.

HIGHEST-RISK ASSUMPTION
  The visual pulse cadence is still estimated rather than measured from a
  classic/pre-Renewal client. The user explicitly accepted secondary-source
  calibration on 2026-08-03, so IceStormProfile.gd records the estimate and its
  provenance instead of presenting it as measured fact. Final visual validation
  may tune it, but must preserve the distinction.

BLOCKING USER DECISIONS
  1. CARRIER SPELL (SG-6): this plan uses ICE PLOW unchanged. Adding or
     renaming a spell would require explicit authorisation.
  2. BATTLE-SPEED DURATION (SG-VALIDATE): approx 2.2 s with a preserved 0.44 s
     pulse interval is an ESTIMATE requiring approval.
  3. AURA RELOCATION (SG-VALIDATE): moving EVERY spell's generic aura from the
     caster to the target centre is a deliberate, user-visible change beyond
     the carrier spell, and needs sign-off.

INSTALLATION STATUS: ACTIVE; SG-1 AND SG-2 IMPLEMENTED
  The user explicitly authorized replacing the unfinished battle-window cycle.
  Its open preview and integrated visual-acceptance outcomes are preserved in
  BACKLOG_CRITICAL.md. The user later authorized secondary-source calibration
  and explicitly authorized the current GPT Sol tier for every remaining item,
  overriding the plan's lower cost-routing assignments. Execution may continue
  from SG-3 in the next session.

--------------------------------------------------------------------------------
SOURCES
--------------------------------------------------------------------------------

  https://irowiki.org/classic/Storm_Gust
  https://ragnarok.fandom.com/wiki/Storm_Gust
  https://wiki.playragnarokzero.com/wiki/Storm_Gust
  https://www.divine-pride.net/database/skill/89
  https://ratemyserver.net/index.php?page=skill_db&skid=89
  https://github.com/rdw-archive/RagnarokFileFormats
  https://ragnarokresearchlab.github.io/file-formats/str/
  https://github.com/skardach/ro-str-viewer
  https://www.robrowser.com/blog/welcome-effects

  Candidate footage (INSPECTED; NONE QUALIFIES AS CLASSIC/PRE-RENEWAL STOCK):
  https://www.youtube.com/watch?v=F9oZbhb_k5c
  https://www.youtube.com/watch?v=ryg8wuHkzPo
  https://www.youtube.com/watch?v=jHKJrPdqZr0
  https://www.youtube.com/watch?v=r337MHlbw3w

================================================================================
END OF PLAN
================================================================================
