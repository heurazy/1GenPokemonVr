param(
  [string]$Version = "0.2.39",
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$android = Join-Path $root "mobile\android"
$sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA "Android\Sdk" }
$ndkVersion = "27.0.12077973"
$ndk = Join-Path $sdk "ndk\$ndkVersion"
$deps = Join-Path $root ".quest-deps"
$aar = Join-Path $deps "openxr_loader_for_android-1.1.53.aar"
$aarRoot = Join-Path $deps "openxr-loader-aar"
$questAssets = Join-Path $android "app\src\quest\assets"
$jni = Join-Path $android "app\src\quest\jniLibs\arm64-v8a"
$build = Join-Path $root "native\openxr_bridge\quest\build-arm64"
$dist = Join-Path $root "dist\quest"

if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must use X.Y.Z" }
if (-not (Test-Path $ndk)) { throw "Android NDK $ndkVersion was not found at $ndk" }

New-Item -ItemType Directory -Force $deps,$questAssets,$jni,$dist | Out-Null

if (-not (Test-Path $aar)) {
  Write-Host "Downloading the official Khronos OpenXR Android loader..."
  Invoke-WebRequest "https://repo1.maven.org/maven2/org/khronos/openxr/openxr_loader_for_android/1.1.53/openxr_loader_for_android-1.1.53.aar" -OutFile $aar
}
if (-not (Test-Path (Join-Path $aarRoot "jni\arm64-v8a\libopenxr_loader.so"))) {
  $aarZip = Join-Path $deps "openxr_loader_for_android-1.1.53.zip"
  Copy-Item -LiteralPath $aar -Destination $aarZip -Force
  Expand-Archive -LiteralPath $aarZip -DestinationPath $aarRoot -Force
}

Write-Host "Packing the ROM-free Quest game payload..."
$lovePath = Join-Path $questAssets "game.love"
if (Test-Path $lovePath) { Remove-Item -LiteralPath $lovePath -Force }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($lovePath, [IO.Compression.ZipArchiveMode]::Create)
try {
  $roots = @("main.lua", "conf.lua", "src", "data", "assets", "mods", "tools\rom_manifest.json", "tools\rom_manifest_blue.json")
  foreach ($item in $roots) {
    $absolute = Join-Path $root $item
    $files = if (Test-Path $absolute -PathType Container) { Get-ChildItem -LiteralPath $absolute -Recurse -File } else { Get-Item -LiteralPath $absolute }
    foreach ($file in $files) {
      $relative = $file.FullName.Substring($root.Length + 1).Replace('\','/')
      $dramaticDev = $relative -match '^mods/dramatic_shape/(tests|tools|assets/docs|oxr)(/|$)'
      $dramaticDesktopVr = $relative -match '^mods/dramatic_shape/assets/vr/'
      $dramaticMetadata = $relative -match '^mods/dramatic_shape/(\.gitignore|\.modkitignore|CHANGELOG\.md|QUEST_PORT\.md|README\.md|mod\.card|oxr\.zip)$'
      $generatedCache = $relative -match '^(data|assets)/generated/'
      $gitMetadata = $relative -match '(^|/)\.git/'
      if ($generatedCache -or $gitMetadata -or $dramaticDev -or $dramaticDesktopVr -or $dramaticMetadata) { continue }
      $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
      $output = $entry.Open()
      try {
        if ($relative -eq 'src/core/Version.lua') {
          $text = [IO.File]::ReadAllText($file.FullName)
          $text = [regex]::Replace($text, 'engine\s*=\s*"[^"]*"', "engine = `"$Version`"")
          $bytes = [Text.Encoding]::UTF8.GetBytes($text)
          $output.Write($bytes, 0, $bytes.Length)
        } else {
          $input = $file.OpenRead()
          try { $input.CopyTo($output) } finally { $input.Dispose() }
        }
      } finally { $output.Dispose() }
    }
  }
  $marker = $archive.CreateEntry("quest_build.txt")
  $markerStream = New-Object IO.StreamWriter($marker.Open())
  try { $markerStream.WriteLine("Quest 3 standalone OpenXR build") } finally { $markerStream.Dispose() }
} finally { $archive.Dispose() }

Write-Host "Building the ARM64 OpenXR/GLES bridge..."
$toolchain = Join-Path $ndk "build\cmake\android.toolchain.cmake"
cmake -S (Join-Path $root "native\openxr_bridge\quest") -B $build `
  -G Ninja `
  "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
  "-DANDROID_ABI=arm64-v8a" `
  "-DANDROID_PLATFORM=android-29" `
  "-DANDROID_STL=c++_shared" `
  "-DCMAKE_BUILD_TYPE=$Configuration" `
  "-DOPENXR_AAR_ROOT=$($aarRoot.Replace('\','/'))"
if ($LASTEXITCODE -ne 0) { throw "Quest bridge configuration failed" }
cmake --build $build
if ($LASTEXITCODE -ne 0) { throw "Quest bridge build failed" }
Copy-Item -LiteralPath (Join-Path $build "libgen1openxr.so") -Destination $jni -Force
Copy-Item -LiteralPath (Join-Path $aarRoot "jni\arm64-v8a\libopenxr_loader.so") -Destination $jni -Force
$cxx = Join-Path $ndk "toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib\aarch64-linux-android\libc++_shared.so"
if (-not (Test-Path -LiteralPath $cxx -PathType Leaf)) {
  throw "Android C++ runtime was not found: $cxx"
}
Copy-Item -LiteralPath $cxx -Destination $jni -Force

Write-Host "Building the standalone Quest APK..."
$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk
$java17 = Join-Path $deps "jdk-17"
if (-not (Test-Path (Join-Path $java17 "bin\java.exe"))) {
  $javaZip = Join-Path $deps "jdk-17.zip"
  Invoke-WebRequest "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse" -OutFile $javaZip
  $unpack = Join-Path $deps "jdk-17-unpack"
  if (Test-Path -LiteralPath $unpack) { Remove-Item -LiteralPath $unpack -Recurse -Force }
  Expand-Archive -LiteralPath $javaZip -DestinationPath $unpack -Force
  $jdkDir = Get-ChildItem -LiteralPath $unpack -Directory | Select-Object -First 1
  if (-not $jdkDir) { throw "The downloaded JDK archive did not contain a JDK directory" }
  Move-Item -LiteralPath $jdkDir.FullName -Destination $java17
}
$env:JAVA_HOME = $java17
$code = ([int]($Version.Split('.')[0]) * 10000) + ([int]($Version.Split('.')[1]) * 100) + [int]($Version.Split('.')[2])

$usedDriveNames = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.ToUpperInvariant() })
$buildDriveName = @('Q','R','S','T','U','V','W','X','Y','Z') |
  Where-Object { $usedDriveNames -notcontains $_ } |
  Select-Object -First 1
if (-not $buildDriveName) { throw "No free drive letter is available for the temporary Quest build drive" }

$buildDrive = "${buildDriveName}:"
$substCreated = $false
$locationPushed = $false
try {
  & subst.exe $buildDrive $root
  if ($LASTEXITCODE -ne 0) { throw "Could not create the temporary Quest build drive $buildDrive" }
  $substCreated = $true

  Push-Location "$buildDrive\mobile\android"
  $locationPushed = $true

  # Pass release identity explicitly so a Quest build never rewrites the
  # checked-in Android defaults or leaks Quest branding into later builds.
  # Explicit project properties also prevent Gradle from reusing an
  # up-to-date APK carrying a previous version.
  $gradleArgs = @(
    "--no-daemon",
    "-Papp.name=1GenPokemonVR Quest",
    "-Papp.version_name=$Version",
    "-Papp.version_code=$code",
    "assembleQuestNoRecord$Configuration"
  )
  $wrapperJar = Join-Path (Get-Location) "gradle\wrapper\gradle-wrapper.jar"
  if ((Test-Path -LiteralPath ".\gradlew.bat" -PathType Leaf) -and
      (Test-Path -LiteralPath $wrapperJar -PathType Leaf)) {
    & .\gradlew.bat @gradleArgs
  } else {
    # Clean source-only publication checkouts intentionally omit binary JARs,
    # including gradle-wrapper.jar. CI installs Gradle 8.1 explicitly; use it
    # as a safe fallback while normal development checkouts keep the wrapper.
    $gradle = Get-Command gradle.bat -ErrorAction SilentlyContinue
    if (-not $gradle) { $gradle = Get-Command gradle -ErrorAction SilentlyContinue }
    if (-not $gradle) {
      throw "Gradle 8.1 was not found and gradle-wrapper.jar is unavailable"
    }
    & $gradle.Source @gradleArgs
  }
  if ($LASTEXITCODE -ne 0) { throw "Quest APK build failed" }
} finally {
  if ($locationPushed) { Pop-Location }
  if ($substCreated) {
    & subst.exe $buildDrive /D
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Could not remove the temporary Quest build drive $buildDrive"
    }
  }
}

$apk = Get-ChildItem (Join-Path $android "app\build\outputs\apk\questNoRecord\$($Configuration.ToLower())") -Filter *.apk |
  Where-Object Name -notmatch '-unsigned\.apk$' |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if (-not $apk) { throw "Gradle finished without producing a signed Quest APK" }

$aapt2 = Get-ChildItem (Join-Path $sdk "build-tools") -Recurse -Filter "aapt2.exe" |
  Sort-Object FullName -Descending |
  Select-Object -First 1
if (-not $aapt2) { throw "Could not find aapt2 to verify the Quest APK" }
$badging = & $aapt2.FullName dump badging $apk.FullName | Select-Object -First 1
$escapedVersion = [regex]::Escape($Version)
if ($badging -notmatch "versionCode='$code'" -or $badging -notmatch "versionName='$escapedVersion'") {
  throw "Quest APK identity mismatch: expected $Version ($code), got: $badging"
}

$outputApk = Join-Path $dist "1GenPokemonVR-Quest3-v$Version.apk"
Copy-Item -LiteralPath $apk.FullName -Destination $outputApk -Force
Write-Host "Quest APK ready: $outputApk"
