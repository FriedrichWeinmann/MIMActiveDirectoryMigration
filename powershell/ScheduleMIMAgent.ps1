<#
.SYNOPSIS
	Executes MIM Run Profiles.

.DESCRIPTION
	Executes MIM Run Profiles.
	Use this script to schedule / automate Run Profile executions.

	Can provide multiple RPs to have them executed in the order provided.

.PARAMETER RunProfile
	The profile(s) to execute. Must be provided in the following format:
	%ManagementAgentName%\%RunProfileName%

	Example:
	"Source Fabrikam\Full Sync"

	Can provide multiple RPs, in which case they are processed in the order here specified.
	Any failure in a Run Profile will lead to script termination in error.

.PARAMETER IntervalSeconds
	Wait time inbetween RunProfiles.
	It is recommended to wait for a few seconds before executing the next profile.
	Defaults to: 15

.EXAMPLE
	PS C:\> .\ScheduleMIMAgent.ps1 -RunProfile 'Fabrikam\Delta Import', 'Fabrikam\Delta Sync', 'Contoso\Delta Sync', 'Contoso\Export'

	Executes the specified RPs in the order provided:
	- Fabrikam\Delta Import
	- Fabrikam\Delta Sync
	- Contoso\Delta Sync
	- Contoso\Export
	Waiting for 15 seconds between each step.
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	[string[]]
	$RunProfile,

	[ValidateRange(1, 2147483647)]
	[int]
	$IntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "SDcript Failed: $_"
	throw $_
}

#region Functions
function Get-ManagementAgent {
	[OutputType([hashtable])]
	[CmdletBinding()]
	param (
		[switch]
		$AsHashtable
	)

	$mgmtAgents = Get-CimInstance -Namespace root\MIcrosoftIdentityIntegrationServer -ClassName MIIS_ManagementAgent
	if (-not $AsHashtable) { return $mgmtAgents }

	$agentHash = @{}
	foreach ($agent in $mgmtAgents) {
		$agentHash[$agent.Name] = $agent
	}
	$agentHash
}

function Invoke-RunProfile {
	[CmdletBinding()]
	param (
		[hashtable]
		$MgmtAgents,

		[string]
		$Task
	)

	$agentName, $profileName = $Task -split '\\'
	if (-not $agentName -or -not $profileName) {
		throw "Invalid task! Provide <agentname>\<profilename> as input: $Task"
	}

	if (-not $MgmtAgents[$agentName]) {
		throw "Invalid task! Management Agent $($agentName) not found. Known MAs: $($MgmtAgents.Keys -join ', ')"
	}

	try {
		$result = $MgmtAgents[$agentName] | Invoke-CimMethod -MethodName Execute -Arguments @{ RunProfileName = $profileName } -ErrorAction Stop
	}
	catch {
		throw "Error executing profile $profileName against $($agentName): $_"
	}
	if ($result.ReturnValue -eq 'no-start-unknown-profile-name') {
		throw "Error executing profile $profileName against $($agentName): Profile not found!"
	}
	if ($result.ReturnValue -ne 'success') {
		throw "Error executing profile $profileName against $($agentName): $($result.ReturnValue)"
	}
}
#endregion Functions

$managementAgents = Get-ManagementAgent -AsHashtable
foreach ($task in $RunProfile) {
	Invoke-RunProfile -MgmtAgents $managementAgents -Task $task
	if ($task -ne $RunProfile[-1]) { Start-Sleep -Seconds $IntervalSeconds }
}