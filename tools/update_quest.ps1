<#
.SYNOPSIS
Updates every connected Quest headset to the newest `main` build in one step.

.DESCRIPTION
The Windows twin of tools/update_quest.sh (DEV-8, playtest #104). Downloads
meltdown-quest-debug.apk and its .sha256 from the rolling main-latest release,
refuses to install on a checksum mismatch, and runs `adb install -r` on each
headset adb lists as `device` (USB or ADB over Wi-Fi). Builds are signed with a
stable debug key, so the update keeps saved data.

Runs in Windows PowerShell 5.1 with nothing installed beyond adb. If scripts
are blocked, run it as:
  powershell -ExecutionPolicy Bypass -File tools\update_quest.ps1

.PARAMETER Launch
Start the game on each headset after installing, without asking.

.PARAMETER UninstallFirst
If a headset holds a copy signed with another key, uninstall it and install
again. Its saved data is lost.
#>
[CmdletBinding()]
param(
	[switch]$Launch,
	[switch]$UninstallFirst
)

$ErrorActionPreference = 'Stop'
# A visible progress bar makes Invoke-WebRequest many times slower in 5.1.
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 may default to TLS 1.0, which GitHub refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# Overridable for testing without the network, as in update_quest.sh.
$releaseUrl = if ($env:MELTDOWN_RELEASE_URL) { $env:MELTDOWN_RELEASE_URL } else { 'https://github.com/noless-zz/meltdown/releases/download/main-latest' }
$releaseApi = if ($env:MELTDOWN_RELEASE_API) { $env:MELTDOWN_RELEASE_API } else { 'https://api.github.com/repos/noless-zz/meltdown/releases/tags/main-latest' }

# How long to wait for a headset to (re)appear on adb before an install
# attempt (#589). A headset just plugged in or woken drops off adb for a few
# seconds; 20 s covers that without hanging on one that is really gone.
$deviceWaitSeconds = if ($env:MELTDOWN_DEVICE_WAIT_SECONDS) { [int]$env:MELTDOWN_DEVICE_WAIT_SECONDS } else { 20 }
# Retries after a failure with no reason, `not found` or `offline` (#589).
$installRetries = 2

$apkName = 'meltdown-quest-debug.apk'
$package = 'io.github.nolesszz.meltdown'

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
	Write-Host 'Missing required tool: adb (install Android platform-tools and add it to PATH)' -ForegroundColor Red
	exit 1
}

# Runs adb and returns its output as text plus whether it succeeded. adb writes
# to stderr on failure, which 5.1 would turn into a terminating error under
# 'Stop', so errors are collected as text here instead.
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
	return [pscustomobject]@{ Ok = $ok; Text = ($lines -join "`n") }
}

# Waits up to $deviceWaitSeconds for adb to list the headset again, then runs a
# trivial shell command to wake the connection (#589). `adb wait-for-device`
# has no timeout of its own, so it runs as a process that is stopped when time
# is up. Returns whether the headset answered.
function Wait-Device {
	param([string]$Serial)
	$info = New-Object System.Diagnostics.ProcessStartInfo
	$info.FileName = (Get-Command adb).Path
	$info.Arguments = "-s $Serial wait-for-device"
	$info.UseShellExecute = $false
	$info.CreateNoWindow = $true
	$process = [System.Diagnostics.Process]::Start($info)
	if (-not $process.WaitForExit($deviceWaitSeconds * 1000)) {
		try { $process.Kill() } catch { }
		return $false
	}
	if ($process.ExitCode -ne 0) {
		return $false
	}
	return (Invoke-Adb @('-s', $Serial, 'shell', 'true')).Ok
}

# adb's text when the headset was not on adb at that moment (#589).
function Test-DroppedOff {
	param([string]$Text)
	return ($Text -match "device( '[^']*')? not found|device offline|did not come back")
}

# A failure with no `Failure [...]` part (#210), or with the headset `not found`
# or `offline` (#589), is the headset dropping off adb for a moment after being
# plugged in or woken. So it waits for the headset and retries without
# streaming, up to $installRetries times. A failure with a reason is not
# retried: the reason will not change. Returns the last attempt's result.
function Install-Apk {
	param([string]$Serial, [string]$Path)
	$result = Invoke-Adb @('-s', $Serial, 'install', '-r', $Path)
	for ($attempt = 1; $attempt -le $installRetries; $attempt++) {
		if ($result.Ok -or $result.Text -match 'Failure \[') {
			return $result
		}
		if (Test-DroppedOff $result.Text) {
			Write-Host '  The headset dropped off USB for a moment; waiting for it, then trying again with --no-streaming...' -ForegroundColor Yellow
		} else {
			Write-Host '  adb gave no reason; waiting for the headset, then trying again with --no-streaming...' -ForegroundColor Yellow
		}
		if (-not (Wait-Device -Serial $Serial)) {
			return [pscustomobject]@{ Ok = $false; Text = ($result.Text + "`nThe headset did not come back within $deviceWaitSeconds s.") }
		}
		$result = Invoke-Adb @('-s', $Serial, 'install', '-r', '--no-streaming', $Path)
	}
	return $result
}

# Always ends with adb's reason, or a plain statement that it gave none, and
# the command to try by hand.
function Write-InstallFailure {
	param([string]$Serial, [string]$Path, [string]$Text)
	Write-Host "  Install failed on ${Serial}:" -ForegroundColor Red
	foreach ($line in ($Text -split "`n")) {
		Write-Host "    $line"
	}
	$match = [regex]::Match($Text, 'Failure \[.*\]')
	if ($match.Success) {
		Write-Host "  Reason: $($match.Value)" -ForegroundColor Red
	} elseif (Test-DroppedOff $Text) {
		Write-Host '  Reason: the headset dropped off USB for a moment and was not back in time.' -ForegroundColor Red
		Write-Host '  Check the cable and that the headset is awake, then run this again.' -ForegroundColor Red
	} else {
		Write-Host '  adb gave no reason.' -ForegroundColor Red
	}
	Write-Host "  To try by hand: adb -s $Serial install -r `"$Path`""
}

# Checked before downloading so a forgotten cable fails in a second.
$serials = @()
$list = Invoke-Adb @('devices')
foreach ($line in ($list.Text -split "`n" | Select-Object -Skip 1)) {
	$fields = $line.Trim() -split '\s+'
	if ($fields.Count -ge 2 -and $fields[1] -eq 'device') {
		$serials += $fields[0]
	}
}
if ($serials.Count -eq 0) {
	Write-Host 'No headset found. Connect one by USB (and allow USB debugging in the headset),' -ForegroundColor Red
	Write-Host "or over Wi-Fi with 'adb connect <headset-ip>:5555', then check 'adb devices'." -ForegroundColor Red
	exit 1
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('meltdown-update-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$exitCode = 0
# Kept after a failed install so the printed manual command has a file to use.
$keepDownload = $false
try {
	$apkPath = Join-Path $work $apkName
	$shaPath = "$apkPath.sha256"
	Write-Host "Downloading $apkName from the main-latest release..."
	Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$apkName" -OutFile $apkPath
	Invoke-WebRequest -UseBasicParsing -Uri "$releaseUrl/$apkName.sha256" -OutFile $shaPath

	$expected = ((Get-Content -Path $shaPath -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
	$actual = (Get-FileHash -Path $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
	if ($expected -ne $actual) {
		Write-Host "Checksum mismatch: the release says $expected but the download is $actual." -ForegroundColor Red
		Write-Host 'Nothing was installed. Try again in a few minutes; the release may be mid-upload.' -ForegroundColor Red
		# exit still runs the finally block below, which removes the download.
		exit 1
	}
	Write-Host "Checksum verified: $actual"

	# The release body (tools/release_notes.sh) names the commit and build time.
	# Only for these two lines, so a failure here does not stop the update.
	$commit = 'unknown'
	$built = 'Built: unknown'
	try {
		$release = Invoke-RestMethod -UseBasicParsing -Uri $releaseApi
		$match = [regex]::Match([string]$release.body, 'commit ([0-9a-f]{40})')
		if ($match.Success) { $commit = $match.Groups[1].Value }
		$match = [regex]::Match([string]$release.body, 'Built: [^\r\n]*')
		if ($match.Success) { $built = $match.Value }
	} catch {
		Write-Host 'Could not read the release text; the update goes ahead.' -ForegroundColor Yellow
	}

	$installed = @()
	foreach ($serial in $serials) {
		Write-Host "Installing on $serial..."
		# Wakes the connection first: the first install after plugging in or
		# waking the headset used to land in its drop-off gap (#589). A headset
		# that does not answer still gets the install attempt and its retries.
		Wait-Device -Serial $serial | Out-Null
		$result = Install-Apk -Serial $serial -Path $apkPath
		if (-not $result.Ok -and $result.Text -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
			Write-Host "  The copy on $serial has a different signature, so it cannot be updated in place." -ForegroundColor Yellow
			if (-not $UninstallFirst) {
				Write-Host '  Run again with -UninstallFirst to remove it and install (saved data is lost).' -ForegroundColor Yellow
				$exitCode = 1
				continue
			}
			Write-Host '  Uninstalling it first; its saved data is lost.' -ForegroundColor Yellow
			Invoke-Adb @('-s', $serial, 'uninstall', $package) | Out-Null
			$result = Install-Apk -Serial $serial -Path $apkPath
		}
		if ($result.Ok) {
			$installed += $serial
			Write-Host '  Installed.'
		} else {
			Write-InstallFailure -Serial $serial -Path $apkPath -Text $result.Text
			$keepDownload = $true
			$exitCode = 1
		}
	}
	if ($keepDownload) {
		Write-Host "The download is kept in $work for that; delete the folder when done." -ForegroundColor Yellow
	}

	Write-Host ''
	Write-Host "Build: commit $commit"
	Write-Host $built

	if ($installed.Count -gt 0) {
		$start = [bool]$Launch
		if (-not $Launch -and -not $UninstallFirst) {
			$answer = Read-Host 'Start the game on the headset now? [y/N]'
			$start = ($answer -match '^(y|yes)$')
		}
		if ($start) {
			foreach ($serial in $installed) {
				Write-Host "Starting the game on $serial..."
				Invoke-Adb @('-s', $serial, 'shell', 'monkey', '-p', $package, '-c', 'android.intent.category.LAUNCHER', '1') | Out-Null
			}
		}
	}
} finally {
	if (-not $keepDownload) {
		Remove-Item -Recurse -Force -Path $work -ErrorAction SilentlyContinue
	}
}
exit $exitCode
