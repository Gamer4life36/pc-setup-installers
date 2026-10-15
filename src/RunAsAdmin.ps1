param([Parameter(Mandatory)][string]$Script)
# Opens an installer window as administrator, so Windows asks for permission once instead of for every program.
$path = Join-Path $PSScriptRoot $Script
Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', ('"{0}"' -f $path))