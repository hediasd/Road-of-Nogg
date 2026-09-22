## Runs a declared experiment on independent process workers, then merges.
##
##     powershell -NoProfile -ExecutionPolicy Bypass -File scripts/battle/run_policy_tournament.ps1 `
##         -Manifest scripts/battle/fixtures/ai/tournament_smoke.json -Output battle_output/tournaments/smoke
##
## Workers are separate processes on purpose. A match that hangs is killed
## without touching the others, a match that crashes takes its own process down
## and nothing else, and the shards already written stay on disk either way --
## which is what makes -Resume able to pick up from a half-finished run.
##
## The watchdog kills a worker that outlives the manifest's timeout. **That is
## an infrastructure failure, not a game result.** It is recorded as one, and a
## killed worker's matches are retried on resume rather than counted as losses.

[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][string]$Manifest,
	[Parameter(Mandatory = $true)][string]$Output,
	[int]$Workers = 0,
	[int]$TimeoutSeconds = 0,
	[switch]$Resume,
	[string]$GodotPath = './Godot_v4.4-stable_win64.exe'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Get-Location).Path

function Fail-Tournament([string]$Reason) {
	[Console]::Error.WriteLine("POLICY_TOURNAMENT_FAILED: $Reason")
	exit 1
}

if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) {
	Fail-Tournament "manifest does not exist: $Manifest"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
	Fail-Tournament "godot binary does not exist: $GodotPath"
}

$manifestData = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Workers -le 0) {
	$Workers = [int]$manifestData.max_workers
	if ($Workers -le 0) { $Workers = 2 }
}
if ($TimeoutSeconds -le 0) {
	$TimeoutSeconds = [int]$manifestData.worker_timeout_seconds
	if ($TimeoutSeconds -le 0) { $TimeoutSeconds = 300 }
}

$outputFull = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $Output))
New-Item -ItemType Directory -Force -Path $outputFull | Out-Null
$logDirectory = Join-Path $outputFull 'logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null

$manifestResource = 'res://' + ($Manifest -replace '\\', '/')
$outputResource = 'res://' + ($Output -replace '\\', '/')

$processes = @()
for ($shard = 0; $shard -lt $Workers; $shard++) {
	$arguments = @(
		'--headless', '--path', '.', '--script',
		'res://scripts/battle/run_policy_tournament.gd', '--',
		"--manifest=$manifestResource", "--output=$outputResource",
		"--shard=$shard", "--shards=$Workers"
	)
	if ($Resume) { $arguments += '--resume' }
	$stdout = Join-Path $logDirectory ("worker_{0:d2}.out.log" -f $shard)
	$stderr = Join-Path $logDirectory ("worker_{0:d2}.err.log" -f $shard)
	$process = Start-Process -FilePath $GodotPath -ArgumentList $arguments -PassThru `
		-NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
	$processes += [pscustomobject]@{ Shard = $shard; Process = $process; Stdout = $stdout }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$killed = @()
$failed = @()
foreach ($entry in $processes) {
	$remaining = [int]([math]::Max(1, ($deadline - (Get-Date)).TotalSeconds))
	if (-not $entry.Process.WaitForExit($remaining * 1000)) {
		## A worker that outran the budget is stopped. Its finished matches are
		## already on disk; the unfinished one is simply absent, and a resume
		## will play it again rather than anyone inventing a result for it.
		try { $entry.Process.Kill($true) } catch {}
		$killed += $entry.Shard
		Write-Output ("worker {0} exceeded {1}s and was stopped" -f $entry.Shard, $TimeoutSeconds)
		continue
	}
	## Judged by its marker, not its exit code. A Godot process can report a
	## non-zero status while shutting down cleanly, and Start-Process does not
	## reliably surface the code at all; the marker is the thing the worker only
	## prints once it has written every row it owed.
	if (-not (Select-String -LiteralPath $entry.Stdout -Pattern 'POLICY_TOURNAMENT_SHARD_OK' -Quiet)) {
		Write-Output ("worker {0} did not finish its shard; see {1}" -f $entry.Shard, $entry.Stdout)
		$failed += $entry.Shard
	}
}

$mergeArguments = @(
	'--headless', '--path', '.', '--script',
	'res://scripts/battle/run_policy_tournament.gd', '--',
	"--manifest=$manifestResource", "--output=$outputResource", '--merge'
)
$mergeOut = Join-Path $logDirectory 'merge.out.log'
$mergeErr = Join-Path $logDirectory 'merge.err.log'
$merge = Start-Process -FilePath $GodotPath -ArgumentList $mergeArguments -PassThru `
	-NoNewWindow -RedirectStandardOutput $mergeOut -RedirectStandardError $mergeErr
$merge.WaitForExit()
Get-Content -LiteralPath $mergeOut | Where-Object { $_ -match 'POLICY_TOURNAMENT' } | Write-Output
if (-not (Select-String -LiteralPath $mergeOut -Pattern 'POLICY_TOURNAMENT_MERGE_OK' -Quiet)) {
	if (Test-Path -LiteralPath $mergeErr) { Get-Content -LiteralPath $mergeErr | Write-Output }
	Fail-Tournament "merge did not complete; see $mergeErr"
}

$summaryPath = Join-Path $outputFull 'summary.json'
if (-not (Test-Path -LiteralPath $summaryPath)) {
	Fail-Tournament "merge produced no summary at $summaryPath"
}
$summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$missing = @($summary.missing_match_ids).Count
Write-Output ("POLICY_TOURNAMENT_OK workers={0} merged={1}/{2} missing={3} killed={4} unfinished={5}" -f `
	$Workers, $summary.merged_rows, $summary.expected_matches, $missing, $killed.Count, $failed.Count)
if ($missing -gt 0 -or $killed.Count -gt 0 -or $failed.Count -gt 0) {
	## Incomplete is a reportable state, not a silent one: the run finished, the
	## result set did not, and re-running with -Resume is what closes the gap.
	Write-Output "run is incomplete; re-run with -Resume to play the remaining matches"
	exit 2
}
exit 0
