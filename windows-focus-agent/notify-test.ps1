# notify-test.ps1 — fire a Windows toast notification to verify Do Not Disturb.
#
# Usage (from PowerShell, in this folder):
#   .\notify-test.ps1
#
# Verification loop:
#   1. Run it once  -> the toast should pop up (baseline: notifications working).
#   2. python focus_agent.py --test on   (with method=focus_assist)
#      Run it again -> if DND is really ON, it should NOT pop up (it goes silently
#      to the notification centre; check with Win+N).
#   3. python focus_agent.py --test off
#      Run it again -> the toast pops up again.

param(
  [string]$Title   = "Focus test",
  [string]$Message = "If this pops up, notifications are NOT suppressed."
)

$ErrorActionPreference = "Stop"

# Load the WinRT toast types.
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.UI.Notifications.ToastNotification,        Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument,                 Windows.Data.Xml.Dom,     ContentType = WindowsRuntime]

# Built-in PowerShell AppUserModelID, so the toast has a registered source.
$AppId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

$xml = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Message</text>
    </binding>
  </visual>
</toast>
"@

$doc = [Windows.Data.Xml.Dom.XmlDocument]::new()
$doc.LoadXml($xml)
$toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)

Write-Host "Toast sent. With DND ON it should be suppressed (silent, only in Win+N centre)."
