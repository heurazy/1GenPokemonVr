param(
    [string]$VcpkgRoot = $env:VCPKG_ROOT,
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Native = Join-Path $Root 'native\openxr_bridge'
$Build = Join-Path $Native 'build'

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake 3.21+ is required. Install it with: winget install Kitware.CMake'
}
if (-not $VcpkgRoot) {
    $VcpkgRoot = Join-Path $Root '.vr-deps\vcpkg'
    if (-not (Test-Path (Join-Path $VcpkgRoot 'vcpkg.exe'))) {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            throw 'Git is required to bootstrap vcpkg.'
        }
        New-Item -ItemType Directory -Force (Split-Path -Parent $VcpkgRoot) | Out-Null
        git clone --depth 1 https://github.com/microsoft/vcpkg $VcpkgRoot
        if ($LASTEXITCODE -ne 0) { throw 'Could not download vcpkg' }
        & (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics
        if ($LASTEXITCODE -ne 0) { throw 'Could not bootstrap vcpkg' }
    }
}
$Toolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'
if (-not (Test-Path $Toolchain)) {
    throw "vcpkg toolchain not found at $Toolchain"
}

& (Join-Path $VcpkgRoot 'vcpkg.exe') install openxr-loader:x64-windows
if ($LASTEXITCODE -ne 0) { throw 'vcpkg failed to install openxr-loader' }

cmake -S $Native -B $Build -A x64 `
    "-DCMAKE_TOOLCHAIN_FILE=$Toolchain" `
    "-DVCPKG_TARGET_TRIPLET=x64-windows"
if ($LASTEXITCODE -ne 0) { throw 'CMake configure failed' }

cmake --build $Build --config $Configuration --clean-first
if ($LASTEXITCODE -ne 0) { throw 'OpenXR bridge build failed' }

$Dll = Join-Path $Native 'bin\gen1openxr.dll'
if (-not (Test-Path $Dll)) { throw "Build completed but $Dll is missing" }
$Loader = Join-Path $VcpkgRoot 'installed\x64-windows\bin\openxr_loader.dll'
if (-not (Test-Path $Loader)) {
    throw "OpenXR loader runtime was not produced by vcpkg: $Loader"
}
Copy-Item $Loader (Join-Path $Native 'bin\openxr_loader.dll') -Force
Write-Host "OpenXR bridge ready: $Dll" -ForegroundColor Green
