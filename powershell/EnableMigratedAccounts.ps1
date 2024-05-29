[CmdletBinding()]
param (
	[string]
	$SearchBase = 'OU=Contoso,DC=contoso,DC=com',

	[int]
	$DaysBack = 7
)

Get-ADUser -SearchBase $SearchBase -LDAPFilter "(&(userAccountControl:1.2.840.113556.1.4.803:=2)(pwdLastSet>=$([DateTime]::now.AddDays(-$DaysBack).ToFileTime())))" -Properties pwdLastSet | Enable-ADAccount