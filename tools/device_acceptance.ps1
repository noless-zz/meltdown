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

After an adb drop (the headset resets its USB, #1436) it waits for the
headset to come back on cable or Wi-Fi before deciding anything, and at the
end reads the reports the game left in its own storage, so a lost log stream
does not lose results.

Exit codes: 0 when the suite passed, or nothing could run (no headset
connected, or the headset locked or asleep: a clean skip, said in the output),
1 when anything failed or the report is missing. What an unattended nightly
run needs from the headset is in docs/device-acceptance.md.

Runs in Windows PowerShell 5.1 with nothing beyond adb. By hand:
  powershell -ExecutionPolicy Bypass -File tools\device_acceptance.ps1 -Suite m1

.PARAMETER Serial
The headset to use when more than one is listed; ANDROID_SERIAL when not given.

.PARAMETER Unattended
Nobody wears the headset: m0's controllers_bound step skips, not fails, when the
controllers are asleep. Also on for scheduled workflow runs and `-Suite nightly`.

.PARAMETER Force
Install even when the headset already holds the release's build. Without it,
the download and install are skipped when the checksum of the APK on the
headset equals the release's (#1437). Also MELTDOWN_FORCE_INSTALL=1.

.PARAMETER Suite
The suite name the game's --acceptance switch takes; `all` runs every suite,
`nightly` every suite but the manual-only soak (#812). Each runs to its end in
one command: the wait for the exit line comes from the suites asked for.

.PARAMETER TimeoutSeconds
How long to wait for the game's exit line. 0 (the default) works it out from the
suites asked for: the sum of their steps' time limits plus a margin
(acceptance_wait.ps1, #1504). Any other value is used as given.
#>
[CmdletBinding()]
param(
	[string]$Suite = 'all',
	[string]$OutDir = 'build/device-acceptance/headset',
	# 0: the sum of the suites' step time limits plus a margin (#1504).
	[int]$TimeoutSeconds = 0,
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
	[string]$LogBufferSize = '16M',
	[string]$Serial = '',
	[switch]$Unattended,
	# How long to wait for the headset after an adb drop before giving up (#1436).
	[int]$ReconnectSeconds = 300,
	[int]$ReconnectPollSeconds = 2,
	# Install even when the headset already has this build (#1437); also MELTDOWN_FORCE_INSTALL=1.
	[switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

. (Join-Path $PSScriptRoot 'acceptance_common.ps1')
. (Join-Path $PSScriptRoot 'acceptance_headset.ps1')
. (Join-Path $PSScriptRoot 'acceptance_recover.ps1')
. (Join-Path $PSScriptRoot 'apk_cache.ps1')
. (Join-Path $PSScriptRoot 'acceptance_progress.ps1')
. (Join-Path $PSScriptRoot 'acceptance_wait.ps1')
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

# A fixed 900 s cut the nightly suite off in m3 (#1504): the wait follows the suites asked for.
if ($TimeoutSeconds -le 0) {
	$wait = Get-AcceptanceWait -Suite $Suite -GameDir (Join-Path (Split-Path -Parent $PSScriptRoot) 'game')
	$TimeoutSeconds = $wait.Seconds
	Write-Host (Format-AcceptanceWaitLine $wait)
}

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
$serials = Get-AdbSerials
if ($serials.Count -eq 0) {
	Stop-Run 'skipped' 'No headset is connected (adb devices lists none in the device state), so nothing ran. Connect the Quest by USB or ADB over Wi-Fi and dispatch the workflow again.'
}
$namedBy = if ($Serial) { '-Serial' } else { 'ANDROID_SERIAL' }
$choice = Select-Headset -Serials $serials -Named $(if ($Serial) { $Serial } else { $env:ANDROID_SERIAL }) -NamedBy $namedBy
if (-not $choice.Serial) {
	Stop-Run 'skipped' "Nothing ran: $($choice.Note)"
}
$script:serial = $choice.Serial
Write-Host "Headset: $script:serial"
if ($choice.Note) {
	Write-Host $choice.Note
}
# Said in the PR for #1436: a scheduled workflow run or the nightly suite has nobody wearing the headset.
$unattendedRun = $Unattended -or $env:GITHUB_EVENT_NAME -eq 'schedule' -or $Suite -eq 'nightly'
$startExtras = @('--es', $intentExtra, $Suite)
if ($unattendedRun) {
	$startExtras += @('--es', 'meltdown_unattended', '1')
	Write-Host 'Unattended run: controllers asleep in m0/controllers_bound are reported skipped.'
}

# 2. The newest main build, unless the headset already holds it (#1437): only
# the release's checksum is read first. Any doubt installs.
$forceInstall = Test-ForceInstall ([bool]$Force)
$expected = Get-ReleaseChecksum -ReleaseUrl $releaseUrl -LocalDir $env:MELTDOWN_APK_DIR -Name $apkName
$current = $false
if (-not $forceInstall -and $expected -and (Wait-Device)) {
	$current = Test-HeadsetHasBuild -Serial $script:serial -Expected $expected
}
if ($current) {
	Write-Host (Format-SkipLine -Serial $script:serial -Checksum $expected)
} else {
	if ($forceInstall) {
		Write-Host 'Installing whatever the headset holds (-Force or MELTDOWN_FORCE_INSTALL=1).'
	}
	# Checked against its checksum, and kept for a rerun (see Get-CachedApk).
	$apk = Get-CachedApk -Expected $expected -ReleaseUrl $releaseUrl -LocalDir $env:MELTDOWN_APK_DIR -Name $apkName
	if ($apk.Problem) {
		Stop-Run 'failed' $apk.Problem
	}

	# 3. Install over the existing copy, after the headset answers on adb. A
	# failure with no reason or with the headset gone is waited out and retried
	# (#210, #589); see Install-Apk.
	$install = Install-Apk -Path $apk.Path
	if (-not $install.Ok) {
		Write-Host $install.Text
		Stop-Run 'failed' "Install failed on ${script:serial}: $(Get-InstallFailureReason $install.Text). By hand: adb -s $script:serial install -r `"$($apk.Path)`""
	}
	Write-Host 'Installed.'
}

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
$dropped = $null
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
	Clear-HeadsetReports -Package $package | Out-Null
	$stream = Start-LogStream -Path $deviceLogPath
	Write-Host "Starting $activity with $intentExtra=$Suite"
	$started = Invoke-Device (@('shell', 'am', 'start', '-n', $activity) + $startExtras)
	if ((Test-NotExported $started.Text) -and $activity -ne $fallbackActivity) {
		Write-Host "Android refused $activity as not exported; trying $fallbackActivity once."
		$activity = $fallbackActivity
		$started = Invoke-Device (@('shell', 'am', 'start', '-n', $activity) + $startExtras)
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
	# A line as each step starts and ends, for whoever watches the headset picture (#1438).
	$progress = New-ProgressState -Suite $Suite
	$nextShot = $ScreenshotEverySeconds
	$stepLines = 0
	$seenForeground = $false
	$crashed = $false
	while ($true) {
		$poll = Invoke-Device @('logcat', '-d', '-v', 'raw', 'godot:V', '*:S')
		if ($poll.Ok) {
			$godotLines = $poll.Text -split "`n"
			Write-ProgressLines (Get-ProgressLines -State $progress -Lines $godotLines -Elapsed $clock.Elapsed.TotalSeconds)
		} elseif (-not (Test-DeviceReachable)) {
			# An adb that cannot reach the headset is not a crash (#1436): wait for it.
			if ($dropped = Resume-AfterDrop $ReconnectSeconds $ReconnectPollSeconds $clock) { break }
			continue
		}
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
			$suffix = if ($foreground) { '' } else { '-background' }
			if (Save-Screenshot (Join-Path $shotDir ('{0:D2}-{1:D4}s{2}.png' -f ($shots + 1), [int]$elapsed, $suffix))) {
				$shots += 1
				$foregroundShots += [int]$foreground
			}
			$nextShot = $elapsed + $ScreenshotEverySeconds
		}
		$stepLines = $steps
		if ($elapsed -ge $TimeoutSeconds) {
			break
		}
		if ($elapsed -ge $StartGraceSeconds -and -not (Invoke-Device @('shell', 'pidof', $package)).Ok) {
			if (Test-DeviceReachable) {
				$crashed = $true
				break
			}
			if ($dropped = Resume-AfterDrop $ReconnectSeconds $ReconnectPollSeconds $clock) { break }
			continue
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
	} elseif ($script:drops -gt 0 -and -not $dropped) {
		# The stream ended at the drop; the headset's buffer still holds the rest.
		$rest = Invoke-Device @('logcat', '-d', '-v', 'threadtime')
		Add-Utf8File -Path $deviceLogPath -Text ("`n--- the stream ended at an adb drop; the headset's log buffer at the end ---`n" + $rest.Text)
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
$outcome = Get-HeadsetOutcome -Lines $godotLines -ExitCode $exitCode -Dropped $dropped -Crashed $crashed `
	-Package $package -OutDir $OutDir -Suite $Suite -TimeoutSeconds $TimeoutSeconds -ReconnectSeconds $ReconnectSeconds
$table = $null
if ($outcome.Reports.Count -gt 0) {
	$table = Format-ResultTable @([pscustomobject]@{ target = 'headset'; status = $outcome.Status; reason = $outcome.Reason; suites = $outcome.Reports })
}
Stop-Run $outcome.Status $outcome.Reason $outcome.Reports $table
