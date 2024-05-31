# Setup - Password Change Notification Service

## Prerequisites

+ Create group in source domain (e.g.: MIMPwdReplicated)
+ Add SPN to MIM Service Account: PCNS/MIMServiceAccount.fabrikam.org

Any SPN on the MIM Service Account will do, so if one already exists, you need not add another ... but it also does not hurt.

> Note: Adding all users under an OU to a group

To add all users in an OU structure to a group, run something like this:

```powershell
Get-ADUser -Filter * -SearchBase 'OU=Customers,DC=contoso,DC=com' | Add-ADPrincipalGroupMembership -MemberOf MIMPwdReplicated
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

> Note: Additional parameters may be needed, if MIM is not installed in the source forest.

Run this to get a list of parameters and their explanation:

```powershell
& "C:\Program Files\Microsoft Password Change Notification\pcnscfg.exe" /?
& "C:\Program Files\Microsoft Password Change Notification\pcnscfg.exe" ADDTARGET /?
& "C:\Program Files\Microsoft Password Change Notification\pcnscfg.exe" MODIFYTARGET /?
& "C:\Program Files\Microsoft Password Change Notification\pcnscfg.exe" REMOVETARGET /?
```
