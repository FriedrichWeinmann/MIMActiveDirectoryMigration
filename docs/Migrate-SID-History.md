# Migrating SID History

To migrate SID History, some preparations are needed:

+ The credentials used for both sides must be direct members of the Domain Admins group. No "Equivalent permissions" or anything like that.
+ There must be a trust between the domains, at least the source domain must trust the destination domain.
+ The principal being migrated must be of the same type (user to user, domain-local group to domain-local group, ...)
+ The DCs targeted in both domains must have "Account Management" auditing enabled
+ The source domain must have a group named "<sourcedomain NetBIOSName>$$$". E.g.: "CONTOSO$$$"
+ The destination Domain must be able to reach the source domain.

## PowerShell Tool

[Here's the PowerShell Script to do the migration.](../powershell/SIDHistoryMigration.ps1)

This tool can safely be run repeatedly to migrate additional accounts.

```powershell
$sourceOU = 'OU=Users,OU=Company,DC=fabrikam,DC=org'
$sourceServer = 'dc1.fabrikam.org'
$destServer = 'dc1.contoso.com'
$sourceCred = Get-Credential 'fabrikam\Administrator'
$destCred = Get-Credential 'contoso\Administrator'

.\SIDHistoryMigration.ps1 -SourceOU $sourceOU -SourceServer $sourceServer -SourceCredential $sourceCred -DestinationServer $destServer -DestinationCredential $destCred
```

This will try to migrate SID for all principals under the defined source OU.
