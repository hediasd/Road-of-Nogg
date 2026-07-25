[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$errors = [System.Collections.Generic.List[string]]::new()

function Add-AuditError([string]$Message) {
    $script:errors.Add($Message)
}

$required = @(
    '.agents/AGENTS.md',
    'README.md',
    'docs/README.md',
    'docs/POLICIES.md',
    'docs/ARCHITECTURE.md',
    'docs/GAME_DESIGN.md',
    'docs/PLAYABLE_BATTLE_PLAN.md',
    'docs/BACKLOG.md',
    'docs/LEARNINGS.md',
    'docs/DEVELOPMENT.md',
    'docs/archive/BATTLE_RUNTIME_MIGRATION.md',
    'gamerefs/tactical_rpg_turn_systems.md'
)

foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
        Add-AuditError "Missing required document: $relativePath"
    }
}

foreach ($retiredPath in @('docs/PROJECT_STRUCTURE.md', 'implementation_plan.md')) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $retiredPath)) {
        Add-AuditError "Retired document returned: $retiredPath"
    }
}

$trackedMarkdownPaths = @(
    & git -C $repoRoot ls-files -- '*.md'
)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate tracked Markdown files.'
}
$markdownFiles = @(
    $trackedMarkdownPaths |
        ForEach-Object { Get-Item -LiteralPath (Join-Path $repoRoot $_) }
)

$forbidden = [ordered]@{
    'absolute file URL' = 'file:///'
    'stale Godot 4.3 executable' = 'Godot_v4.3'
    'removed BattleSample scene' = 'BattleSample.tscn'
    'removed SimpleBrain script' = 'SimpleBrain.gd'
    'retired project-structure document' = 'PROJECT_STRUCTURE.md'
    'removed AI architecture path' = 'ai/ARCHITECTURE.md'
}

foreach ($file in $markdownFiles) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $displayPath = $file.FullName
    if ($displayPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $displayPath = $displayPath.Substring($repoRoot.Length).TrimStart('\', '/')
    }

    foreach ($entry in $forbidden.GetEnumerator()) {
        if ($text.Contains($entry.Value)) {
            Add-AuditError "$displayPath contains $($entry.Key): $($entry.Value)"
        }
    }

    $lineNumber = 0
    foreach ($line in [System.Text.RegularExpressions.Regex]::Split($text, '\r?\n')) {
        $lineNumber += 1
        if ($line -match '[ \t]+$') {
            Add-AuditError "${displayPath}:$lineNumber has trailing whitespace"
        }
    }

    $links = [System.Text.RegularExpressions.Regex]::Matches($text, '!?(?:\[[^\]]*\])\(([^)]+)\)')
    foreach ($link in $links) {
        $target = $link.Groups[1].Value.Trim().Trim('<', '>')
        if ($target -match '^(?:https?://|mailto:|#)') { continue }
        $target = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($target)) { continue }
        $decoded = [System.Uri]::UnescapeDataString($target)
        if ([System.IO.Path]::IsPathRooted($decoded)) {
            Add-AuditError "$displayPath uses an absolute local link: $target"
            continue
        }
        $resolved = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $decoded))
        if (-not (Test-Path -LiteralPath $resolved)) {
            Add-AuditError "$displayPath has a broken local link: $target"
        }
    }
}

$aspectFiles = @(
    $markdownFiles |
        Where-Object {
            $_.DirectoryName -eq (Join-Path $repoRoot 'gamerefs') -and
            $_.Name -like 'trpg_*.md'
        } |
        Sort-Object Name
)
if ($aspectFiles.Count -ne 18) {
    Add-AuditError "Expected 18 gameref aspect modules; found $($aspectFiles.Count)"
}

$masterPath = Join-Path $repoRoot 'gamerefs/tactical_rpg_turn_systems.md'
$masterText = if (Test-Path -LiteralPath $masterPath) { [System.IO.File]::ReadAllText($masterPath) } else { '' }
foreach ($aspect in $aspectFiles) {
    $text = [System.IO.File]::ReadAllText($aspect.FullName)
    $takeawayCount = [System.Text.RegularExpressions.Regex]::Matches($text, '(?m)^## Implementation Takeaways for Road of Nogg\r?$').Count
    $backLinkCount = [System.Text.RegularExpressions.Regex]::Matches($text, '(?m)^\[Back to Master Index\]\(\./tactical_rpg_turn_systems\.md\)\r?$').Count
    if ($takeawayCount -ne 1) {
        Add-AuditError "$($aspect.Name) must have exactly one implementation-takeaways section"
    }
    if ($backLinkCount -ne 1) {
        Add-AuditError "$($aspect.Name) must have exactly one relative master-index link"
    }
    if ($text.Contains('Master List Checklist Validation') -or $text.Contains('(TBD)')) {
        Add-AuditError "$($aspect.Name) contains retired checklist/TBD boilerplate"
    }
    if (-not $masterText.Contains("(./$($aspect.Name))")) {
        Add-AuditError "Master index does not link $($aspect.Name)"
    }
}

$agentText = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.agents/AGENTS.md'))
if (-not $agentText.Contains('Consult `docs/LEARNINGS.md`')) {
    Add-AuditError 'AGENTS.md must explicitly route relevant work through LEARNINGS.md'
}

if ($errors.Count -gt 0) {
    Write-Error ("Documentation audit failed:`n- " + ($errors -join "`n- "))
    exit 1
}

Write-Host "Documentation audit passed ($($markdownFiles.Count) Markdown files, $($aspectFiles.Count) gameref modules)."
exit 0
