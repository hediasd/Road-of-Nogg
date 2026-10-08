# Module Map

Status: current. Last reconciled with source: 2026-08-02.

This is the **routing guide**: which directory owns what, what it may depend
on, and where to make a given change. It deliberately stays shallow.
[`ARCHITECTURE.md`](./ARCHITECTURE.md) remains the detailed source of truth for
runtime ownership, turn execution, and the event contract — when the two
disagree, ARCHITECTURE wins and this file is the one to correct.

## Directories

| Directory | Responsibility | Public entry points | Dependency boundary | Owning doc |
|---|---|---|---|---|
| `data/` | Authored catalogs, maps, scenarios and world-map documents | JSON files | Inert data; no code dependencies | [`REFERENCE_CATALOGS.md`](./REFERENCE_CATALOGS.md) |
| `simulation/` | Canonical battle state/runtime, resolvers, board storage and spatial algorithms | `BattleSimulator`, `BattleState`, `HexGrid`, resolvers | Headless; never imports presentation or scene-tree code | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `ai/` | CPU decision-making and the frozen legacy policy baseline | brains, deliberation, policy catalog | Headless; consumes simulation/content, never presentation | [`AI_ARCHITECTURE.md`](./AI_ARCHITECTURE.md) |
| `content/` | Passive runtime content objects plus JSON-to-object factories | entities, `*References`, setup presets | Headless; owns catalog conversion | [`REFERENCE_CATALOGS.md`](./REFERENCE_CATALOGS.md) |
| `road/` | The road between battles: state, Belief/level/ascension rules, battle composition and tally, saves | `RoadState`, `RoadRules`, `RoadBattle`, `RoadSave` | Headless; consumes content and simulation contracts (scenario factory, battle events and state), never presentation | [`ARCHITECTURE.md`](./ARCHITECTURE.md), "The road" |
| `battle/` | Scene orchestration, battle camera/meshes, adapters, records and playback | `HexBattleController`, adapters, render controllers | Reads/submits through simulation contracts; never mutates battle state directly | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `ui/` | HUD, menus, windows, fonts and shared theme widgets | `HexBattleHud`, `NoggTheme`, command/status controls | Presentation only | [`UI_DESIGN.md`](./UI_DESIGN.md) |
| `effects/` | VFX playback, spell effects and the cube-placeholder collection | `VfxPlayback`, catalogs, profiles | Presentation only; existing shared resources remain compatibility surfaces | [`VFX_DESIGN.md`](./VFX_DESIGN.md) |
| `worldmap/` | World-map rendering, framing, sky, clouds and props | world-map presentation classes | Presentation only | [`WORLDMAP_DESIGN.md`](./WORLDMAP_DESIGN.md) |
| `map_editor/` | World-map editing, document, workspace and export code | editor controller, document/export services | May consume world-map and headless map contracts; runtime never imports it | [`WORLDMAP_EDITOR.md`](./WORLDMAP_EDITOR.md) |
| `scenes/` | Maintained Godot entry/debug scenes | `HexBattle.tscn`, world-map/editor and VFX scenes | Instantiates presentation/orchestration code | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `assets/` | Retained fonts, models, textures, shaders, UI and world-map art | Resource files | Art collections are preserved; bundle exceptions beat unsafe reserialization | [`UI_DESIGN.md`](./UI_DESIGN.md), [`VFX_DESIGN.md`](./VFX_DESIGN.md) |
| `tools/` | Manual runners, generators, captures and analysis utilities | battle/tournament and authoring tools | May consume runtime; runtime never imports tools | [`DEVELOPMENT.md`](./DEVELOPMENT.md) |
| `checks/` | Probe sweep, process runner, manifests, fixtures and probes | `run_probe_sweep.ps1`, `run_probe.ps1` | Verification only; never imported by runtime | [`DEVELOPMENT.md`](./DEVELOPMENT.md) |
| `references/` | Game research and the frozen square-battle package | reference documents/package | Never imported by active runtime | [`README.md`](./README.md) |

Physical flattening does not merge logical layers: `simulation/`, `ai/`, `content/`, and `road/` remain headless; `battle/`, `ui/`, `effects/`, `worldmap/`, and `map_editor/` remain presentation or authoring. `data/` is loaded only through `content/` factories.

## Dependency direction

`	ext
data/ --> content/ --> simulation/ <-- ai/
                         |
             BattleEvents / adapter contracts
                         |
                         v
              battle/ + ui/ + effects/
                         |
                         v
                       scenes/

worldmap/ <-- map_editor/

content/ + simulation/ <-- road/ <-- worldmap/ (road scene) --> scenes/HexBattle.tscn (embedded)
`

Presentation submits commands and observes authoritative state. No dependency points from the headless roots into battle, UI, effects, world-map, editor, or scene code.

## Where to make a change

| Change | Go to |
|---|---|
| Catalog content or JSON conversion | `data/`, then `content/` when the schema/conversion changes |
| Combat, movement, turn order, replay or serialization | `simulation/` |
| CPU behavior | `ai/` |
| Battle lifecycle, camera, meshes, adapters or playback | `battle/` |
| HUD, menus, windows, fonts or theme | `ui/` |
| Visual effects and animation pacing | `effects/` |
| Road progression: Belief, levels on the road, ascension, road battles, saves | `road/` (rules and state), `data/roads.json` (content) |
| The road scene and its markers | `worldmap/WorldMapRoad*.gd`, `ui/RoadPanel.gd` |
| World-map rendering | `worldmap/` |
| World-map authoring, documents and export | `map_editor/` |
| Headless probes and fixtures | `checks/` |
| Manual runners, generators and analysis | `tools/` |
