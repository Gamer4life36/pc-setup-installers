<#
  Builds the two installers into dist\ using only tools that ship with Windows:
    - .zip packages      (Compress-Archive)
    - .exe launchers     (csc.exe, the C# compiler included with .NET Framework 4)
  Run:  powershell -ExecutionPolicy Bypass -File build\Build.ps1
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root 'src'
$dist = Join-Path $root 'dist'
$work = Join-Path $env:TEMP ('pcinstallers_build_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $dist, $work | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw 'csc.exe was not found. It comes with .NET Framework 4, which is part of Windows 10/11.' }

$products = @(
    @{ Name = 'Gamer-Installer'; Folder = 'Gamer'; Script = 'GamerInstaller.ps1'; Title = 'Gamer & Streamer Installer'
       Files = @('InstallerApp.ps1', 'RunAsAdmin.ps1', 'GamerInstaller.ps1', 'Gamer Installer.bat', 'Gamer Installer (Admin).bat',
                 'gamer.config.json', 'gamer-catalog.json', 'gamer-icons.json', 'gamer-presets.json', 'README.txt')
       Dirs = @('icons') },
    @{ Name = 'Programmer-Installer'; Folder = 'Programmer'; Script = 'ProgrammerInstaller.ps1'; Title = 'Programmer Installer'
       Files = @('InstallerApp.ps1', 'RunAsAdmin.ps1', 'ProgrammerInstaller.ps1', 'Programmer Installer.bat', 'Programmer Installer (Admin).bat',
                 'programmer.config.json', 'programmer-catalog.json', 'programmer-icons.json', 'programmer-presets.json', 'README.txt')
       Dirs = @('icons-programmer') }
)

foreach ($p in $products) {
    # 1. zip package
    $stage = Join-Path $work $p.Name
    New-Item -ItemType Directory $stage | Out-Null
    foreach ($f in $p.Files) { Copy-Item (Join-Path $src $f) $stage }
    foreach ($d in $p.Dirs)  { Copy-Item (Join-Path $src $d) (Join-Path $stage $d) -Recurse }
    $zip = Join-Path $dist ($p.Name + '.zip')
    Remove-Item $zip -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip

    # 2. .exe: the zip is embedded as a resource; the exe unpacks it and starts the installer window
    $code = (Get-Content (Join-Path $PSScriptRoot 'launcher.cs.template') -Raw).
        Replace('TITLE_TEXT', '"' + $p.Title + '"').
        Replace('FOLDER_NAME', '"' + $p.Folder + '"').
        Replace('SCRIPT_NAME', '"' + $p.Script + '"')
    $cs = Join-Path $work ($p.Name + '.cs')
    [IO.File]::WriteAllText($cs, $code, (New-Object Text.UTF8Encoding $false))
    $exe = Join-Path $dist ($p.Name + '.exe')
    Remove-Item $exe -ErrorAction SilentlyContinue
    & $csc /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$(Join-Path $PSScriptRoot 'app.ico')" "/win32manifest:$(Join-Path $PSScriptRoot 'app.manifest')" "/resource:$zip,payload.zip" /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Windows.Forms.dll $cs
    if (-not (Test-Path $exe)) { throw "Build failed for $($p.Name)" }
}

# 3. checksums, so downloads can be verified
Get-FileHash (Join-Path $dist '*.exe'), (Join-Path $dist '*.zip') -Algorithm SHA256 |
    ForEach-Object { '{0}  {1}' -f $_.Hash.ToLower(), (Split-Path $_.Path -Leaf) } |
    Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Remove-Item $work -Recurse -Force
Get-ChildItem $dist | Select-Object Name, @{ n = 'KB'; e = { [math]::Round($_.Length / 1KB) } }