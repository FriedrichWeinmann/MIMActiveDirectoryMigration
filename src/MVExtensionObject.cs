
using System;
using System.Text.RegularExpressions;
using Microsoft.MetadirectoryServices;
using Microsoft.MetadirectoryServices.Logging;
using Mms_Metaverse.Config;

namespace Mms_Metaverse
{
	public class MVExtensionObject : IMVSynchronization
    {
        private SolutionConfiguration _SolutionConfiguration;

        public MVExtensionObject()
        {
            
        }

        #region Interface Implementation
        void IMVSynchronization.Initialize ()
        {
            Logging.Log(new string('=', 60));
            Logging.Log("MV extension [Initialize] started", loggingLevel: 3);
            Utility.LogDllInfos(System.Reflection.Assembly.GetExecutingAssembly());
            try { _SolutionConfiguration = new SolutionConfiguration(); }
            catch (Exception e)
            {
                Logging.LogException(e, "MV Extension MIMActiveDirectoryMigration [Initialize]", "Configuration File Error", false);
                throw e;
            }
            Logging.Log("MV extension [Initialize] finished", loggingLevel: 3);
        }

        void IMVSynchronization.Terminate ()
        {
            Logging.Log("MV extension [Terminate] started", loggingLevel: 3);
            Logging.Log("MV extension [Terminate] finished", loggingLevel: 3);
            Logging.Log(new string('=', 60));
        }

        void IMVSynchronization.Provision (MVEntry mventry)
        {
            // Skip empty objects as delete provisions
            if (GetAttributeCount(mventry) == 0)
                return;

            Logging.Log("Provision start", true, 3);
            
            switch (mventry.ObjectType.ToLower())
            {
                case "person":
                    try { ProvisionUser(mventry); }
                    catch (Exception e)
                    {
                        string userDN = $"<unknown: {mventry.ToString()}>";
                        // On Delete this will fail
                        try { userDN = mventry["distinguishedName"].Value; }
                        catch {
                            Logging.Log("MV Extension [Provision] mventry with unexpected keys found, missing DistinguishedName");
                            foreach (string attrib in mventry)
                                Logging.Log($"MV Extension [Provision] [Debug] Attribute {attrib} | Value {mventry[attrib].Value}");
                        }
                        Logging.LogException(e, "Extension MIMActiveDirectoryMigration [Provision]", $"Person Provisioning Error: {userDN}", false);
                        Utility.LogExceptionDetails(e);
                        throw e;
                    }
                    break;
                default:
                    throw new EntryPointNotImplementedException();
            }
        }	

        bool IMVSynchronization.ShouldDeleteFromMV (CSEntry csentry, MVEntry mventry)
        {
            Logging.Log("MV extension [ShouldDeleteFromMV] started", loggingLevel: 3);
            // delete MV object, if the object is the SourceConnector
            bool shouldDeleteFromMV = Utility.IsSourceConnector(csentry);
            Logging.Log(String.Format("object '{0}' will be delete: {1}", mventry.ToString(), shouldDeleteFromMV.ToString()), loggingLevel: 3);
            Logging.Log("MV extension [ShouldDeleteFromMV] finished", loggingLevel: 3);
            return shouldDeleteFromMV;
        }
        #endregion Interface Implementation

        #region Flow Implementations
        public void ProvisionUser(MVEntry mventry)
        {
            if (!(mventry["distinguishedName"].IsPresent && mventry["accountName"].IsPresent))
            {
                Logging.Log($"Error provisioning person, missing critical information: {mventry["distinguishedName"].Value} | {mventry["accountName"].Value}", true);
                return;
            }

            foreach (ConnectorConfig target in _SolutionConfiguration.Targets)
            {
                ConnectedMA targetMA = mventry.ConnectedMAs[target.Connector];
                CSEntry csentry;
                switch (targetMA.Connectors.Count)
                {
                    case 0:
                        Logging.Log($"[{target.Name}][{mventry["distinguishedName"].Value}] Target not yet found in connectorspace. Creating ...", true, 3);
                        csentry = targetMA.Connectors.StartNewConnector("user");
                        csentry.DN = targetMA.CreateDN(ResolveProvisionDN(mventry["distinguishedName"].Value, target));
                        //csentry["distinguishedName"].Value = target.InsertRoot(mventry["distinguishedName"].Value);
                        csentry["sAMAccountName"].Value = mventry["accountName"].Value;
                        csentry["cn"].Value = mventry["cn"].Value;
                        try { csentry.CommitNewConnector(); }
                        catch (Exception e)
                        {
                            if (Regex.IsMatch(e.Message, "already exists in management agent"))
                            {
                                Logging.Log($"[{target.Name}][{mventry["distinguishedName"].Value}] Target already found in connectorspace. Updating ...", true, 3);
                                break;
                            }
                            throw e;
                        }
                        break;
                    case 1:
                        Logging.Log($"[{target.Name}][{mventry["distinguishedName"].Value}] Target already found in connectorspace. Updating ...", true, 3);
                        break;
                    default:
                        // How the hell did this happen?!
                        Logging.Log($"[{target.Name}][{mventry["distinguishedName"].Value}] Error processing user - more than one matching entry found in the connectorspace!", true, 1);
                        throw new ObjectAlreadyExistsException($"[{target.Name}][{mventry["distinguishedName"]}] Error processing user - more than one matching entry found in the connectorspace!");
                }
            }
        }
        #endregion Flow Implementations

        #region Utility
        private string ResolveProvisionDN(string SourceDN, ConnectorConfig Target)
        {
            if (SourceDN.EndsWith("%ROOT%", StringComparison.OrdinalIgnoreCase))
                return Regex.Replace(SourceDN, "%ROOT%$", Target.Root, RegexOptions.IgnoreCase);

            foreach (ConnectorConfig source in _SolutionConfiguration.Connectors)
                if (SourceDN.EndsWith(source.Root, StringComparison.OrdinalIgnoreCase))
                    return Regex.Replace(SourceDN, $"{source.Root}$", Target.Root, RegexOptions.IgnoreCase);

            return SourceDN;
        }
        
        private int GetAttributeCount(MVEntry mventry)
        {
            int count = 0;
            foreach (string attribute in mventry)
                count++;
            return count;
        }
        #endregion Utility
    }
}
