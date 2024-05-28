using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml;
using Microsoft.MetadirectoryServices;
using Microsoft.MetadirectoryServices.Logging;

namespace Mms_Metaverse
{
    public class Utility
    {
        public static void LogDllInfos(System.Reflection.Assembly assembly)
        {
            Logging.Log("Common.Utils [getDllInfos] started", loggingLevel: 3);

            string dllName = assembly.GetName().Name;
            string dllVersion = assembly.GetName().Version.ToString();
            string dllCodebase = assembly.CodeBase.Remove(0, 8); // remove 'file:///' from string
            string dllFileCreationTime = System.IO.File.GetLastWriteTimeUtc(dllCodebase).ToString();

            Logging.Log(string.Format("extension name: {0}", dllName), loggingLevel: 2);
            Logging.Log(string.Format("extension file: {0}", dllCodebase), loggingLevel: 2);
            Logging.Log(string.Format("extension version: {0}", dllVersion), loggingLevel: 2);
            Logging.Log(string.Format("extension file creation time : {0}", dllFileCreationTime), loggingLevel: 2);
            Logging.Log("Common.Utils [getDllInfos] finished", loggingLevel: 3);
        }

        public static void LogExceptionDetails(Exception e)
        {
            Logging.Log(new string('-', 50));
            Logging.Log(e.Message, true, 1);
            Logging.Log(new string('_', 20));
            foreach (string line in e.StackTrace.Split('\n'))
                Logging.Log(line.TrimEnd(), true, 1);
            Logging.Log(new string('-', 50));
        }

        public static bool IsSourceConnector(CSEntry csentry)
        {
            bool isSourceConnector = csentry.ConnectionRule.Equals(RuleType.Projection);
            return isSourceConnector;
        }
    }
}
