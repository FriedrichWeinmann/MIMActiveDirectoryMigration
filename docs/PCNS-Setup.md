# Setup - Password Change Notification Service

## Prerequisites

+ Create group in source domain (e.g.: XXX)
+ Add SPN to MIM Service Account: PCNS/MIMServiceAccount.fabrikam.org

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
