## Runs every registered probe through scripts/hex_battle/run_probe.ps1, one at a time.
##
## A probe is registered in a manifest under scripts/checks/probes/. Each entry names the script,
## the exact marker the probe prints on success, its timeout, whether the sweep expects a pass or a
## failure (the runner's own negative control expects a failure), whether the entry gates the sweep,
## and whether it needs a renderer -- a renderer entry is listed and skipped, because run_probe.ps1
## always launches Godot headless.
##
## A quarantined entry (gate false) still runs and is still reported; it just cannot fail the sweep.
## Its note says why it was quarantined. See docs/DEVELOPMENT.md.

[CmdletBinding()]
param(
	[string]$Filter = '',
	[string]$ManifestDirectory = 'scripts/checks/probes',
	[string]$RunProbePath = 'scripts/hex_battle/run_probe.ps1'
)

$ErrorActionPreference = 'Stop'

function Fail-Sweep([string]$Reason) {
	[Console]::Error.WriteLine($Reason)
	exit 1
}

$projectRoot = (Get-Location).Path

function Resolve-ProjectPath([string]$Path) {
	$relative = $Path
	if ($relative.StartsWith('res://', [System.StringComparison]::Ordinal)) {
		$relative = $relative.Substring(6)
	}
	$relative = $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
	if ([System.IO.Path]::IsPathRooted($relative)) {
		return [System.IO.Path]::GetFullPath($relative)
	}
	return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
}

$manifestDirectoryPath = Resolve-ProjectPath $ManifestDirectory
if (-not (Test-Path -LiteralPath $manifestDirectoryPath -PathType Container)) {
	Fail-Sweep "Manifest directory does not exist: $manifestDirectoryPath"
}

$runProbe = Resolve-ProjectPath $RunProbePath
if (-not (Test-Path -LiteralPath $runProbe -PathType Leaf)) {
	Fail-Sweep "Probe runner does not exist: $runProbe"
}

$manifestFiles = @(Get-ChildItem -LiteralPath $manifestDirectoryPath -Filter '*.json' -File | Sort-Object Name)
if ($manifestFiles.Count -eq 0) {
	Fail-Sweep "No manifests in $manifestDirectoryPath"
}

$entries = @()
$seenScripts = @{}
foreach ($manifestFile in $manifestFiles) {
	$manifest = $null
	try {
		$manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
	} catch {
		Fail-Sweep "$($manifestFile.Name): not valid JSON -- $($_.Exception.Message)"
	}
	if ($null -eq $manifest.probes) {
		Fail-Sweep "$($manifestFile.Name): no 'probes' array"
	}
	foreach ($probe in $manifest.probes) {
		foreach ($field in @('script', 'marker', 'timeout', 'expect', 'gate', 'renderer')) {
			if ($null -eq $probe.$field) {
				Fail-Sweep "$($manifestFile.Name): an entry is missing '$field'"
			}
		}
		if ($probe.expect -ne 'pass' -and $probe.expect -ne 'fail') {
			Fail-Sweep "$($manifestFile.Name): $($probe.script) has expect '$($probe.expect)', not pass or fail"
		}
		if ($seenScripts.ContainsKey($probe.script)) {
			Fail-Sweep "$($probe.script) is registered twice: $($seenScripts[$probe.script]) and $($manifestFile.Name)"
		}
		$seenScripts[$probe.script] = $manifestFile.Name
		$scriptPath = Resolve-ProjectPath $probe.script
		if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
			Fail-Sweep "$($manifestFile.Name): probe script does not exist: $($probe.script)"
		}
		$entries += [pscustomobject]@{
			Manifest = $manifestFile.Name
			Script = [string]$probe.script
			Marker = [string]$probe.marker
			Timeout = [int]$probe.timeout
			Expect = [string]$probe.expect
			Gate = [bool]$probe.gate
			Renderer = [bool]$probe.renderer
		}
	}
}

if ($Filter -ne '') {
	$entries = @($entries | Where-Object { $_.Script -like "*$Filter*" })
	if ($entries.Count -eq 0) {
		Fail-Sweep "No registered probe matches filter '$Filter'"
	}
}

$logDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("road-of-nogg-sweep-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$gated = 0
$passed = 0
$failed = 0
$skipped = 0
$quarantined = 0
foreach ($entry in $entries) {
	if ($entry.Renderer) {
		# Counted as skipped rather than gated: a gated probe the sweep never ran must not read as
		# a failure in the final ratio.
		$skipped += 1
		Write-Output ("SKIP {0} -" -f $entry.Script)
		continue
	}
	if ($entry.Gate) {
		$gated += 1
	} else {
		$quarantined += 1
	}

	$logStem = Join-Path $logDirectory ([System.IO.Path]::GetFileNameWithoutExtension($entry.Script))
	$stdoutPath = "$logStem.out.log"
	$stderrPath = "$logStem.err.log"
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
	## Start-Process does not quote for you, and this repository's path contains a space.
	$process = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
		'-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $runProbe),
		'-Script', ('"{0}"' -f $entry.Script), '-Marker', ('"{0}"' -f $entry.Marker),
		'-TimeoutSeconds', $entry.Timeout
	) -WorkingDirectory $projectRoot -NoNewWindow -Wait -PassThru `
		-RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
	$stopwatch.Stop()

	$met = $false
	if ($entry.Expect -eq 'pass') {
		$met = ($process.ExitCode -eq 0)
	} else {
		$met = ($process.ExitCode -ne 0)
	}

	$verdict = ''
	if ($entry.Gate) {
		if ($met) {
			$verdict = 'PASS'
			$passed += 1
		} else {
			$verdict = 'FAIL'
			$failed += 1
		}
	} else {
		if ($met) {
			$verdict = 'QUARANTINED-PASS'
		} else {
			$verdict = 'QUARANTINED-FAIL'
		}
	}

	Write-Output ("{0} {1} {2:N1}s" -f $verdict, $entry.Script, $stopwatch.Elapsed.TotalSeconds)
	if (-not $met) {
		foreach ($line in @(Get-Content -LiteralPath $stderrPath -ErrorAction SilentlyContinue)) {
			if ($line.Trim() -ne '') {
				Write-Output ("    {0}" -f $line)
			}
		}
		Write-Output ("    sweep logs: {0}" -f $logDirectory)
	}
}

$tail = "{0} quarantined, {1} skipped" -f $quarantined, $skipped
if ($failed -eq 0) {
	Write-Output ("PROBE_SWEEP_OK {0}/{1} ({2})" -f $passed, $gated, $tail)
	exit 0
}

Write-Output ("PROBE_SWEEP_FAILED {0} of {1} gated ({2})" -f $failed, $gated, $tail)
exit 1
