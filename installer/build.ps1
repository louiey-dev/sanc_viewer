param(
    [switch]$SkipBuild,
    [string]$IsccPath,
    [string]$FlutterPath = 'flutter',
    [string]$VCRuntimeDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    if (-not $IsccPath) {
        $candidates = @(
            "$projectRoot\build\installer-tools\inno\ISCC.exe",
            "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
        )
        $IsccPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $IsccPath) {
            $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
            if ($command) { $IsccPath = $command.Source }
        }
    }
    if (-not $IsccPath) { throw 'Inno Setup compiler not found. Pass -IsccPath with the path to ISCC.exe.' }

    if (-not $SkipBuild) {
        if (-not (Get-Command $FlutterPath -ErrorAction SilentlyContinue)) {
            if (Test-Path 'C:\flutter\flutter\bin\flutter.bat') {
                $FlutterPath = 'C:\flutter\flutter\bin\flutter.bat'
            } else { throw 'Flutter not found. Pass -FlutterPath.' }
        }
        $flutterCommand = Get-Command $FlutterPath -ErrorAction Stop
        $flutterRoot = Split-Path (Split-Path $flutterCommand.Source -Parent) -Parent
        $dart = Join-Path $flutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
        $snapshot = Join-Path $flutterRoot 'bin\cache\flutter_tools.snapshot'
        if ((Test-Path -LiteralPath $dart) -and (Test-Path -LiteralPath $snapshot)) {
            & $dart $snapshot build windows --release
        } else {
            & $FlutterPath build windows --release
        }
        if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    }

    $releaseDir = "$projectRoot\build\windows\x64\runner\Release"
    foreach ($required in @('sanc_viewer.exe', 'flutter_windows.dll', 'data\app.so', 'data\flutter_assets')) {
        if (-not (Test-Path -LiteralPath "$releaseDir\$required")) { throw "Release file missing: $required" }
    }

    if (-not $VCRuntimeDirectory) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Pass -VCRuntimeDirectory pointing to the x64 Microsoft.VC143.CRT directory.' }
        $cache = Select-String -Path 'build/windows/x64/CMakeCache.txt' -Pattern '^CMAKE_GENERATOR_INSTANCE:INTERNAL=(.+)$'
        $visualStudio = if ($cache) { $cache.Matches[0].Groups[1].Value } else {
            & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        }
        $VCRuntimeDirectory = Get-ChildItem -Path "$visualStudio\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory |
            Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path -LiteralPath "$VCRuntimeDirectory\$required")) { throw "x64 Visual C++ runtime missing: $required" }
    }
    $runtimeStage = "$projectRoot\build\installer-runtime"
    New-Item -ItemType Directory -Force $runtimeStage | Out-Null
    Copy-Item -Path "$VCRuntimeDirectory\*.dll" -Destination $runtimeStage -Force

    $versionMatch = Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)'
    if (-not $versionMatch) { throw 'Could not read the application version from pubspec.yaml.' }
    $version = $versionMatch.Matches[0].Groups[1].Value
    & $IsccPath "/DAppVersion=$version" "$PSScriptRoot\sanc_viewer.iss"
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
    $installer = "$projectRoot\dist\SancViewer-$version-windows-x64-Setup.exe"
    (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash + '  ' + (Split-Path $installer -Leaf) |
        Set-Content -LiteralPath "$installer.sha256" -Encoding ascii
    Write-Output "Installer: $installer"
} finally {
    Pop-Location
}
