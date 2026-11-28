<#
Live progress lines for device_acceptance.ps1 (#1438, DEV-6): while a suite
runs on the headset, one line when a step starts and one when it ends, with the
time since the start, the suite and the step's number, and a line when a suite
starts and ends. Failures are red, with the step's message. The owner watches
the headset picture on the PC; these lines say which step he is looking at.

Read from the lines the game already prints (acceptance_runner.gd):
  Meltdown: acceptance: step <id>                      a step starts
  Meltdown: acceptance: step <id> <result>             it ends
and, once #1444 is in, `suite=<name> index=<n> count=<m>` after either, and a
`(<message>)` on a step that ran out of time. Without those fields the suite is
the one asked for (or "suite <n>" for `all` and `nightly` until its report
names it) and the number is counted, with no total. A suite ends with its
report between the markers; its summary and its failed steps' messages come
from that report.

Dot-sourced after acceptance_common.ps1 (Get-ReportBlocks). Runs in Windows
PowerShell 5.1 and PowerShell 7, so nothing here uses 7-only syntax.
#>

$script:ProgressStepPattern = 'Meltdown: acceptance: step (\S+)(.*)$'
$script:ProgressResults = @('pass', 'fail', 'skipped')

# What the progress lines have seen so far. $Suite is the -Suite asked for.
function New-ProgressState {
	param([string]$Suite)
	$named = ''
	if ($Suite -and $Suite -notin @('all', 'nightly')) {
		$named = $Suite
	}
	return @{
		# Each event the earlier polls read, as text, oldest first (Get-NewEventStart).
		Seen = New-Object System.Collections.Generic.List[string]
		Named = $named
		SuiteNumber = 0
		Suite = $null
		StepNumber = 0
		Starts = @{}
	}
}

# `[mm:ss]` for a number of seconds since the start.
function Format-ProgressTime {
	param([double]$Seconds)
	$whole = [int][Math]::Floor($Seconds)
	return '[{0:D2}:{1:D2}]' -f [int][Math]::Floor($whole / 60), ($whole % 60)
}

# The progress lines for what the log holds that earlier polls did not, as
# @{ Text; Color } with Color $null for the default. $Lines is the whole log so
# far (each poll reads the headset's whole buffer); $Elapsed is the seconds
# since the start. What counts is the step lines and whole report blocks seen,
# not the line count, so other lines coming and going change nothing. Every
# step that ended since the last poll gets its line, however many there are.
function Get-ProgressLines {
	param([hashtable]$State, [string[]]$Lines, [double]$Elapsed)
	$out = New-Object System.Collections.Generic.List[object]
	$events = Get-ProgressEvents $Lines
	$keys = New-Object System.Collections.Generic.List[string]
	foreach ($entry in $events) {
		$keys.Add($entry.Key)
	}
	$stamp = Format-ProgressTime $Elapsed
	for ($i = (Get-NewEventStart -Seen $State.Seen -Keys $keys); $i -lt $events.Count; $i++) {
		$entry = $events[$i]
		if ($entry.Report) {
			Add-SuiteEndLines -State $State -Out $out -Block $entry.Report
		} else {
			Add-StepLine -State $State -Out $out -Id $entry.Id -Rest $entry.Rest -Stamp $stamp -Elapsed $Elapsed
		}
	}
	$State.Seen = $keys
	return $out.ToArray()
}

# Where the events not seen before start in $Keys. On a busy headset the log
# buffer drops its oldest lines between polls, so the events now held are the
# tail of those seen plus the new ones: counting events from the front skipped
# as many new steps as old lines were dropped (#1504: steps 4 to 12 of m1 never
# got a line). So the longest tail of $Seen that $Keys starts with is found,
# and what follows it is new. A cleared buffer shares no tail: all of it is new.
function Get-NewEventStart {
	param($Seen, $Keys)
	for ($from = 0; $from -lt $Seen.Count; $from++) {
		$shared = $Seen.Count - $from
		if ($shared -gt $Keys.Count -or $Keys[0] -ne $Seen[$from]) {
			continue
		}
		$same = $true
		for ($i = 1; $i -lt $shared; $i++) {
			if ($Keys[$i] -ne $Seen[$from + $i]) {
				$same = $false
				break
			}
		}
		if ($same) {
			return $shared
		}
	}
	return 0
}

# The step lines (Id, Rest) and complete report blocks (Report: the block's
# lines with their markers) in $Lines, in order.
function Get-ProgressEvents {
	param([string[]]$Lines)
	$events = New-Object System.Collections.Generic.List[object]
	$block = $null
	foreach ($raw in @($Lines)) {
		$line = ([string]$raw).TrimEnd("`r", "`n")
		if ($line.IndexOf($script:ReportBegin) -ge 0) {
			$block = New-Object System.Collections.Generic.List[string]
		}
		if ($null -ne $block) {
			$block.Add($line)
			if ($line.IndexOf($script:ReportEnd) -ge 0) {
				$events.Add(@{ Report = $block.ToArray(); Key = ($block -join "`n") })
				$block = $null
			}
			continue
		}
		$match = [regex]::Match($line, $script:ProgressStepPattern)
		if ($match.Success) {
			$events.Add(@{ Report = $null; Id = $match.Groups[1].Value; Rest = $match.Groups[2].Value; Key = $match.Value })
		}
	}
	return , $events
}

# Writes what Get-ProgressLines returned to the console.
function Write-ProgressLines {
	param($Progress)
	foreach ($entry in $Progress) {
		if ($entry.Color) {
			Write-Host $entry.Text -ForegroundColor $entry.Color
		} else {
			Write-Host $entry.Text
		}
	}
}

function Add-StepLine {
	param([hashtable]$State, $Out, [string]$Id, [string]$Rest, [string]$Stamp, [double]$Elapsed)
	$result = $null
	$suiteField = $null
	$index = 0
	$count = 0
	$message = ''
	$paren = $Rest.IndexOf('(')
	if ($paren -ge 0) {
		$message = $Rest.Substring($paren + 1).TrimEnd().TrimEnd(')')
		$Rest = $Rest.Substring(0, $paren)
	}
	foreach ($token in ($Rest.Trim() -split '\s+')) {
		if ($token -in $script:ProgressResults) {
			$result = $token
		} elseif ($token -match '^suite=(\S+)$') {
			$suiteField = $Matches[1]
		} elseif ($token -match '^index=(\d+)$') {
			$index = [int]$Matches[1]
		} elseif ($token -match '^count=(\d+)$') {
			$count = [int]$Matches[1]
		}
	}
	if ($null -eq $State.Suite -or ($suiteField -and $suiteField -ne $State.Suite)) {
		$State.SuiteNumber += 1
		$State.StepNumber = 0
		$State.Suite = $suiteField
		if (-not $State.Suite) {
			$State.Suite = $State.Named
		}
		if (-not $State.Suite) {
			$State.Suite = "suite $($State.SuiteNumber)"
		}
		$Out.Add(@{ Text = "== $($State.Suite) =="; Color = 'Cyan' })
	}
	# A step counts once: at its start, or at its end when its start line was not seen.
	if ($null -eq $result -or -not $State.Starts.ContainsKey($Id)) {
		$State.StepNumber += 1
	}
	if ($index -le 0) {
		$index = $State.StepNumber
	}
	$place = "$index"
	if ($count -gt 0) {
		$place = "$index/$count"
	}
	$head = "$Stamp $($State.Suite)  $place  $Id"
	if ($null -eq $result) {
		$State.Starts[$Id] = $Elapsed
		$Out.Add(@{ Text = "$head ... running"; Color = $null })
		return
	}
	$took = ''
	if ($State.Starts.ContainsKey($Id)) {
		$took = '  ({0} s)' -f [int][Math]::Round($Elapsed - $State.Starts[$Id])
		$State.Starts.Remove($Id)
	}
	$text = "$head     $($result.ToUpper())$took"
	if ($message) {
		$text += ": $message"
	}
	$color = 'Green'
	if ($result -eq 'fail') {
		$color = 'Red'
	} elseif ($result -eq 'skipped') {
		$color = 'Yellow'
	}
	$Out.Add(@{ Text = $text; Color = $color })
}

# The suite's summary from the report just read, and each failed step with its message.
function Add-SuiteEndLines {
	param([hashtable]$State, $Out, [string[]]$Block)
	$blocks = Get-ReportBlocks $Block
	$report = $null
	if ($blocks.Count -gt 0) {
		try {
			$report = $blocks[0] | ConvertFrom-Json
		} catch {
			$report = $null
		}
	}
	$name = $State.Suite
	if ($null -ne $report -and $report.suite) {
		$name = $report.suite
	}
	$State.Suite = $null
	if ($null -eq $report) {
		$Out.Add(@{ Text = "== ${name}: its report could not be read =="; Color = 'Red' })
		return
	}
	$passed = @($report.steps | Where-Object { $_.result -eq 'pass' }).Count
	$failed = @($report.steps | Where-Object { $_.result -eq 'fail' })
	$skipped = @($report.steps | Where-Object { $_.result -eq 'skipped' }).Count
	$summary = "== ${name}: $passed passed, $($failed.Count) failed"
	if ($skipped -gt 0) {
		$summary += ", $skipped skipped"
	}
	$color = 'Green'
	if ($failed.Count -gt 0) {
		$color = 'Red'
	}
	$Out.Add(@{ Text = "$summary =="; Color = $color })
	foreach ($step in $failed) {
		$Out.Add(@{ Text = "   FAIL $name/$($step.id): $($step.message)"; Color = 'Red' })
	}
}
