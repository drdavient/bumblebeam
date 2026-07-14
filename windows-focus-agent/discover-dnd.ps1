# discover-dnd.ps1 — find what your Windows 11 build changes when DND toggles.
#
# Windows 11 has no supported API to set Do Not Disturb, and the legacy Focus
# Assist WNF / notifications registry toggle don't work on newer builds. So we
# reverse-engineer the lever on THIS machine:
#
#   .\discover-dnd.ps1 before      # DND OFF
#   # ...manually turn DND ON (Win+A -> Do not disturb), then:
#   .\discover-dnd.ps1 after       # DND ON
#   Compare-Object (Get-Content dnd-before.txt) (Get-Content dnd-after.txt)
#
# Whatever value flips is the lever; paste the diff back and I'll wire the agent
# to write it (via method=command or a new built-in).
#
# RESULT (2026-07-14, Ultra-Magners, Windows 11 2026 build): the before/after
# dumps were byte-identical — toggling DND changes NOTHING under these roots.
# The CloudStore quiethourssettings blob still read
# Microsoft.QuietHoursProfile.Unrestricted with DND visibly ON, so the registry
# copy is a lazily-flushed cache; the live state exists only in shell memory.
# Conclusion: no registry lever exists on this build. The agent's `dnd` method
# drives the real Quick Settings toggle via UI Automation instead.

param([Parameter(Mandatory=$true)][string]$Tag)

$roots = @(
  "HKCU\Software\Microsoft\Windows\CurrentVersion\Notifications",
  "HKCU\Software\Microsoft\Windows\CurrentVersion\PushNotifications",
  "HKCU\Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\Cache\DefaultAccount"
)

$out = "dnd-$Tag.txt"
Remove-Item $out -ErrorAction SilentlyContinue
foreach ($r in $roots) {
  "### $r" | Out-File -Append $out
  reg query $r /s 2>$null | Out-File -Append $out
}
Write-Host "wrote $out ($(Get-Content $out | Measure-Object -Line | Select-Object -Expand Lines) lines)"
