<#
.SYNOPSIS
	Executes MIM Run Profiles.

.DESCRIPTION
	Executes MIM Run Profiles.
	Use this script to schedule / automate Run Profile executions.

	Provide a psd1 configuration file, describing what should be executed in what order and what way.
	Structure:
	@{
		1 = %config%
		2 = %config%
		3 = %config%
	}

	%config% would look like this:
	@{
		Name = 'Import'
		WaitAfter = 15
		RunProfiles = %profiles%
		Parallel = $true
	}

	%profiles% would looke like this:
	@(
		'<MA name>\<profile name 1>'
		'<MA name>\<profile name 2>'
		'<MA name>\<profile name 3>'
		'<MA name>\<profile name 4>'
		...
	)

	All entries supported by a config entry:
	- Name: Name of the step. Used for messages.
	- RunProfiles: List of Run Profiles to execute. Must be prefixed by the name of the Management Agent (e.g.: "ContosoMA\Delta Import")
	- WaitBefore: How many seconds to wait before starting a task
	- WaitAfter: How many seconds to wait after the task is complete
	- RetryCount: How many times to try again in case of non-terminal failure
	- RetryWait: How many seconds to wait before trying again after failing
	- Parallel: Whether to execute all Run Profiles in parallel or not
	- ContinueOnFail: Whether a failure on this step should cause the entire config consider itself failed
	- ExecuteWhenFailed: Execute this step, even if the config is failed

.PARAMETER ConfigPath
	Path to the config file, containing the steps to execuute

.PARAMETER PassThru
	Return the individual run profile reports.
	By default, no output will be produced.

.EXAMPLE
	PS C:\> .\ScheduleMIMAgent-parallel.ps1 -ConfigPath .\deltasync.config.psd1

	Executes the steps provided in "deltasync.config.psd1"
#>
[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	[string]
	$ConfigPath,

	[switch]
	$PassThru
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "Script Failed: $_"
	throw $_
}

$script:profileConfig = Import-PowerShellDataFile -Path $ConfigPath

#region Functions
function Invoke-Runspace {
	<#
	.SYNOPSIS
		Execute code in parallel.
	
	.DESCRIPTION
		Execute code in parallel.
		Will run the provided code for each item provided in parallel.
	
	.PARAMETER Scriptblock
		The code to parallelize.
	
	.PARAMETER Variables
		Variables to provide in each iteration.
	
	.PARAMETER Functions
		Functions to inject into the parallel tasks.
		Provide either function object or name.
	
	.PARAMETER Modules
		Modules to pre-import for each execution.
	
	.PARAMETER Throttle
		How many parallel executions should be performed.
		Defaults to 4 times the number of CPU cores.
	
	.PARAMETER Wait
		Whether to wait for it all to complete.
		Otherwise the command will return an object with a .Collect() method to wait for completion and retrieve results.
	
	.PARAMETER InputObject
		The items for which to create parallel runspaces.
	
	.EXAMPLE
		PS C:\> Get-Mailbox | Invoke-Runspace -ScriptBlock $addADData

		For each mailbox retrieved, execute the code stored in $addADData
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[scriptblock]
		$Scriptblock,

		[hashtable]
		$Variables,

		$Functions,

		$Modules,

		[int]
		$Throttle = ($env:NUMBER_OF_PROCESSORS * 4),

		[switch]
		$Wait,

		[Parameter(Mandatory = $true, ValueFromPipeline = $true)]
		$InputObject
	)

	begin {
		#region Functions
		function Add-SSVariable {
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[System.Management.Automation.Runspaces.InitialSessionState]
				$SessionState,

				[Parameter(Mandatory = $true)]
				[hashtable]
				$Variables
			)

			foreach ($pair in $Variables.GetEnumerator()) {
				$variable = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new($pair.Key, $pair.Value, "")
				$null = $SessionState.Variables.Add($variable)
			}
		}
		
		function Add-SSFunction {
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[System.Management.Automation.Runspaces.InitialSessionState]
				$SessionState,

				[Parameter(Mandatory = $true)]
				$Functions
			)

			foreach ($function in $Functions) {
				$functionDefinition = $function
				if ($function -is [string]) { $functionDefinition = Get-Command $function }

				$commandEntry = [System.Management.Automation.Runspaces.SessionStateFunctionEntry]::new(
					$functionDefinition.Name,
					$functionDefinition.Definition
				)
				$null = $SessionState.Commands.Add($commandEntry)
			}
		}
		
		function Add-SSModule {
			[CmdletBinding()]
			param (
				[Parameter(Mandatory = $true)]
				[System.Management.Automation.Runspaces.InitialSessionState]
				$SessionState,

				[Parameter(Mandatory = $true)]
				$Modules
			)

			foreach ($module in $Modules) {
				$moduleInfo = $module
				if ($module.ModuleBase) { $moduleInfo = $module.ModuleBase }
				$moduleSpec = [Microsoft.PowerShell.Commands.ModuleSpecification]::new($moduleInfo)
				$SessionState.ImportPSModule($moduleSpec)
			}
		}
		#endregion Functions

		$sessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
		if ($Variables) { Add-SSVariable -SessionState $sessionState -Variables $Variables }
		if ($Functions) { Add-SSFunction -SessionState $sessionState -Functions $Functions }
		if ($Modules) { Add-SSModule -SessionState $sessionState -Modules $Modules }

		$pool = [RunspaceFactory]::CreateRunspacePool($sessionState)
		$Null = $pool.SetMinRunspaces(1)
		$Null = $pool.SetMaxRunspaces($Throttle)
		$pool.ApartmentState = "MTA"
		$pool.Open()

		$result = [PSCustomObject]@{
			PSTypeName = 'Runspace.Job'
			Pool       = $pool
			Runspaces  = [System.Collections.ArrayList]@()
		}
		Add-Member -InputObject $result -MemberType ScriptMethod -Name Collect -Value {
			try {
				# Receive Results and cleanup
				foreach ($runspace in $this.Runspaces) {
					$runspace.Pipe.EndInvoke($runspace.Status)
					$runspace.Pipe.Dispose()
				}
			}
			finally {
				# Cleanup Runspace Pool
				$this.Pool.Close()
				$this.Pool.Dispose()
			}
		}
	}
	process {
		#region Set up new Runspace
		$runspace = [PowerShell]::Create()
		$null = $runspace.AddScript($Scriptblock)
		$null = $runspace.AddArgument($InputObject)
		$runspace.RunspacePool = $pool
		$rsObject = [PSCustomObject]@{
			Pipe   = $runspace
			Status = $runspace.BeginInvoke()
		}
		$null = $result.Runspaces.Add($rsObject)
		#endregion Set up new Runspace
	}
	end {
		if ($Wait) { $result.Collect() }
		else { $result }
	}
}

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
	$result = [PSCustomObject]@{
		MAName      = $agentName
		Profile     = $profileName
		Success     = $false
		Critical    = $true # Was the error bad enough that no retries are to be done?
		Error       = $null
		ReturnValue = ''
		Duration    = $null
	}

	if (-not $agentName -or -not $profileName) {
		$result.Error = "Invalid task! Provide <agentname>\<profilename> as input: $Task"
		return $result
	}

	if (-not $MgmtAgents[$agentName]) {
		$result.Error = "Invalid task! Management Agent $($agentName) not found. Known MAs: $($MgmtAgents.Keys -join ', ')"
		return $result
	}
	$result.Critical = $false

	try {
		$response = $MgmtAgents[$agentName] | Invoke-CimMethod -MethodName Execute -Arguments @{ RunProfileName = $profileName } -ErrorAction Stop
	}
	catch {
		$result.Error = "Error executing profile $profileName against $($agentName): $_"
		return $result
	}
	
	$result.ReturnValue = $response.ReturnValue
	if ($response.ReturnValue -eq 'no-start-unknown-profile-name') {
		$result.Error = "Error executing profile $profileName against $($agentName): Profile not found!"
		$result.Critical = $true
		return $result
	}
	if ($response.ReturnValue -ne 'success') {
		$result.Error = "Error executing profile $profileName against $($agentName): $($result.ReturnValue)"
		return $result	
	}
	$result.Success = $true
	$result
}

function Update-RunProfileConfig {
	[CmdletBinding()]
	param (
		[hashtable]
		$Config
	)

	$defaults = @{
		# Name of the task. Used for messages
		Name              = '<Unnnamed>'
		# How many seconds to wait before starting a task
		WaitBefore        = 0
		# How many seconds to wait after the task is complete
		WaitAfter         = 15
		# How many times to try again in case of non-terminal failure
		RetryCount        = 0
		# How many seconds to wait before trying again after failing
		RetryWait         = 15
		# Whether to execute all Run Profiles in parallel or not
		Parallel          = $false
		# Whether a failure on this step should cause the entire config consider itself failed
		ContinueOnFail    = $false
		# Execute this step, even if the config is failed
		ExecuteWhenFailed = $false
	}

	foreach ($pair in $defaults.GetEnumerator()) {
		if ($Config.Keys -contains $pair.Key) { continue }
		$Config[$pair.Key] = $pair.Value
	}
}

function Invoke-RunProfileConfig {
	[CmdletBinding()]
	param (
		[hashtable]
		$Config,

		[hashtable]
		$Agents,

		[bool]
		$Healthy
	)

	Update-RunProfileConfig -Config $Config
	if (-not ($Healthy -or $Config.ExecuteWhenFailed)) {
		Write-Verbose "[$($Config.Name)] Skipping, as previous step failed!"
		return
	}
	Write-Verbose "[$($Config.Name)] Starting processing $($Config.RunProfiles.Count) Run Profile(s)"

	#region Code
	$code = {
		param (
			$RunProfile
		)

		$ErrorActionPreference = 'Stop'
		trap {
			[PSCustomObject]@{
				Profile  = $RunProfile
				Success  = $false
				Error    = $_
				Duration = (Get-Date) - $start
			}
			return
		}

		if ($WaitBefore -gt 0) { Start-Sleep -Seconds $WaitBefore }

		$start = Get-Date

		$currentCount = 0
		do {
			if ($currentCount -gt 0) { Start-Sleep -Seconds $RetryWait }

			$result = Invoke-RunProfile -MgmtAgents $managementAgents -Task $RunProfile
			if ($result.Success) { break } # All is well, no need to retry
			if ($result.Critical) { break } # No success is possible, no point trying again

			$currentCount++
		}
		until ($currentCount -gt $RetryCount)
		$result.Duration = (Get-Date) - $start

		if ($WaitAfter -gt 0) { Start-Sleep -Seconds $WaitAfter }

		$result
	}
	#endregion Code

	#region Execute
	$jobCount = 1
	if ($Config.Parallel) {
		$jobCount = $Config.RunProfiles.Count
		if ($Config.Throttle) { $jobCount = $Config.Throttle }
	}
	if ($jobCount -lt 1) { $jobCount = 1 }

	$results = $Config.RunProfiles | Invoke-Runspace -Scriptblock $code -Variables @{
		managementAgents = $Agents
		WaitBefore       = $Config.WaitBefore
		WaitAfter        = $Config.WaitAfter
		RetryCount       = $Config.RetryCount
		RetryWait        = $Config.RetryWait
	} -Functions @(
		Get-Command -Name Invoke-RunProfile -CommandType Function
	) -Throttle $jobCount -Wait
	#endregion Execute

	#region Result Processing
	$finalResult = [PSCustomObject]@{
		Name    = $Config.Name
		Config  = $Config
		Success = $true
		Tasks   = $results
	}

	foreach ($result in $results) {
		Write-Verbose "[$($Config.Name)]   RunProfile $($result.Profile) > Duration: $($result.Duration) | Success: $($result.Success)"
	}
	$failed = $results | Where-Object { -not $_.Success }
	if (-not $failed) { return $finalResult }

	foreach ($result in $failed) {
		Write-Warning "[$($Config.Name)]   RunProfile $($result.Profile) failed after $($result.Duration) | Error: $($result.Error)"
	}
	if ($Config.ContinueOnFail) { return $finalResult }
	Write-Warning "[$($Config.Name)] Failed in $($failed.Count) instance(s). The overall sequence is considered failed."

	$finalResult.Success = $false
	$finalResult
	#endregion Result Processing
}
#endregion Functions

$managementAgents = Get-ManagementAgent -AsHashtable
$healthy = $true
foreach ($step in $script:profileConfig.Keys | Sort-Object) {
	$result = Invoke-RunProfileConfig -Config $script:profileConfig[$step] -Agents $managementAgents -Healthy $healthy
	if (-not $result.Success) { $healthy = $false }
	if ($PassThru) { $result.Tasks }
}

if (-not $healthy -and -not $PassThru) {
	throw "Task Sequence Failed"
}