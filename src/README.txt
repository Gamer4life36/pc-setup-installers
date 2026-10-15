GAMER & PROGRAMMER INSTALLERS
=============================
Two friendly installer windows. Pick programs, press one button, and they download and
install quietly through Windows' built-in package manager (winget).

  - Gamer Installer       : 99 programs - game stores, mod tools, streaming, emulators, gear software
  - Programmer Installer  : 118 programs - editors, languages, Git, Docker, databases, AI tools, game dev

HOW TO USE
1. Double-click "Gamer Installer.bat" or "Programmer Installer.bat". A window opens.
   (Use the "(Admin)" version to approve administrator permission ONCE instead of for every program.)
2. Click the programs you want. GREEN = will be installed. RED = skipped.
   - QUICK PICKS: one click adds a ready-made group (for example "Streamer starter" or "Web developer").
     Quick picks only ADD programs; use "Clear everything" to start over.
   - The search box finds programs by name or by what they do. Press Esc to clear it.
   - "All" / "None" on each category box picks or clears that whole group.
   - "Installed on this PC" means you already have it, so you can leave it red.
3. Press the big green "Install selected" button and confirm.
   Programs install one after another. A progress bar and a log show what is happening.
   "Stop after this program" finishes the current program and skips the rest.
4. Some programs may show a Windows permission (UAC) prompt. That is normal - choose Yes.

MORE FEATURES
- Save my picks / Load picks: save your selection to a file and load it on another PC.
- Update installed programs: appears when programs you already have (from the list) have a newer version.
- Retry failed: if some programs fail, the log says why in plain words and you can retry just those.
- Install order: programs that others depend on (for example WSL before Docker) go first.
- Restart notice: after installing, it tells you if a restart is needed. A log of every run is saved in
  %LOCALAPPDATA%\PCInstallers\logs and the "Open install log" button shows it.
- If winget is missing, the window says so and offers a button to get it from the Microsoft Store.
REQUIREMENTS
- Windows 10 (1809 or newer) or Windows 11 with winget ("App Installer"), already on most PCs.
- An internet connection.
- Nothing is installed until you press the green button and confirm.

FILES (keep each installer's files together in one folder)
Shared:      InstallerApp.ps1, RunAsAdmin.ps1
Gamer:       Gamer Installer.bat, Gamer Installer (Admin).bat, GamerInstaller.ps1, gamer.config.json,
             gamer-catalog.json, gamer-icons.json, gamer-presets.json, icons\
Programmer:  Programmer Installer.bat, Programmer Installer (Admin).bat, ProgrammerInstaller.ps1,
             programmer.config.json, programmer-catalog.json, programmer-icons.json,
             programmer-presets.json, icons-programmer\

TO ADD OR REMOVE A PROGRAM
Edit the catalog file (gamer-catalog.json or programmer-catalog.json). Each entry needs:
category, name, id (the winget ID), source ("winget" or "msstore"), and description.
Find a winget ID by running:  winget search <name>
To change the quick picks, edit the presets file. To change which programs start ticked,
edit "starter" in the .config.json file.

NOTES
- Emulators (in the Gamer Installer) do not include games or console BIOS files. You need your own
  legally obtained copies.
- A few programs are not on winget and have to be downloaded by hand. Lists are in GAMER-LIST.md.
- Some programs without a findable logo show a coloured letter badge instead.
- Logos come from Simple Icons (simpleicons.org, CC0) and from each program's own website or project
  page. Brand logos belong to their owners and are shown only to identify each program.