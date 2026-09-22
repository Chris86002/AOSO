using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using kOS.AddOns.AOSO.Native;

namespace kOS.AddOns.AOSO.Game
{
    internal sealed class InterplanetaryOptions
    {
        public int DepartureSamples;
        public int TofSamples;
        public int RefineSeeds;
        public double StartUt;
        public double EndUt;
        public double TofMin;
        public double TofMax;
        public double DesiredPe;
        public double ParkingRadius;
        public double TimeCostPerDay;
    }

    internal sealed class InterplanetaryCandidate
    {
        public double DepartureUt;
        public double ArrivalUt;
        public double Tof;
        public double Score;
        public double EjectionDv;
        public double CaptureDv;
        public double TotalDv;
        public double VInfinityOut;
        public double VInfinityIn;
        public bool LongWay;
    }

    // Body-to-body Lambert porkchop for stock KSP. This deliberately does
    // not implement n-body propagation: stock KSP's own Keplerian body
    // ephemerides are the universe AOSO must fly in. The job is chunked so
    // it cannot monopolize Unity's main thread.
    internal sealed class InterplanetaryJob
    {
        private enum SearchStage
        {
            Coarse,
            PrepareRefine,
            Refine,
            Done
        }

        private readonly Vessel vessel;
        private readonly CelestialBody departure;
        private readonly CelestialBody target;
        private readonly CelestialBody parent;
        private readonly InterplanetaryOptions options;
        private readonly Orbit parkingOrbit;
        private readonly List<InterplanetaryCandidate> candidates =
            new List<InterplanetaryCandidate>();

        private SearchStage stage = SearchStage.Coarse;
        private int depIndex;
        private int tofIndex;
        private List<InterplanetaryCandidate> refineSeeds;
        private int refineSeedIndex;
        private int refineDepIndex;
        private int refineTofIndex;
        private double depStep;
        private double tofStep;

        public int DoneCount { get; private set; }
        public int ValidCount { get; private set; }
        public string Error { get; private set; }

        public bool Done
        {
            get { return stage == SearchStage.Done; }
        }

        public double Progress
        {
            get
            {
                if (Done)
                    return 1.0;

                int coarse = options.DepartureSamples * options.TofSamples;
                int refine = Math.Max(1, options.RefineSeeds) * 7 * 7;
                return Math.Min(1.0, (double)DoneCount / Math.Max(1, coarse + refine));
            }
        }

        public InterplanetaryJob(
            Vessel sourceVessel,
            CelestialBody targetBody,
            InterplanetaryOptions jobOptions)
        {
            if (sourceVessel == null || sourceVessel.orbit == null)
                throw new ArgumentException("no_vessel");
            if (targetBody == null || targetBody.orbit == null)
                throw new ArgumentException("bad_target");

            vessel = sourceVessel;
            departure = sourceVessel.orbit.referenceBody;
            target = targetBody;
            if (departure == null || departure.orbit == null)
                throw new ArgumentException("bad_departure");

            parent = departure.orbit.referenceBody;
            if (parent == null || target.orbit.referenceBody != parent)
                throw new ArgumentException("different_parent");

            options = jobOptions ?? throw new ArgumentNullException("jobOptions");
            NormalizeOptions();

            parkingOrbit = new Orbit();
            parkingOrbit.UpdateFromOrbitAtUT(
                sourceVessel.orbit,
                Planetarium.GetUniversalTime(),
                departure);

            depStep = options.DepartureSamples > 1
                ? (options.EndUt - options.StartUt) / (options.DepartureSamples - 1)
                : 0.0;
            tofStep = options.TofSamples > 1
                ? (options.TofMax - options.TofMin) / (options.TofSamples - 1)
                : 0.0;
        }

        public void Poll(double budgetMilliseconds, int maxCells)
        {
            if (Done)
                return;

            budgetMilliseconds = Math.Max(0.5, Math.Min(20.0, budgetMilliseconds));
            maxCells = Math.Max(1, Math.Min(512, maxCells));
            var timer = Stopwatch.StartNew();
            int cells = 0;

            try
            {
                while (!Done &&
                       cells < maxCells &&
                       timer.Elapsed.TotalMilliseconds < budgetMilliseconds)
                {
                    switch (stage)
                    {
                        case SearchStage.Coarse:
                            StepCoarse();
                            break;
                        case SearchStage.PrepareRefine:
                            PrepareRefine();
                            break;
                        case SearchStage.Refine:
                            StepRefine();
                            break;
                    }
                    ++cells;
                }
            }
            catch (Exception ex)
            {
                Error = ex.GetType().Name;
                stage = SearchStage.Done;
            }
        }

        public List<InterplanetaryCandidate> GetCandidates()
        {
            return candidates
                .OrderBy(candidate => candidate.Score)
                .ThenBy(candidate => candidate.TotalDv)
                .Take(20)
                .ToList();
        }

        private void NormalizeOptions()
        {
            double now = Planetarium.GetUniversalTime();

            options.DepartureSamples = ClampInt(options.DepartureSamples, 16, 96, 48);
            options.TofSamples = ClampInt(options.TofSamples, 10, 64, 28);
            options.RefineSeeds = ClampInt(options.RefineSeeds, 2, 10, 6);

            if (!FinitePositive(options.StartUt) || options.StartUt < now + 60.0)
                options.StartUt = now + 120.0;
            if (!FinitePositive(options.EndUt) ||
                options.EndUt <= options.StartUt + 60.0)
                options.EndUt = options.StartUt + Math.Max(21600.0, departure.orbit.period);

            if (!FinitePositive(options.TofMin))
                options.TofMin = 3600.0;
            if (!FinitePositive(options.TofMax) ||
                options.TofMax <= options.TofMin + 60.0)
                options.TofMax = options.TofMin * 2.0;

            if (!FinitePositive(options.DesiredPe))
                options.DesiredPe = Math.Max(15000.0, target.Radius * 0.08);
            if (!FinitePositive(options.ParkingRadius))
                options.ParkingRadius = Math.Max(
                    departure.Radius + 10000.0,
                    sourceParkingRadius());
            if (!IsFinite(options.TimeCostPerDay) || options.TimeCostPerDay < 0.0)
                options.TimeCostPerDay = 20.0;
        }

        private double sourceParkingRadius()
        {
            double radius = parkingOrbit.semiMajorAxis;
            if (!FinitePositive(radius))
                radius = departure.Radius + 80000.0;
            return radius;
        }

        private void StepCoarse()
        {
            if (depIndex >= options.DepartureSamples)
            {
                stage = SearchStage.PrepareRefine;
                return;
            }

            double depUt = options.DepartureSamples <= 1
                ? options.StartUt
                : options.StartUt + depStep * depIndex;
            double tof = options.TofSamples <= 1
                ? options.TofMin
                : options.TofMin + tofStep * tofIndex;

            EvaluateLambertPair(depUt, tof);
            ++DoneCount;

            ++tofIndex;
            if (tofIndex >= options.TofSamples)
            {
                tofIndex = 0;
                ++depIndex;
            }

            if (depIndex >= options.DepartureSamples)
                stage = SearchStage.PrepareRefine;
        }

        private void PrepareRefine()
        {
            refineSeeds = candidates
                .OrderBy(candidate => candidate.Score)
                .ThenBy(candidate => candidate.TotalDv)
                .Take(options.RefineSeeds)
                .Select(CopyCandidate)
                .ToList();

            refineSeedIndex = 0;
            refineDepIndex = 0;
            refineTofIndex = 0;
            stage = refineSeeds.Count == 0 ? SearchStage.Done : SearchStage.Refine;
        }

        private void StepRefine()
        {
            if (refineSeeds == null || refineSeedIndex >= refineSeeds.Count)
            {
                stage = SearchStage.Done;
                return;
            }

            InterplanetaryCandidate seed = refineSeeds[refineSeedIndex];
            double fineDep = Math.Max(30.0, depStep / 6.0);
            double fineTof = Math.Max(60.0, tofStep / 6.0);
            double depUt = seed.DepartureUt + (refineDepIndex - 3) * fineDep;
            double tof = seed.Tof + (refineTofIndex - 3) * fineTof;

            if (depUt >= options.StartUt &&
                depUt <= options.EndUt &&
                tof >= options.TofMin &&
                tof <= options.TofMax)
                EvaluateLambertPair(depUt, tof);

            ++DoneCount;
            ++refineTofIndex;
            if (refineTofIndex >= 7)
            {
                refineTofIndex = 0;
                ++refineDepIndex;
                if (refineDepIndex >= 7)
                {
                    refineDepIndex = 0;
                    ++refineSeedIndex;
                }
            }

            if (refineSeedIndex >= refineSeeds.Count)
                stage = SearchStage.Done;
        }

        private void EvaluateLambertPair(double departureUt, double tof)
        {
            InterplanetaryCandidate shortCandidate;
            InterplanetaryCandidate longCandidate;
            bool shortOk = TryLambertCandidate(departureUt, tof, false, out shortCandidate);
            bool longOk = TryLambertCandidate(departureUt, tof, true, out longCandidate);

            if (shortOk)
                KeepCandidate(shortCandidate, 40);
            if (longOk)
                KeepCandidate(longCandidate, 40);
        }

        private bool TryLambertCandidate(
            double departureUt,
            double tof,
            bool longWay,
            out InterplanetaryCandidate candidate)
        {
            candidate = null;
            if (departureUt <= Planetarium.GetUniversalTime() + 30.0 || tof < 30.0)
                return false;

            double arrivalUt = departureUt + tof;
            Vector3d depPosRaw = departure.orbit.getRelativePositionAtUT(departureUt);
            Vector3d arrPosRaw = target.orbit.getRelativePositionAtUT(arrivalUt);
            Vector3d depVelRaw = departure.orbit.getOrbitalVelocityAtUT(departureUt);
            Vector3d arrVelRaw = target.orbit.getOrbitalVelocityAtUT(arrivalUt);

            LambertSolver.Result solution = LambertSolver.Solve(
                ToVec(depPosRaw),
                ToVec(arrPosRaw),
                tof,
                parent.gravParameter,
                longWay);

            if (!solution.Ok)
                return false;

            Vec vInfOutVec = solution.Vel1 - ToVec(depVelRaw);
            Vec vInfInVec = solution.Vel2 - ToVec(arrVelRaw);
            double vInfOut = vInfOutVec.Magnitude;
            double vInfIn = vInfInVec.Magnitude;

            if (!FinitePositive(vInfOut) || !FinitePositive(vInfIn))
                return false;

            double ejectionDv = EstimateEjectionDv(vInfOut);
            double captureDv = EstimateCaptureDv(vInfIn);
            if (!IsFinite(ejectionDv) || !IsFinite(captureDv))
                return false;

            double totalDv = ejectionDv + captureDv;
            double waitSeconds = Math.Max(0.0, departureUt - Planetarium.GetUniversalTime());
            double kerbinDays = (waitSeconds + tof) / 21600.0;
            double score = totalDv + kerbinDays * options.TimeCostPerDay;

            candidate = new InterplanetaryCandidate
            {
                DepartureUt = departureUt,
                ArrivalUt = arrivalUt,
                Tof = tof,
                Score = score,
                EjectionDv = ejectionDv,
                CaptureDv = captureDv,
                TotalDv = totalDv,
                VInfinityOut = vInfOut,
                VInfinityIn = vInfIn,
                LongWay = longWay
            };
            ++ValidCount;
            return true;
        }

        private double EstimateEjectionDv(double vInfinity)
        {
            double radius = Math.Max(departure.Radius + 1000.0, options.ParkingRadius);
            double mu = departure.gravParameter;
            double parkingSpeedSq = mu * (2.0 / radius - 1.0 / parkingOrbit.semiMajorAxis);
            if (parkingSpeedSq <= 0.0)
                parkingSpeedSq = mu / radius;
            double parkingSpeed = Math.Sqrt(parkingSpeedSq);
            double hyperbolicSpeed = Math.Sqrt(vInfinity * vInfinity + 2.0 * mu / radius);
            return Math.Abs(hyperbolicSpeed - parkingSpeed);
        }

        private double EstimateCaptureDv(double vInfinity)
        {
            double radius = target.Radius + options.DesiredPe;
            if (radius <= target.Radius)
                radius = target.Radius + Math.Max(5000.0, target.Radius * 0.08);
            double mu = target.gravParameter;
            double hyperbolicSpeed = Math.Sqrt(vInfinity * vInfinity + 2.0 * mu / radius);
            double circularSpeed = Math.Sqrt(mu / radius);
            return Math.Max(0.0, hyperbolicSpeed - circularSpeed);
        }

        private void KeepCandidate(InterplanetaryCandidate candidate, int maxCount)
        {
            if (candidate == null)
                return;

            for (int index = 0; index < candidates.Count; ++index)
            {
                InterplanetaryCandidate existing = candidates[index];
                if (Math.Abs(existing.DepartureUt - candidate.DepartureUt) < 1.0 &&
                    Math.Abs(existing.Tof - candidate.Tof) < 1.0 &&
                    existing.LongWay == candidate.LongWay)
                {
                    if (candidate.Score < existing.Score)
                        candidates[index] = CopyCandidate(candidate);
                    return;
                }
            }

            if (candidates.Count < maxCount)
            {
                candidates.Add(CopyCandidate(candidate));
                return;
            }

            int worstIndex = 0;
            double worstScore = candidates[0].Score;
            for (int index = 1; index < candidates.Count; ++index)
            {
                if (candidates[index].Score > worstScore)
                {
                    worstScore = candidates[index].Score;
                    worstIndex = index;
                }
            }

            if (candidate.Score < worstScore)
                candidates[worstIndex] = CopyCandidate(candidate);
        }

        private static InterplanetaryCandidate CopyCandidate(InterplanetaryCandidate source)
        {
            return new InterplanetaryCandidate
            {
                DepartureUt = source.DepartureUt,
                ArrivalUt = source.ArrivalUt,
                Tof = source.Tof,
                Score = source.Score,
                EjectionDv = source.EjectionDv,
                CaptureDv = source.CaptureDv,
                TotalDv = source.TotalDv,
                VInfinityOut = source.VInfinityOut,
                VInfinityIn = source.VInfinityIn,
                LongWay = source.LongWay
            };
        }

        private static Vec ToVec(Vector3d value)
        {
            return new Vec(value.x, value.y, value.z);
        }

        private static int ClampInt(int value, int min, int max, int fallback)
        {
            if (value <= 0)
                return fallback;
            return Math.Max(min, Math.Min(max, value));
        }

        private static bool FinitePositive(double value)
        {
            return IsFinite(value) && value > 0.0;
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }
    }
}
