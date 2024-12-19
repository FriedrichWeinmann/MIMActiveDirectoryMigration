<#
.SYNOPSIS
	Transfers descriptions of OUs from one OU structure to another.

.DESCRIPTION
	Transfers descriptions of OUs from one OU structure to another.
	This transfer can happen within the same organization or across Active Directory domains.
	The executing account must have write access in the destination organization (At least for the OUs to be modified).

	The OUs will be considered the same based off their relative path to their respective root path.

.PARAMETER SourceOU
	The base OU from the OUs under which to take the Descriptions.

.PARAMETER DestinationOU
	The base OU to the OUs under which the description will be updated (if needed).

.PARAMETER ExcludeRoot
	Do not update the description of the root OU itself.
	By default, if the destination root OU has a different description, that too will be updated.

.PARAMETER WhatIf
	If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

.PARAMETER Confirm
	If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

.EXAMPLE
	PS C:\> .\Copy-OUDescription.ps1 -SourceOU 'OU=Fabrikam,DC=fabrikam,DC=org' -DestinationOU 'OU=Contoso,DC=contoso,DC=com'

	Copies all the descriptions from the source OUs under 'OU=Fabrikam,DC=fabrikam,DC=org' to the destination OUs under 'OU=Contoso,DC=contoso,DC=com'
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[Parameter(Mandatory = $true)]
	[string]
	$SourceOU,

	[Parameter(Mandatory = $true)]
	[string]
	$DestinationOU,

	[switch]
	$ExcludeRoot
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "Script Failed: $_"
	throw $_
}

#region Functions
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


function Get-OUDescription {
	[CmdletBinding()]
	param (
		[string]
		$Path
	)

	$escapedPath = [regex]::Escape($Path)
	$server = $Path -replace '^.+?,DC=' -replace ',DC=', '.'
	foreach ($adOU in Get-LdapObject -Server $server -SearchRoot $Path -LdapFilter '(objectCategory=organizationalUnit)' -Property Description, DistinguishedName) {
		[PSCustomObject]@{
			Path              = $adOU.DistinguishedName -replace $escapedPath, '%ROOT%'
			Description       = $adOU.Description
			Server            = $Server
			DistinguishedName = $adOU.DistinguishedName
		}
	}
}

function Resolve-OUDescriptionUpdate {
	[CmdletBinding()]
	param (
		$Source,
		$Destination
	)

	$sourceHash = @{}
	foreach ($sourceOU in $Source) {
		$sourceHash[$sourceOU.Path] = $sourceOU
	}

	foreach ($destinationOU in $Destination) {
		if (-not $sourceHash[$destinationOU.Path]) { continue }
		if ($sourceHash[$destinationOU.Path].Description -eq $destinationOU.Description) { continue }

		[PSCustomObject]@{
			Path = $destinationOU.Path
			Old = $destinationOU.Description
			New = $sourceHash[$destinationOU.Path].Description
			Server = $destinationOU.Server
			DistinguishedName = $destinationOU.DistinguishedName
		}
	}
}

function Update-OUDescription {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(ValueFromPipeline = $true)]
		$InputObject,

		[switch]
		$ExcludeRoot
	)

	process {
		foreach ($item in $InputObject) {
			if ($ExcludeRoot -and $item.Path -eq '%ROOT%') { continue }
			if (-not $PSCmdlet.ShouldProcess($item.DistinguishedName, "Update Description to: $($item.New)")) { continue }
			if (-not $item.New) { Set-ADObject -Server $item.Server -Identity $item.DistinguishedName -Clear Description -Confirm:$false }
			else { Set-ADObject -Server $item.Server -Identity $item.DistinguishedName -Replace @{ Description = $item.New } -Confirm:$false}
		}
	}
}
#endregion Functions

$sourceDescriptions = Get-OUDescription -Path $SourceOU
$destinationDescriptions = Get-OUDescription -Path $DestinationOU
Resolve-OUDescriptionUpdate -Source $sourceDescriptions -Destination $destinationDescriptions | Update-OUDescription -ExcludeRoot:$ExcludeRoot