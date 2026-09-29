## Runs a declared experiment on independent process workers, then merges.
##
##     powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_policy_tournament.ps1 `
##         -Manifest checks/fixtures/tournament_smoke.json -Output battle_output/tournaments/smoke
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

## Start-Process on this host can fail while copying PATH/path into its
## environment dictionary. ProcessStartInfo also gives us a reliable exit code
## and a handle to the exact worker that a watchdog may need to stop.
function ConvertTo-WindowsArgument([string]$Value) {
	if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
	$quoted = [System.Text.StringBuilder]::new()
	$null = $quoted.Append('"')
	$backslashes = 0
	foreach ($character in $Value.ToCharArray()) {
		if ($character -eq '\') { $backslashes += 1; continue }
		if ($character -eq '"') {
			$null = $quoted.Append('\', ($backslashes * 2) + 1)
			$null = $quoted.Append('"')
			$backslashes = 0
			continue
		}
		$null = $quoted.Append('\', $backslashes)
		$null = $quoted.Append($character)
		$backslashes = 0
	}
	$null = $quoted.Append('\', $backslashes * 2)
	$null = $quoted.Append('"')
	return $quoted.ToString()
}

function Start-GodotJob([string[]]$JobArguments, [string]$StdoutPath, [string]$StderrPath) {
	$info = [System.Diagnostics.ProcessStartInfo]::new()
	$info.FileName = if ([System.IO.Path]::IsPathRooted($GodotPath)) {
		[System.IO.Path]::GetFullPath($GodotPath)
	} else {
		[System.IO.Path]::GetFullPath((Join-Path $projectRoot $GodotPath))
	}
	$info.WorkingDirectory = $projectRoot
	$info.UseShellExecute = $false
	$info.CreateNoWindow = $true
	$info.RedirectStandardOutput = $true
	$info.RedirectStandardError = $true
	$info.Arguments = ($JobArguments | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $info
	if (-not $process.Start()) { Fail-Tournament "Godot failed to start: $($info.FileName)" }
	return [pscustomobject]@{
		Process = $process
		StdoutTask = $process.StandardOutput.ReadToEndAsync()
		StderrTask = $process.StandardError.ReadToEndAsync()
		StdoutPath = $StdoutPath
		StderrPath = $StderrPath
	}
}

function Finish-GodotJob($Job, [int]$RemainingSeconds) {
	$timedOut = -not $Job.Process.WaitForExit([math]::Max(1, $RemainingSeconds) * 1000)
	if ($timedOut -and -not $Job.Process.HasExited) { $Job.Process.Kill() }
	$Job.Process.WaitForExit()
	$encoding = [System.Text.UTF8Encoding]::new($false)
	$stdoutText = $Job.StdoutTask.GetAwaiter().GetResult()
	$stderrText = $Job.StderrTask.GetAwaiter().GetResult()
	[System.IO.File]::WriteAllText($Job.StdoutPath, $stdoutText, $encoding)
	[System.IO.File]::WriteAllText($Job.StderrPath, $stderrText, $encoding)
	return [pscustomobject]@{
		TimedOut = $timedOut
		ExitCode = $Job.Process.ExitCode
		Stdout = $stdoutText
		Stderr = $stderrText
	}
}

$processes = @()
for ($shard = 0; $shard -lt $Workers; $shard++) {
	$arguments = @(
		'--headless', '--path', '.', '--script',
		'res://tools/run_policy_tournament.gd', '--',
		"--manifest=$manifestResource", "--output=$outputResource",
		"--shard=$shard", "--shards=$Workers"
	)
	if ($Resume) { $arguments += '--resume' }
	$stdout = Join-Path $logDirectory ("worker_{0:d2}.out.log" -f $shard)
	$stderr = Join-Path $logDirectory ("worker_{0:d2}.err.log" -f $shard)
	$job = Start-GodotJob $arguments $stdout $stderr
	$processes += [pscustomobject]@{ Shard = $shard; Job = $job }
}

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$killed = @()
$failed = @()
foreach ($entry in $processes) {
	$remaining = [int]([math]::Max(1, ($deadline - (Get-Date)).TotalSeconds))
	$result = Finish-GodotJob $entry.Job $remaining
	if ($result.TimedOut) {
		## A worker that outran the budget is stopped. Its finished matches are
		## already on disk; the unfinished one is simply absent, and a resume
		## will play it again rather than anyone inventing a result for it.
		$killed += $entry.Shard
		Write-Output ("worker {0} exceeded {1}s and was stopped" -f $entry.Shard, $TimeoutSeconds)
		continue
	}
	if ($result.ExitCode -ne 0 -or $result.Stdout -notmatch '(?m)^POLICY_TOURNAMENT_SHARD_OK ') {
		Write-Output ("worker {0} did not finish its shard (exit {1}); see {2}" -f `
			$entry.Shard, $result.ExitCode, $entry.Job.StdoutPath)
		$failed += $entry.Shard
	}
}

$mergeArguments = @(
	'--headless', '--path', '.', '--script',
	'res://tools/run_policy_tournament.gd', '--',
	"--manifest=$manifestResource", "--output=$outputResource", '--merge'
)
$mergeOut = Join-Path $logDirectory 'merge.out.log'
$mergeErr = Join-Path $logDirectory 'merge.err.log'
$mergeJob = Start-GodotJob $mergeArguments $mergeOut $mergeErr
$merge = Finish-GodotJob $mergeJob $TimeoutSeconds
Get-Content -LiteralPath $mergeOut | Where-Object { $_ -match 'POLICY_TOURNAMENT' } | Write-Output
if ($merge.TimedOut -or $merge.ExitCode -ne 0 -or `
		$merge.Stdout -notmatch '(?m)^POLICY_TOURNAMENT_MERGE_OK ') {
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
