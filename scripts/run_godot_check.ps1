[CmdletBinding()]
param(
    [string]$Script = "",
    [string]$ExpectedMarker = "",
    [ValidateRange(1, 600)]
    [int]$TimeoutSeconds = 60,
    [ValidateRange(0, 100000)]
    [int]$QuitAfter = 0,
    [string]$LogStem = "godot_check",
    [string[]]$ScriptArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$godot = Join-Path $repoRoot "Godot_v4.4-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw "Godot executable not found: $godot"
}

$safeStem = [System.Text.RegularExpressions.Regex]::Replace(
    $LogStem,
    "[^A-Za-z0-9_.-]",
    "_"
)
$logRoot = Join-Path ([System.IO.Path]::GetTempPath()) "RoadOfNoggChecks"
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$godotLog = Join-Path $logRoot "$safeStem.godot.log"
$stdoutLog = Join-Path $logRoot "$safeStem.stdout.log"
$stderrLog = Join-Path $logRoot "$safeStem.stderr.log"

$arguments = @(
    "--headless",
    "--disable-crash-handler",
    "--path", ".",
    "--rendering-method", "gl_compatibility",
    "--audio-driver", "Dummy",
    "--log-file", $godotLog
)
if ($QuitAfter -gt 0) {
    $arguments += @("--quit-after", $QuitAfter.ToString())
}
if (-not [string]::IsNullOrWhiteSpace($Script)) {
    $arguments += @("-s", $Script)
}
if ($ScriptArgs.Count -gt 0) {
    # Everything after "--" becomes the script's OS.get_cmdline_user_args().
    $arguments += @("--")
    $arguments += $ScriptArgs
}

$quotedArguments = ($arguments | ForEach-Object {
    if ($_ -match '[\s"]') {
        '"' + $_.Replace('"', '\"') + '"'
    } else {
        $_
    }
}) -join " "

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $godot
$startInfo.Arguments = $quotedArguments
$startInfo.WorkingDirectory = $repoRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
    throw "Godot process failed to start."
}

$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
if ($timedOut) {
    $process.Kill()
}
$process.WaitForExit()

$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
[System.IO.File]::WriteAllText($stdoutLog, $stdout)
[System.IO.File]::WriteAllText($stderrLog, $stderr)
$godotOutput = if (Test-Path -LiteralPath $godotLog) {
    [System.IO.File]::ReadAllText($godotLog)
} else {
    ""
}
$combined = "$godotOutput`n$stdout`n$stderr"

$displayParts = [System.Collections.Generic.List[string]]::new()
foreach ($fragment in @($godotOutput, $stdout, $stderr)) {
    $normalized = $fragment.Replace("`r`n", "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        continue
    }
    $alreadyShown = $false
    foreach ($shown in $displayParts) {
        if ($shown.Contains($normalized)) {
            $alreadyShown = $true
            break
        }
    }
    if (-not $alreadyShown) {
        $displayParts.Add($normalized)
    }
}
Write-Host ($displayParts -join "`n")
Write-Host "Godot exit code: $($process.ExitCode)"
Write-Host "Logs: $logRoot"

if ($timedOut) {
    Write-Error "Godot check timed out after $TimeoutSeconds seconds."
    exit 3
}
if ($process.ExitCode -ne 0) {
    exit $process.ExitCode
}
if (
    -not [string]::IsNullOrWhiteSpace($ExpectedMarker) -and
    -not $combined.Contains($ExpectedMarker)
) {
    Write-Error "Expected success marker not found: $ExpectedMarker"
    exit 2
}

$unexpectedErrors = @(
    [System.Text.RegularExpressions.Regex]::Matches(
        $combined,
        "(?m)^(?:SCRIPT ERROR:|ERROR:).*$"
    ) | ForEach-Object { $_.Value } | Where-Object {
        $_ -notmatch '^ERROR: \d+ resources still in use at exit'
    } | Select-Object -Unique
)
if ($unexpectedErrors.Count -gt 0) {
    Write-Error ("Godot reported runtime errors:`n" + ($unexpectedErrors -join "`n"))
    exit 2
}

exit 0
