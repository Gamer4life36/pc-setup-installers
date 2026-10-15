@echo off
rem Same as Programmer Installer.bat but asks for administrator permission once.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0RunAsAdmin.ps1" ProgrammerInstaller.ps1
