$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$dialogueDir = Join-Path $projectRoot "Dialogues"
$levelDir = Join-Path $projectRoot "Resources\Levels"

$levelIds = Get-ChildItem $levelDir -Filter "*.tres" | ForEach-Object { $_.BaseName } | Sort-Object
$dialogueIds = Get-ChildItem $dialogueDir -Filter "*.dialogue" | ForEach-Object { $_.BaseName } | Sort-Object

$levelsWithoutDialogue = @()
foreach ($levelId in $levelIds) {
    $directPath = Join-Path $dialogueDir ($levelId + ".dialogue")
    $startPath = Join-Path $dialogueDir ($levelId + "_start.dialogue")
    if (-not (Test-Path $directPath) -and -not (Test-Path $startPath)) {
        $levelsWithoutDialogue += $levelId
    }
}

$dialoguesWithoutLevel = @()
foreach ($dialogueId in $dialogueIds) {
    if ($dialogueId -eq "level1") { continue }
    if ($dialogueId -match "_victory$") { continue }
    if ($dialogueId -match "_start$") {
        $baseId = $dialogueId -replace "_start$", ""
        if ($baseId -notin $levelIds) {
            $dialoguesWithoutLevel += $dialogueId
        }
        continue
    }
    if ($dialogueId -notin $levelIds) {
        $dialoguesWithoutLevel += $dialogueId
    }
}

Write-Output "LEVELS WITHOUT DIALOGUE:"
if ($levelsWithoutDialogue.Count -eq 0) {
    Write-Output "  (none)"
} else {
    $levelsWithoutDialogue | ForEach-Object { Write-Output "  $_" }
}

Write-Output ""
Write-Output "DIALOGUES WITHOUT LEVEL:"
if ($dialoguesWithoutLevel.Count -eq 0) {
    Write-Output "  (none)"
} else {
    $dialoguesWithoutLevel | Sort-Object -Unique | ForEach-Object { Write-Output "  $_" }
}
