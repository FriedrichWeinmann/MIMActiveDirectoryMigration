# MIM Active Directory User Migration

Welcome to the project to facilitate migrating users from one Active Directory Domain to another.
This projects uses the following tools to make it all happen:

+ Microsoft Identity Manager: For Replicating user objects and their attributes
+ Password Change Notification Service: To migrate passwords as they get changed by the users in the source environment(s)
+ PowerShell: To migrate SID history and general automation

> Note: This project is intended for mono-directional replication, not multi-directional replication.
> It is perfectly fine for multiple source domains being replicated into multiple destination domains.
> It will try to replicate the same relative OU structure in the target domains, under its own custom base path as configured.

## Steps to Migration

> Detailed Docs pending for each entry that has no link.

+ Install MIM Replication, ideally in the source Domain. Needs a SQL Server database, does _not_ need SharePoint or the MIM Portal.
+ Update Migration Extension if needed.
+ Install Migration Extension and configure it.
+ Configure Source settings on MIM.
+ Configure Destination settings on MIM.
+ [Execute object migration & schedule frequent updates](docs/Execute-and-Schedule.md)
+ [Set up Password Change Notification Service in source domains/forests](docs/PCNS-Setup.md)
+ [Execute SID History Migration](docs/Migrate-SID-History.md)
