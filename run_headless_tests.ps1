$source = $PSScriptRoot
$shadow = "C:\temp\RoadOfNogg_Shadow"

# Mirror the project to the shadow folder, excluding heavy/locked directories
# /MIR : Mirror a directory tree
# /XD  : Exclude directories matching given names/paths
# /XF  : Exclude files matching given names/paths
# /NFL /NDL /NJH /NJS /nc /ns /np : Suppress all robocopy output for speed/cleanness
robocopy $source $shadow /MIR /XD ".git" "assets" ".godot\editor" /XF "gut_report.xml" /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null

# Run Godot headless from the shadow directory
Push-Location $shadow
Start-Process -FilePath ".\Godot_v4.4-stable_win64.exe" -ArgumentList "--headless", "-s", "run_gut.gd", "--user-data-dir", ".\userdata" -Wait

# Copy the report back to the main project
if (Test-Path "gut_report.xml") {
    Copy-Item "gut_report.xml" -Destination "$source\gut_report.xml" -Force
    Write-Host "Tests executed successfully in shadow folder."
} else {
    Write-Host "WARNING: Tests failed to generate a report."
}

Pop-Location
