using Microsoft.MetadirectoryServices;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml;

namespace Mms_Metaverse.Config
{
    public abstract class ConverterBase
    {
        public string Attribute;
        public string SourceAttribute;
        public string Connector;
        public Direction Direction;

        public ConverterBase(XmlElement Configuration, Direction Direction) { }

        public abstract void Convert(MVEntry mventry, CSEntry csentry, ConnectorConfig Config);
    }
}
