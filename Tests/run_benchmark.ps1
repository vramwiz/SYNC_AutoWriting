param([Parameter(Mandatory=$true)][string]$PluginPath, [Parameter(Mandatory=$true)][string]$OutputPath)
# 本番AUF2だけをCLIで計測する。IDE・AviUtl2は起動せず、学習データも保存しない。
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectDirectory 'Win64\Benchmark'
$dcuDirectory = Join-Path $buildDirectory 'DCU'
New-Item -ItemType Directory -Force $dcuDirectory | Out-Null
$compiler = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
$libraryDirectory = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\lib\Win64\release'
Push-Location $PSScriptRoot
try {
    & $compiler '--no-config' '-B' '-Q' '-TX.exe' '-NSSystem;Winapi;Vcl' `
        "-U$libraryDirectory;$libraryDirectory\JA" "-E$buildDirectory" "-NU$dcuDirectory" 'AutoWriting_Benchmark.dpr'
    if ($LASTEXITCODE -ne 0) { throw 'Benchmark build failed' }
    & (Join-Path $buildDirectory 'AutoWriting_Benchmark.exe') $PluginPath $OutputPath
    if ($LASTEXITCODE -ne 0) { throw 'Benchmark failed' }
}
finally { Pop-Location }
