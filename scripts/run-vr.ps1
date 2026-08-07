$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$NativeBin = Join-Path $Root 'native\openxr_bridge\bin'
$Bridge = Join-Path $NativeBin 'gen1openxr.dll'
$Loader = Join-Path $NativeBin 'openxr_loader.dll'
$BridgeSource = Join-Path $Root 'native\openxr_bridge\gen1openxr.cpp'
$BridgeProject = Join-Path $Root 'native\openxr_bridge\CMakeLists.txt'

$NeedsBuild = -not (Test-Path $Bridge) -or -not (Test-Path $Loader)
if (-not $NeedsBuild) {
    $DllTime = (Get-Item $Bridge).LastWriteTimeUtc
    foreach ($source in @($BridgeSource, $BridgeProject)) {
        if ((Test-Path $source) -and (Get-Item $source).LastWriteTimeUtc -gt $DllTime) {
            $NeedsBuild = $true
            break
        }
    }
}
if ($NeedsBuild) {
    Write-Host 'Building the OpenXR bridge first...' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'build-vr.ps1')
}
if (-not (Test-Path $Bridge)) { throw "OpenXR bridge is missing: $Bridge" }
if (-not (Test-Path $Loader)) { throw "OpenXR loader is missing: $Loader" }

$LoveCommand = Get-Command love.exe -ErrorAction SilentlyContinue
if (-not $LoveCommand) { $LoveCommand = Get-Command love -ErrorAction SilentlyContinue }
$LovePath = if ($LoveCommand) { $LoveCommand.Source } else { $null }

if (-not $LovePath) {
    foreach ($candidate in @(
        "$env:ProgramFiles\LOVE\love.exe",
        "${env:ProgramFiles(x86)}\LOVE\love.exe",
        "$env:LOCALAPPDATA\Programs\LOVE\love.exe"
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $LovePath = [IO.Path]::GetFullPath($candidate)
            break
        }
    }
}

if (-not $LovePath) {
    $distRoot = Join-Path $Root 'dist\win'
    if (Test-Path -LiteralPath $distRoot -PathType Container) {
        $bundledLove = Get-ChildItem -LiteralPath $distRoot -Recurse -File -Filter 'love.exe' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($bundledLove) { $LovePath = $bundledLove.FullName }
    }
}
if (-not $LovePath) {
    throw 'LÖVE 11.x was not found. Install LÖVE or build/download a Windows package containing love.exe.'
}

$env:GEN1RECOMP_VR = '1'
$env:GEN1RECOMP_OPENXR_DLL = $Bridge
# Both gen1openxr.dll itself and its openxr_loader.dll dependency must be
# visible to LoadLibrary.  FFI's source path alone is not a dependency path.
$env:Path = "$NativeBin;$env:Path"

$quotedRoot = '"' + $Root + '"'
$process = Start-Process -FilePath $LovePath `
    -ArgumentList @($quotedRoot, '--vr') `
    -WorkingDirectory $Root `
    -PassThru `
    -Wait
exit $process.ExitCode
