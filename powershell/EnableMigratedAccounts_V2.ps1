<#
.SYNOPSIS
	Enables all accounts in the destination OU that are also enabled in the source OU.

.DESCRIPTION
	Enables all accounts in the destination OU that are also enabled in the source OU.
	The users are matched by SamAccountName.

	If needed, a new random password will be assigned before enabling the account.
	The password will NOT be reported anywhere - this is merely to meet the technical requirements needed to enable it.

.PARAMETER SourceOU
	The OU from which enabled users are read as reference.
	Will search the entire subtree.

.PARAMETER DestinationOU
	The OU under which disabled accounts are searched, that should be enabled.
	Will search the entire subtree.

.PARAMETER Credential
	The credentials that should be used against the destination domain.

.PARAMETER SourceCredential
	The crdentials that should be used against the source domain.

.EXAMPLE
	PS C:\> .\EnableMigratedAccounts_V2.ps1 -SourceOU 'OU=Fabrikam,DC=fabrikam,DC=org' -DestinationOU 'OU=Contoso,DC=contoso,DC=com'

	Enables all users under 'OU=Contoso,DC=contoso,DC=com' that also exist and are enabled under 'OU=Fabrikam,DC=fabrikam,DC=org' is needed.
	No action is taken against accounts already set up, no passwords will be applied to accounts that already have them.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[string]
	$SourceOU,

	[string]
	$DestinationOU,

	[PSCredential]
	$Credential,

	[PSCredential]
	$SourceCredential
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "Script Failed: $_"
	throw $_
}

#region Functions
function New-Password {
	<#
		.SYNOPSIS
			Generate a new, complex password.
		
		.DESCRIPTION
			Generate a new, complex password.
		
		.PARAMETER Length
			The length of the password calculated.
			Defaults to 32

		.PARAMETER AsSecureString
			Returns the password as secure string.
		
		.EXAMPLE
			PS C:\> New-Password

			Generates a new 32 character password.
	#>
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
	[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
	[CmdletBinding()]
	Param (
		[int]
		$Length = 32,

		[switch]
		$AsSecureString
	)
	
	begin {
		$characters = @{
			0 = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
			1 = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
			2 = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
			3 = @('#', '$', '%', '&', "'", '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@')
			4 = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
			5 = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
			6 = @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9)
			7 = @('#', '$', '%', '&', "'", '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@')
		}
	}
	process {
		$letters = foreach ($number in (1..$Length)) {
			$characters[(($number % 4) + (1..4 | Get-Random))] | Get-Random
		}
		$letters = $letters | Sort-Object { Get-Random }
		if ($AsSecureString) { $letters -join "" | ConvertTo-SecureString -AsPlainText -Force }
		else { $letters -join "" }
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

function Enable-Account {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(ValueFromPipeline = $true)]
		$InputObject,

		[string]
		$Server,

		[AllowNull()]
		[PSCredential]
		$Credential
	)

	begin {
		$adParam = @{ }
		if ($Server) { $adParam.Server = $Server }
		if ($Credential) { $adParam.Credential = $Credential }

		$adParam.Server = (Get-ADDomain @adParam).PDCEmulator
	}
	process {
		foreach ($user in $InputObject) {
			if ($user.PwdLastSet -eq 0) {
				$null = Set-ADAccountPassword @adParam -Identity $user.SamAccountName -PassThru -NewPassword (New-Password -Length 32 -AsSecureString)
			}

			$null = Enable-ADAccount @adParam -Identity $user.SamAccountName
		}
	}
}

function Disable-Account {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(ValueFromPipeline = $true)]
		$InputObject,

		[string]
		$Server,

		[AllowNull()]
		[PSCredential]
		$Credential
	)

	begin {
		$adParam = @{ }
		if ($Server) { $adParam.Server = $Server }
		if ($Credential) { $adParam.Credential = $Credential }

		$adParam.Server = (Get-ADDomain @adParam).PDCEmulator
	}

	process {
		foreach ($user in $InputObject) {
			$null = Disable-ADAccount @adParam -Identity $user.SamAccountName
		}
	}
}

#endregion Functions

#-> Enable in Destination what is Enabled in Source
$sourceEnabledUsers = Get-LdapUser -Credential $SourceCredential -SearchRoot $SourceOU -Type Enabled -Property SamAccountName
$destinationDisabledUsers = Get-LdapUser -Credential $Credential -SearchRoot $DestinationOU -Type Disabled -Property SamAccountName, PwdLastSet
$destinationDisabledUsers | Where-Object SamAccountName -In $sourceEnabledUsers.SamAccountName | Enable-Account -Server ($DestinationOU -replace '^.+?,DC=' -replace ',DC=', '.') -Credential $Credential

#-> Disable in Destination what is Disabled in Source
$sourceDisabledUsers = Get-LdapUser -Credential $SourceCredential -SearchRoot $SourceOU -Type Disabled -Property SamAccountName
$destinationEnabledUsers = Get-LdapUser -Credential $Credential -SearchRoot $DestinationOU -Type Enabled -Property SamAccountName, PwdLastSet
$destinationEnabledUsers | Where-Object SamAccountName -In $sourceDisabledUsers.SamAccountName | Disable-Account -Server ($DestinationOU -replace '^.+?,DC=' -replace ',DC=', '.') -Credential $Credential