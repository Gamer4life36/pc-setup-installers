@echo off
rem Same as Gamer Installer.bat but asks for administrator permission once.
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0RunAsAdmin.ps1" GamerInstaller.ps1
