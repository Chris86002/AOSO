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
            AddSuffix("VERSION", new Suffix<StringValue>(() => new StringValue("0.3.0")));
            AddSuffix("LAMBERT", new OneArgsSuffix<Lexicon, Lexicon>(Lambert));
            AddSuffix("PORKCHOP", new OneArgsSuffix<Lexicon, Lexicon>(Porkchop));
            AddSuffix("PORKCHOPSTART", new OneArgsSuffix<Lexicon, Lexicon>(PorkchopStart));
            AddSuffix("PORKCHOPPOLL", new NoArgsSuffix<Lexicon>(PorkchopPoll));
            AddSuffix("PORKCHOPRESULT", new NoArgsSuffix<Lexicon>(PorkchopResult));
        }

        private static Structure RequestValue(Lexicon request, string key)
        {
            if (request == null)
                return null;

            Structure value;
            if (!request.TryGetValue(new StringValue(key), out value))
                return null;
            return value;
        }

        private Lexicon Lambert(Lexicon request)
        {
            try
            {
                Vector pos1 = RequestValue(request, "pos1") as Vector;
                Vector pos2 = RequestValue(request, "pos2") as Vector;
                ScalarValue tofValue = RequestValue(request, "tof") as ScalarValue;
                ScalarValue muValue = RequestValue(request, "mu") as ScalarValue;
                BooleanValue longValue = RequestValue(request, "long_way") as BooleanValue;

                if (pos1 == null || pos2 == null || tofValue == null || muValue == null)
                    return KosTypes.LambertBadArgs();

                bool longWay = longValue != null && longValue.Value;

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

        private Lexicon Porkchop(Lexicon request)
        {
            Lexicon start = PorkchopStart(request);
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

        private Lexicon PorkchopStart(Lexicon request)
        {
            try
            {
                BodyTarget hop = RequestValue(request, "hop") as BodyTarget;
                Lexicon options = RequestValue(request, "options") as Lexicon;
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

                // Keep the hard 8 ms main-thread slice, but let cheap cells
                // fill that slice instead of stopping after only 64.
                porkchopJob.Poll(8.0, 128);
                bool pollOk = string.IsNullOrEmpty(porkchopJob.Error);
                return KosTypes.PorkchopStatus(
                    pollOk,
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
