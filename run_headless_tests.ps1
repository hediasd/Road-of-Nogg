param(
    [switch]$ForceGut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $ForceGut) {
    Write-Host "GUT is isolated after a reproducible Godot 4.4 access violation."
    Write-Host "See docs/BACKLOG.md. Use -ForceGut only for future diagnostics."
    exit 4
}

$source = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$godot = Join-Path $source "Godot_v4.4-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot -PathType Leaf)) {
    throw "Godot executable not found: $godot"
}

# A fresh shadow cache keeps CLI imports separate from an open editor session.
$tempRoot = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::GetTempPath()
).TrimEnd("\")
$shadow = Join-Path $tempRoot "RoadOfNogg_Gut_Shadow"
New-Item -ItemType Directory -Force -Path $shadow | Out-Null
$shadow = (Resolve-Path -LiteralPath $shadow).Path
if (-not $shadow.StartsWith(
    $tempRoot + "\",
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to mirror into unexpected path: $shadow"
}

robocopy $source $shadow /MIR `
    /XD ".git" ".godot" ".import" "assets" "debug" `
    /XF "Godot_v*.exe" "*.blend1" "*.blend2" "godot_*.txt" `
        "test_out.txt" "gut_report.xml" "gut_report.txt" `
    /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
$copyExitCode = $LASTEXITCODE
if ($copyExitCode -gt 7) {
    throw "Shadow project copy failed with robocopy code $copyExitCode."
}

$shadowReport = Join-Path $shadow "gut_report.xml"
$shadowStdout = Join-Path $shadow "gut_stdout.log"
$shadowStderr = Join-Path $shadow "gut_stderr.log"
foreach ($generatedFile in @($shadowReport, $shadowStdout, $shadowStderr)) {
    if (Test-Path -LiteralPath $generatedFile) {
        Remove-Item -LiteralPath $generatedFile -Force
    }
}

# GUT 9.4 owns the complete test lifecycle and maps failures to process code 1.
$arguments = @(
    "--headless",
    "--disable-crash-handler",
    "--path", $shadow,
    "--rendering-method", "gl_compatibility",
    "--audio-driver", "Dummy",
    "-s", "res://addons/gut/gut_cmdln.gd",
    "-gexit",
    "-gdisable_colors"
)
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
$timedOut = -not $process.WaitForExit(120000)
if ($timedOut) {
    $process.Kill()
}
$process.WaitForExit()
[System.IO.File]::WriteAllText(
    $shadowStdout, $stdoutTask.GetAwaiter().GetResult()
)
[System.IO.File]::WriteAllText(
    $shadowStderr, $stderrTask.GetAwaiter().GetResult()
)
if ($timedOut) {
    Write-Host "Tests timed out after 120 seconds."
    exit 3
}

$debugDirectory = Join-Path $source "debug"
New-Item -ItemType Directory -Force -Path $debugDirectory | Out-Null
Copy-Item -LiteralPath $shadowStdout `
    -Destination (Join-Path $debugDirectory "gut_stdout.log") -Force
Copy-Item -LiteralPath $shadowStderr `
    -Destination (Join-Path $debugDirectory "gut_stderr.log") -Force

if (-not (Test-Path -LiteralPath $shadowReport -PathType Leaf)) {
    Write-Host "GUT did not generate a JUnit report. See debug/gut_stderr.log."
    exit 2
}
Copy-Item -LiteralPath $shadowReport `
    -Destination (Join-Path $source "gut_report.xml") -Force

if ($process.ExitCode -ne 0) {
    Write-Host "Tests failed with exit code $($process.ExitCode)."
    exit $process.ExitCode
}

Write-Host "Tests passed. Report: $source\gut_report.xml"
exit 0
