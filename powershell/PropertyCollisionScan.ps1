<#
.SYNOPSIS
	Name collision scan, searching for users across multiple domains that share a property.

.DESCRIPTION
	Name collision scan, searching for users across multiple domains that share a property.
	Use this script to prevent unexpected collisions between accounts across domains.

	Helps avoiding trouble in user migrations and MIM replications where multiple domains contain accounts that will collide,
	when in fact they should not.

.PARAMETER Server
	The domains / DCs to scan. Avoid specifying multiple DCs of the same domain, as that will lead to result duplication.
	You can also provide the DistinguishedName of an OU instead of a domain.

.PARAMETER Credential
	The credentials to use for the connections.
	Will be used for ALL servers provided in -Server - if you need differentiated credentials per server, use the -Connections parameter instead.

.PARAMETER Connections
	A hashtable of connections to use.
	The hashtable must use the domain/dc name (or OU Path) as key and the credentials as value.
	Example:
	@{ 'contoso.com' = $cred }
	Keys without values or values that are not PSCredential will be queried as the current account.

.PARAMETER Properties
	What properties to check for collision.
	Defaults to Name, SamAccountName

.EXAMPLE
	PS C:\> .\PropertyCollisionScan.ps1 -Server contoso.com, fabrikam.org

	Scans the domains contoso.com, fabrikam.org for users, that share a name or SamAccountName.
#>
[CmdletBinding()]
param (
	[string[]]
	$Server,

	[PSCredential]
	$Credential,

	[hashtable]
	$Connections,

	[string[]]
	$Properties = @('Name', 'SamAccountName')
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "Script Failed: $_"
	throw $_
}

#region Functions
function Invoke-TerminatingException {
	<#
	.SYNOPSIS
		Throw a terminating exception in the context of the caller.
	
	.DESCRIPTION
		Throw a terminating exception in the context of the caller.
		Masks the actual code location from the end user in how the message will be displayed.
	
	.PARAMETER Cmdlet
		The $PSCmdlet variable of the calling command.
	
	.PARAMETER Message
		The message to show the user.
	
	.PARAMETER Exception
		A nested exception to include in the exception object.
	
	.PARAMETER Category
		The category of the error.
	
	.PARAMETER ErrorRecord
		A full error record that was caught by the caller.
		Use this when you want to rethrow an existing error.
	
	.EXAMPLE
		PS C:\> Invoke-TerminatingException -Cmdlet $PSCmdlet -Message 'Unknown calling module'
	
		Terminates the calling command, citing an unknown caller.
#>
	[CmdletBinding()]
	Param (
		[Parameter(Mandatory = $true)]
		$Cmdlet,
		
		[string]
		$Message,
		
		[System.Exception]
		$Exception,
		
		[System.Management.Automation.ErrorCategory]
		$Category = [System.Management.Automation.ErrorCategory]::NotSpecified,
		
		[System.Management.Automation.ErrorRecord]
		$ErrorRecord
	)
	
	process {
		if ($ErrorRecord -and -not $Message) {
			$Cmdlet.ThrowTerminatingError($ErrorRecord)
		}
		
		$exceptionType = switch ($Category) {
			default { [System.Exception] }
			'InvalidArgument' { [System.ArgumentException] }
			'InvalidData' { [System.IO.InvalidDataException] }
			'AuthenticationError' { [System.Security.Authentication.AuthenticationException] }
			'InvalidOperation' { [System.InvalidOperationException] }
		}
		
		
		if ($Exception) { $newException = $Exception.GetType()::new($Message, $Exception) }
		elseif ($ErrorRecord) { $newException = $ErrorRecord.Exception.GetType()::new($Message, $ErrorRecord.Exception) }
		else { $newException = $exceptionType::new($Message) }
		$record = [System.Management.Automation.ErrorRecord]::new($newException, (Get-PSCallStack)[1].FunctionName, $Category, $Target)
		$Cmdlet.ThrowTerminatingError($record)
	}
}

function Resolve-Connection {
	[CmdletBinding()]
	param (
		[AllowEmptyCollection()]
		[AllowNull()]
		[string[]]
		$Server,

		[AllowNull()]
		[PSCredential]
		$Credential,

		[AllowNull()]
		[hashtable]
		$Connections,

		$Cmdlet
	)

	if (-not $Server -and -not $Connections) {
		Invoke-TerminatingException -Cmdlet $Cmdlet -Message "Must provide either -Server or -Connections parameter!" -Category InvalidArgument
	}

	$credParam = @{ }
	if ($Credential) { $credParam.Credential = $Credential }

	foreach ($computer in $Server) {
		if ($computer -match ',DC=') {
			@{
				Server = $computer -replace '^.+?,DC=' -replace ',DC=','.'
				SearchRoot = $computer
			} + $credParam
			continue
		}

		@{ Server = $Computer } + $credParam
	}

	if (-not $Connections) { return }
	foreach ($pair in $Connections.GetEnumerator()) {
		if ($pair.Key -in $Server) { continue }

		$param = @{ Server = $pair.Key }
		if ($param.Server -match ',DC=') {
			$param = @{
				Server = $param.Server -replace '^.+?,DC=' -replace ',DC=','.'
				SearchRoot = $param.Server
			}
		}

		if ($pair.Value -is [PSCredential]) {
			$param.Credential = $pair.Value
		}
		$param
	}
}

function Get-LdapObject {

	<#
        .SYNOPSIS
            Use LDAP to search in Active Directory

        .DESCRIPTION
            Utilizes LDAP to perform swift and efficient LDAP Queries.

        .PARAMETER LdapFilter
            The search filter to use when searching for objects.
            Must be a valid LDAP filter.

        .PARAMETER Property
            The properties to retrieve.
            Keep bandwidth in mind and only request what is needed.

        .PARAMETER SearchRoot
            The root path to search in.
            This generally expects either the distinguished name of the Organizational unit or the DNS name of the domain.
            Alternatively, any legal LDAP protocol address can be specified.

        .PARAMETER Configuration
            Rather than searching in a specified path, switch to the configuration naming context.

        .PARAMETER Raw
            Return the raw AD object without processing it for PowerShell convenience.

        .PARAMETER PageSize
            Rather than searching in a specified path, switch to the schema naming context.

        .PARAMETER MaxSize
            The maximum number of items to return.

        .PARAMETER SearchScope
            Whether to search all OUs beneath the target root, only directly beneath it or only the root itself.
    
        .PARAMETER AddProperty
            Add additional properties to the output object.
            Use to optimize performance, avoiding needing to use Add-Member.

        .PARAMETER Server
            The server to contact for this query.

        .PARAMETER Credential
            The credentials to use for authenticating this query.
    
        .PARAMETER TypeName
            The name to give the output object

        .EXAMPLE
            PS C:\> Get-LdapObject -LdapFilter '(PrimaryGroupID=516)'
            
            Searches for all objects with primary group ID 516 (hint: Domain Controllers).
    #>
	[Alias('ldap')]
	[CmdletBinding(DefaultParameterSetName = 'SearchRoot')]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[string]
		$LdapFilter,
        
		[Alias('Properties')]
		[string[]]
		$Property = "*",
        
		[Parameter(ParameterSetName = 'SearchRoot')]
		[Alias('SearchBase')]
		[string]
		$SearchRoot,
        
		[Parameter(ParameterSetName = 'Configuration')]
		[switch]
		$Configuration,
        
		[switch]
		$Raw,
        
		[ValidateRange(1, 1000)]
		[int]
		$PageSize = 1000,
        
		[Alias('SizeLimit')]
		[int]
		$MaxSize,
        
		[System.DirectoryServices.SearchScope]
		$SearchScope = 'Subtree',
        
		[System.Collections.Hashtable]
		$AddProperty,
        
		[string]
		$Server,
        
		[PSCredential]
		$Credential,
        
		[Parameter(DontShow = $true)]
		[string]
		$TypeName
	)
    
	begin {
		#region Utility Functions
		function Get-PropertyName {
			[OutputType([string])]
			[CmdletBinding()]
			param (
				[string]
				$Key,
                
				[string[]]
				$Property
			)
            
			if ($hit = @($Property).Where{ $_ -eq $Key }) { return $hit[0] }
			if ($Key -eq 'ObjectClass') { return 'ObjectClass' }
			if ($Key -eq 'ObjectGuid') { return 'ObjectGuid' }
			if ($Key -eq 'ObjectSID') { return 'ObjectSID' }
			if ($Key -eq 'DistinguishedName') { return 'DistinguishedName' }
			if ($Key -eq 'SamAccountName') { return 'SamAccountName' }
			$script:culture.TextInfo.ToTitleCase($Key)
		}
        
		function New-DirectoryEntry {
			<#
        .SYNOPSIS
            Generates a new directoryy entry object.
        
        .DESCRIPTION
            Generates a new directoryy entry object.
        
        .PARAMETER Path
            The LDAP path to bind to.
        
        .PARAMETER Server
            The server to connect to.
        
        .PARAMETER Credential
            The credentials to use for the connection.
        
        .EXAMPLE
            PS C:\> New-DirectoryEntry

            Creates a directory entry in the default context.

        .EXAMPLE
            PS C:\> New-DirectoryEntry -Server dc1.contoso.com -Credential $cred

            Creates a directory entry in the default context of the target server.
            The connection is established to just that server using the specified credentials.
    #>
			[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
			[CmdletBinding()]
			param (
				[string]
				$Path,
        
				[AllowEmptyString()]
				[string]
				$Server,
        
				[PSCredential]
				[AllowNull()]
				$Credential
			)
    
			if (-not $Path) { $resolvedPath = '' }
			elseif ($Path -like "LDAP://*") { $resolvedPath = $Path }
			elseif ($Path -notlike "*=*") { $resolvedPath = "LDAP://DC={0}" -f ($Path -split "\." -join ",DC=") }
			else { $resolvedPath = "LDAP://$($Path)" }
    
			if ($Server -and ($resolvedPath -notlike "LDAP://$($Server)/*")) {
				$resolvedPath = ("LDAP://{0}/{1}" -f $Server, $resolvedPath.Replace("LDAP://", "")).Trim("/")
			}
    
			if (($null -eq $Credential) -or ($Credential -eq [PSCredential]::Empty)) {
				if ($resolvedPath) { New-Object System.DirectoryServices.DirectoryEntry($resolvedPath) }
				else {
					$entry = New-Object System.DirectoryServices.DirectoryEntry
					New-Object System.DirectoryServices.DirectoryEntry(('LDAP://{0}' -f $entry.distinguishedName[0]))
				}
			}
			else {
				if ($resolvedPath) { New-Object System.DirectoryServices.DirectoryEntry($resolvedPath, $Credential.UserName, $Credential.GetNetworkCredential().Password) }
				else { New-Object System.DirectoryServices.DirectoryEntry(("LDAP://DC={0}" -f ($env:USERDNSDOMAIN -split "\." -join ",DC=")), $Credential.UserName, $Credential.GetNetworkCredential().Password) }
			}
		}
		#endregion Utility Functions
        
		$script:culture = Get-Culture

		#region Prepare Searcher
		$searcher = New-Object system.directoryservices.directorysearcher
		$searcher.PageSize = $PageSize
		$searcher.SearchScope = $SearchScope
        
		if ($MaxSize -gt 0) {
			$Searcher.SizeLimit = $MaxSize
		}
        
		if ($SearchRoot) {
			$searcher.SearchRoot = New-DirectoryEntry -Path $SearchRoot -Server $Server -Credential $Credential
		}
		else {
			$searcher.SearchRoot = New-DirectoryEntry -Server $Server -Credential $Credential
		}
		if ($Configuration) {
			$searcher.SearchRoot = New-DirectoryEntry -Path ("LDAP://CN=Configuration,{0}" -f $searcher.SearchRoot.distinguishedName[0]) -Server $Server -Credential $Credential
		}
        
		Write-Verbose "Searching $($SearchScope) in $($searcher.SearchRoot.Path)"
        
		if ($Credential) {
			$searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry($searcher.SearchRoot.Path, $Credential.UserName, $Credential.GetNetworkCredential().Password)
		}
        
		$searcher.Filter = $LdapFilter
        
		foreach ($propertyName in $Property) {
			$null = $searcher.PropertiesToLoad.Add($propertyName)
		}
        
		Write-Verbose "Search filter: $LdapFilter"
		#endregion Prepare Searcher
	}
	process {
		try {
			$ldapObjects = $searcher.FindAll()
		}
		catch {
			throw
		}
		foreach ($ldapobject in $ldapObjects) {
			if ($Raw) {
				$ldapobject
				continue
			}
			#region Process/Refine Output Object
			$resultHash = @{ }
			foreach ($key in $ldapobject.Properties.Keys) {
				$resultHash[(Get-PropertyName -Key $key -Property $Property)] = switch ($key) {
					'ObjectClass' { $ldapobject.Properties[$key][@($ldapobject.Properties[$key]).Count - 1] }
					'ObjectGuid' { [guid]::new(([byte[]]($ldapobject.Properties[$key] | Write-Output))) }
					'ObjectSID' { [System.Security.Principal.SecurityIdentifier]::new(([byte[]]($ldapobject.Properties[$key] | Write-Output)), 0) }
                        
					default { $ldapobject.Properties[$key] | Write-Output }
				}
			}
			if ($resultHash.ContainsKey("ObjectClass")) { $resultHash["PSTypeName"] = $resultHash["ObjectClass"] }
			if ($TypeName) { $resultHash["PSTypeName"] = $TypeName }
			if ($AddProperty) { $resultHash += $AddProperty }
			$item = [pscustomobject]$resultHash
			Add-Member -InputObject $item -MemberType ScriptMethod -Name ToString -Value {
				if ($this.DistinguishedName) { $this.DistinguishedName }
				else { $this.AdsPath }
			} -Force -PassThru
			#endregion Process/Refine Output Object
		}
	}
}

function Get-LdapUser {
	[CmdletBinding(DefaultParameterSetName = 'Filter')]
	param (
		[string]
		$Server,

		[PSCredential]
		$Credential,

		[Parameter(ParameterSetName = 'Filter')]
		[string]
		$LdapFilter = '(objectCategory=user)',

		[Parameter(ParameterSetName = 'Build')]
		[ValidateSet('Enabled', 'Disabled')]
		[string[]]
		$Type,

		[string]
		$SearchRoot,

		[string[]]
		$Property
	)

	if ($Type) {
		$fragments = @('(objectCategory=user)')
		foreach ($entry in $Type) {
			switch ($entry) {
				Enabled { $fragments += '(!(userAccountControl:1.2.840.113556.1.4.803:=2))' }
				Disabled { $fragments += '(userAccountControl:1.2.840.113556.1.4.803:=2)' }
			}
		}
		$LdapFilter = '(&{0})' -f ($fragments -join '')
	}

	if ($SearchRoot -and -not $Server) {
		$Server = $SearchRoot -replace '^.+?,DC=' -replace ',DC=', '.'
	}

	$param = @{}
	if ($Server) { $param.Server = $Server }
	if ($Credential) { $param.Credential = $Credential }
	if ($SearchRoot) { $param.SearchRoot = $SearchRoot }

	$users = Get-LdapObject @param -LdapFilter $LdapFilter -Property $Property -Raw
	foreach ($user in $users) {
		$userHash = @{ }
		$userHash.DistinguishedName = $user.Path -replace '^LDAP://[^/]+/'
		foreach ($name in $Property) {
			$userHash[$name] = $user.Properties[$name.ToLower()][0]
		}

		$userHash.Domain = $user.Path -replace '^.+?,DC=' -replace ',DC=', '.'
		[PSCUstomObject]$userHash
	}
}

function ConvertTo-ADPropertyDuplication {
	[CmdletBinding()]
	param (
		$Data,

		$Property
	)

	$grouped = $Data | Group-Object $Property | Where-Object Count -GT 1
	foreach ($group in $grouped) {
		[PSCustomObject]@{
			Property = $Property
			Value    = $group.Name
			Domains  = $group.Group.Domain
			Users    = $group.Group.DistinguishedName
		}
	}
}
#endregion Functions

$connectionData = Resolve-Connection -Connections $Connections -Server $Server -Credential $Credential -Cmdlet $PSCmdlet
$users = foreach ($connectionEntry in $connectionData) {
	Get-LdapUser @connectionEntry -Property $Properties
}
foreach ($property in $Properties) {
	ConvertTo-ADPropertyDuplication -Data $users -Property $property
}