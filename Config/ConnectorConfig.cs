using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml;

namespace Mms_Metaverse.Config
{
    public class ConnectorConfig
    {
        public string Name;
        public string Root;
        public string Connector;
        public bool Target;

        public ConnectorConfig() { }

        public ConnectorConfig(XmlElement Node)
        {
            foreach (XmlElement child in Node.ChildNodes)
            {
                switch (child.Name.ToLower())
                {
                    case "name":
                        Name = child.InnerText;
                        break;
                    case "root":
                        Root = child.InnerText;
                        break;
                    case "connector":
                        Connector = child.InnerText;
                        break;
                    case "target":
                        Target = String.Equals("true", child.InnerText, StringComparison.OrdinalIgnoreCase);
                        break;
                    default:
                        break;
                }
            }
            if (String.IsNullOrEmpty(Connector) || String.IsNullOrEmpty(Root) || String.IsNullOrEmpty(Name))
                throw new ArgumentException($"Not all required settings (name, root, connector) found in element! {Node.InnerXml}");
        }

        public bool IsRoot(string Path)
        {
            return Path.EndsWith(Root, StringComparison.OrdinalIgnoreCase);
        }

        public string InsertRoot(string Path)
        {
            return Regex.Replace(Path, "%ROOT%$", $",{Root}", RegexOptions.IgnoreCase);
        }
    }
}