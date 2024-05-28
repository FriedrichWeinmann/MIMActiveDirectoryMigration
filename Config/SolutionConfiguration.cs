using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml;
//using System.Xml.Linq;
using System.IO;
using Microsoft.MetadirectoryServices;
using Microsoft.MetadirectoryServices.Logging;

namespace Mms_Metaverse.Config
{
    public class SolutionConfiguration
    {
        public List<ConnectorConfig> Connectors = new List<ConnectorConfig>();
        public List<ConnectorConfig> Targets = new List<ConnectorConfig>();
        public Dictionary<string, ConnectorConfig> ConnectorsByName = new Dictionary<string, ConnectorConfig>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, ConnectorConfig> ConnectorsByConnectorName = new Dictionary<string, ConnectorConfig>(StringComparer.OrdinalIgnoreCase);

        public List<ConverterBase> AttributeConverters = new List<ConverterBase>();
        public Dictionary<string, ConverterBase> ConverterImportByAttribute = new Dictionary<string, ConverterBase>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, ConverterBase> ConverterExportByAttribute = new Dictionary<string, ConverterBase>(StringComparer.OrdinalIgnoreCase);

        // constructor
        public SolutionConfiguration()
        {
            Logging.Log("SolutionConfiguration [constructor] started", loggingLevel: 3);
            try { LoadConfiguration(); }
            catch (Exception e)
            {
                Utility.LogExceptionDetails(e);
                throw e;
            }
            Logging.Log("SolutionConfiguration [constructor] finished", loggingLevel: 3);
        }
        public void LoadConfiguration()
        {
            Logging.Log("SolutionConfiguration [LoadConfiguration] started", loggingLevel: 3);
            string configPath = Path.Combine(Utils.ExtensionsDirectory, Constants.ConfigFolder, Constants.ConfigFileName);
            XmlDocument document = new XmlDocument();
            document.Load(configPath);
            
            // Load Connector Configurations
            foreach (XmlElement entry in document.SelectNodes(Constants.ConfigXPathConnectors))
            {
                ConnectorConfig organization = new ConnectorConfig(entry);
                Connectors.Add(organization);
                ConnectorsByName[organization.Name] = organization;
                ConnectorsByConnectorName[organization.Connector] = organization;
                if (organization.Target)
                    Targets.Add(organization);
            }

            // Load Import Conversions
            foreach (XmlElement entry in document.SelectNodes(Constants.ConfigXPathImportConversion))
                CreateConverter(entry, Direction.Import);

            // Load Export Conversions
            foreach (XmlElement entry in document.SelectNodes(Constants.ConfigXPathExportConversion))
                CreateConverter(entry, Direction.Export);

            Logging.Log("SolutionConfiguration [LoadConfiguration] finished", loggingLevel: 3);
        }

        private void CreateConverter(XmlElement Entry, Direction Direction)
        {
            XmlNode typeNode = Entry.SelectSingleNode("type");
            if (typeNode == null)
            {
                Logging.Log($"SolutionConfiguration: Error loading conversion configuration - {Direction} attribute conversion without a 'type' identifier! {Entry.InnerXml}", loggingLevel: 1);
                throw new ArgumentException("Bad configuration entry, no type defined!", "type");
            }

            ConverterBase converter;

            switch (typeNode.InnerText.ToLower())
            {
                case "replace":
                    converter = new ConverterReplace(Entry, Direction);
                    break;
                default:
                    Logging.Log($"SolutionConfiguration: Error loading conversion configuration - {Direction} attribute conversion with an unknown 'type' identifier! {typeNode.InnerText} {Entry.InnerXml}", loggingLevel: 1);
                    throw new ArgumentException($"Bad configuration entry, unknown converter type! {typeNode.InnerText}", "type");
            }

            AttributeConverters.Add(converter);
            if (Direction == Direction.Import)
                ConverterImportByAttribute[converter.Attribute] = converter;
            else
                ConverterExportByAttribute[converter.Attribute] = converter;
        }
    }
}