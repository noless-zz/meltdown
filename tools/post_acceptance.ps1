<#
.SYNOPSIS
Puts the headset and simulator results of a device acceptance run side by side (#154).

.DESCRIPTION
The last job of .github/workflows/device-acceptance.yml. Reads
<ResultsDir>/headset/result.json and <ResultsDir>/simulator/result.json, writes
one table with a column per target to the job summary and, on a scheduled run:

- comments the table on the open gate issue of the earliest open milestone,
  replacing the comment it left there before;
- if a step failed, opens one issue labelled `playtest` naming the suite and
  step, or comments on that issue when it is already open (decision record
  0005, point 5).

Uses only the workflow's GITHUB_TOKEN (issues: write). With -DryRun it prints
the requests instead of sending them, for tools/test_device_acceptance.sh.
#>
[CmdletBinding()]
param(
	[string]$ResultsDir = 'results',
	[string]$Suite = 'all',
	[string]$EventName = $env:GITHUB_EVENT_NAME,
	[string]$Repository = $env:GITHUB_REPOSITORY,
	[string]$RunUrl = '',
	[switch]$DryRun
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'acceptance_common.ps1')

# Hidden markers so a later run finds its own comment and issue again.
$gateMarker = '<!-- meltdown-device-acceptance -->'
$regressionMarker = '<!-- meltdown-nightly-regression -->'
$footer = "`n`n---`n_Posted by the device acceptance workflow (#154)._"

$results = @(
	(Read-RunResult -Path (Join-Path $ResultsDir 'headset/result.json') -Target 'headset'),
	(Read-RunResult -Path (Join-Path $ResultsDir 'simulator/result.json') -Target 'simulator')
)
$table = Format-ResultTable $results
$failures = Get-FailureLines $results
$title = "Device acceptance, suite ``$Suite``"
$body = @($gateMarker, "### $title", '')
if ($RunUrl) {
	$body += "Run: $RunUrl"
	$body += ''
}
$body += $table
$bodyText = $body -join "`n"
Write-JobSummary (@("### $title", '') + $table)

if ($EventName -ne 'schedule') {
	# The headset and simulator jobs already fail the run on a failed step.
	Write-Host "Event '$EventName': no issue comments; they are for the nightly run only."
	exit 0
}

function Invoke-Api {
	param([string]$Method, [string]$Path, $Body = $null)
	$uri = "https://api.github.com/repos/$Repository/$Path"
	if ($DryRun) {
		Write-Host "DRY RUN $Method $Path"
		if ($null -ne $Body) {
			Write-Host (ConvertTo-Json -InputObject $Body -Depth 5)
		}
		if ($Method -eq 'GET') {
			# Nothing found: no gate and no open regression issue.
			return
		}
		return [pscustomobject]@{ number = 0; html_url = '' }
	}
	$headers = @{
		Authorization = "Bearer $env:GITHUB_TOKEN"
		Accept = 'application/vnd.github+json'
		'X-GitHub-Api-Version' = '2022-11-28'
	}
	$arguments = @{ Method = $Method; Uri = $uri; Headers = $headers }
	if ($null -ne $Body) {
		$arguments['Body'] = (ConvertTo-Json -InputObject $Body -Depth 5)
		$arguments['ContentType'] = 'application/json'
	}
	return Invoke-RestMethod @arguments
}

# The open gate issue of the earliest open milestone, or $null.
$gates = @(Invoke-Api 'GET' 'issues?state=open&labels=gate&per_page=100') |
	Where-Object { $_.milestone } |
	Sort-Object { [int]$_.milestone.number }
$gate = $gates | Select-Object -First 1
if ($gate) {
	$comments = @(Invoke-Api 'GET' "issues/$($gate.number)/comments?per_page=100")
	$previous = $comments | Where-Object { [string]$_.body -like "*$gateMarker*" } | Select-Object -Last 1
	if ($previous) {
		Invoke-Api 'PATCH' "issues/comments/$($previous.id)" @{ body = $bodyText + $footer } | Out-Null
		Write-Host "Replaced the result comment on gate #$($gate.number)."
	} else {
		Invoke-Api 'POST' "issues/$($gate.number)/comments" @{ body = $bodyText + $footer } | Out-Null
		Write-Host "Commented the result on gate #$($gate.number)."
	}
} else {
	Write-Host 'No open gate issue in an open milestone; no gate comment.'
}

if ($failures.Count -eq 0) {
	exit 0
}

# One regression issue at a time: reuse the open one, else open it.
$failureText = ($failures | ForEach-Object { "- $_" }) -join "`n"
$open = @(Invoke-Api 'GET' 'issues?state=open&labels=playtest&per_page=100') |
	Where-Object { -not $_.pull_request -and [string]$_.body -like "*$regressionMarker*" } |
	Select-Object -First 1
if ($open) {
	Invoke-Api 'POST' "issues/$($open.number)/comments" @{ body = "Still failing on the nightly run.`n`n$failureText`n`n$bodyText$footer" } | Out-Null
	Write-Host "Commented on the open regression issue #$($open.number)."
} else {
	$first = $failures[0]
	$issue = @{
		title = "Nightly device acceptance fails: $first"
		labels = @('playtest')
		body = "$regressionMarker`nThe nightly device acceptance run failed (decision record 0005, point 5; DEV-7).`n`n$failureText`n`n$bodyText$footer"
	}
	if ($issue.title.Length -gt 200) {
		$issue.title = $issue.title.Substring(0, 200)
	}
	Invoke-Api 'POST' 'issues' $issue | Out-Null
	Write-Host 'Opened a playtest issue for the failure.'
}
exit 0
