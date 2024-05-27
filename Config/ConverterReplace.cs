using Microsoft.MetadirectoryServices;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml;

namespace Mms_Metaverse.Config
{
    public class ConverterReplace : ConverterBase
    {
        public bool UseDomainRoot;
        public string NewValue;
        public string Value;

        public ConverterReplace(XmlElement Configuration, Direction Direction)
            :base(Configuration, Direction)
        {
            this.Direction = Direction;

            foreach (XmlElement child in Configuration.ChildNodes)
            {
                switch (child.Name.ToLower())
                {
                    case "name":
                        Attribute = child.InnerText;
                        break;
                    case "domainroot":
                        UseDomainRoot = String.Equals("true", child.InnerText, StringComparison.OrdinalIgnoreCase);
                        break;
                    case "newvalue":
                        NewValue = child.InnerText;
                        break;
                    case "value":
                        Value = child.InnerText;
                        break;
                    case "simplevalue":
                        Value = Regex.Escape(child.InnerText);
                        break;
                    default:
                        break;
                }
            }
            if (Direction == Direction.Export)
                if (String.IsNullOrEmpty(Value) || (String.IsNullOrEmpty(NewValue) && !UseDomainRoot))
                    throw new ArgumentException($"Not all required settings (Value or SimpleValue and either Value or DomainRoot) found in element! {Configuration.InnerXml}");
            else
                if (String.IsNullOrEmpty(NewValue) || (String.IsNullOrEmpty(Value) && !UseDomainRoot))
                    throw new ArgumentException($"Not all required settings (NewValue and either Value, SimpleValue or DomainRoot) found in element! {Configuration.InnerXml}");
        }

        public override void Convert(MVEntry mventry, CSEntry csentry, ConnectorConfig Config)
        {
            string inputValue;
            if (Direction == Direction.Export)
                inputValue = mventry[Attribute].Value;
            else
                inputValue = csentry[Attribute].Value;

            string targetValue;
            if (!UseDomainRoot)
                targetValue = Regex.Replace(inputValue, Value, NewValue);
            else
            {
                if (Direction == Direction.Export)
                    targetValue = Regex.Replace(inputValue, Value, Regex.Escape(Config.Root));
                else
                    targetValue = Regex.Replace(inputValue, Regex.Escape(Config.Root), NewValue);
            }

            if (Direction == Direction.Export)
                csentry[Attribute].Value = targetValue;
            else
                mventry[Attribute].Value = targetValue;
        }
    }
}
