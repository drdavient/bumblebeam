# install-autostart.ps1 — run the focus agent in the background at every logon.
#
#   .\install-autostart.ps1
#   .\install-autostart.ps1 -Uninstall
#
# (Needs local scripts enabled once for your user:
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned )
#
# Registers a Scheduled Task that starts pythonw (no console window) with this
# folder as the working directory (so config.ini is found), and starts it now.
#
# The task deliberately runs ONLY while the user is logged on: the dnd method
# drives the interactive desktop (Win+N / Enter), which does not exist in the
# hidden session used by "run whether user is logged on or not". The keyring
# credential is DPAPI-encrypted to the same user account, so it resolves too.

param([switch]$Uninstall)

$ErrorActionPreference = "Stop"
$TaskName = "Pomodoro focus agent"

if ($Uninstall) {
  Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  Write-Host "removed scheduled task '$TaskName'"
  return
}

$pythonw = (Get-Command pythonw.exe).Source
$script  = Join-Path $PSScriptRoot "focus_agent.py"

$action  = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$script`"" `
  -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
# No execution time limit (PT0S = disabled); restart if the process dies;
# never launch a second copy alongside a running one.
$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
  -ExecutionTimeLimit (New-TimeSpan -Seconds 0) `
  -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
  -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "installed and started '$TaskName' (runs at logon, background, only while logged on)"
Write-Host "check: Get-ScheduledTask '$TaskName' | Get-ScheduledTaskInfo"
