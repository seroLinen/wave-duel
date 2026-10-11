# Adds the game to the Windows Start menu as an app (search "CHAKANA" in Start, or find it under All apps, and pin it from there).
# It launches Godot directly with this project, so there is no console window. No desktop icon is created.
#
#   powershell -ExecutionPolicy Bypass -File tools\install_start_menu.ps1
#
# Godot's path comes from godot_path.txt in the project folder (git-ignored) or the GODOT environment variable.
# Re-run it if you move the project or Godot. To remove the app, delete the shortcut it prints at the end.
$root = Split-Path -Parent $PSScriptRoot
$godot = $null
$cfg = Join-Path $root "godot_path.txt"
if (Test-Path $cfg) { $godot = (Get-Content $cfg -TotalCount 1).Trim() }
if (-not $godot -and $env:GODOT) { $godot = $env:GODOT }
if (-not $godot -or -not (Test-Path $godot)) { Write-Error "Put the path to your Godot 4.3 .exe in godot_path.txt (one line) and run this again."; exit 1 }
$icon = Join-Path $root "art\app_icon.ico"
$programs = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$lnk = Join-Path $programs "CHAKANA.EXE Kagami Network.lnk"
$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = $godot
$s.Arguments = "--path `"$root`""
$s.WorkingDirectory = $root
if (Test-Path $icon) { $s.IconLocation = $icon }
$s.Description = "CHAKANA.EXE Kagami Network (Wave Duel)"
$s.Save()
Write-Host "Created: $lnk"
