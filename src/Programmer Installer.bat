@echo off
rem Opens the Programmer Installer window. Double-click this file.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0ProgrammerInstaller.ps1"
