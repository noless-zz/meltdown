<#
Shared helpers for the device acceptance workflow (#154, DEV-6, decision record
0005). Dot-sourced by device_acceptance.ps1, simulator_acceptance.ps1 and
post_acceptance.ps1. Runs in Windows PowerShell 5.1 (the owner's quest-pc
runner) and in PowerShell 7 (the CI checks and the report job on Linux), so
nothing here uses 7-only syntax.

Every run writes `result.json` in its output folder:
  target  "headset" or "simulator"
  status  "passed", "failed" or "skipped"
  reason  one line saying why, shown in the job summary and the gate comment
  suites  the AcceptanceReport dictionaries the game printed, in run order
#>

# The game echoes each report between these lines (acceptance_report.gd) and
# ends with "Meltdown: acceptance: exit <code>" (acceptance_runner.gd).
$script:ReportBegin = 'MELTDOWN_ACCEPTANCE_BEGIN'
$script:ReportEnd = 'MELTDOWN_ACCEPTANCE_END'
$script:ExitPattern = 'Meltdown: acceptance: exit (-?\d+)'

# UTF-8 without a byte order mark, so the files read the same on both shells.
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8File {
	param([string]$Path, [string]$Text)
	[IO.File]::WriteAllText($Path, $Text, $script:Utf8)
}

function Add-Utf8File {
	param([string]$Path, [string]$Text)
	[IO.File]::AppendAllText($Path, $Text, $script:Utf8)
}

# The JSON text of every report block in the log, in order. A log line may
# carry a prefix (a logcat tag or time), so markers are found anywhere in the
# line and the text before a marker is the prefix to cut from the lines
# between them.
function Get-ReportBlocks {
	param([string[]]$Lines)
	$blocks = @()
	$current = $null
	$prefixLength = 0
	foreach ($raw in $Lines) {
		$line = ([string]$raw).TrimEnd("`r", "`n")
		$begin = $line.IndexOf($script:ReportBegin)
		if ($begin -ge 0) {
			$current = New-Object System.Collections.Generic.List[string]
			$prefixLength = $begin
			continue
		}
		if ($null -eq $current) {
			continue
		}
		if ($line.IndexOf($script:ReportEnd) -ge 0) {
			$blocks += ($current -join "`n")
			$current = $null
			continue
		}
		if ($prefixLength -gt 0 -and $line.Length -ge $prefixLength) {
			$line = $line.Substring($prefixLength)
		}
		$current.Add($line)
	}
	return , $blocks
}

# The exit code the acceptance runner printed last, or $null if it never did.
function Get-AcceptanceExitCode {
	param([string[]]$Lines)
	$code = $null
	foreach ($line in $Lines) {
		$match = [regex]::Match([string]$line, $script:ExitPattern)
		if ($match.Success) {
			$code = [int]$match.Groups[1].Value
		}
	}
	return $code
}

# Parses the report blocks. Blocks that are not valid JSON are skipped and
# counted in $Problems, so a cut-off log line cannot pass for a report.
function ConvertFrom-ReportBlocks {
	param([string[]]$Blocks, [System.Collections.Generic.List[string]]$Problems)
	$reports = @()
	foreach ($block in $Blocks) {
		try {
			$reports += ($block | ConvertFrom-Json)
		} catch {
			$Problems.Add('a report in the log is not valid JSON')
		}
	}
	return , $reports
}

# Decides the run's status from what the game printed. Returns
# @{ Status; Reason }. Any failed step, a missing report, a missing or
# non-zero exit line all fail the run.
function Get-RunVerdict {
	param($Reports, $ExitCode, [string[]]$Problems)
	if ($Problems.Count -gt 0) {
		return @{ Status = 'failed'; Reason = ($Problems -join '; ') }
	}
	if ($Reports.Count -eq 0) {
		return @{ Status = 'failed'; Reason = 'no acceptance report was found in the log' }
	}
	$failed = @()
	foreach ($report in $Reports) {
		foreach ($step in $report.steps) {
			if ($step.result -eq 'fail') {
				$failed += "$($report.suite)/$($step.id)"
			}
		}
	}
	if ($failed.Count -gt 0) {
		return @{ Status = 'failed'; Reason = ('failed steps: ' + ($failed -join ', ')) }
	}
	if ($null -eq $ExitCode) {
		return @{ Status = 'failed'; Reason = 'the game never printed its exit line' }
	}
	if ($ExitCode -ne 0) {
		# The runner exits 1 when a suite ran no step at all (every step skipped).
		return @{ Status = 'failed'; Reason = "the game exited with $ExitCode (a suite with no passing step counts as failed)" }
	}
	return @{ Status = 'passed'; Reason = 'every step passed or was skipped' }
}

function Write-RunResult {
	param([string]$OutDir, [string]$Target, [string]$Status, [string]$Reason, $Reports)
	if ($null -eq $Reports) {
		$Reports = @()
	}
	$result = [ordered]@{
		target = $Target
		status = $Status
		reason = $Reason
		suites = @($Reports)
	}
	New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
	Write-Utf8File -Path (Join-Path $OutDir 'result.json') -Text (ConvertTo-Json -InputObject $result -Depth 12)
	foreach ($report in $Reports) {
		$name = ([string]$report.suite -replace '[^A-Za-z0-9_-]', '_') + '.json'
		Write-Utf8File -Path (Join-Path $OutDir $name) -Text (ConvertTo-Json -InputObject $report -Depth 10)
	}
}

# Reads result.json, or returns a placeholder when the job left none (it was
# cancelled, timed out or never reached the runner).
function Read-RunResult {
	param([string]$Path, [string]$Target)
	if (Test-Path -LiteralPath $Path) {
		return (Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json)
	}
	return [pscustomobject]@{
		target = $Target
		status = 'missing'
		reason = 'the job left no result (cancelled, timed out, or the runner was offline)'
		suites = @()
	}
}

# Table cells must stay on one line and not split the table.
function Format-Cell {
	param([string]$Text)
	return (($Text -replace '[\r\n]+', ' ') -replace '\|', '\|').Trim()
}

# A Markdown table with one row per suite step and one column per target.
function Format-ResultTable {
	param($Results)
	$order = New-Object System.Collections.Generic.List[string]
	$cells = @{}
	foreach ($result in $Results) {
		foreach ($report in $result.suites) {
			foreach ($step in $report.steps) {
				$key = "$($report.suite)|$($step.id)"
				if (-not $order.Contains($key)) {
					$order.Add($key)
				}
				$cell = [string]$step.result
				if ($step.result -ne 'pass' -and $step.message) {
					$cell = "${cell}: $($step.message)"
				}
				$cells["$key|$($result.target)"] = Format-Cell $cell
			}
		}
	}
	$lines = New-Object System.Collections.Generic.List[string]
	$header = '| Suite | Step |'
	$rule = '| --- | --- |'
	foreach ($result in $Results) {
		$header += " $((Get-Culture).TextInfo.ToTitleCase($result.target)) |"
		$rule += ' --- |'
	}
	$lines.Add($header)
	$lines.Add($rule)
	foreach ($key in $order) {
		$parts = $key.Split('|')
		$row = "| $($parts[0]) | $($parts[1]) |"
		foreach ($result in $Results) {
			$value = $cells["$key|$($result.target)"]
			if (-not $value) {
				$value = 'not run'
			}
			$row += " $value |"
		}
		$lines.Add($row)
	}
	$lines.Add('')
	foreach ($result in $Results) {
		$lines.Add("- **$($result.target)**: $($result.status). $(Format-Cell ([string]$result.reason))")
	}
	return , $lines.ToArray()
}

# Suite/step pairs that failed, as "<target> <suite>/<step>: <message>", plus
# one line for a failed run that has no failed step (for example no report).
function Get-FailureLines {
	param($Results)
	$lines = @()
	foreach ($result in $Results) {
		if ($result.status -ne 'failed') {
			continue
		}
		$found = $false
		foreach ($report in $result.suites) {
			foreach ($step in $report.steps) {
				if ($step.result -eq 'fail') {
					$lines += "$($result.target) $($report.suite)/$($step.id): $(Format-Cell ([string]$step.message))"
					$found = $true
				}
			}
		}
		if (-not $found) {
			$lines += "$($result.target): $(Format-Cell ([string]$result.reason))"
		}
	}
	return , $lines
}

# Appends to the job summary when there is one (GitHub Actions), and always
# prints, so a local run shows the same text.
function Write-JobSummary {
	param([string[]]$Lines)
	$text = ($Lines -join "`n") + "`n"
	Write-Host $text
	if ($env:GITHUB_STEP_SUMMARY) {
		Add-Utf8File -Path $env:GITHUB_STEP_SUMMARY -Text $text
	}
}
