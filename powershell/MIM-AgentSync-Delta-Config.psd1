<#
@{
	# Name of the task. Used for messages
	Name = '<Unnnamed>'

	# How many seconds to wait before starting a task
	WaitBefore = 0

	# How many seconds to wait after the task is complete
	WaitAfter = 15

	# How many times to try again in case of non-terminal failure
	RetryCount = 0

	# How many seconds to wait before trying again after failing
	RetryWait = 15

	# Whether to execute all Run Profiles in parallel or not
	Parallel = $false

	# Whether a failure on this step should cause the entire config consider itself failed
	ContinueOnFail = $false
	
	# Execute this step, even if the config is failed
	ExecuteWhenFailed = $false
}
#>
@{
	# Import
	1 = @{
		Name        = 'Import'
		WaitBefore  = 0
		WaitAfter   = 15
		RetryCount  = 0
		RetryWait   = 300
		RunProfiles = @(
			'fabrikamMA\Users1 Delta Import (Stage Only)'
			'fabrikamMA\Users2 Delta Import (Stage Only)'
		)
		Parallel    = $true
		# ContinueOnFail = $true
		# ExecuteWhenFailed = $true
	}
	# Sync
	2 = @{
		Name        = 'Sync'
		WaitBefore  = 0
		WaitAfter   = 15
		RetryCount  = 0
		RetryWait   = 300
		RunProfiles = @(
			'fabrikamMA\Users1 Delta Synchronization'
			'fabrikamMA\Users2 Delta Synchronization'
		)
		Parallel    = $false
		# ContinueOnFail = $true
		# ExecuteWhenFailed = $true
	}
	# Export
	3 = @{
		Name        = 'Export'
		WaitBefore  = 0
		WaitAfter   = 0
		RetryCount  = 0
		RetryWait   = 300
		RunProfiles = @(
			'ContosoMA\UsersAll Export'
		)
		Parallel    = $true
		# ContinueOnFail = $true
		ExecuteWhenFailed = $true
	}
}