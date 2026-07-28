# Long-term backlog

## Weather system

- Design a competitive catalog of 5-10 weather states. Eligible monsters
  establish them according to their element and/or race; each weather needs a
  clear duration, owner, replacement rule, and visible battle-state
  representation.
- Give weather specialists meaningful control over timing: weather spells can
  establish, clear, overwrite, or make a limited compatible transformation of
  the active weather. Use shared tags and rules rather than isolated buffs.
- Keep individual effects tactical and globally legible: movement, visibility,
  healing, status duration, terrain interaction, and elemental interaction are
  preferable to universal raw-damage multipliers. Serialize active weather and
  validate its source through the reference catalog.
## Tooling

- Re-evaluate the Windows GUT access violation in an isolated run. Focused
  headless SceneTree checks remain the routine verification path.
- `tests/scene/test_capsule_features.gd` (ported 2026-07-27 from
  `run_capsule_features_check.gd`, same underlying issue) reports "Expected
  success marker not found" through `run_godot_check.ps1` on this Windows
  host, even against a clean `HEAD` checkout with no pending changes (verified
  via `git stash` bisection before the port). The Godot process itself exits 0
  and the test's own assertions never fail — confirmed by running it alone via
  `tests/run_tests.gd -- scene` and finding zero `TEST_FAILED` lines in the
  captured log, only the RID-leak noise below. **A real fix attempt failed**:
  adding an explicit multi-frame + `OS.delay_msec(1500)` pause before `quit()`
  in `tests/run_tests.gd` did not surface the marker either, which rules out a
  simple timing race and points to Godot's own internal print/log buffering on
  this Windows build, not something reachable from GDScript.
  **Consolidation side effect**: this test now shares one Godot process with
  every other `scene`-tier test (`tests/run_tests.gd -- scene`, and therefore
  `-- all`). When it triggers, the entire process's buffered stdout is lost —
  not just this test's own output — so `test_setup_ui_flow.gd`,
  `test_cursor_ownership.gd`, and `test_status_icons.gd` also lose their PASS
  lines and the run's `TESTS_OK` marker in the same batch, even though all
  three independently verified passing when capsule was excluded. The check
  also leaks three RID allocations (`DummyMesh`/`DummyMaterial`/`DummyShader`)
  not covered by `run_godot_check.ps1`'s benign-error allowlist.
  **Practical consequence**: `scripts/hooks/pre-push` (which runs tier `all`)
  will currently report failure on every run regardless of real test outcomes,
  once this test's shutdown path executes. Do not trust a red `pre-push` alone;
  corroborate via `tests/run_tests.gd -- unit` and `-- integration` (both
  reliable) before concluding there is a real regression. Needs isolated
  investigation — likely in Godot's own logging internals — before this test
  can gate anything automatically. Options once someone can reproduce with
  `--verbose`: report upstream to Godot, or move this test to its own isolated
  `run_godot_check.ps1` invocation outside the shared `scene` process so it
  cannot take other tests' output down with it.
