using kOS.AddOns.AOSO.Native;
using kOS.Safe.Encapsulation;
using kOS.Suffixed;

namespace kOS.AddOns.AOSO.Bridge
{
    internal static class KosTypes
    {
        public static Vec ToNative(Vector value)
        {
            return new Vec(value.X, value.Y, value.Z);
        }

        public static Vector ToKos(Vec value)
        {
            return new Vector(value.X, value.Y, value.Z);
        }

        public static Lexicon LambertResult(LambertSolver.Result result)
        {
            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), new BooleanValue(result.Ok));
            lex.Add(new StringValue("vel1"), ToKos(result.Vel1));
            lex.Add(new StringValue("vel2"), ToKos(result.Vel2));
            lex.Add(new StringValue("err"), new StringValue(result.Error ?? string.Empty));
            lex.Add(new StringValue("src"), new StringValue("native"));
            return lex;
        }

        public static Lexicon LambertBadArgs()
        {
            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), BooleanValue.False);
            lex.Add(new StringValue("vel1"), Vector.Zero);
            lex.Add(new StringValue("vel2"), Vector.Zero);
            lex.Add(new StringValue("err"), new StringValue("bad_args"));
            lex.Add(new StringValue("src"), new StringValue("native"));
            return lex;
        }
    }
}
