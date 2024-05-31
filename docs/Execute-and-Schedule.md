# Execute and Schedule Object Sync in MIM

To execute the migration, there are two phases:

+ Initial Replication
+ Continued Update throughout the migration phase

> Important: Any imports can be run in parallel, but never run more than one sync concurrently

## Initial Replication

+ First we need to full import from the _destination_ domains. Otherwise, provisioning of migrated users will fail, as the paths cannot be mapped.
+ Then we can do a full import of the source domains.
+ Then a full sync from the source(s) & a full sync of the destination(s)
+ Finally, export to destinations

## Schedule

MIM Run Profiles can be triggered via commandline, which can be scheduled in the Windows Task Scheduler on the MIM server.

[This script implements that.](../powershell/ScheduleMIMAgent.ps1)

This script could be called like this:

```powershell
powershell.exe -File C:\Scripts\ScheduleMIMAgent.ps1 -RunProfile 'Fabrikam\Delta Import', 'Fabrikam\Delta Sync', 'Contoso\Delta Sync', 'Contoso\Export'
```

Executes the specified RPs in the order provided:

+ Fabrikam\Delta Import
+ Fabrikam\Delta Sync
+ Contoso\Delta Sync
+ Contoso\Export

> "Fabrikam" being a Management Agent, "Delta Import" and "Delta Sync" being two of its Run Profiles.
