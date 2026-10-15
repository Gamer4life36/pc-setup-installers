@echo off
rem Opens the Gamer & Streamer Installer window. Double-click this file.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0GamerInstaller.ps1"
