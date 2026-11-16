<#
.SYNOPSIS
Runs an acceptance suite from source under Meta XR Simulator on the owner's PC (#154).

.DESCRIPTION
The simulator half of the device acceptance workflow
(.github/workflows/device-acceptance.yml). Imports the project, starts the game
windowed with --acceptance=<suite> while Meta XR Simulator is the active OpenXR
runtime, waits for it to quit, and writes the report, screenshots and log to
-OutDir with a result.json (see acceptance_common.ps1).

It skips cleanly (exit 0, with the reason) when the simulator cannot run
unattended: not on Windows, the runner is a service with no desktop, another
OpenXR runtime is active, or Godot is missing. Frame timing from the simulator
is not evidence for PRF-1 to PRF-3; only the headset job counts for those.

.PARAMETER Godot
The Godot 4.7.2 executable. Defaults to $env:GODOT_PATH, then `godot` on PATH.
#>
[CmdletBinding()]
param(
	[string]$Suite = 'all',
	[string]$OutDir = 'build/device-acceptance/simulator',
	[string]$Godot = '',
	[string]$ProjectDir = 'game',
	[int]$TimeoutSeconds = 900,
	[int]$ScreenshotEverySeconds = 30,
	[int]$MaxScreenshots = 10
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'acceptance_common.ps1')

$godotVersion = '4.7.2'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path
$logPath = Join-Path $OutDir 'godot.log'
$shotDir = Join-Path $OutDir 'screenshots'

function Stop-Run {
	param([string]$Status, [string]$Reason, $Reports, [string[]]$Table, [string]$Runtime = '')
	Write-RunResult -OutDir $OutDir -Target 'simulator' -Status $Status -Reason $Reason -Reports $Reports
	$lines = @('### Device acceptance: Meta XR Simulator', '')
	if ($Runtime) {
		$lines += "Active OpenXR runtime: ``$Runtime``"
		$lines += ''
	}
	$lines += "Suite ``$Suite``: **$Status**. $Reason"
	if ($Table) {
		$lines += ''
		$lines += $Table
	}
	Write-JobSummary $lines
	if ($Status -eq 'skipped') {
		Write-Host "::notice title=Simulator acceptance skipped::$Reason"
		exit 0
	}
	if ($Status -eq 'failed') {
		Write-Host "::error title=Simulator acceptance failed::$Reason"
		exit 1
	}
	exit 0
}

# The manifest the OpenXR loader will use: XR_RUNTIME_JSON wins over the
# registry, as in the loader itself.
function Get-ActiveRuntime {
	if ($env:XR_RUNTIME_JSON) {
		return $env:XR_RUNTIME_JSON
	}
	try {
		return [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Khronos\OpenXR\1' -Name 'ActiveRuntime' -ErrorAction Stop).ActiveRuntime
	} catch {
		return ''
	}
}

# The whole primary screen as a PNG; the simulator draws its window there.
function Save-Screen {
	param([string]$Path)
	try {
		Add-Type -AssemblyName System.Windows.Forms, System.Drawing
		$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
		$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
		$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
		$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
		$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
		$graphics.Dispose()
		$bitmap.Dispose()
		return $true
	} catch {
		Write-Host "Screenshot failed: $($_.Exception.Message)"
		return $false
	}
}

# 1. Preconditions; each missing one is a clean skip with its reason.
if ($env:OS -ne 'Windows_NT') {
	Stop-Run 'skipped' 'Not on Windows: Meta XR Simulator runs only on the owner''s Windows PC.'
}
$runtime = Get-ActiveRuntime
Write-Host "Active OpenXR runtime: $runtime"
if ((Get-Process -Id $PID).SessionId -eq 0) {
	Stop-Run 'skipped' 'The runner is running as a Windows service (session 0), which has no desktop for the simulator window. Start the runner with run.cmd in the logged-in session.' -Runtime $runtime
}
if ($runtime -notmatch 'simulator') {
	Stop-Run 'skipped' "Meta XR Simulator is not the active OpenXR runtime (active: '$runtime'). Make it active in the simulator or set XR_RUNTIME_JSON for the runner." -Runtime $runtime
}
if (-not $Godot) {
	$Godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { 'godot' }
}
$godotCommand = Get-Command $Godot -ErrorAction SilentlyContinue
if (-not $godotCommand) {
	Stop-Run 'skipped' "Godot $godotVersion was not found ('$Godot'). Put it on the runner's PATH or set the repository variable GODOT_PATH." -Runtime $runtime
}
$Godot = $godotCommand.Source
$previous = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$version = (& $Godot --headless --version 2>&1 | ForEach-Object { "$_" }) -join ' '
$ErrorActionPreference = $previous
if ($version -notmatch [regex]::Escape($godotVersion)) {
	Stop-Run 'skipped' "Godot on the runner reports '$version', not $godotVersion." -Runtime $runtime
}

# 2. Import, then the game in a window with the acceptance switch.
Write-Host 'Importing the project...'
$import = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', "`"$ProjectDir`"", '--import') -NoNewWindow -Wait -PassThru
if ($import.ExitCode -ne 0) {
	Stop-Run 'failed' "The project import exited with $($import.ExitCode)." -Runtime $runtime
}
Write-Host "Starting the game with --acceptance=$Suite"
$arguments = @('--path', "`"$ProjectDir`"", '--log-file', "`"$logPath`"", '--', "--acceptance=$Suite")
$game = Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru
# Holding the handle keeps ExitCode readable after the process ends (5.1).
$null = $game.Handle
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
$clock = [Diagnostics.Stopwatch]::StartNew()
$shots = 0
$timedOut = $false
while (-not $game.HasExited) {
	if ($shots -lt $MaxScreenshots -and $clock.Elapsed.TotalSeconds -ge $shots * $ScreenshotEverySeconds) {
		$shot = Join-Path $shotDir ('{0:D2}-{1:D4}s.png' -f ($shots + 1), [int]$clock.Elapsed.TotalSeconds)
		if (Save-Screen $shot) {
			$shots += 1
		} else {
			$MaxScreenshots = 0
		}
	}
	if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
		$timedOut = $true
		Stop-Process -Id $game.Id -Force -ErrorAction SilentlyContinue
		break
	}
	Start-Sleep -Seconds 1
}

# 3. The verdict, from the log the game wrote.
$lines = @()
if (Test-Path -LiteralPath $logPath) {
	$lines = Get-Content -Encoding UTF8 -LiteralPath $logPath
}
$problems = New-Object System.Collections.Generic.List[string]
$reports = ConvertFrom-ReportBlocks -Blocks (Get-ReportBlocks $lines) -Problems $problems
$exitCode = Get-AcceptanceExitCode $lines
if ($timedOut) {
	$problems.Add("the game did not quit within $TimeoutSeconds s (see godot.log)")
} elseif ($null -eq $exitCode -and $reports.Count -eq 0) {
	$problems.Add("the game quit with $($game.ExitCode) before it printed a report (see godot.log)")
}
$verdict = Get-RunVerdict -Reports $reports -ExitCode $exitCode -Problems $problems.ToArray()
$table = $null
if ($reports.Count -gt 0) {
	$table = Format-ResultTable @([pscustomobject]@{ target = 'simulator'; status = $verdict.Status; reason = $verdict.Reason; suites = $reports })
}
Write-Host "Screenshots: $shots"
Stop-Run $verdict.Status $verdict.Reason $reports $table -Runtime $runtime
