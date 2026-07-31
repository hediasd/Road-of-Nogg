# Development and Verification

Status: current for Godot 4.4 on Windows. Last verified: 2026-07-31.

This is the executable workflow reference. Start with a clean understanding of
the working tree, but preserve unrelated user changes.

## No automated test suite right now

The previous test suite (unit/integration/scene tiers), the GUT addon, the
`scripts/run_godot_check.ps1` / `scripts/check_docs.ps1` runners, and the git
hooks that invoked them were all removed to be rebuilt fresh. There is
currently no automated way to verify a change.

`scripts/demo_battle.gd` remains available as a manual, non-automated seeded
4v4 console battle. Run it from the repository root through a waited process
and require its explicit `Battle complete!` marker; a zero exit code alone is
not sufficient evidence on this Windows host.

## Validation timing

For a multi-item implementation plan, implementation sessions stop at a focused
diff review, `git diff --check`, an item commit, and a Resolution marked
**implemented; pending end-of-plan validation**. Do not relaunch the game and
repeat acceptance flows after every item.

The plan's final validation item launches the game once all implementation
items are committed. It exercises the combined affected paths, deduplicates
overlapping checks, fixes any integration defect it finds, and changes covered
items from pending validation to done. A narrow compile/load smoke probe is
allowed earlier only when a later item cannot safely proceed against code that
might not parse; it is not acceptance evidence.

A single-item plan performs its manual validation at the end of that item.

## Windows execution safeguards

These apply whenever you launch the bundled Godot binary or generate edits
through nested Windows tooling:

- Do not treat `$LASTEXITCODE` from a direct interactive launch of the bundled
  Windows Godot binary as completion evidence. The host can return before the
  detached process finishes. Wait for the exact process and require a known
  output/log marker.
- Run from the repository root and pass `--path .`; PowerShell argument handling
  can split absolute paths containing spaces.
- Godot writes logs and caches under AppData. If the sandbox reports AppData
  access failures or an access-violation exit, rerun the same bounded command
  with the required permission before diagnosing project code.
- Treat `--editor --quit` as an import diagnostic, not a runtime smoke test. It
  can hit progress-dialog or message-queue errors during import.
- If the patch helper reports an infrastructure error such as
  `windows sandbox failed: helper_unknown_error`, inspect the target immediately
  and stop retrying the same path. After confirming the file is unchanged, use
  one exact, asserted workspace-scoped replacement and review its focused diff.
- Do not generate a `git diff --no-index` patch against a temp file outside the
  repository on Windows: the diff can contain an absolute drive path that
  `git apply` rejects. Keep any fallback temp next to the target or avoid that
  route.
- Avoid inline source generation across JavaScript, PowerShell, and Python when
  the payload contains escape sequences. Outer layers can consume `\"`,
  `\n`, or `\t` before the inner language sees them. Prefer a short temporary
  helper file, single-quoted diagnostics, and character APIs such as
  `[char]10` / `chr(10)`.
- Force generated text to LF. PowerShell and Python on Windows can translate
  line endings to CRLF, which this repository's `git diff --check` reports as
  trailing whitespace. In Python, open with `newline=chr(10)`; in PowerShell,
  normalize before `WriteAllText`.
- Keep native process windows hidden unless the user needs to interact with
  them. Keep reusable logs in the temp directory rather than tracked source.
- Workspace edit permission does not imply permission for external executables
  or Git index writes; honor the permission boundary shown by the tool.

## Failure-triage order

1. Classify the failure as project code, sandbox/permission, process waiting,
   patch infrastructure, or multi-layer quoting before changing source.
2. Inspect the intended target and `git status`; do not assume a failed helper
   either changed nothing or completed successfully.
3. Change execution strategy once. Repeatedly trying equivalent patch/temp/
   launch variants creates more uncertainty than evidence.
4. After the environment is trustworthy, capture the originating parser/runtime
   error from Godot's output or AppData log and fix that exact defect.
5. Run the relevant validation only at the plan's final validation boundary.

## Implementation-item checkpoint

1. Inspect `git status` and the focused diff.
2. Run `git diff --check`.
3. Update the plan Resolution to implemented, pending end-of-plan validation.
4. Stage only task-owned files and commit the item.

## Final validation checklist

1. Start from all implementation items committed and a clean working tree.
2. Launch the game through a bounded, waited process.
3. Exercise the union of affected behavior once, using integrated flows where
   possible.
4. Fix and rerun only the failed/relevant combined checks.
5. Run `git diff --check`, update plan Resolutions to done, and commit the
   validation evidence/fixes.
