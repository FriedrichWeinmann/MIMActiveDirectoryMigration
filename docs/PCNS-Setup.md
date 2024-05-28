# Setup - Password Change Notification Service

## Prerequisites

+ Create group in source domain (e.g.: MIMPwdReplicated)
+ Add SPN to MIM Service Account: PCNS/MIMServiceAccount.fabrikam.org

> Note: Adding all users under an OU to a group

To add all users in an OU structure to a group, run something like this:

```powershell
Get-ADUser -Filter * -SearchBase 'OU=Kunden,DC=contoso,DC=com' | Add-ADPrincipalGroupMembership -MemberOf MIMPwdReplicated
```

## Setup

Deploy setup files on all DCs in source domain.

> Once on Schema Master

```cmd
msiexec.exe /i "C:\PCNS\x64\Password Change Notification Service.msi" SCHEMAONLY=TRUE
```

> On all DCs

```cmd
msiexec.exe /i "C:\PCNS\x64\Password Change Notification Service.msi"
```

## Configure

```powershell
$name = 'MIM'
$hostname = 'mimsomim.fabrikam.org'
$serviceAccountSPN = 'PCNS/MIMServiceAccount.fabrikam.org'
$inclusionGroupName = 'MIMPwdReplicated'
& "C:\Program Files\Microsoft Password Change Notification\pcnscfg.exe" ADDTARGET /N:$name /A:$hostname /S:$serviceAccountSPN /FI:$inclusionGroupName
```
