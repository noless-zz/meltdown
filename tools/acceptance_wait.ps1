<#
How long device_acceptance.ps1 waits for the game's exit line (#1504, DEV-6):
the sum of the time limits of every step in the suites asked for, plus one
margin, instead of a fixed 900 s. On 27 Nov the nightly suite outgrew 900 s:
the run was cut off in m3 and m4 and m6 never ran.

Each step's limit follows the #1444 rule (game/acceptance/acceptance_time_limit.gd,
AcceptanceTimeLimit.seconds_for): a step's own `time_limit_seconds` as written,
otherwise its suite's `default_time_limit_seconds` (120 s when unset) plus the
seconds it is told to wait (`settle_seconds`, `measure_seconds`, `view_seconds`,
`pause_seconds`) plus the time its `replay` and `next_replay` take to fly at
72 Hz, one tick per line after `inputs`. A `loop_replay` step flies for its
`measure_seconds`, already counted. The runner fails a step at its limit, so
the whole run cannot take longer than the sum, apart from what the margin covers.

The suites are read from this checkout's game/acceptance/suites, as the game
picks them (AcceptanceSuite.load_named): one suite, `all`, or `nightly` (every
suite not marked `manual_only`), with each suite's `include` parts.

Dot-sourced by device_acceptance.ps1. Runs in Windows PowerShell 5.1 and
PowerShell 7, so nothing here uses 7-only syntax.
#>

# The one place the margin is set: the game's start, the level loads and scene
# changes between steps, the reports written at each suite's end and the polls.
$script:AcceptanceWaitMarginSeconds = 300
# Used when the suite files cannot be read (a script copied without the game
# folder, or a suite name with no file): long enough for today's nightly suite.
$script:AcceptanceWaitFallbackSeconds = 3600

# AcceptanceTimeLimit's values; acceptance_time_limit.gd is the source.
$script:StepDefaultLimitSeconds = 120.0
$script:ReplaySlowestHz = 72.0
$script:StepWaitFields = @('settle_seconds', 'measure_seconds', 'view_seconds', 'pause_seconds')

# Whether the parsed JSON object $Object has the field $Name.
function Test-JsonField {
	param($Object, [string]$Name)
	return ($null -ne $Object -and @($Object.PSObject.Properties.Name) -contains $Name)
}

function Read-JsonFile {
	param([string]$Path)
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		throw "no file $Path"
	}
	try {
		return ([IO.File]::ReadAllText($Path) | ConvertFrom-Json)
	} catch {
		throw "$Path is not valid JSON: $($_.Exception.Message)"
	}
}

# The suite files `-Suite $Name` runs, in name order for `all` and `nightly`.
function Get-AcceptanceSuiteFiles {
	param([string]$Name, [string]$SuitesDir)
	if ($Name -ne 'all' -and $Name -ne 'nightly') {
		return , @(Join-Path $SuitesDir "$Name.json")
	}
	$files = @()
	foreach ($file in @(Get-ChildItem -LiteralPath $SuitesDir -File | Where-Object { $_.Extension -eq '.json' } | Sort-Object Name)) {
		if ($Name -eq 'nightly') {
			$data = Read-JsonFile $file.FullName
			if ((Test-JsonField $data 'manual_only') -and $data.manual_only -eq $true) {
				continue
			}
		}
		$files += $file.FullName
	}
	return , $files
}

# The ticks a replay file flies: its lines after `inputs`, blank and `#` lines
# left out (ReplayHeader.read_text). A missing file counts as none, as in the game.
function Get-ReplayTicks {
	param([string]$Path)
	if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
		return 0
	}
	$ticks = 0
	$inHeader = $true
	foreach ($raw in [IO.File]::ReadAllLines($Path)) {
		$line = $raw.Trim()
		if ($line -eq '' -or $line.StartsWith('#')) {
			continue
		}
		if ($inHeader) {
			if ($line -eq 'inputs') {
				$inHeader = $false
			}
			continue
		}
		$ticks += 1
	}
	return $ticks
}

# A `res://` path as a path under $GameDir, the Godot project root.
function Resolve-ResPath {
	param([string]$Path, [string]$GameDir)
	if ($Path.StartsWith('res://')) {
		return (Join-Path $GameDir $Path.Substring(6))
	}
	return $Path
}

# The seconds one step may run (AcceptanceTimeLimit.seconds_for).
function Get-StepLimitSeconds {
	param($Step, [double]$SuiteDefault, [string]$GameDir)
	if (Test-JsonField $Step 'time_limit_seconds') {
		return [double]$Step.time_limit_seconds
	}
	$seconds = $SuiteDefault
	foreach ($field in $script:StepWaitFields) {
		if (Test-JsonField $Step $field) {
			$seconds += [double]$Step.$field
		}
	}
	if ((Test-JsonField $Step 'loop_replay') -and $Step.loop_replay -eq $true) {
		return $seconds
	}
	$ticks = 0
	foreach ($field in @('replay', 'next_replay')) {
		if ((Test-JsonField $Step $field) -and $Step.$field) {
			$ticks += Get-ReplayTicks (Resolve-ResPath ([string]$Step.$field) $GameDir)
		}
	}
	return $seconds + $ticks / $script:ReplaySlowestHz
}

# The sum of the step limits of one suite file and the parts it includes.
function Get-SuiteLimitSeconds {
	param([string]$Path, [string]$SuitesDir, [string]$GameDir)
	$data = Read-JsonFile $Path
	$default = $script:StepDefaultLimitSeconds
	if (Test-JsonField $data 'default_time_limit_seconds') {
		$default = [double]$data.default_time_limit_seconds
	}
	$steps = @()
	if (Test-JsonField $data 'steps') {
		$steps += @($data.steps)
	}
	if (Test-JsonField $data 'include') {
		foreach ($part in @($data.include)) {
			$partData = Read-JsonFile (Join-Path $SuitesDir "$part.json")
			if (Test-JsonField $partData 'steps') {
				$steps += @($partData.steps)
			}
		}
	}
	$sum = 0.0
	foreach ($step in $steps) {
		if ($null -ne $step) {
			$sum += Get-StepLimitSeconds -Step $step -SuiteDefault $default -GameDir $GameDir
		}
	}
	return $sum
}

# The wait for `-Suite $Suite`: Seconds (the sum plus the margin, whole seconds
# up), Sum, Margin, Suites (the names counted) and Problem (why the suites could
# not be read; Seconds is then the fallback).
function Get-AcceptanceWait {
	param([string]$Suite, [string]$GameDir)
	$suitesDir = Join-Path $GameDir 'acceptance/suites'
	try {
		if (-not (Test-Path -LiteralPath $suitesDir -PathType Container)) {
			throw "no suites folder at $suitesDir"
		}
		$sum = 0.0
		$names = @()
		foreach ($file in (Get-AcceptanceSuiteFiles -Name $Suite -SuitesDir $suitesDir)) {
			$sum += Get-SuiteLimitSeconds -Path $file -SuitesDir $suitesDir -GameDir $GameDir
			$names += [IO.Path]::GetFileNameWithoutExtension($file)
		}
		if ($names.Count -eq 0) {
			throw "no suite files in $suitesDir"
		}
		return [pscustomobject]@{
			Seconds = [int][Math]::Ceiling($sum + $script:AcceptanceWaitMarginSeconds)
			Sum = $sum
			Margin = $script:AcceptanceWaitMarginSeconds
			Suites = $names
			Problem = $null
		}
	} catch {
		return [pscustomobject]@{
			Seconds = $script:AcceptanceWaitFallbackSeconds
			Sum = 0.0
			Margin = $script:AcceptanceWaitMarginSeconds
			Suites = @()
			Problem = $_.Exception.Message
		}
	}
}

# The line that says how long the run waits and why.
function Format-AcceptanceWaitLine {
	param($Wait)
	if ($Wait.Problem) {
		return "Waiting up to $($Wait.Seconds) s for the exit line: the step time limits could not be read ($($Wait.Problem)). -TimeoutSeconds sets the wait."
	}
	return ("Waiting up to {0} s for the exit line: the step time limits of {1} add up to {2} s, plus {3} s margin. -TimeoutSeconds overrides." `
		-f $Wait.Seconds, ($Wait.Suites -join ', '), [int][Math]::Ceiling($Wait.Sum), $Wait.Margin)
}
