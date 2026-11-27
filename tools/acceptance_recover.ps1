<#
What device_acceptance.ps1 can still learn when the log stream was lost (#1436).
Dot-sourced after acceptance_common.ps1 and acceptance_headset.ps1. Runs in
Windows PowerShell 5.1 and PowerShell 7.

The game writes each suite's report to its own storage (user://acceptance,
acceptance_runner.gd), and, from #1444 on, `acceptance_exit.json` when the run
ends. A debuggable build lets `run-as` read that folder, so the reports
survive an adb drop that cuts the log. Without them, the step lines the
script saw still give a partial table that says it is partial.
#>

$script:StorageDir = 'files/acceptance'
$script:ExitFileName = 'acceptance_exit.json'
$script:StepPattern = 'Meltdown: acceptance: step (\S+)(.*)$'

# Removes the reports earlier runs left, so what is there at the end is this run's.
function Clear-HeadsetReports {
	param([string]$Package)
	return (Invoke-Device @('shell', 'run-as', $Package, 'rm', '-rf', $script:StorageDir)).Ok
}

# Copies every .json in the game's storage to $Dir. Returns Reports (suite
# reports, oldest first), Exit (acceptance_exit.json, or $null) and Note (why
# nothing could be read, or $null).
function Get-HeadsetReports {
	param([string]$Package, [string]$Dir, [System.Collections.Generic.List[string]]$Problems)
	$found = [pscustomobject]@{ Reports = @(); Exit = $null; Note = $null }
	$listing = Invoke-Device @('shell', 'run-as', $Package, 'ls', '-tr', $script:StorageDir)
	if (-not $listing.Ok) {
		$found.Note = "the game's storage could not be read ($(Format-Cell $listing.Text))"
		return $found
	}
	$names = @($listing.Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[\w.-]+\.json$' })
	if ($names.Count -gt 0) {
		New-Item -ItemType Directory -Force -Path $Dir | Out-Null
	}
	foreach ($name in $names) {
		$read = Invoke-Device @('exec-out', 'run-as', $Package, 'cat', "$($script:StorageDir)/$name")
		if (-not $read.Ok) {
			$Problems.Add("$name could not be read from the headset")
			continue
		}
		Write-Utf8File -Path (Join-Path $Dir $name) -Text $read.Text
		try {
			$data = $read.Text | ConvertFrom-Json
		} catch {
			$Problems.Add("$name on the headset is not valid JSON")
			continue
		}
		if ($name -eq $script:ExitFileName) {
			$found.Exit = $data
		} else {
			$found.Reports += $data
		}
	}
	return $found
}

# The logged reports, then any stored report for a suite the log did not hold.
function Merge-Reports {
	param($Logged, $Stored)
	$merged = @($Logged)
	$seen = @($Logged | ForEach-Object { [string]$_.suite })
	foreach ($report in $Stored) {
		if ($seen -notcontains [string]$report.suite) {
			$merged += $report
			$seen += [string]$report.suite
		}
	}
	return , $merged
}

# The exit code acceptance_exit.json stands for: its `exit_code` (or `exit`)
# field, else 0 when it counts no failed suite and 1 when it does.
function Get-ExitFileCode {
	param($Exit)
	if ($null -eq $Exit) {
		return $null
	}
	foreach ($field in @('exit_code', 'exit')) {
		$property = $Exit.PSObject.Properties[$field]
		if ($property -and "$($property.Value)" -match '^-?\d+$') {
			return [int]$property.Value
		}
	}
	$failed = $Exit.PSObject.Properties['failed']
	if ($failed) {
		$count = if ($failed.Value -is [array]) { $failed.Value.Count } else { [int]$failed.Value }
		return [int]($count -gt 0)
	}
	return $null
}

# The steps the log shows after its last report: the suite that was running
# when the log ended, as a report marked partial, or $null when there are none.
# The suite is the line's `suite=` field (#1444), else $Suite when a single
# suite was asked for, else "unknown".
function Get-UnreportedSteps {
	param([string[]]$Lines, [string]$Suite)
	$steps = New-Object System.Collections.Generic.List[object]
	$name = if ($Suite -in @('all', 'nightly')) { 'unknown' } else { $Suite }
	foreach ($raw in $Lines) {
		$line = [string]$raw
		if ($line.IndexOf($script:ReportEnd) -ge 0) {
			$steps.Clear()
			continue
		}
		$match = [regex]::Match($line, $script:StepPattern)
		if (-not $match.Success) {
			continue
		}
		$id = $match.Groups[1].Value
		$result = $null
		foreach ($token in ($match.Groups[2].Value.Trim() -split '\s+')) {
			if ($token -in @('pass', 'fail', 'skipped')) {
				$result = $token
			} elseif ($token -match '^suite=(\S+)$') {
				$name = $Matches[1]
			}
		}
		$last = if ($steps.Count -gt 0) { $steps[$steps.Count - 1] } else { $null }
		if ($last -and $last.id -eq $id -and $last.result -eq 'no result') {
			$steps.RemoveAt($steps.Count - 1)
		}
		if ($result) {
			$steps.Add([pscustomobject]@{ id = $id; result = $result; message = 'from the log line only' })
		} else {
			$steps.Add([pscustomobject]@{ id = $id; result = 'no result'; message = 'running when the log ended' })
		}
	}
	if ($steps.Count -eq 0) {
		return $null
	}
	return [pscustomobject]@{ suite = $name; partial = $true; steps = $steps.ToArray() }
}

# The run's status, reason and reports, from the log and the game's storage.
# A connection that dropped and never came back says so instead of judging the
# steps from a partial log; with no exit line and no exit file, the last
# suite's steps come from the step lines and the reason says the table is partial.
function Get-HeadsetOutcome {
	param([string[]]$Lines, $ExitCode, [string]$Dropped, [bool]$Crashed, [string]$Package, [string]$OutDir,
		[string]$Suite, [int]$TimeoutSeconds, [int]$ReconnectSeconds)
	$problems = New-Object System.Collections.Generic.List[string]
	$logged = ConvertFrom-ReportBlocks -Blocks (Get-ReportBlocks $Lines) -Problems $problems
	$stored = [pscustomobject]@{ Reports = @(); Exit = $null; Note = 'the headset was not back to read them' }
	if (-not $Dropped) {
		$stored = Get-HeadsetReports -Package $Package -Dir (Join-Path $OutDir 'from-headset') -Problems $problems
	}
	if ($stored.Note) {
		Write-Host "Reports in the game's storage not read: $($stored.Note)."
	}
	$reports = Merge-Reports -Logged $logged -Stored $stored.Reports
	if ($null -eq $ExitCode) {
		$ExitCode = Get-ExitFileCode $stored.Exit
		if ($null -ne $ExitCode) {
			Write-Host "No exit line in the log; $($script:ExitFileName) stands for exit $ExitCode."
		}
	}
	$partial = if ($null -eq $ExitCode) { Get-UnreportedSteps -Lines $Lines -Suite $Suite } else { $null }
	if ($partial) {
		$reports += $partial
	}
	if ($Dropped) {
		$problems.Clear()
		$problems.Add("the connection to the headset dropped at $Dropped and the headset was not back within $ReconnectSeconds s, so the suites' results are unknown")
	} elseif ($null -eq $ExitCode -and $Crashed -and $reports.Count -eq [int][bool]$partial) {
		$problems.Add('the game stopped before it printed a report (see device.log)')
	} elseif ($null -eq $ExitCode -and $reports.Count -eq 0) {
		$problems.Add("no exit line within $TimeoutSeconds s and no report (see device.log)")
	}
	$verdict = Get-RunVerdict -Reports $reports -ExitCode $ExitCode -Problems $problems.ToArray()
	if ($partial) {
		$verdict.Reason += "; the table is partial: with no exit line and no $($script:ExitFileName), the last suite's rows come from the step lines in the log"
	}
	return [pscustomobject]@{ Status = $verdict.Status; Reason = $verdict.Reason; Reports = $reports }
}
