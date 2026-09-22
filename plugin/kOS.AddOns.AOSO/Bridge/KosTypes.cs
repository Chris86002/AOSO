using System;
using kOS.AddOns.AOSO.Game;
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

        public static PorkchopOptions PorkchopOptionsFromLexicon(Lexicon lex)
        {
            return new PorkchopOptions
            {
                DepSamples = GetInt(lex, "dep_samples", 24),
                DvSamples = GetInt(lex, "dv_samples", 18),
                NormalSamples = GetInt(lex, "nml_samples", 5),
                TofSamples = GetInt(lex, "tof_samples", 6),
                DvHoh = GetDouble(lex, "dv_hoh", 80.0),
                DvMax = GetDouble(lex, "dv_max", 100.0),
                SoonUt = GetDouble(lex, "t_soon", 0.0),
                HohmannUt = GetDouble(lex, "t_hoh", 0.0),
                PeriodSeconds = GetDouble(lex, "period_s", 600.0),
                SearchStepSeconds = GetDouble(lex, "step_win", 12.0),
                DesiredPe = GetDouble(lex, "desired_pe", 0.0),
                MinimumPe = GetDouble(lex, "pe_min", 0.0),
                MaximumPe = GetDouble(lex, "pe_max", 0.0),
                SoiAltitude = GetDouble(lex, "soi_alt", 0.0),
                TofMinFraction = GetDouble(lex, "tof_min", 0.06),
                TofMaxFraction = GetDouble(lex, "tof_max", 1.7)
            };
        }

        public static Lexicon PorkchopStatus(
            bool ok,
            bool done,
            double progress,
            int nDone,
            int nHit,
            int nOk,
            string error)
        {
            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), new BooleanValue(ok));
            lex.Add(new StringValue("done"), new BooleanValue(done));
            lex.Add(new StringValue("progress"), ScalarValue.Create(progress));
            lex.Add(new StringValue("n_done"), ScalarValue.Create(nDone));
            lex.Add(new StringValue("n_hit"), ScalarValue.Create(nHit));
            lex.Add(new StringValue("n_ok"), ScalarValue.Create(nOk));
            lex.Add(new StringValue("err"), new StringValue(error ?? string.Empty));
            lex.Add(new StringValue("src"), new StringValue("native"));
            return lex;
        }

        public static Lexicon PorkchopResult(PorkchopJob job)
        {
            if (job == null)
                return PorkchopFailure("no_job");

            var list = new ListValue();
            foreach (PorkchopCandidate candidate in job.GetCandidates())
            {
                var item = new Lexicon();
                item.Add(new StringValue("ut"), ScalarValue.Create(candidate.Ut));
                item.Add(new StringValue("pg"), ScalarValue.Create(candidate.Prograde));
                item.Add(new StringValue("rad"), ScalarValue.Create(candidate.Radial));
                item.Add(new StringValue("nml"), ScalarValue.Create(candidate.Normal));
                item.Add(new StringValue("sc"), ScalarValue.Create(candidate.Score));
                item.Add(new StringValue("dv"), ScalarValue.Create(candidate.DeltaV));
                item.Add(new StringValue("pe"), ScalarValue.Create(candidate.Periapsis));
                list.Add(item);
            }

            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), new BooleanValue(job.Done && string.IsNullOrEmpty(job.Error)));
            lex.Add(new StringValue("src"), new StringValue("native"));
            lex.Add(new StringValue("cands"), list);
            lex.Add(new StringValue("n_hit"), ScalarValue.Create(job.HitCount));
            lex.Add(new StringValue("n_ok"), ScalarValue.Create(job.CaptureCount));
            lex.Add(new StringValue("n_done"), ScalarValue.Create(job.DoneCount));
            lex.Add(new StringValue("err"), new StringValue(job.Error ?? string.Empty));
            return lex;
        }

        public static Lexicon PorkchopFailure(string error)
        {
            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), BooleanValue.False);
            lex.Add(new StringValue("src"), new StringValue("native"));
            lex.Add(new StringValue("cands"), new ListValue());
            lex.Add(new StringValue("n_hit"), ScalarValue.Create(0));
            lex.Add(new StringValue("n_ok"), ScalarValue.Create(0));
            lex.Add(new StringValue("n_done"), ScalarValue.Create(0));
            lex.Add(new StringValue("err"), new StringValue(error ?? "error"));
            return lex;
        }

        private static double GetDouble(Lexicon lex, string key, double fallback)
        {
            if (lex == null)
                return fallback;

            Structure raw;
            if (!lex.TryGetValue(new StringValue(key), out raw))
                return fallback;

            ScalarValue scalar = raw as ScalarValue;
            return scalar == null ? fallback : scalar.GetDoubleValue();
        }

        private static int GetInt(Lexicon lex, string key, int fallback)
        {
            return (int)Math.Round(GetDouble(lex, key, fallback));
        }

        public static Lexicon LambertResult(LambertSolver.Result result)
        {
            var lex = new Lexicon();
            lex.Add(new StringValue("ok"), new BooleanValue(result.Ok));
            lex.Add(new StringValue("vel1"), ToKos(result.Vel1));
            lex.Add(new StringValue("vel2"), ToKos(result.Vel2));
            lex.Add(new StringValue("err"), new StringValue(result.Error ?? string.Empty));
            lex.Add(new StringValue("src"), new StringValue("native"));
            lex.Add(new StringValue("z"), ScalarValue.Create(result.Z));
            lex.Add(new StringValue("tof_err"), ScalarValue.Create(result.TofError));
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
