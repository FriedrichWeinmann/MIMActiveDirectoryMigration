<#
.SYNOPSIS
	Adds or removes members to/from groups in bulk.

.DESCRIPTION
	Adds or removes members to/from groups in bulk.
	You can select principals to add based on pre-prepared filters or by defining your own.

.PARAMETER Group
	The group to add to or remove from.

.PARAMETER Mode
	Whether to add or remove.

.PARAMETER LdapFilter
	A custom LDAP Filter to select members by.
	If specified together with -Conditions, both filter parts are merged in an AND logic.

.PARAMETER Conditions
	Specific conditions to select principals by.
	Multiple conditions will be merged, with OR logic within their category (e.g. 'User' OR 'Computer'),
	with AND logic withut (e.g. 'User' AND 'Enabled')

.PARAMETER SearchBase
	The root OU to search from for members.

.PARAMETER Server
	The server / domain to work against.

.PARAMETER Credential
	The credentials to use for the operation.

.PARAMETER WhatIf
	If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

.PARAMETER Confirm
	If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

.EXAMPLE
	PS C:\> .\BulkGroupMembers.ps1 -Group HR-Discussions -Conditions User, Enabled -Mode Add -SearchBase 'OU=HR,OU=Users,DC=contoso,DC=com'

	Will add all enabled users under 'OU=HR,OU=Users,DC=contoso,DC=com' to the group "HR-DIscussions"
#>
[CmdletBinding(DefaultParameterSetName = 'Filter', SupportsShouldProcess = $true)]
param (
	[Parameter(Mandatory = $true)]
	[string]
	$Group,

	[Parameter(Mandatory = $true)]
	[ValidateSet('Add', 'Remove')]
	[string]
	$Mode,

	[string]
	$LdapFilter,

	[ValidateSet('Enabled', 'Disabled', 'User', 'Group', 'Computer', 'gMSA')]
	[string[]]
	$Conditions,

	[string]
	$SearchBase,

	[string]
	$Server,

	[PSCredential]
	$Credential
)

$ErrorActionPreference = 'Stop'
trap {
	Write-Warning "Script Failed: $_"
	$PSCmdlet.ThrowTerminatingError($_)
}

#region Functions
function Resolve-ADParameter {
	[OutputType([hashtable])]
	[CmdletBinding()]
	param (
		[AllowEmptyString()]
		[string]
		$Server,

		[AllowNull()]
		[PSCredential]
		$Credential
	)

	$param = @{ }
	if ($Server) { $param.Server = $Server }
	if ($Credential) { $param.Credential = $Credential }
	$param
}

function Resolve-SearchParameter {
	[OutputType([hashtable])]
	[CmdletBinding()]
	param (
		[AllowEmptyString()]
		[string]
		$SearchBase,

		[string]
		$SearchScope,

		[string]
		$LdapFilter,

		[string[]]
		$Conditions
	)

	$conditionGroups = @{
		Category = @{
			Filter = '(objectCategory={0})'
			Values = @(
				'User'
				'Group'
				'Computer'
				'gMSA'
			)
		}
		State    = @{
			Values = @(
				'Enabled'
				'Disabled'
			)
			FilterHash = @{
				Enabled = '(!(userAccountControl:1.2.840.113556.1.4.803:=2))'
				Disabled = '(userAccountControl:1.2.840.113556.1.4.803:=2)'
			}
		}
	}


	$param = @{ }
	if ($SearchBase) { $param.SearchBase = $SearchBase }
	if ($SearchScope) { $param.SearchScope = $SearchScope }

	$filterFragments = @()
	if ($LdapFilter) { $filterFragments += $LdapFilter }
	if ($Conditions) {
		$processed = [System.Collections.ArrayList]@()

		foreach ($pair in $conditionGroups.GetEnumerator()) {
			$chosen = @($pair.Value.Values).Where{ $_ -in $Conditions }
			if ($chosen.Count -lt 1) { continue }

			$subFragments = foreach ($entry in $chosen) {
				$filter = $pair.Value.Filter
				if ($pair.Value.FilterHash.$entry) {
					$filter = $pair.Value.FilterHash.$entry
				}
				$filter -f $entry
			}
			if ($subFragments.Count -eq 1) {
				$filterFragments += $subFragments
			}
			else {
				$filterFragments += '(|{0})' -f ($subFragments -join '')
			}
			$processed.AddRange($chosen)
		}

		foreach ($item in $Conditions) {
			if ($processed -contains $item) { continue }

			switch ($item) {
				default {
					Write-Warning "No filter condition implemented for $item!"
				}
			}
		}
	}

	if (-not $filterFragments) { $filterFragments = '(objectClass=*)' }
	$param.LdapFilter = '(&{0})' -f ($filterFragments -join '')

	$param
}

function Update-GroupMembership {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateSet('Add', 'Remove')]
		[string]
		$Mode,

		[string]
		$Group,

		[parameter(ValueFromPipeline = $true)]
		$InputObject,
	
		[AllowEmptyString()]
		[string]
		$Server,

		[AllowNull()]
		[PSCredential]
		$Credential
	)

	begin {
		$adParam = Resolve-ADParameter -Server $Server -Credential $Credential

		$principals = [System.Collections.ArrayList]@()
	}
	process {
		$principals.AddRange(@($InputObject))
	}
	end {
		switch ($Mode) {
			Add {
				Add-ADGroupMember @adParam -Identity $Group -Members $principals
			}
			Remove {
				Remove-ADGroupMember @adParam -Identity $Group -Members $principals
			}
		}
	}
}
#endregion Functions

$adParam = Resolve-ADParameter -Server $Server -Credential $Credential
$searchParam = Resolve-SearchParameter -SearchBase $SearchBase -LdapFilter $LdapFilter -Conditions $Conditions
Get-ADObject @adParam @searchParam | Update-GroupMembership @adParam -Group $Group -Mode $Mode