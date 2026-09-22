using System;
using System.Diagnostics;
using kOS.AddOns.AOSO.Bridge;
using kOS.AddOns.AOSO.Game;
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
        private PorkchopJob porkchopJob;

        public Addon(SharedObjects shared) : base(shared)
        {
            InitializeAosoSuffixes();
        }

        private void InitializeAosoSuffixes()
        {
            AddSuffix("VERSION", new Suffix<StringValue>(() => new StringValue("0.2.0")));
            AddSuffix("LAMBERT", new VarArgsSuffix<Lexicon, Structure>(Lambert));
            AddSuffix("PORKCHOP", new VarArgsSuffix<Lexicon, Structure>(Porkchop));
            AddSuffix("PORKCHOPSTART", new VarArgsSuffix<Lexicon, Structure>(PorkchopStart));
            AddSuffix("PORKCHOPPOLL", new NoArgsSuffix<Lexicon>(PorkchopPoll));
            AddSuffix("PORKCHOPRESULT", new NoArgsSuffix<Lexicon>(PorkchopResult));
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

        private Lexicon Porkchop(Structure[] args)
        {
            Lexicon start = PorkchopStart(args);
            BooleanValue startOk = start[new StringValue("ok")] as BooleanValue;
            if (startOk == null || !startOk.Value)
                return start;

            var timer = Stopwatch.StartNew();
            while (porkchopJob != null && !porkchopJob.Done &&
                   timer.Elapsed.TotalMilliseconds < 40.0)
                porkchopJob.Poll(5.0, 64);

            if (porkchopJob != null && porkchopJob.Done)
                return PorkchopResult();

            return KosTypes.PorkchopFailure("async_required");
        }

        private Lexicon PorkchopStart(Structure[] args)
        {
            try
            {
                if (args == null || args.Length != 2)
                    return KosTypes.PorkchopFailure("bad_args");

                BodyTarget hop = args[0] as BodyTarget;
                Lexicon options = args[1] as Lexicon;
                if (hop == null || options == null)
                    return KosTypes.PorkchopFailure("bad_args");
                if (shared.Vessel == null || shared.Vessel.orbit == null)
                    return KosTypes.PorkchopFailure("no_vessel");
                if (!shared.Vessel.loaded)
                    return KosTypes.PorkchopFailure("vessel_not_loaded");
                if (hop.Body == null || hop.Body.orbit == null)
                    return KosTypes.PorkchopFailure("bad_target");
                if (hop.Body.orbit.referenceBody != shared.Vessel.orbit.referenceBody)
                    return KosTypes.PorkchopFailure("different_parent");

                porkchopJob = new PorkchopJob(
                    shared.Vessel,
                    hop.Body,
                    KosTypes.PorkchopOptionsFromLexicon(options));

                return KosTypes.PorkchopStatus(
                    true,
                    porkchopJob.Done,
                    porkchopJob.Progress,
                    porkchopJob.DoneCount,
                    porkchopJob.HitCount,
                    porkchopJob.CaptureCount,
                    string.Empty);
            }
            catch (Exception ex)
            {
                porkchopJob = null;
                return KosTypes.PorkchopFailure(ex.GetType().Name);
            }
        }

        private Lexicon PorkchopPoll()
        {
            try
            {
                if (porkchopJob == null)
                    return KosTypes.PorkchopFailure("no_job");

                porkchopJob.Poll(8.0, 64);
                return KosTypes.PorkchopStatus(
                    true,
                    porkchopJob.Done,
                    porkchopJob.Progress,
                    porkchopJob.DoneCount,
                    porkchopJob.HitCount,
                    porkchopJob.CaptureCount,
                    porkchopJob.Error);
            }
            catch (Exception ex)
            {
                porkchopJob = null;
                return KosTypes.PorkchopFailure(ex.GetType().Name);
            }
        }

        private Lexicon PorkchopResult()
        {
            try
            {
                PorkchopJob completedJob = porkchopJob;
                Lexicon result = KosTypes.PorkchopResult(completedJob);
                if (completedJob != null && completedJob.Done)
                    porkchopJob = null;
                return result;
            }
            catch (Exception ex)
            {
                porkchopJob = null;
                return KosTypes.PorkchopFailure(ex.GetType().Name);
            }
        }

        public override BooleanValue Available()
        {
            return BooleanValue.True;
        }
    }
}
