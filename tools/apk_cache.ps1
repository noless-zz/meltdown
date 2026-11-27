<#
The build check and download cache shared by update_quest.ps1 and
device_acceptance.ps1 (#1437, DEV-6, DEV-8). Rerunning a suite or an update
used to download and install the whole APK every time, even when the headset
already held that exact build.

- Get-ReleaseChecksum reads only the release's .sha256 (a few bytes).
- Test-HeadsetHasBuild compares it with the base.apk the headset holds. Any
  doubt (no package, a failed adb call, an unreadable answer) means install.
- Get-CachedApk keeps one verified APK per checksum under the temp folder, so a
  second headset or a rerun after a failed install does not download again.

Needs the caller's Invoke-Adb (both callers define one with the same shape).
Runs in Windows PowerShell 5.1 and PowerShell 7.
#>

$script:apkPackage = 'io.github.nolesszz.meltdown'

# The digest from the first non-empty line of `sha256sum` output, lowercase, or
# $null when that line does not start with one.
function Get-Sha256FromText {
	param([string]$Text)
	foreach ($line in ($Text -split "`r?`n")) {
		$field = ($line.Trim() -split '\s+')[0]
		if (-not $field) {
			continue
		}
		# sha256sum prefixes the line with a backslash when it escapes the file name.
		$digest = $field.TrimStart('\').ToLowerInvariant()
		if ($digest -match '^[0-9a-f]{64}$') {
			return $digest
		}
		return $null
	}
	return $null
}

# -Force or MELTDOWN_FORCE_INSTALL=1: install even when the headset has the build.
function Test-ForceInstall {
	param([bool]$Force)
	return ($Force -or $env:MELTDOWN_FORCE_INSTALL -eq '1')
}

# The checksum the release publishes for $Name, from $LocalDir in tests, or
# $null when it cannot be read.
function Get-ReleaseChecksum {
	param([string]$ReleaseUrl, [string]$LocalDir, [string]$Name)
	$temp = Join-Path ([IO.Path]::GetTempPath()) ('meltdown-sha-' + [Guid]::NewGuid().ToString('N'))
	try {
		if ($LocalDir) {
			$text = Get-Content -Raw -LiteralPath (Join-Path $LocalDir "$Name.sha256")
		} else {
			# To a file: 5.1 and 7 disagree on whether an octet-stream body is text.
			Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseUrl/$Name.sha256" -OutFile $temp
			$text = Get-Content -Raw -LiteralPath $temp
		}
		return Get-Sha256FromText ([string]$text)
	} catch {
		return $null
	} finally {
		Remove-Item -Force -LiteralPath $temp -ErrorAction SilentlyContinue
	}
}

# The checksum of the build installed on the headset, or $null when the package
# is missing or anything about the answer is unclear.
function Get-HeadsetApkChecksum {
	param([string]$Serial)
	$paths = Invoke-Adb @('-s', $Serial, 'shell', 'pm', 'path', $script:apkPackage)
	if (-not $paths.Ok) {
		return $null
	}
	$base = $null
	foreach ($line in ($paths.Text -split "`r?`n")) {
		if ($line.Trim() -match '^package:(/\S*/base\.apk)$') {
			$base = $Matches[1]
			break
		}
	}
	if (-not $base) {
		return $null
	}
	$sum = Invoke-Adb @('-s', $Serial, 'shell', 'sha256sum', $base)
	if (-not $sum.Ok) {
		return $null
	}
	return Get-Sha256FromText $sum.Text
}

# Whether the headset holds exactly the build whose checksum is $Expected.
# Never true on doubt: an unknown release checksum or headset checksum is false.
function Test-HeadsetHasBuild {
	param([string]$Serial, [string]$Expected)
	if (-not $Expected) {
		return $false
	}
	$installed = Get-HeadsetApkChecksum -Serial $Serial
	return ([bool]$installed -and $installed -eq $Expected)
}

# The line said when an install is skipped.
function Format-SkipLine {
	param([string]$Serial, [string]$Checksum, [string]$Commit)
	$build = if ($Commit -and $Commit -match '^[0-9a-f]{7,}$') { "build $($Commit.Substring(0, 7))" } else { 'this build' }
	return "Headset $Serial already has $build (checksum $($Checksum.Substring(0, 12)) matches); skipping download and install."
}

function Get-ApkCacheRoot {
	return (Join-Path ([IO.Path]::GetTempPath()) 'meltdown-apk-cache')
}

function Get-FileSha256 {
	param([string]$Path)
	return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# Downloads the APK at $Path (or copies it from $LocalDir, for tests) with its
# .sha256 and checks one against the other. Returns $null when it matches, else
# the reason, and then nothing must be installed.
function Get-CheckedApk {
	param([string]$Path, [string]$ReleaseUrl, [string]$LocalDir)
	$name = Split-Path -Leaf $Path
	New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
	try {
		if ($LocalDir) {
			Copy-Item -LiteralPath (Join-Path $LocalDir $name) -Destination $Path
			Copy-Item -LiteralPath (Join-Path $LocalDir "$name.sha256") -Destination "$Path.sha256"
		} else {
			Write-Host "Downloading $name from the main-latest release..."
			Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseUrl/$name" -OutFile $Path
			Invoke-WebRequest -UseBasicParsing -Uri "$ReleaseUrl/$name.sha256" -OutFile "$Path.sha256"
		}
	} catch {
		return "Could not download the build: $($_.Exception.Message)"
	}
	$expected = ((Get-Content -LiteralPath "$Path.sha256" -TotalCount 1) -split '\s+')[0].ToLowerInvariant()
	$actual = Get-FileSha256 $Path
	if ($expected -ne $actual) {
		return "Checksum mismatch: the release says $expected but the download is $actual. Nothing was installed; the release may have been mid-upload."
	}
	Write-Host "Checksum verified: $actual"
	return $null
}

# The release APK, verified, at <cache>/<checksum>/<name>. A cached copy whose
# checksum is $Expected is used without downloading; otherwise it is downloaded
# and checked as before. Older builds in the cache are deleted. Returns Path
# (empty on failure), Checksum and Problem (the reason, or $null).
function Get-CachedApk {
	param([string]$Expected, [string]$ReleaseUrl, [string]$LocalDir, [string]$Name)
	$root = Get-ApkCacheRoot
	New-Item -ItemType Directory -Force -Path $root | Out-Null
	$path = $null
	$checksum = $null
	if ($Expected) {
		$cached = Join-Path (Join-Path $root $Expected) $Name
		if ((Test-Path -LiteralPath $cached) -and (Get-FileSha256 $cached) -eq $Expected) {
			Write-Host "Using the copy already downloaded ($($Expected.Substring(0, 12)))."
			$path = $cached
			$checksum = $Expected
		}
	}
	if (-not $path) {
		$partial = Join-Path $root ('partial-' + [Guid]::NewGuid().ToString('N'))
		$download = Join-Path $partial $Name
		$problem = Get-CheckedApk -Path $download -ReleaseUrl $ReleaseUrl -LocalDir $LocalDir
		if ($problem) {
			Remove-Item -Recurse -Force -LiteralPath $partial -ErrorAction SilentlyContinue
			return [pscustomobject]@{ Path = ''; Checksum = $null; Problem = $problem }
		}
		# Named by what was downloaded: the release may have moved on since
		# $Expected was read, and the folder must name its own contents.
		$checksum = Get-FileSha256 $download
		$folder = Join-Path $root $checksum
		Remove-Item -Recurse -Force -LiteralPath $folder -ErrorAction SilentlyContinue
		Move-Item -LiteralPath $partial -Destination $folder
		$path = Join-Path $folder $Name
	}
	# Another run's download in progress is left alone unless it is old enough
	# to be a leftover.
	$stale = (Get-Date).AddHours(-1)
	foreach ($entry in (Get-ChildItem -LiteralPath $root -Directory)) {
		if ($entry.Name -like 'partial-*' -and $entry.LastWriteTime -gt $stale) {
			continue
		}
		if ($entry.Name -ne $checksum) {
			Remove-Item -Recurse -Force -LiteralPath $entry.FullName -ErrorAction SilentlyContinue
		}
	}
	return [pscustomobject]@{ Path = $path; Checksum = $checksum; Problem = $null }
}
