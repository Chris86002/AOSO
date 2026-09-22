using System;
using kOS.AddOns.AOSO.Bridge;
using kOS.AddOns.AOSO.Native;
using kOS.Safe.Encapsulation;
using kOS.Safe.Encapsulation.Suffixes;
using kOS.Safe.Utilities;
using kOS.Suffixed;

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
            AddSuffix("LAMBERT", new VarArgsSuffix<Lexicon, Structure>(Lambert));
        }

        private Lexicon Lambert(Structure[] args)
        {
            try
            {
                if (args == null || args.Length < 4 || args.Length > 5)
                    return KosTypes.LambertBadArgs();

                Vector pos1 = args[0] as Vector;
                Vector pos2 = args[1] as Vector;
                ScalarValue tofValue = args[2] as ScalarValue;
                ScalarValue muValue = args[3] as ScalarValue;
                if (pos1 == null || pos2 == null || tofValue == null || muValue == null)
                    return KosTypes.LambertBadArgs();

                bool longWay = false;
                if (args.Length == 5)
                {
                    BooleanValue longValue = args[4] as BooleanValue;
                    if (longValue == null)
                        return KosTypes.LambertBadArgs();
                    longWay = longValue.Value;
                }

                LambertSolver.Result result = LambertSolver.Solve(
                    KosTypes.ToNative(pos1),
                    KosTypes.ToNative(pos2),
                    tofValue.GetDoubleValue(),
                    muValue.GetDoubleValue(),
                    longWay);

                return KosTypes.LambertResult(result);
            }
            catch (Exception)
            {
                // Never throw a numerical/backend failure into the kOS VM.
                return KosTypes.LambertBadArgs();
            }
        }

        public override BooleanValue Available()
        {
            return BooleanValue.True;
        }
    }
}
