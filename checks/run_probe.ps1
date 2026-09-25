[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[string]$Script,
	[Parameter(Mandatory = $true)]
	[string]$Marker,
	[string]$GodotPath = './Godot_v4.4-stable_win64.exe',
	[ValidateRange(1, [int]::MaxValue)]
	[int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'

$taskDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("road-of-nogg-hex-probe-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
$stdoutPath = Join-Path $taskDirectory 'stdout.log'
$stderrPath = Join-Path $taskDirectory 'stderr.log'
[System.IO.File]::WriteAllText($stdoutPath, '', [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($stderrPath, '', [System.Text.UTF8Encoding]::new($false))

function Fail-Probe([string]$Reason) {
	[Console]::Error.WriteLine($Reason)
	[Console]::Error.WriteLine("stdout: $stdoutPath")
	[Console]::Error.WriteLine("stderr: $stderrPath")
	exit 1
}

function ConvertTo-WindowsCommandLineArgument([string]$Value) {
	if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
		return $Value
	}

	$quoted = [System.Text.StringBuilder]::new()
	$null = $quoted.Append('"')
	$backslashCount = 0
	foreach ($character in $Value.ToCharArray()) {
		if ($character -eq '\') {
			$backslashCount += 1
			continue
		}
		if ($character -eq '"') {
			$null = $quoted.Append('\', ($backslashCount * 2) + 1)
			$null = $quoted.Append('"')
			$backslashCount = 0
			continue
		}
		$null = $quoted.Append('\', $backslashCount)
		$null = $quoted.Append($character)
		$backslashCount = 0
	}
	$null = $quoted.Append('\', $backslashCount * 2)
	$null = $quoted.Append('"')
	return $quoted.ToString()
}

try {
	if ($TimeoutSeconds -le 0) {
		Fail-Probe 'TimeoutSeconds must be positive.'
	}

	$projectRoot = (Get-Location).Path
	$resolvedGodotPath = if ([System.IO.Path]::IsPathRooted($GodotPath)) {
		[System.IO.Path]::GetFullPath($GodotPath)
	} else {
		[System.IO.Path]::GetFullPath((Join-Path $projectRoot $GodotPath))
	}
	if (-not (Test-Path -LiteralPath $resolvedGodotPath -PathType Leaf)) {
		Fail-Probe "Godot executable does not exist: $resolvedGodotPath"
	}

	$scriptRelativePath = if ($Script.StartsWith('res://', [System.StringComparison]::Ordinal)) {
		$Script.Substring(6).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
	} else {
		$Script
	}
	$resolvedScriptPath = if ([System.IO.Path]::IsPathRooted($scriptRelativePath)) {
		[System.IO.Path]::GetFullPath($scriptRelativePath)
	} else {
		[System.IO.Path]::GetFullPath((Join-Path $projectRoot $scriptRelativePath))
	}
	if (-not (Test-Path -LiteralPath $resolvedScriptPath -PathType Leaf)) {
		Fail-Probe "Probe script does not exist: $resolvedScriptPath"
	}

	$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
	$startInfo.FileName = $resolvedGodotPath
	$startInfo.WorkingDirectory = $projectRoot
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.Arguments = (@('--headless', '--path', '.', '--script', $Script) |
		ForEach-Object { ConvertTo-WindowsCommandLineArgument $_ }) -join ' '

	$process = [System.Diagnostics.Process]::new()
	$process.StartInfo = $startInfo
	if (-not $process.Start()) {
		Fail-Probe "Could not start Godot: $resolvedGodotPath"
	}

	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
		if (-not $process.HasExited) {
			$process.Kill()
		}
		$process.WaitForExit()
		[System.IO.File]::WriteAllText($stdoutPath, $stdoutTask.GetAwaiter().GetResult(), [System.Text.UTF8Encoding]::new($false))
		[System.IO.File]::WriteAllText($stderrPath, $stderrTask.GetAwaiter().GetResult(), [System.Text.UTF8Encoding]::new($false))
		Fail-Probe "Godot timed out after $TimeoutSeconds seconds."
	}
	$process.WaitForExit()
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	[System.IO.File]::WriteAllText($stdoutPath, $stdout, [System.Text.UTF8Encoding]::new($false))
	[System.IO.File]::WriteAllText($stderrPath, $stderr, [System.Text.UTF8Encoding]::new($false))

	$combinedOutput = $stdout + [Environment]::NewLine + $stderr
	$markerPattern = '(?m)^' + [regex]::Escape($Marker) + '\r?$'
	$hasMarker = [regex]::IsMatch($combinedOutput, $markerPattern)
	$hasGodotScriptError = [regex]::IsMatch($combinedOutput, '(?im)^(?:SCRIPT ERROR|Parse Error|ERROR:.*(?:script|parse))')
	if ($process.ExitCode -ne 0 -or -not $hasMarker -or $hasGodotScriptError) {
		Fail-Probe "Godot probe failed (exit code $($process.ExitCode); marker present: $hasMarker; script error: $hasGodotScriptError)."
	}

	Write-Output "Probe passed: $Marker"
	Write-Output "stdout: $stdoutPath"
	Write-Output "stderr: $stderrPath"
	exit 0
} catch {
	Fail-Probe "Probe launcher error: $($_.Exception.Message)"
}
