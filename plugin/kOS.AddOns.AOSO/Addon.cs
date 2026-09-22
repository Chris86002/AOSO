using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;

namespace kOS.AddOns.AOSO
{
    [kOSAddon("AOSO")]
    [KOSNomenclature("AOSOAddon")]
    public class Addon : kOS.Suffixed.Addon
    {
        public Addon(SharedObjects shared) : base(shared)
        {
            InitializeAosoSuffixes();
        }

        private void InitializeAosoSuffixes()
        {
            AddSuffix("VERSION", new Suffix<StringValue>(() => new StringValue("0.1.0")));
        }

        public override BooleanValue Available()
        {
            return BooleanValue.True;
        }
    }
}
