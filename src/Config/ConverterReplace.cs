﻿using Microsoft.MetadirectoryServices;
using Microsoft.MetadirectoryServices.Logging;
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

            foreach (XmlNode child in Configuration.ChildNodes)
            {
                switch (child.Name.ToLower())
                {
                    case "name":
                        Attribute = child.InnerText;
                        break;
                    case "sourcename":
                        SourceAttribute = child.InnerText;
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
                    case "connector":
                        Connector = child.InnerText;
                        break;
                    default:
                        break;
                }
            }
            if (String.IsNullOrEmpty(SourceAttribute))
                SourceAttribute = Attribute;
            if (Direction == Direction.Export)
                if (String.IsNullOrEmpty(Value) || (String.IsNullOrEmpty(NewValue) && !UseDomainRoot))
                    throw new ArgumentException($"Not all required settings (Value or SimpleValue and either Value or DomainRoot) found in element! {Configuration.InnerXml}");
            else
                if (String.IsNullOrEmpty(NewValue) || (String.IsNullOrEmpty(Value) && !UseDomainRoot))
                    throw new ArgumentException($"Not all required settings (NewValue and either Value, SimpleValue or DomainRoot) found in element! {Configuration.InnerXml}");
        }

        public override void Convert(MVEntry mventry, CSEntry csentry, ConnectorConfig Config)
        {
            Logging.Log($"Converter: Mapping {SourceAttribute} to {Attribute} (starting)", true, 4);
            string inputValue;
            if (Direction == Direction.Export)
                inputValue = mventry[SourceAttribute].Value;
            else
                if (SourceAttribute == "DN")
                    inputValue = csentry.DN.ToString();
                else
                    inputValue = csentry[SourceAttribute].Value;

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
            Logging.Log($"Converter: Mapping {SourceAttribute} to {Attribute}, input value '{inputValue}' translated to '{targetValue}'", true, 4);
            if (Direction == Direction.Export)
                csentry[Attribute].Value = targetValue;
            else
                mventry[Attribute].Value = targetValue;
        }
    }
}
