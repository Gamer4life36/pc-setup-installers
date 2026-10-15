param([string]$SnapshotPath = '', [string]$DemoSearch = '')
& (Join-Path $PSScriptRoot 'InstallerApp.ps1') -Config 'gamer.config.json' -SnapshotPath $SnapshotPath -DemoSearch $DemoSearch