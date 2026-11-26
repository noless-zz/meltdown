<#
.SYNOPSIS
Runs an acceptance suite on the connected Quest 3 and collects its report (#154).

.DESCRIPTION
The headset half of the device acceptance workflow
(.github/workflows/device-acceptance.yml, DEV-6, decision record 0005). Installs
the newest `main` build from the main-latest release after checking its
checksum, keeps the headset awake, starts the game with the acceptance intent
extra, waits for the runner's exit line in the log, and writes the reports,
screenshots and device log to -OutDir with a result.json (see
acceptance_common.ps1).

Exit codes: 0 when the suite passed, or nothing could run (no headset
connected, or the headset locked or asleep: a clean skip, said in the output),
1 when anything failed or the report is missing. What an unattended nightly
run needs from the headset is in docs/device-acceptance.md.

Runs in Windows PowerShell 5.1 with nothing beyond adb. By hand:
  powershell -ExecutionPolicy Bypass -File tools\device_acceptance.ps1 -Suite m1

.PARAMETER Suite
The suite name the game's --acceptance switch takes; `all` runs every suite,
`nightly` every suite but the manual-only soak (#812). With `soak` or `all`, pass
a -TimeoutSeconds that fits the 25-minute soak; the workflow uses 3000.
#>
[CmdletBinding()]
param(
	[string]$Suite = 'all',
	[string]$OutDir = 'build/device-acceptance/headset',
	[int]$TimeoutSeconds = 900,
	[int]$PollSeconds = 5,
	# One more on each step line; none before the first step or after the exit line.
	[int]$ScreenshotEverySeconds = 5,
	[int]$MaxScreenshots = 60,
	# A process that is gone this long after the start, with no exit line, crashed.
	[int]$StartGraceSeconds = 30,
	# A game never in the foreground this long after the start, with no step
	# line, is behind a lock screen or a system dialog: the run skips.
	[int]$ForegroundGraceSeconds = 60,
	# How long to wait for the headset to reappear on adb around an install (#589).
	[int]$DeviceWaitSeconds = 20,
	# Time for the display to come on after the wake-up key, before the lock check.
	[int]$WakeSeconds = 3,
	# Between activity lookups; one can come back empty right after an install (#1392).
	[int]$ResolveRetrySeconds = 1,
	# The headset's log buffer, raised so start-up lines survive a busy log (#599).
	[string]$LogBufferSize = '16M'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'acceptance_common.ps1')
. (Join-Path $PSScriptRoot 'acceptance_headset.ps1')
$script:deviceWaitSeconds = $DeviceWaitSeconds
$script:warnings = New-Object System.Collections.Generic.List[string]

# Overridable for testing without the network or a headset (test_device_acceptance.sh).
$releaseUrl = if ($env:MELTDOWN_RELEASE_URL) { $env:MELTDOWN_RELEASE_URL } else { 'https://github.com/noless-zz/meltdown/releases/download/main-latest' }
$apkName = 'meltdown-quest-debug.apk'
$package = 'io.github.nolesszz.meltdown'
# Godot's Android activity; asked from the package manager first. Only the
# launcher activity is exported, so only it can be started from adb (#1392).
$fallbackActivity = "$package/com.godot.game.GodotAppLauncher"
$intentExtra = 'meltdown_acceptance'

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$shotDir = Join-Path $OutDir 'screenshots'

function Stop-Run {
	param([string]$Status, [string]$Reason, $Reports, [string[]]$Table)
	Write-RunResult -OutDir $OutDir -Target 'headset' -Status $Status -Reason $Reason -Reports $Reports
	$lines = @('### Device acceptance: headset', '', "Suite ``$Suite``: **$Status**. $Reason")
	if ($Table) {
		$lines += ''
		$lines += $Table
	}
	foreach ($warning in $script:warnings) {
		$lines += ''
		$lines += "Warning: $warning"
		Write-Host "::warning title=Device acceptance::$warning"
	}
	Write-JobSummary $lines
	if ($Status -eq 'skipped') {
		Write-Host "::notice title=Device acceptance skipped::$Reason"
		exit 0
	}
	if ($Status -eq 'failed') {
		Write-Host "::error title=Device acceptance failed::$Reason"
		exit 1
	}
	exit 0
}

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
	Stop-Run 'failed' 'adb is not on the runner''s PATH (install Android platform-tools)'
}

# 1. A headset, or a clean skip.
$serials = @()
foreach ($line in ((Invoke-Adb @('devices')).Text -split "`n" | Select-Object -Skip 1)) {
	$fields = $line.Trim() -split '\s+'
	if ($fields.Count -ge 2 -and $fields[1] -eq 'device') {
		$serials += $fields[0]
	}
}
if ($serials.Count -eq 0) {
	Stop-Run 'skipped' 'No headset is connected (adb devices lists none in the device state), so nothing ran. Connect the Quest by USB or ADB over Wi-Fi and dispatch the workflow again.'
}
$script:serial = $serials[0]
Write-Host "Headset: $script:serial"
if ($serials.Count -gt 1) {
	Write-Host "More than one headset is connected; using $script:serial only."
}

# 2. The newest main build, checked against its checksum.
$work = Join-Path ([IO.Path]::GetTempPath()) ('meltdown-acceptance-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$apkPath = Join-Path $work $apkName
try {
	if ($env:MELTDOWN_APK_DIR) {
		Copy-Item -LiteralPath (Join-Path $env:MELTDOWN_APK_DIR $apkName) -Destination $apkPath
		Copy-Item -LiteralPath (Join-Path $env:MELTDOWN_APK_DIR "$apkName.sha256") -Destination "$apkPath.sha256"
	} else {
		Write-Host "Downloading $apkName from the main-latest release..."
		Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$apkName" -OutFile $apkPath
		Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$apkName.sha256" -OutFile "$apkPath.sha256"
	}
} catch {
	Stop-Run 'failed' "Could not download the build: $($_.Exception.Message)"
}
$expected = ((Get-Content -LiteralPath "$apkPath.sha256" -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
$actual = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expected -ne $actual) {
	Stop-Run 'failed' "Checksum mismatch: the release says $expected but the download is $actual. Nothing was installed; the release may have been mid-upload."
}
Write-Host "Checksum verified: $actual"

# 3. Install over the existing copy, after the headset answers on adb. A
# failure with no reason or with the headset gone is waited out and retried
# (#210, #589); see Install-Apk.
$install = Install-Apk -Path $apkPath
if (-not $install.Ok) {
	Write-Host $install.Text
	Stop-Run 'failed' "Install failed on ${script:serial}: $(Get-InstallFailureReason $install.Text). By hand: adb -s $script:serial install -r $apkName"
}
Write-Host 'Installed.'
Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue

# Said whenever the headset cannot show the game, with what an unattended run needs.
$lockAdvice = 'Put the headset on and unlock it, then run again. An unattended nightly run needs the headset left unlocked on its charger; with a lock pattern set it skips (docs/device-acceptance.md).'

# 4. Keep the headset awake for the run; the finally block below restores it.
$stayOn = (Invoke-Device @('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in')).Text.Trim()
if ($stayOn -notmatch '^\d+$') {
	$stayOn = '0'
}
$deviceLogPath = Join-Path $OutDir 'device.log'
$stream = $null
$godotLines = @()
$exitCode = $null
$shots = 0
$foregroundShots = 0
$blocked = $null
try {
	Invoke-Device @('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '7') | Out-Null
	Invoke-Device @('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP') | Out-Null
	# The proximity sensor would blank the display with nobody wearing the headset.
	Invoke-Device @('shell', 'am', 'broadcast', '-a', 'com.oculus.vrpowermanager.prox_close') | Out-Null
	Start-Sleep -Seconds $WakeSeconds

	# A locked or sleeping headset never lets the game run (#599): skip, do not hang.
	$lock = Get-HeadsetLockReason
	if ($lock) {
		Stop-Run 'skipped' "Nothing ran: $lock. $lockAdvice"
	}

	# 5. Start the game with the acceptance extra, the log cleared and streamed
	# from before the start so the engine banner and start-up lines are kept.
	$lookup = Resolve-GameActivity -Package $package -Fallback $fallbackActivity -RetrySeconds $ResolveRetrySeconds
	$activity = $lookup.Activity
	if ($lookup.Reason) {
		Write-Host "Fell back to $activity because $($lookup.Reason)."
	}
	Invoke-Device @('shell', 'am', 'force-stop', $package) | Out-Null
	if (-not (Invoke-Device @('logcat', '-G', $LogBufferSize)).Ok) {
		Write-Host "The headset refused a $LogBufferSize log buffer; keeping its own size."
	}
	Invoke-Device @('logcat', '-c') | Out-Null
	$stream = Start-LogStream -Path $deviceLogPath
	Write-Host "Starting $activity with $intentExtra=$Suite"
	$started = Invoke-Device @('shell', 'am', 'start', '-n', $activity, '--es', $intentExtra, $Suite)
	if ((Test-NotExported $started.Text) -and $activity -ne $fallbackActivity) {
		Write-Host "Android refused $activity as not exported; trying $fallbackActivity once."
		$activity = $fallbackActivity
		$started = Invoke-Device @('shell', 'am', 'start', '-n', $activity, '--es', $intentExtra, $Suite)
	}
	if (-not $started.Ok -or $started.Text -match 'Error|Exception') {
		Write-Host $started.Text
		Stop-Run 'failed' "The game did not start: $(Format-Cell $started.Text)"
	}

	# 6. Wait for the exit line. Screenshots are taken while the suite runs:
	# on each new step line and every $ScreenshotEverySeconds, never before the
	# first poll or after the exit line (the owner's first run only caught the
	# room after the game had exited, #599).
	New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
	$clock = [Diagnostics.Stopwatch]::StartNew()
	$nextShot = $ScreenshotEverySeconds
	$stepLines = 0
	$seenForeground = $false
	$crashed = $false
	while ($true) {
		$godotLines = (Invoke-Device @('logcat', '-d', '-v', 'raw', 'godot:V', '*:S')).Text -split "`n"
		$exitCode = Get-AcceptanceExitCode $godotLines
		if ($null -ne $exitCode) {
			break
		}
		$elapsed = $clock.Elapsed.TotalSeconds
		$steps = @($godotLines | Where-Object { $_ -match 'Meltdown: acceptance: step ' }).Count
		$foreground = Test-GameForeground -Package $package
		if ($foreground) {
			$seenForeground = $true
		}
		if ($shots -lt $MaxScreenshots -and ($steps -gt $stepLines -or $elapsed -ge $nextShot)) {
			$remote = '/sdcard/meltdown-acceptance.png'
			$suffix = if ($foreground) { '' } else { '-background' }
			$shot = Join-Path $shotDir ('{0:D2}-{1:D4}s{2}.png' -f ($shots + 1), [int]$elapsed, $suffix)
			if ((Invoke-Device @('shell', 'screencap', '-p', $remote)).Ok -and (Invoke-Device @('pull', $remote, $shot)).Ok) {
				$shots += 1
				if ($foreground) {
					$foregroundShots += 1
				}
			}
			Invoke-Device @('shell', 'rm', '-f', $remote) | Out-Null
			$nextShot = $elapsed + $ScreenshotEverySeconds
		}
		$stepLines = $steps
		if ($elapsed -ge $TimeoutSeconds) {
			break
		}
		if ($elapsed -ge $StartGraceSeconds -and -not (Invoke-Device @('shell', 'pidof', $package)).Ok) {
			$crashed = $true
			break
		}
		if ($elapsed -ge $ForegroundGraceSeconds -and -not $seenForeground -and $steps -eq 0) {
			$blocked = Get-HeadsetLockReason
			if (-not $blocked) {
				$blocked = 'the headset is probably locked or showing a system dialog'
			}
			$blocked = "the game never reached the foreground within $ForegroundGraceSeconds s ($blocked)"
			break
		}
		Start-Sleep -Seconds $PollSeconds
	}
} finally {
	# 7. Whatever happened: the full log, the game stopped, the headset as it was.
	Stop-LogStream -Process $stream -Path $deviceLogPath
	if (-not (Test-Path -LiteralPath $deviceLogPath) -or (Get-Item -LiteralPath $deviceLogPath).Length -eq 0) {
		# No stream (it could not start, or the run stopped before the game did):
		# what the headset's buffer still holds.
		$deviceLog = Invoke-Device @('logcat', '-d', '-v', 'threadtime')
		Write-Utf8File -Path $deviceLogPath -Text $deviceLog.Text
	}
	Invoke-Device @('shell', 'am', 'force-stop', $package) | Out-Null
	Invoke-Device @('shell', 'am', 'broadcast', '-a', 'com.oculus.vrpowermanager.automation_disable') | Out-Null
	Invoke-Device @('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', $stayOn) | Out-Null
}

if ($blocked) {
	Stop-Run 'skipped' "Nothing ran: $blocked. $lockAdvice"
}

# 8. The verdict.
Write-Host "Screenshots: $shots, $foregroundShots with the game in the foreground"
if ($foregroundShots -eq 0) {
	$script:warnings.Add("no screenshot was taken while the game was in the foreground ($shots taken); the suite may have ended before the first one, or the headset showed something else.")
}
$problems = New-Object System.Collections.Generic.List[string]
$reports = ConvertFrom-ReportBlocks -Blocks (Get-ReportBlocks $godotLines) -Problems $problems
if ($null -eq $exitCode -and $reports.Count -eq 0) {
	if ($crashed) {
		$problems.Add('the game stopped before it printed a report (see device.log)')
	} else {
		$problems.Add("no exit line within $TimeoutSeconds s and no report (see device.log)")
	}
}
$verdict = Get-RunVerdict -Reports $reports -ExitCode $exitCode -Problems $problems.ToArray()
$table = $null
if ($reports.Count -gt 0) {
	$table = Format-ResultTable @([pscustomobject]@{ target = 'headset'; status = $verdict.Status; reason = $verdict.Reason; suites = $reports })
}
Stop-Run $verdict.Status $verdict.Reason $reports $table
