using Microsoft.MetadirectoryServices;
using Microsoft.MetadirectoryServices.Logging;
using Mms_Metaverse.Config;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Mms_Metaverse
{
    public class MAExtensionObject : IMASynchronization
    {
        private Utility _Util = new Utility();
        private SolutionConfiguration _SolutionConfiguration;

        public MAExtensionObject()
        {
            //
            // TODO: Add constructor logic here
            //
        }

        #region Interface Implementation: Not Used
        void IMASynchronization.Terminate()
        {
            //
            // TODO: write termination code.
            //
        }

        bool IMASynchronization.ShouldProjectToMV(CSEntry csentry, out string MVObjectType)
        {
            //
            // TODO: Remove this throw statement if you implement this method.
            //
            throw new EntryPointNotImplementedException();
        }

        DeprovisionAction IMASynchronization.Deprovision(CSEntry csentry)
        {
            //
            // TODO: Remove this throw statement if you implement this method.
            //
            throw new EntryPointNotImplementedException();
        }

        bool IMASynchronization.FilterForDisconnection(CSEntry csentry)
        {
            //
            // TODO: write disconnection filter code.
            //
            throw new EntryPointNotImplementedException();
        }

        void IMASynchronization.MapAttributesForJoin(string FlowRuleName, CSEntry csentry, ref ValueCollection values)
        {
            //
            // TODO: write join mapping code.
            //
            throw new EntryPointNotImplementedException();
        }

        bool IMASynchronization.ResolveJoinSearch(string joinCriteriaName, CSEntry csentry, MVEntry[] rgmventry, out int imventry, ref string MVObjectType)
        {
            //
            // TODO: write join resolution code.
            //
            throw new EntryPointNotImplementedException();
        }

        void IMASynchronization.MapAttributesForExport(string FlowRuleName, MVEntry mventry, CSEntry csentry)
        {
            //
            // TODO: write your export attribute flow code.
            //
            throw new EntryPointNotImplementedException();
        }
        #endregion Interface Implementation: Not Used

        void IMASynchronization.Initialize()
        {
            Logging.Log(new string('=', 60));
            Logging.Log("MA extension [Initialize] started", loggingLevel: 3);
            _Util.LogDllInfos(System.Reflection.Assembly.GetExecutingAssembly());
            try { _SolutionConfiguration = new SolutionConfiguration(); }
            catch (Exception e)
            {
                Logging.LogException(e, "MA Extension MIMActiveDirectoryMigration [Initialize]", "Configuration File Error", false);
                throw e;
            }
            Logging.Log("MA extension [Initialize] finished", loggingLevel: 3);
        }

        void IMASynchronization.MapAttributesForImport(string FlowRuleName, CSEntry csentry, MVEntry mventry)
        {
            Logging.Log($"MA extension: MapAttributesForImport - FlowRuleName: {FlowRuleName} | CSE: {csentry} | MVE: {mventry}", true, 4);
            ConnectorConfig config = _SolutionConfiguration.ConnectorsByConnectorName[csentry.MA.Name];

            if (config == null)
            {
                Logging.Log($"MA extension: No configuration defined for Connector '{csentry.MA.Name}'", true, 1);
                return;
            }

            if (config.Target)
                foreach (ConverterBase converter in _SolutionConfiguration.ConverterExportByAttribute.Values)
                    converter.Convert(mventry, csentry, config);
            else
                foreach (ConverterBase converter in _SolutionConfiguration.ConverterImportByAttribute.Values)
                    converter.Convert(mventry, csentry, config);
        }

    }
}
