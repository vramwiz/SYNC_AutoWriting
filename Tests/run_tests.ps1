param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_AutoWriting\SYNC_AutoWriting.auf2',
    [string]$OutputDirectory,
    [switch]$Demo
)

# 本番AUF2を検査する。IDE・AviUtl2は起動しない。
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectDirectory 'Win64\Verification'
$dcuDirectory = Join-Path $buildDirectory 'DCU'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectDirectory 'Win64\LatestVerification\Images' }
New-Item -ItemType Directory -Path $dcuDirectory -Force | Out-Null
$compiler = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$libraryDirectory = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\Win64\release'
Push-Location $PSScriptRoot
try {
    & $compiler '--no-config' '-B' '-Q' '-TX.exe' '-$R+' '-$Q+' '-NSSystem;Winapi;Vcl' `
        "-U$libraryDirectory;$libraryDirectory\JA" "-E$buildDirectory" "-NU$dcuDirectory" 'AutoWriting_Tests.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'Test build failed.' }
    $testArguments = @($PluginPath, $OutputDirectory)
    if ($Demo) { $testArguments += '--demo' }
    & (Join-Path $buildDirectory 'AutoWriting_Tests.exe') @testArguments
    if ($LASTEXITCODE -ne 0) { throw 'Production AUF2 tests failed.' }
}
finally { Pop-Location }
