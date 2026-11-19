<#
adb helpers for the headset half of device acceptance (#154, #599). Dot-sourced
by device_acceptance.ps1 after it sets $script:serial and
$script:deviceWaitSeconds. Runs in Windows PowerShell 5.1 and PowerShell 7.
#>

$script:installRetries = 2

# adb with its output as text and whether it succeeded. Errors are collected as
# text because 5.1 would turn adb's stderr into a terminating error under 'Stop'.
function Invoke-Adb {
	param([string[]]$AdbArgs)
	$previous = $ErrorActionPreference
	$ErrorActionPreference = 'Continue'
	try {
		$lines = & adb @AdbArgs 2>&1 | ForEach-Object { "$_" }
		$ok = ($LASTEXITCODE -eq 0)
	} finally {
		$ErrorActionPreference = $previous
	}
	return [pscustomobject]@{ Ok = $ok; Text = (@($lines) -join "`n") }
}

function Invoke-Device {
	param([string[]]$AdbArgs)
	return Invoke-Adb (@('-s', $script:serial) + $AdbArgs)
}

# Waits up to $script:deviceWaitSeconds for adb to list the headset, then runs a
# trivial shell command to wake the connection. A Quest just plugged in or
# woken drops off adb for a few seconds (#589, as in update_quest.ps1).
# `adb wait-for-device` has no timeout of its own, so it runs as a process that
# is stopped when time is up. Returns whether the headset answered.
function Wait-Device {
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = (Get-Command adb).Path
	$info.Arguments = "-s $script:serial wait-for-device"
	$info.UseShellExecute = $false
	$info.CreateNoWindow = $true
	$process = [System.Diagnostics.Process]::Start($info)
	if (-not $process.WaitForExit($script:deviceWaitSeconds * 1000)) {
		try { $process.Kill() } catch { }
		return $false
	}
	if ($process.ExitCode -ne 0) {
		return $false
	}
	return (Invoke-Device @('shell', 'true')).Ok
}

# adb's text when the headset was not on adb at that moment (#589).
function Test-DroppedOff {
	param([string]$Text)
	return ($Text -match "device( '[^']*')? not found|device offline|did not come back")
}

# A failure with no `Failure [...]` part (#210), or with the headset `not found`
# or `offline` (#589), is the headset dropping off adb for a moment. So it waits
# for the headset and retries without streaming, up to $script:installRetries
# times. A failure with a reason is not retried: the reason will not change.
function Install-Apk {
	param([string]$Path)
	if (-not (Wait-Device)) {
		return [pscustomobject]@{ Ok = $false; Text = "The headset did not come back within $script:deviceWaitSeconds s." }
	}
	$result = Invoke-Device @('install', '-r', $Path)
	for ($attempt = 1; $attempt -le $script:installRetries; $attempt++) {
		if ($result.Ok -or $result.Text -match 'Failure \[') {
			return $result
		}
		if (Test-DroppedOff $result.Text) {
			Write-Host 'The headset dropped off USB for a moment; waiting for it, then trying again with --no-streaming.'
		} else {
			Write-Host 'Install failed without a reason; waiting for the headset, then trying again with --no-streaming.'
		}
		if (-not (Wait-Device)) {
			return [pscustomobject]@{ Ok = $false; Text = ($result.Text + "`nThe headset did not come back within $script:deviceWaitSeconds s.") }
		}
		$result = Invoke-Device @('install', '-r', '--no-streaming', $Path)
	}
	return $result
}

# The one-line reason an install failed, for the report.
function Get-InstallFailureReason {
	param([string]$Text)
	$reason = [regex]::Match($Text, 'Failure \[[^\]]*\]').Value
	if ($reason) {
		return $reason
	}
	if (Test-DroppedOff $Text) {
		return 'the headset dropped off USB for a moment and was not back in time; check the cable and that the headset is awake'
	}
	return 'adb gave no reason'
}

# Why the headset cannot show the game right now, or $null. Asleep or dozing
# comes from `dumpsys power`; a lock screen from the keyguard flags `dumpsys
# window` prints. The Quest's own lock may not set those flags, which is why
# the run also gives up when the game never reaches the foreground.
function Get-HeadsetLockReason {
	$power = (Invoke-Device @('shell', 'dumpsys', 'power')).Text
	if ($power -match 'mWakefulness=(Asleep|Dozing)') {
		return "the headset is asleep ($($Matches[1].ToLowerInvariant()))"
	}
	$window = (Invoke-Device @('shell', 'dumpsys', 'window')).Text
	if ($window -match '(isKeyguardShowing|mShowingLockscreen|mDreamingLockscreen|mKeyguardShowing)=true') {
		return 'the headset is locked'
	}
	return $null
}

# Whether the game's activity is the resumed (foreground) one.
function Test-GameForeground {
	param([string]$Package)
	$activities = (Invoke-Device @('shell', 'dumpsys', 'activity', 'activities')).Text
	foreach ($line in ($activities -split "`n")) {
		if ($line -match 'ResumedActivity' -and $line.Contains("$Package/")) {
			return $true
		}
	}
	return $false
}

# The whole device log streamed to a file from before the game starts, so the
# engine banner and start-up lines are kept however busy the headset's log
# buffer is (#599). Returns the process, or $null if it could not start.
function Start-LogStream {
	param([string]$Path)
	try {
		return Start-Process -FilePath (Get-Command adb).Path -NoNewWindow -PassThru `
			-ArgumentList @('-s', $script:serial, 'logcat', '-v', 'threadtime') `
			-RedirectStandardOutput $Path -RedirectStandardError "$Path.err"
	} catch {
		Write-Host "Could not stream the device log: $($_.Exception.Message)"
		return $null
	}
}

function Stop-LogStream {
	param($Process, [string]$Path)
	if ($null -ne $Process) {
		try {
			if (-not $Process.HasExited) {
				$Process.Kill()
			}
			$Process.WaitForExit(5000) | Out-Null
		} catch { }
	}
	Remove-Item -LiteralPath "$Path.err" -ErrorAction SilentlyContinue
}
