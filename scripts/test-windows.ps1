param(
  [switch]$Quick,
  [string]$LovePath = $env:LOVE_EXE
)

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Runner = Join-Path $Root 'tests\love_runner'

function Resolve-LoveExecutable {
  param([string]$ExplicitPath)

  if ($ExplicitPath) {
    $resolved = [IO.Path]::GetFullPath($ExplicitPath)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
      throw "LOVE_EXE does not exist: $resolved"
    }
    return $resolved
  }

  $command = Get-Command love.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command love -ErrorAction SilentlyContinue }
  if ($command) { return $command.Source }

  $candidates = @(
    (Join-Path $Root 'dist\win\gen1recomp-vr-current-win64\love.exe'),
    (Join-Path $Root 'dist\win\1GenPokemonVR-v0.1.0-win64\love.exe'),
    (Join-Path $Root 'dist\win\gen1recomp-vr-spatial-fixed-win64\love.exe'),
    "$env:ProgramFiles\LOVE\love.exe",
    "${env:ProgramFiles(x86)}\LOVE\love.exe",
    "$env:LOCALAPPDATA\Programs\LOVE\love.exe"
  )
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return [IO.Path]::GetFullPath($candidate)
    }
  }

  throw 'LÖVE 11.x was not found. Install LÖVE or set LOVE_EXE to love.exe.'
}

function Get-LuaSuites {
  param([string]$Directory)

  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
  return @(
    Get-ChildItem -LiteralPath $Directory -File -Filter '*.lua' |
      Where-Object { -not $_.Name.StartsWith('_') -and $_.Name -ne 'facts.lua' } |
      Sort-Object FullName
  )
}

$Love = Resolve-LoveExecutable $LovePath
if (-not (Test-Path -LiteralPath $Runner -PathType Container)) {
  throw "LÖVE test runner is missing: $Runner"
}

$Suites = [Collections.Generic.List[IO.FileInfo]]::new()
foreach ($suite in (Get-LuaSuites (Join-Path $Root 'tests\engine'))) {
  $Suites.Add($suite)
}
foreach ($suite in (Get-LuaSuites (Join-Path $Root 'tests\modkit\cases'))) {
  $Suites.Add($suite)
}

$ModsRoot = Join-Path $Root 'mods'
if (Test-Path -LiteralPath $ModsRoot -PathType Container) {
  foreach ($mod in (Get-ChildItem -LiteralPath $ModsRoot -Directory | Sort-Object Name)) {
    if ($mod.Name.Contains('.') -or $mod.Name.StartsWith('example_')) { continue }
    foreach ($suite in (Get-LuaSuites (Join-Path $mod.FullName 'tests'))) {
      $Suites.Add($suite)
    }
  }
}

$ContentSuites = @()
if (-not $Quick -and (Test-Path -LiteralPath (Join-Path $Root 'data\generated\maps.lua'))) {
  $ContentSuites = @(
    'tests\run_tests.lua',
    'tests\run_save_editor_tests.lua',
    'tests\run_link_tests.lua'
  ) | ForEach-Object { Get-Item -LiteralPath (Join-Path $Root $_) }
}
foreach ($suite in $ContentSuites) { $Suites.Add($suite) }

$OldScript = $env:POKEPORT_TEST_SCRIPT
$OldResult = $env:POKEPORT_TEST_RESULT
$ResultPath = Join-Path ([IO.Path]::GetTempPath()) ("gen1recomp-test-{0}.txt" -f [Guid]::NewGuid().ToString('N'))
$Failed = [Collections.Generic.List[string]]::new()
$Passed = 0

Push-Location $Root
try {
  $env:POKEPORT_TEST_RESULT = $ResultPath
  foreach ($suite in $Suites) {
    $relative = $suite.FullName.Substring($Root.Length).TrimStart([char[]]'\/').Replace('\', '/')
    $env:POKEPORT_TEST_SCRIPT = $relative
    Remove-Item -LiteralPath $ResultPath -Force -ErrorAction SilentlyContinue

    $process = Start-Process -FilePath $Love `
      -ArgumentList 'tests\love_runner' `
      -WorkingDirectory $Root `
      -WindowStyle Hidden `
      -PassThru `
      -Wait

    if ($process.ExitCode -eq 0) {
      $Passed++
      Write-Host "PASS $relative"
    } else {
      $Failed.Add($relative)
      Write-Host "FAIL $relative" -ForegroundColor Red
      if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
        Write-Host (Get-Content -LiteralPath $ResultPath -Raw)
      } else {
        Write-Host 'The LÖVE runner exited without producing a report.'
      }
    }
  }
} finally {
  Remove-Item -LiteralPath $ResultPath -Force -ErrorAction SilentlyContinue
  $env:POKEPORT_TEST_SCRIPT = $OldScript
  $env:POKEPORT_TEST_RESULT = $OldResult
  Pop-Location
}

Write-Host ''
Write-Host '=============================================================='
Write-Host ("  WINDOWS TESTS: {0}/{1} PASSED" -f $Passed, $Suites.Count)
if ($ContentSuites.Count -eq 0 -and -not $Quick) {
  Write-Host '  Content suites skipped: data/generated/maps.lua is absent.'
}
if ($Failed.Count -gt 0) {
  foreach ($path in $Failed) { Write-Host "    FAIL $path" -ForegroundColor Red }
  Write-Host '=============================================================='
  exit 1
}
Write-Host '=============================================================='
exit 0
