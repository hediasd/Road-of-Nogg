#Requires -Version 5.1
[CmdletBinding()]
param(
	[string]$SourceCommit = "0c101e16f6dd26062cb6c76d0b74b46d6dc73361",
	[string]$OutputDirectory = "references/square-battle",
	[string]$ExtractionDirectory = "builds/square-reference/hxb2-verification"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimePaths = @(
	"project.godot",
	"export_presets.cfg",
	"assets",
	"data",
	"scenes",
	"src",
	"scripts/demo_battle.gd",
	"scripts/demo_battle.gd.uid",
	"docs/README.md"
)

function Get-RepositoryChildPath {
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string]$RepositoryRoot,
		[Parameter(Mandatory = $true)][string]$Label
	)

	$absolute = if ([IO.Path]::IsPathRooted($Path)) {
		[IO.Path]::GetFullPath($Path)
	} else {
		[IO.Path]::GetFullPath((Join-Path $RepositoryRoot $Path))
	}
	$prefix = $RepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
		[IO.Path]::DirectorySeparatorChar
	if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "$Label must remain inside the repository: $absolute"
	}
	return $absolute
}

function Assert-UnderRoot {
	param(
		[Parameter(Mandatory = $true)][string]$Path,
		[Parameter(Mandatory = $true)][string]$AllowedRoot,
		[Parameter(Mandatory = $true)][string]$Label
	)

	$prefix = $AllowedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) +
		[IO.Path]::DirectorySeparatorChar
	if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
		throw "$Label must remain below $AllowedRoot`: $Path"
	}
}

function Invoke-GitChecked {
	param([Parameter(Mandatory = $true)][string[]]$Arguments)

	$output = & git @Arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
	}
	return $output
}

$repositoryRoot = (Invoke-GitChecked -Arguments @("rev-parse", "--show-toplevel") |
	Select-Object -First 1).Trim()
$repositoryRoot = [IO.Path]::GetFullPath($repositoryRoot)
$outputPath = Get-RepositoryChildPath -Path $OutputDirectory `
	-RepositoryRoot $repositoryRoot -Label "OutputDirectory"
$extractionPath = Get-RepositoryChildPath -Path $ExtractionDirectory `
	-RepositoryRoot $repositoryRoot -Label "ExtractionDirectory"
$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot "references"))
$allowedExtractionRoot = [IO.Path]::GetFullPath(
	(Join-Path $repositoryRoot "builds/square-reference"))
Assert-UnderRoot -Path $outputPath -AllowedRoot $allowedOutputRoot `
	-Label "OutputDirectory"
Assert-UnderRoot -Path $extractionPath -AllowedRoot $allowedExtractionRoot `
	-Label "ExtractionDirectory"

if (Test-Path -LiteralPath $extractionPath) {
	throw "ExtractionDirectory already exists and will not be removed: $extractionPath"
}

$commit = (Invoke-GitChecked -Arguments @(
	"rev-parse", "--verify", "$SourceCommit`^{commit}")) |
	Select-Object -First 1
$commit = $commit.Trim()
if ($commit -notmatch "^[0-9a-f]{40}$") {
	throw "Git did not resolve SourceCommit to a full commit ID: $commit"
}

foreach ($runtimePath in $runtimePaths) {
	Invoke-GitChecked -Arguments @("cat-file", "-e", "$commit`:$runtimePath") |
		Out-Null
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$gdignorePath = Join-Path $outputPath ".gdignore"
if (-not (Test-Path -LiteralPath $gdignorePath -PathType Leaf)) {
	throw "Missing required archive guard: $gdignorePath"
}

$stagingRoot = Join-Path $allowedExtractionRoot (
	".preserve-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString("N"))
$stagingExtract = Join-Path $stagingRoot "project"
$stagingArchive = Join-Path $stagingRoot "source.zip"
New-Item -ItemType Directory -Path $stagingExtract -Force | Out-Null

try {
	$archiveArguments = @("archive", "--format=zip", "--output=$stagingArchive", $commit, "--")
	$archiveArguments += $runtimePaths
	Invoke-GitChecked -Arguments $archiveArguments | Out-Null
	Expand-Archive -LiteralPath $stagingArchive -DestinationPath $stagingExtract

	$files = Get-ChildItem -LiteralPath $stagingExtract -File -Recurse |
		Sort-Object FullName
	if ($files.Count -eq 0) {
		throw "The reconstructed package is empty."
	}

	$inventory = @()
	$forbidden = @()
	$absoluteReferences = @()
	$resourceDependencies = [Collections.Generic.HashSet[string]]::new(
		[StringComparer]::Ordinal)
	$textExtensions = [Collections.Generic.HashSet[string]]::new(
		[StringComparer]::OrdinalIgnoreCase)
	@(".cfg", ".gd", ".gdshader", ".godot", ".json", ".md", ".tres", ".tscn") |
		ForEach-Object { [void]$textExtensions.Add($_) }
	$resourcePattern = [regex]::new(
		'res://(?<path>[A-Za-z0-9_./ @+()%-]+?\.(?:gdshader|tscn|tres|jpeg|webp|gltf|json|png|jpg|svg|glb|obj|wav|ogg|mp3|ttf|otf|gd))',
		[Text.RegularExpressions.RegexOptions]::IgnoreCase)
	$stagingPrefix = $stagingExtract.TrimEnd([IO.Path]::DirectorySeparatorChar) +
		[IO.Path]::DirectorySeparatorChar

	foreach ($file in $files) {
		if (-not $file.FullName.StartsWith(
				$stagingPrefix, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Archived file escaped staging root: $($file.FullName)"
		}
		$relative = $file.FullName.Substring($stagingPrefix.Length).
			Replace([IO.Path]::DirectorySeparatorChar, "/")
		if ($relative -match '(^|/)(\.godot|\.import|\.env|credentials?|secrets?)(/|$)' -or
			$relative -match '(^|/)Godot_v[^/]*\.(exe|x86_64)$') {
			$forbidden += $relative
		}
		$hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
		$inventory += [ordered]@{
			path = $relative
			size = $file.Length
			sha256 = $hash
		}

		if ($textExtensions.Contains($file.Extension)) {
			$content = [IO.File]::ReadAllText($file.FullName)
			if ($content -match '(?i)[A-Z]:\\Users\\' -or
				$content.IndexOf($repositoryRoot, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
				$absoluteReferences += $relative
			}
			foreach ($match in $resourcePattern.Matches($content)) {
				$resourcePath = $match.Groups["path"].Value
				if ($resourcePath.Contains("%") -or $resourcePath.StartsWith(
						"debug/", [StringComparison]::OrdinalIgnoreCase)) {
					continue
				}
				[void]$resourceDependencies.Add($resourcePath)
			}
		}
	}

	if ($forbidden.Count -gt 0) {
		throw "Forbidden package entries: $($forbidden -join ', ')"
	}
	if ($absoluteReferences.Count -gt 0) {
		throw "Active absolute paths found in: $($absoluteReferences -join ', ')"
	}

	$missingResources = @()
	foreach ($resourcePath in ($resourceDependencies | Sort-Object)) {
		$localPath = Join-Path $stagingExtract ($resourcePath.Replace("/", `
			[IO.Path]::DirectorySeparatorChar))
		if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
			$missingResources += "res://$resourcePath"
		}
	}
	if ($missingResources.Count -gt 0) {
		throw "Missing literal res:// dependencies: $($missingResources -join ', ')"
	}

	$archiveHash = (Get-FileHash -LiteralPath $stagingArchive -Algorithm SHA256).
		Hash.ToLowerInvariant()
	$sourceTimestamp = (Invoke-GitChecked -Arguments @(
		"show", "-s", "--format=%cI", $commit) | Select-Object -First 1).Trim()
	$manifest = [ordered]@{
		schema_version = 1
		artifact = "frozen-square-battle"
		godot_version = "4.4-stable"
		source_commit = $commit
		source_commit_timestamp = $sourceTimestamp
		runtime_paths = $runtimePaths
		archive = [ordered]@{
			path = "source.zip"
			sha256 = $archiveHash
			file_count = $inventory.Count
		}
		resolved_static_resources = @($resourceDependencies | Sort-Object |
			ForEach-Object { "res://$_" })
		files = $inventory
		deferred_acceptance = @(
			"Fresh Godot import and main-scene launch",
			"Representative CPU vs CPU and Player vs CPU battles",
			"Snapshot restore and command replay parity",
			"Representative VFX render comparison"
		)
	}

	$archiveDestination = Join-Path $outputPath "source.zip"
	if (Test-Path -LiteralPath $archiveDestination -PathType Leaf) {
		$existingHash = (Get-FileHash -LiteralPath $archiveDestination -Algorithm SHA256).
			Hash.ToLowerInvariant()
		if ($existingHash -ne $archiveHash) {
			throw "Existing source.zip differs and will not be overwritten: $archiveDestination"
		}
	} else {
		Copy-Item -LiteralPath $stagingArchive -Destination $archiveDestination
	}

	$manifestPath = Join-Path $outputPath "PACKAGE_MANIFEST.json"
	$manifestJson = $manifest | ConvertTo-Json -Depth 8
	[IO.File]::WriteAllText($manifestPath, $manifestJson + [Environment]::NewLine,
		[Text.UTF8Encoding]::new($false))

	Move-Item -LiteralPath $stagingExtract -Destination $extractionPath
	Copy-Item -LiteralPath $gdignorePath -Destination (Join-Path $extractionPath ".gdignore")

	Write-Output "SQUARE_REFERENCE_OK"
	Write-Output "SOURCE_COMMIT=$commit"
	Write-Output "ARCHIVE_SHA256=$archiveHash"
	Write-Output "FILE_COUNT=$($inventory.Count)"
	Write-Output "EXTRACTED_TO=$extractionPath"
} finally {
	if (Test-Path -LiteralPath $stagingRoot) {
		$resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
		Assert-UnderRoot -Path $resolvedStaging -AllowedRoot $allowedExtractionRoot `
			-Label "Staging cleanup"
		Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
	}
}
