[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)]
	[ValidateSet('SelfTest', 'ValidatePlan', 'Apply', 'Verify')]
	[string]$Mode
)

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$script:ManifestPath = Join-Path $PSScriptRoot 'folder_layout_manifest.json'
$script:BaselinePath = Join-Path $PSScriptRoot 'folder_layout_baseline.json'
$script:ToolRelativePaths = @(
	'tools/folder_layout.ps1',
	'tools/folder_layout_manifest.json',
	'tools/folder_layout_baseline.json'
)
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Fail([string]$Message) {
	throw "FOLDER_LAYOUT_FAILURE: $Message"
}

function Normalize-RelativePath([string]$Path) {
	if ([string]::IsNullOrWhiteSpace($Path)) {
		Fail 'empty relative path'
	}
	$normalized = $Path.Replace('\', '/').TrimStart('/')
	if ($normalized -eq '.' -or $normalized.Contains('//')) {
		Fail "invalid relative path: $Path"
	}
	return $normalized
}

function Resolve-SafePath([string]$RelativePath) {
	$normalized = Normalize-RelativePath $RelativePath
	if ([System.IO.Path]::IsPathRooted($RelativePath) -or $normalized -match '(^|/)\.\.(/|$)') {
		Fail "path escapes repository: $RelativePath"
	}
	$absolute = [System.IO.Path]::GetFullPath((Join-Path $script:ProjectRoot $normalized))
	$rootPrefix = $script:ProjectRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
	if (-not $absolute.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		Fail "path resolves outside repository: $RelativePath"
	}
	return $absolute
}

function Get-Sha256([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		Fail "missing file for hash: $Path"
	}
	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256([string]$Text, [bool]$Bom) {
	$encoding = [System.Text.UTF8Encoding]::new($Bom)
	$bytes = $encoding.GetBytes($Text)
	$sha = [System.Security.Cryptography.SHA256]::Create()
	try {
		return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
	} finally {
		$sha.Dispose()
	}
}

function Read-Utf8File([string]$Path) {
	$bytes = [System.IO.File]::ReadAllBytes($Path)
	$bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
	$offset = if ($bom) { 3 } else { 0 }
	$text = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
	return [pscustomobject]@{ Text = $text; Bom = $bom }
}

function Write-Utf8FileAtomically([string]$Path, [string]$Text, [bool]$Bom) {
	$directory = Split-Path -Parent $Path
	if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
		New-Item -ItemType Directory -Path $directory -Force | Out-Null
	}
	$tempPath = Join-Path $directory ('.folder-layout-' + [guid]::NewGuid().ToString('N') + '.tmp')
	try {
		$encoding = [System.Text.UTF8Encoding]::new($Bom)
		[System.IO.File]::WriteAllText($tempPath, $Text, $encoding)
		Move-Item -LiteralPath $tempPath -Destination $Path -Force
	} finally {
		if (Test-Path -LiteralPath $tempPath) {
			Remove-Item -LiteralPath $tempPath -Force
		}
	}
}

function Read-Json([string]$Path) {
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		Fail "missing contract file: $Path"
	}
	return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-RepositoryFiles {
	$files = @(& git -C $script:ProjectRoot ls-files)
	if ($LASTEXITCODE -ne 0) {
		Fail 'git ls-files failed'
	}
	return @($files | ForEach-Object { $_.Replace('\', '/') } | Sort-Object)
}

function Test-IsFrozenPath([string]$Path) {
	$normalized = Normalize-RelativePath $Path
	return $normalized.StartsWith('docs/plans/', [System.StringComparison]::OrdinalIgnoreCase) -or
		$normalized.StartsWith('references/square-battle/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IsArt([string]$Path) {
	$extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
	return $Path.StartsWith('assets/', [System.StringComparison]::OrdinalIgnoreCase) -or
		$extension -in @('.png', '.jpg', '.jpeg', '.webp', '.svg', '.ttf', '.otf', '.blend', '.dae', '.gltf', '.glb', '.mtl', '.material', '.gdshader')
}

function Test-IsTextPath([string]$Path) {
	$name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()
	$extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
	if ($name -in @('.gitignore', '.gitattributes', '.gdignore')) { return $true }
	return $extension -in @('.gd', '.uid', '.import', '.json', '.md', '.ps1', '.py', '.cfg', '.godot', '.tscn', '.tres', '.gltf', '.dae', '.mtl', '.material', '.gdshader', '.txt', '.svg', '.html', '.xml', '.csv')
}

function Test-InWriteBoundary([string]$Path) {
	$normalized = Normalize-RelativePath $Path
	if ($normalized -in @('AGENTS.md', 'README.md', 'BACKLOG.md', '.gitignore', 'project.godot', 'export_presets.cfg')) { return $true }
	foreach ($prefix in @('src/', 'simulation/', 'ai/', 'content/', 'battle/', 'ui/', 'effects/', 'worldmap/', 'map_editor/', 'assets/', 'scenes/', 'data/', 'scripts/', 'tools/', 'checks/', 'gamerefs/')) {
		if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
	}
	if ($normalized -match '^references/[^/]+\.md$') { return $true }
	if ($normalized -match '^docs/[^/]+\.md$') { return $true }
	foreach ($prefix in @('docs/effects/', 'docs/lore/', 'docs/sketches/')) {
		if ($normalized.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
	}
	return $false
}

function Get-PathDepth([string]$Path) {
	return ([regex]::Matches((Normalize-RelativePath $Path), '/')).Count
}

function Get-RelativeDirectory([string]$Path) {
	$directory = [System.IO.Path]::GetDirectoryName((Normalize-RelativePath $Path).Replace('/', '\'))
	if ([string]::IsNullOrEmpty($directory)) { return '' }
	return $directory.Replace('\', '/')
}

function Assert-ManifestShape($Manifest, $Baseline) {
	if ($Manifest.schemaVersion -ne 1 -or $Baseline.schemaVersion -ne 1) {
		Fail 'unsupported manifest or baseline schema'
	}
	$destinations = @{}
	$sources = @{}
	foreach ($move in @($Manifest.moves)) {
		$source = Normalize-RelativePath ([string]$move.source)
		$destination = Normalize-RelativePath ([string]$move.destination)
		if (-not (Test-InWriteBoundary $source) -or -not (Test-InWriteBoundary $destination)) {
			Fail "move outside write boundary: $source -> $destination"
		}
		if ((Test-IsFrozenPath $source) -or (Test-IsFrozenPath $destination)) {
			Fail "move touches frozen path: $source -> $destination"
		}
		$key = $destination.ToLowerInvariant()
		if ($destinations.ContainsKey($key)) {
			Fail "case-insensitive destination collision: $destination and $($destinations[$key])"
		}
		$destinations[$key] = $destination
		$sources[$source.ToLowerInvariant()] = $source
		if ($source.Equals($destination, [System.StringComparison]::OrdinalIgnoreCase)) {
			Fail "case-only or no-op move is forbidden: $source -> $destination"
		}
	}
	foreach ($patch in @($Manifest.patches)) {
		$before = Normalize-RelativePath ([string]$patch.pathBefore)
		$after = Normalize-RelativePath ([string]$patch.pathAfter)
		if (-not (Test-InWriteBoundary $before) -or -not (Test-InWriteBoundary $after)) {
			Fail "patch outside write boundary: $before -> $after"
		}
		if ((Test-IsFrozenPath $before) -or (Test-IsFrozenPath $after)) {
			Fail "patch touches frozen path: $before"
		}
		if (@($patch.replacements).Count -eq 0) {
			Fail "patch has no replacements: $before"
		}
	}
	foreach ($delete in @($Manifest.deletes)) {
		if (-not (Test-InWriteBoundary ([string]$delete.path)) -or (Test-IsFrozenPath ([string]$delete.path))) {
			Fail "delete outside boundary or frozen: $($delete.path)"
		}
	}
	$baselineKeys = @{}
	foreach ($entry in @($Baseline.entries)) {
		$key = ([string]$entry.path).ToLowerInvariant()
		if ($baselineKeys.ContainsKey($key)) {
			Fail "case-insensitive baseline collision: $($entry.path)"
		}
		$baselineKeys[$key] = $entry
	}
	foreach ($move in @($Manifest.moves)) {
		if (-not $baselineKeys.ContainsKey(([string]$move.source).ToLowerInvariant())) {
			Fail "move source absent from baseline: $($move.source)"
		}
	}
}

function Assert-Preflight($Manifest, $Baseline) {
	Assert-ManifestShape $Manifest $Baseline
	$moveSources = @{}
	foreach ($move in @($Manifest.moves)) { $moveSources[([string]$move.source).ToLowerInvariant()] = $true }
	foreach ($entry in @($Baseline.entries)) {
		$path = Resolve-SafePath ([string]$entry.path)
		if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
			Fail "baseline input missing: $($entry.path)"
		}
		$actual = Get-Sha256 $path
		if ($actual -ne [string]$entry.sha256) {
			Fail "baseline input changed: $($entry.path) expected $($entry.sha256), got $actual"
		}
	}
	foreach ($move in @($Manifest.moves)) {
		$source = Resolve-SafePath ([string]$move.source)
		$destination = Resolve-SafePath ([string]$move.destination)
		if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
			Fail "move source missing: $($move.source)"
		}
		if ((Get-Sha256 $source) -ne [string]$move.preSha256) {
			Fail "move source hash changed: $($move.source)"
		}
		if ((Test-Path -LiteralPath $destination) -and -not $moveSources.ContainsKey(([string]$move.destination).ToLowerInvariant())) {
			Fail "destination already exists: $($move.destination)"
		}
	}
	foreach ($delete in @($Manifest.deletes)) {
		$path = Resolve-SafePath ([string]$delete.path)
		$companion = Resolve-SafePath ([string]$delete.requiredAbsentCompanion)
		if (Test-Path -LiteralPath $companion) {
			Fail "conditional delete companion exists: $($delete.requiredAbsentCompanion)"
		}
		if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Sha256 $path) -ne [string]$delete.preSha256) {
			Fail "conditional delete input missing or changed: $($delete.path)"
		}
	}
	foreach ($patch in @($Manifest.patches)) {
		$path = Resolve-SafePath ([string]$patch.pathBefore)
		if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Sha256 $path) -ne [string]$patch.preSha256) {
			Fail "patch source missing or changed: $($patch.pathBefore)"
		}
		$file = Read-Utf8File $path
		$text = $file.Text
		foreach ($replacement in @($patch.replacements)) {
			$count = ([regex]::Matches($text, [regex]::Escape([string]$replacement.old))).Count
			if ($count -ne [int]$replacement.count) {
				Fail "projected replacement count changed in $($patch.pathBefore): $($replacement.old) expected $($replacement.count), got $count"
			}
			$text = $text.Replace([string]$replacement.old, [string]$replacement.new)
		}
		if ((Get-StringSha256 $text $file.Bom) -ne [string]$patch.postSha256) {
			Fail "projected post-patch hash mismatch: $($patch.pathBefore)"
		}
	}
}

function Assert-BaselineContracts($Manifest, $Baseline) {
	$entries = @($Baseline.entries)
	if ($entries.Count -ne [int]$Baseline.trackedRetainedCount -or $entries.Count -ne [int]$Manifest.expectedPre.retainedFiles) {
		Fail 'baseline retained-file count is inconsistent'
	}
	$artEntries = @($entries | Where-Object { [bool]$_.isArt })
	if ($artEntries.Count -ne [int]$Baseline.artCount -or $artEntries.Count -ne [int]$Manifest.expectedPre.artFiles -or $artEntries.Count -ne [int]$Manifest.expectedPost.artFiles) {
		Fail 'art multiplicity is inconsistent'
	}
	$payload = @($artEntries | Where-Object { -not ([string]$_.path).EndsWith('.import') -and -not ([string]$_.path).EndsWith('.uid') })
	if ($payload.Count -ne [int]$Baseline.artPayloadCount) { Fail 'art payload count is inconsistent' }
	$actualDuplicateGroups = @($payload | Group-Object { [string]$_.sha256 } | Where-Object Count -gt 1 | Sort-Object Name)
	$recordedGroups = @($Baseline.duplicateArtGroups | Sort-Object sha256)
	if ($actualDuplicateGroups.Count -ne $recordedGroups.Count) { Fail 'duplicate-art group count is inconsistent' }
	for ($index = 0; $index -lt $actualDuplicateGroups.Count; $index++) {
		$actualPaths = @($actualDuplicateGroups[$index].Group | ForEach-Object { [string]$_.path } | Sort-Object)
		$recordedPaths = @($recordedGroups[$index].paths | Sort-Object)
		if ($actualDuplicateGroups[$index].Name -ne [string]$recordedGroups[$index].sha256 -or ($actualPaths -join "`n") -ne ($recordedPaths -join "`n")) {
			Fail "duplicate-art group changed at index $index"
		}
	}
	$entryByPath = @{}
	foreach ($entry in $entries) { $entryByPath[[string]$entry.path] = $entry }
	foreach ($patch in @($Manifest.patches)) {
		if (-not $entryByPath.ContainsKey([string]$patch.pathBefore) -or [string]$entryByPath[[string]$patch.pathBefore].kind -ne 'text') {
			Fail "patch targets an untracked or binary input: $($patch.pathBefore)"
		}
	}
	$entryPaths = @($entries | ForEach-Object { [string]$_.path })
	foreach ($uid in @($entryPaths | Where-Object { $_.EndsWith('.gd.uid', [System.StringComparison]::OrdinalIgnoreCase) })) {
		if ($uid.Substring(0, $uid.Length - 4) -notin $entryPaths) { Fail "baseline contains dangling UID sidecar: $uid" }
	}
}

function Assert-ProjectedReferences($Manifest, $Baseline) {
	$patchByPath = @{}
	foreach ($patch in @($Manifest.patches)) { $patchByPath[[string]$patch.pathBefore] = $patch }
	$stalePatterns = @(
		'res://src/', 'src/', 'res://scripts/', 'scripts/', 'gamerefs/',
		'data/battle/', 'data/worldmap/authored/', 'data/worldmap/tilesets/',
		'assets/shaders/effects/', 'assets/textures/effects/',
		'assets/textures/sky/', 'assets/ui/references/', 'assets/vfx/aurora_veil/',
		'assets/vfx/solar_storm/', 'assets/vfx/spell_cast_aura/',
		'assets/vfx/technique_charge_aura/', 'assets/vfx/technique_charge_aura_v2/',
		'assets/worldmap/clouds/', 'assets/worldmap/regions/', 'assets/worldmap/skies/',
		'assets/worldmap/tilesets/', 'scenes/battle/', 'scenes/debug/', 'scenes/entities/',
		'scenes/worldmap/generated/'
	)
	foreach ($entry in @($Baseline.entries)) {
		$path = [string]$entry.path
		if ([string]$entry.kind -ne 'text' -or (Test-IsFrozenPath $path) -or $path -eq 'scripts/preserve_square_battle.ps1') { continue }
		$file = Read-Utf8File (Resolve-SafePath $path)
		$text = $file.Text
		if ($patchByPath.ContainsKey($path)) {
			foreach ($replacement in @($patchByPath[$path].replacements)) { $text = $text.Replace([string]$replacement.old, [string]$replacement.new) }
		}
		foreach ($pattern in $stalePatterns) {
			if ($text.Contains($pattern)) { Fail "projected live text retains old path '$pattern' in $path" }
		}
	}
}

function Get-ProbeRegistry([string]$ManifestDirectoryRelative) {
	$manifestDirectory = Resolve-SafePath $ManifestDirectoryRelative
	if (-not (Test-Path -LiteralPath $manifestDirectory -PathType Container)) {
		Fail "probe manifest directory missing: $ManifestDirectoryRelative"
	}
	$entries = @()
	foreach ($file in @(Get-ChildItem -LiteralPath $manifestDirectory -Filter '*.json' -File | Sort-Object Name)) {
		$json = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
		foreach ($probe in @($json.probes)) {
			$entries += [pscustomobject]@{
				manifest = $file.Name
				script = [string]$probe.script
				marker = [string]$probe.marker
				timeout = [int]$probe.timeout
				expect = [string]$probe.expect
				gate = [bool]$probe.gate
				renderer = [bool]$probe.renderer
				note = [string]$probe.note
			}
		}
	}
	return @($entries | Sort-Object manifest, script)
}

function Assert-ProbeParity($Manifest, [bool]$PostMigration) {
	$directory = if ($PostMigration) { 'checks/manifests' } else { 'scripts/checks/probes' }
	$actual = @(Get-ProbeRegistry $directory)
	$expected = if ($PostMigration) { @($Manifest.probeRegistryAfter) } else { @($Manifest.probeRegistryBefore) }
	if ($actual.Count -ne $expected.Count) {
		Fail "probe registry count changed: expected $($expected.Count), got $($actual.Count)"
	}
	for ($index = 0; $index -lt $expected.Count; $index++) {
		$actualJson = $actual[$index] | ConvertTo-Json -Compress
		$expectedJson = $expected[$index] | ConvertTo-Json -Compress
		if ($actualJson -ne $expectedJson) {
			Fail "probe registry entry changed at index $index"
		}
	}
}

function Invoke-ValidatePlan {
	$manifest = Read-Json $script:ManifestPath
	$baseline = Read-Json $script:BaselinePath
	Assert-BaselineContracts $manifest $baseline
	Assert-Preflight $manifest $baseline
	Assert-ProjectedReferences $manifest $baseline
	Assert-ProbeParity $manifest $false
	$deletePaths = @($manifest.deletes | ForEach-Object { [string]$_.path })
	$tracked = @(Get-RepositoryFiles | Where-Object { $_ -notin $script:ToolRelativePaths -and $_ -notin $deletePaths })
	$expected = @($baseline.entries | ForEach-Object { [string]$_.path } | Sort-Object)
	if (($tracked -join "`n") -ne ($expected -join "`n")) {
		Fail 'tracked inventory differs from baseline'
	}
	Write-Output ("FOLDER_LAYOUT_PLAN_OK files={0} moves={1} patches={2} art={3}" -f $baseline.entries.Count, $manifest.moves.Count, $manifest.patches.Count, $baseline.artCount)
}

function Invoke-Apply {
	$manifest = Read-Json $script:ManifestPath
	$baseline = Read-Json $script:BaselinePath
	$allSourcesPresent = $true
	foreach ($move in @($manifest.moves)) {
		if (-not (Test-Path -LiteralPath (Resolve-SafePath ([string]$move.source)) -PathType Leaf)) { $allSourcesPresent = $false; break }
	}
	if ($allSourcesPresent) {
		Assert-Preflight $manifest $baseline
	} else {
		Assert-ManifestShape $manifest $baseline
		Write-Output 'FOLDER_LAYOUT_RESUME partial move state detected; each completed destination will be hash-checked'
	}

	foreach ($move in @($manifest.moves | Sort-Object { (Get-PathDepth ([string]$_.source)) } -Descending)) {
		$source = Resolve-SafePath ([string]$move.source)
		$destination = Resolve-SafePath ([string]$move.destination)
		if (Test-Path -LiteralPath $source -PathType Leaf) {
			if ((Get-Sha256 $source) -ne [string]$move.preSha256) { Fail "changed move source: $($move.source)" }
			if (Test-Path -LiteralPath $destination) { Fail "destination appeared during apply: $($move.destination)" }
			$directory = Split-Path -Parent $destination
			if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
			Move-Item -LiteralPath $source -Destination $destination
		} elseif (-not (Test-Path -LiteralPath $destination -PathType Leaf) -or (Get-Sha256 $destination) -ne [string]$move.preSha256) {
			Fail "neither valid source nor completed destination exists: $($move.source)"
		}
	}

	foreach ($patch in @($manifest.patches)) {
		$path = Resolve-SafePath ([string]$patch.pathAfter)
		$currentHash = Get-Sha256 $path
		if ($currentHash -eq [string]$patch.postSha256) { continue }
		if ($currentHash -ne [string]$patch.preSha256) { Fail "patch input changed: $($patch.pathAfter)" }
		$file = Read-Utf8File $path
		$text = $file.Text
		foreach ($replacement in @($patch.replacements)) {
			$old = [string]$replacement.old
			$count = ([regex]::Matches($text, [regex]::Escape($old))).Count
			if ($count -ne [int]$replacement.count) { Fail "replacement count changed in $($patch.pathAfter): $old" }
			$text = $text.Replace($old, [string]$replacement.new)
		}
		if ((Get-StringSha256 $text $file.Bom) -ne [string]$patch.postSha256) { Fail "post-patch hash mismatch: $($patch.pathAfter)" }
		Write-Utf8FileAtomically $path $text $file.Bom
	}
	$sourceDirectories = @($manifest.moves | ForEach-Object { Get-RelativeDirectory ([string]$_.source) } | Where-Object { $_ } | Sort-Object { Get-PathDepth $_ } -Descending -Unique)
	foreach ($relative in $sourceDirectories) {
		$directory = Resolve-SafePath $relative
		if ((Test-Path -LiteralPath $directory -PathType Container) -and @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
			Remove-Item -LiteralPath $directory
		}
	}

	foreach ($delete in @($manifest.deletes)) {
		$path = Resolve-SafePath ([string]$delete.path)
		$companion = Resolve-SafePath ([string]$delete.requiredAbsentCompanion)
		if (Test-Path -LiteralPath $companion) { Fail "delete companion appeared: $($delete.requiredAbsentCompanion)" }
		if (Test-Path -LiteralPath $path -PathType Leaf) {
			if ((Get-Sha256 $path) -ne [string]$delete.preSha256) { Fail "delete input changed: $($delete.path)" }
			Remove-Item -LiteralPath $path -Force
		}
	}
	foreach ($relative in @($manifest.emptyDirectories)) {
		$directory = Resolve-SafePath ([string]$relative)
		if (Test-Path -LiteralPath $directory -PathType Container) {
			if (@(Get-ChildItem -LiteralPath $directory -Force).Count -ne 0) { Fail "directory is no longer empty: $relative" }
			Remove-Item -LiteralPath $directory
		}
	}
	Invoke-Verify
}

function Invoke-Verify {
	$manifest = Read-Json $script:ManifestPath
	$baseline = Read-Json $script:BaselinePath
	Assert-BaselineContracts $manifest $baseline
	Assert-ManifestShape $manifest $baseline
	$moveBySource = @{}
	$patchByAfter = @{}
	foreach ($move in @($manifest.moves)) { $moveBySource[([string]$move.source).ToLowerInvariant()] = $move }
	foreach ($patch in @($manifest.patches)) { $patchByAfter[([string]$patch.pathAfter).ToLowerInvariant()] = $patch }
	foreach ($entry in @($baseline.entries)) {
		$expectedPath = [string]$entry.path
		$expectedHash = [string]$entry.sha256
		$key = $expectedPath.ToLowerInvariant()
		if ($moveBySource.ContainsKey($key)) { $expectedPath = [string]$moveBySource[$key].destination }
		$afterKey = $expectedPath.ToLowerInvariant()
		if ($patchByAfter.ContainsKey($afterKey)) { $expectedHash = [string]$patchByAfter[$afterKey].postSha256 }
		$absolute = Resolve-SafePath $expectedPath
		if (-not (Test-Path -LiteralPath $absolute -PathType Leaf) -or (Get-Sha256 $absolute) -ne $expectedHash) {
			Fail "post-migration file missing or changed: $expectedPath"
		}
	}
	foreach ($move in @($manifest.moves)) {
		if (Test-Path -LiteralPath (Resolve-SafePath ([string]$move.source))) { Fail "move source remains: $($move.source)" }
	}
	foreach ($delete in @($manifest.deletes)) {
		if (Test-Path -LiteralPath (Resolve-SafePath ([string]$delete.path))) { Fail "deleted path remains: $($delete.path)" }
	}
	$expectedPaths = @($baseline.entries | ForEach-Object {
		$key = ([string]$_.path).ToLowerInvariant()
		if ($moveBySource.ContainsKey($key)) { [string]$moveBySource[$key].destination } else { [string]$_.path }
	}) + $script:ToolRelativePaths
	$expectedPaths = @($expectedPaths | Sort-Object -Unique)
	$expectedPost = @($baseline.entries).Count + $script:ToolRelativePaths.Count
	if ($expectedPaths.Count -ne $expectedPost) { Fail "post path count expected $expectedPost, got $($expectedPaths.Count)" }

	foreach ($uid in @($expectedPaths | Where-Object { $_.EndsWith('.gd.uid', [System.StringComparison]::OrdinalIgnoreCase) })) {
		$scriptPath = $uid.Substring(0, $uid.Length - 4)
		if (-not (Test-Path -LiteralPath (Resolve-SafePath $scriptPath) -PathType Leaf)) { Fail "dangling UID sidecar: $uid" }
	}
	foreach ($exception in @($manifest.depthExceptions)) {
		if ([string]::IsNullOrWhiteSpace([string]$exception.reason)) { Fail "depth exception lacks reason: $($exception.path)" }
	}
	$exceptionPrefixes = @($manifest.depthExceptions | ForEach-Object { [string]$_.path })
	foreach ($path in $expectedPaths) {
		if ((Get-PathDepth $path) -le 2) { continue }
		$allowed = $false
		foreach ($prefix in $exceptionPrefixes) { if ($path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $allowed = $true; break } }
		if (-not $allowed) { Fail "unapproved deep path remains: $path" }
	}
	Assert-ProbeParity $manifest $true
	Write-Output ("FOLDER_LAYOUT_VERIFY_OK files={0} moves={1} patches={2} art={3}" -f $expectedPaths.Count, $manifest.moves.Count, $manifest.patches.Count, $baseline.artCount)
}

function Invoke-SelfTest {
	$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('road-of-nogg-folder-layout-' + [guid]::NewGuid().ToString('N'))
	New-Item -ItemType Directory -Path $tempRoot | Out-Null
	try {
		$outsideRejected = $false
		try { Resolve-SafePath '../outside.txt' | Out-Null } catch { $outsideRejected = $true }
		if (-not $outsideRejected) { Fail 'self-test: out-of-root path was accepted' }
		if (-not (Test-IsFrozenPath 'docs/plans/frozen.md') -or -not (Test-IsFrozenPath 'references/square-battle/source.zip')) { Fail 'self-test: frozen path rule failed' }

		$bytes = [byte[]](1, 4, 9, 16, 25)
		$a = Join-Path $tempRoot 'a.bin'; $b = Join-Path $tempRoot 'b.bin'; $c = Join-Path $tempRoot 'c.bin'
		[System.IO.File]::WriteAllBytes($a, $bytes); [System.IO.File]::WriteAllBytes($b, $bytes); [System.IO.File]::WriteAllBytes($c, [byte[]](1, 4, 9))
		if ((Get-Sha256 $a) -ne (Get-Sha256 $b)) { Fail 'self-test: binary retention hash failed' }
		if ((Get-Sha256 $a) -eq (Get-Sha256 $c)) { Fail 'self-test: changed input was not detected' }
		$duplicateGroups = @(@($a, $b, $c) | Group-Object { Get-Sha256 $_ } | Where-Object Count -gt 1)
		if ($duplicateGroups.Count -ne 1 -or $duplicateGroups[0].Count -ne 2) { Fail 'self-test: duplicate multiplicity failed' }

		$syntheticManifest = [pscustomobject]@{
			schemaVersion = 1
			moves = @(
				[pscustomobject]@{ source = 'src/a.gd'; destination = 'battle/A.gd' },
				[pscustomobject]@{ source = 'src/b.gd'; destination = 'battle/a.gd' }
			)
			patches = @(); deletes = @()
		}
		$syntheticBaseline = [pscustomobject]@{ schemaVersion = 1; entries = @([pscustomobject]@{ path = 'src/a.gd' }, [pscustomobject]@{ path = 'src/b.gd' }) }
		$collisionRejected = $false
		try { Assert-ManifestShape $syntheticManifest $syntheticBaseline } catch { $collisionRejected = $true }
		if (-not $collisionRejected) { Fail 'self-test: case-insensitive collision accepted' }

		$uidSet = @('ui/Widget.gd.uid')
		$fileSet = @('ui/Other.gd')
		$dangling = @($uidSet | Where-Object { ($_.Substring(0, $_.Length - 4)) -notin $fileSet })
		if ($dangling.Count -ne 1) { Fail 'self-test: UID pair detection failed' }
		Write-Output 'FOLDER_LAYOUT_SELF_TEST_OK collision uid changed-input binary duplicate out-of-root frozen'
	} finally {
		if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
	}
}

switch ($Mode) {
	'SelfTest' { Invoke-SelfTest }
	'ValidatePlan' { Invoke-ValidatePlan }
	'Apply' { Invoke-Apply }
	'Verify' { Invoke-Verify }
}
