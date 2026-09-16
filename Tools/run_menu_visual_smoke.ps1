param(
    [Parameter(Mandatory = $true)]
    [string]$GodotPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = (Resolve-Path -LiteralPath $GodotPath).Path
$qaProfile = Join-Path $projectRoot 'output/qa-profile'
New-Item -ItemType Directory -Force -Path $qaProfile | Out-Null
$previousAppData = $env:APPDATA
try {
    # Limit saves/settings written by these tests to the ignored QA directory.
    $env:APPDATA = $qaProfile
    foreach ($testName in @('MainMenuSmoke', 'MenuVisualSmoke')) {
        $logPath = Join-Path $projectRoot ('output/' + $testName + '.log')
        $arguments = @('--path', ('"' + $projectRoot + '"'), '--rendering-method', 'gl_compatibility', '--single-window', '--script', ('res://Tests/' + $testName + '.gd'), '--log-file', ('"' + $logPath + '"'))
        $process = Start-Process -FilePath $runtimePath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        $log = Get-Content -LiteralPath $logPath -Raw
        if ($process.ExitCode -ne 0 -or $log -match 'SCRIPT ERROR|SMOKE: FAIL' -or $log -notmatch 'SMOKE: PASS') {
            throw "$testName failed. See $logPath"
        }
        Write-Output "$testName PASS — $logPath"
    }
} finally {
    $env:APPDATA = $previousAppData
}
