using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using kOS.AddOns.AOSO.Native;
using UnityEngine;

namespace kOS.AddOns.AOSO.Game
{
    internal sealed class PorkchopOptions
    {
        public int DepSamples;
        public int DvSamples;
        public int NormalSamples;
        public int TofSamples;
        public double DvHoh;
        public double DvMax;
        public double SoonUt;
        public double HohmannUt;
        public double PeriodSeconds;
        public double SearchStepSeconds;
        public double DesiredPe;
        public double MinimumPe;
        public double MaximumPe;
        public double SoiAltitude;
        public double TofMinFraction;
        public double TofMaxFraction;
    }

    internal sealed class PorkchopCandidate
    {
        public double Ut;
        public double Prograde;
        public double Radial;
        public double Normal;
        public double Score;
        public double DeltaV;
        public double Periapsis;
    }

    // Chunked, main-thread patched-conic candidate search. It never creates
    // ManeuverNode objects and never touches controls. KerboScript re-applies
    // returned burns to a real node and finalize_node remains authoritative.
    internal sealed class PorkchopJob
    {
        private enum SearchStage
        {
            LambertSeeds,
            CoarseGrid,
            WindowSweep,
            Densify,
            Done
        }

        private readonly Orbit initialOrbit;
        private readonly CelestialBody target;
        private readonly CelestialBody parent;
        private readonly PorkchopOptions options;
        private readonly List<double> departures;
        private readonly List<PorkchopCandidate> candidates = new List<PorkchopCandidate>();
        private readonly PatchedConics.SolverParameters solverParameters = new PatchedConics.SolverParameters();

        private readonly double dvLow;
        private readonly double normalSpan;
        private readonly double hohmannTof;
        private readonly double aimOffset;

        private SearchStage stage = SearchStage.LambertSeeds;

        private int seedDepIndex;
        private int seedTofIndex;
        private int seedStride;
        private double[] seedTofs;

        private int depIndex;
        private int dvIndex;
        private int normalIndex;

        private double sweepStartUt;
        private double sweepStep;
        private int sweepTimeCount;
        private int sweepTimeIndex;
        private int sweepDvIndex;
        private int sweepNormalIndex;

        private List<PorkchopCandidate> densifySeeds;
        private int densifySeedIndex;
        private int densifyTimeIndex;
        private int densifyDvIndex;
        private int densifyNormalIndex;
        private int densifyRadialIndex;

        public int DoneCount { get; private set; }
        public int HitCount { get; private set; }
        public int CaptureCount { get; private set; }
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

                int seedCount = ((departures.Count + Math.Max(1, seedStride) - 1) / Math.Max(1, seedStride)) *
                    Math.Max(1, seedTofs == null ? 1 : seedTofs.Length);
                int coarseCount = departures.Count * options.DvSamples * options.NormalSamples;
                int sweepCount = Math.Max(0, sweepTimeCount) * 5 * 3;
                int densifyCount = 5 * 7 * 7 * 3 * 5;
                int total = Math.Max(1, seedCount + coarseCount + sweepCount + densifyCount);
                return Math.Min(1.0, (double)DoneCount / total);
            }
        }

        public PorkchopJob(Vessel vessel, CelestialBody targetBody, PorkchopOptions jobOptions)
        {
            if (vessel == null || vessel.orbit == null)
                throw new ArgumentException("no_vessel");
            if (targetBody == null || targetBody.orbit == null)
                throw new ArgumentException("bad_target");

            target = targetBody;
            parent = vessel.orbit.referenceBody;
            if (parent == null || target.orbit.referenceBody != parent)
                throw new ArgumentException("different_parent");

            options = jobOptions ?? throw new ArgumentNullException("jobOptions");
            NormalizeOptions();

            double now = Planetarium.GetUniversalTime();
            initialOrbit = new Orbit();
            initialOrbit.UpdateFromOrbitAtUT(vessel.orbit, now, parent);

            departures = BuildDepartures(now);
            dvLow = ComputeDvLow();
            normalSpan = Math.Max(20.0, Math.Min(90.0, options.DvHoh * 0.12));
            hohmannTof = ComputeHohmannTof();
            aimOffset = target.Radius + options.DesiredPe;

            seedStride = departures.Count > 32 ? 3 : (departures.Count > 16 ? 2 : 1);
            seedTofs = BuildSeedTofs();
        }

        public void Poll(double budgetMilliseconds, int maxCells)
        {
            if (Done)
                return;

            budgetMilliseconds = Math.Max(0.5, Math.Min(20.0, budgetMilliseconds));
            maxCells = Math.Max(1, Math.Min(256, maxCells));

            var timer = Stopwatch.StartNew();
            int cells = 0;
            try
            {
                while (!Done && cells < maxCells && timer.Elapsed.TotalMilliseconds < budgetMilliseconds)
                {
                    switch (stage)
                    {
                        case SearchStage.LambertSeeds:
                            StepLambertSeed();
                            break;
                        case SearchStage.CoarseGrid:
                            StepCoarse();
                            break;
                        case SearchStage.WindowSweep:
                            StepWindowSweep();
                            break;
                        case SearchStage.Densify:
                            StepDensify();
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

        public List<PorkchopCandidate> GetCandidates()
        {
            return candidates
                .OrderBy(candidate => IsCapturePe(candidate.Periapsis) ? 0 : 1)
                .ThenBy(candidate => candidate.Score)
                .ThenBy(candidate => candidate.DeltaV)
                .Take(20)
                .ToList();
        }

        private void NormalizeOptions()
        {
            options.DepSamples = ClampInt(options.DepSamples, 10, 40, 24);
            options.DvSamples = ClampInt(options.DvSamples, 8, 28, 18);
            options.NormalSamples = ClampInt(options.NormalSamples, 1, 7, 5);
            options.TofSamples = ClampInt(options.TofSamples, 3, 6, 6);

            if (!FinitePositive(options.DvHoh))
                options.DvHoh = 80.0;
            if (!FinitePositive(options.DvMax))
                options.DvMax = Math.Max(100.0, options.DvHoh * 1.5);
            if (!FinitePositive(options.PeriodSeconds))
                options.PeriodSeconds = 600.0;
            if (!FinitePositive(options.SearchStepSeconds))
                options.SearchStepSeconds = 12.0;
            options.SearchStepSeconds = Math.Max(3.0, Math.Min(18.0, options.SearchStepSeconds));
            if (!FinitePositive(options.SoonUt))
                options.SoonUt = Planetarium.GetUniversalTime() + 90.0;
            if (!FinitePositive(options.HohmannUt) || options.HohmannUt < options.SoonUt)
                options.HohmannUt = options.SoonUt;
            if (!FinitePositive(options.DesiredPe))
                options.DesiredPe = Math.Max(15000.0, target.Radius * 0.08);
            if (!FinitePositive(options.MinimumPe))
                options.MinimumPe = Math.Max(5000.0, options.DesiredPe * 0.6);
            if (!FinitePositive(options.MaximumPe))
                options.MaximumPe = Math.Max(options.DesiredPe + 8000.0, options.DesiredPe * 2.2);
            if (!FinitePositive(options.SoiAltitude))
                options.SoiAltitude = Math.Max(2000.0, target.sphereOfInfluence - target.Radius);
            if (!FinitePositive(options.TofMinFraction))
                options.TofMinFraction = 0.06;
            if (!FinitePositive(options.TofMaxFraction))
                options.TofMaxFraction = 1.7;
        }

        private List<double> BuildDepartures(double now)
        {
            var result = new List<double>();

            const int coarseSamples = 8;
            for (int index = 0; index < coarseSamples; ++index)
            {
                result.Add(options.SoonUt +
                    index * (options.PeriodSeconds * 1.2 / Math.Max(1, coarseSamples - 1)));
            }

            int fineSamples = Math.Max(12, options.DepSamples);
            double half = (fineSamples - 1) / 2.0;
            for (int index = 0; index < fineSamples; ++index)
            {
                double departure = options.HohmannUt + (index - half) * options.SearchStepSeconds;
                if (departure > now + 50.0)
                    result.Add(departure);
            }

            return result;
        }

        private double[] BuildSeedTofs()
        {
            double low = Math.Max(600.0, hohmannTof * options.TofMinFraction);
            double high = hohmannTof * options.TofMaxFraction;
            if (high < low + 60.0)
                high = low + 60.0;

            var values = new List<double>();
            for (int index = 0; index < options.TofSamples; ++index)
            {
                double fraction = options.TofSamples > 1 ?
                    index / (double)(options.TofSamples - 1) : 0.0;
                values.Add(low + (high - low) * fraction);
            }
            values.Add(hohmannTof);
            return values.ToArray();
        }

        private double ComputeDvLow()
        {
            double low = options.DvHoh * 0.35;
            if (low < 80.0)
                low = 80.0;
            if (low > options.DvMax * 0.4)
                low = options.DvMax * 0.4;
            return low;
        }

        private double ComputeHohmannTof()
        {
            double radius1 = initialOrbit.semiMajorAxis;
            if (!FinitePositive(radius1))
                radius1 = initialOrbit.getRelativePositionAtUT(options.SoonUt).magnitude;
            double radius2 = target.orbit.semiMajorAxis;
            double transferSma = (radius1 + radius2) / 2.0;
            if (!FinitePositive(transferSma) || parent.gravParameter <= 0.0)
                return 600.0;
            return Math.Max(600.0,
                Math.PI * Math.Sqrt(transferSma * transferSma * transferSma / parent.gravParameter));
        }

        private void StepLambertSeed()
        {
            if (departures.Count == 0 || seedDepIndex >= departures.Count)
            {
                stage = SearchStage.CoarseGrid;
                return;
            }

            double departureUt = departures[seedDepIndex];
            bool nearWindow = Math.Abs(departureUt - options.HohmannUt) < options.PeriodSeconds * 0.2;
            if (nearWindow)
            {
                PorkchopCandidate candidate;
                if (TryLambertCandidate(departureUt, seedTofs[seedTofIndex], out candidate))
                    EvaluateCandidate(candidate);
                ++DoneCount;
                ++seedTofIndex;
                if (seedTofIndex >= seedTofs.Length)
                {
                    seedTofIndex = 0;
                    seedDepIndex += seedStride;
                }
            }
            else
            {
                ++DoneCount;
                seedTofIndex = 0;
                seedDepIndex += seedStride;
            }

            if (seedDepIndex >= departures.Count)
                stage = SearchStage.CoarseGrid;
        }

        private void StepCoarse()
        {
            if (depIndex >= departures.Count)
            {
                PrepareWindowSweep();
                return;
            }

            double prograde = dvLow;
            if (options.DvSamples > 1)
            {
                prograde = dvLow +
                    (options.DvMax - dvLow) * dvIndex / (double)(options.DvSamples - 1);
            }

            double normal = 0.0;
            if (options.NormalSamples > 1)
            {
                normal = -normalSpan +
                    (2.0 * normalSpan) * normalIndex / (double)(options.NormalSamples - 1);
            }

            EvaluateCandidate(new PorkchopCandidate
            {
                Ut = departures[depIndex],
                Prograde = prograde,
                Radial = 0.0,
                Normal = normal
            });
            ++DoneCount;

            ++normalIndex;
            if (normalIndex >= options.NormalSamples)
            {
                normalIndex = 0;
                ++dvIndex;
                if (dvIndex >= options.DvSamples)
                {
                    dvIndex = 0;
                    ++depIndex;
                }
            }

            if (depIndex >= departures.Count)
                PrepareWindowSweep();
        }

        // If the fast coarse porkchop did not already find a capture PE,
        // sweep the entire practical departure window at SOI-sized time
        // spacing near Hohmann dV. The KerboScript fallback had to do this
        // after native v0.2.1 missed a valid Minmus window ~15 minutes away.
        // This is still bounded and chunked by Poll(), so it never blocks the
        // Unity/KSP main thread for an unbounded search.
        private void PrepareWindowSweep()
        {
            // Always sweep the practical window, even if the sparse coarse
            // grid already found a capture. Native search is cheap enough to
            // compare later windows too, which lets us choose the best
            // capture candidate rather than stopping at the first acceptable
            // one.
            double now = Planetarium.GetUniversalTime();
            sweepStep = Math.Max(3.0, options.SearchStepSeconds * 2.0);
            double sweepEndUt = options.HohmannUt + options.PeriodSeconds;
            sweepStartUt = Math.Max(now + 50.0, options.HohmannUt - options.PeriodSeconds);
            if (sweepEndUt < sweepStartUt)
                sweepEndUt = sweepStartUt;

            sweepTimeCount = Math.Max(1,
                (int)Math.Ceiling((sweepEndUt - sweepStartUt) / sweepStep) + 1);
            sweepTimeIndex = 0;
            sweepDvIndex = 0;
            sweepNormalIndex = 0;
            stage = SearchStage.WindowSweep;
        }

        private void StepWindowSweep()
        {
            if (sweepTimeIndex >= sweepTimeCount)
            {
                PrepareDensify();
                return;
            }

            double scale;
            switch (sweepDvIndex)
            {
                case 0: scale = 0.98; break;
                case 1: scale = 0.99; break;
                case 2: scale = 1.00; break;
                case 3: scale = 1.01; break;
                default: scale = 1.02; break;
            }

            double departureUt = sweepStartUt + sweepTimeIndex * sweepStep;
            double prograde = options.DvHoh * scale;
            double normal = (sweepNormalIndex - 1) * 12.0;

            if (prograde > options.DvMax)
                prograde = options.DvMax;
            if (prograde > 0.0 && departureUt > Planetarium.GetUniversalTime() + 25.0)
            {
                EvaluateCandidate(new PorkchopCandidate
                {
                    Ut = departureUt,
                    Prograde = prograde,
                    Radial = 0.0,
                    Normal = normal
                });
            }
            ++DoneCount;

            ++sweepNormalIndex;
            if (sweepNormalIndex >= 3)
            {
                sweepNormalIndex = 0;
                ++sweepDvIndex;
                if (sweepDvIndex >= 5)
                {
                    sweepDvIndex = 0;
                    ++sweepTimeIndex;
                }
            }

            if (sweepTimeIndex >= sweepTimeCount)
                PrepareDensify();
        }

        private void PrepareDensify()
        {
            densifySeeds = candidates
                .OrderBy(candidate => IsCapturePe(candidate.Periapsis) ? 0 : 1)
                .ThenBy(candidate => candidate.Score)
                .ThenBy(candidate => candidate.DeltaV)
                .Take(5)
                .Select(CopyCandidate)
                .ToList();

            densifySeedIndex = 0;
            densifyTimeIndex = 0;
            densifyDvIndex = 0;
            densifyNormalIndex = 0;
            densifyRadialIndex = 0;
            stage = densifySeeds.Count == 0 ? SearchStage.Done : SearchStage.Densify;
        }

        private void StepDensify()
        {
            if (densifySeeds == null || densifySeedIndex >= densifySeeds.Count)
            {
                stage = SearchStage.Done;
                return;
            }

            PorkchopCandidate seed = densifySeeds[densifySeedIndex];
            double fineTimeStep = Math.Max(1.0, options.SearchStepSeconds * 0.5);
            double radialStep = Math.Max(4.0, Math.Min(10.0, options.DvHoh * 0.008));
            double departureUt = seed.Ut + (densifyTimeIndex - 3) * fineTimeStep;
            double prograde = seed.Prograde + (densifyDvIndex - 3) * 3.0;
            double normal = seed.Normal + (densifyNormalIndex - 1) * 4.0;
            double radial = seed.Radial + (densifyRadialIndex - 2) * radialStep;

            if (departureUt > Planetarium.GetUniversalTime() + 25.0)
            {
                if (prograde > options.DvMax)
                    prograde = options.DvMax;

                EvaluateCandidate(new PorkchopCandidate
                {
                    Ut = departureUt,
                    Prograde = prograde,
                    Radial = radial,
                    Normal = normal
                });
            }
            ++DoneCount;

            ++densifyRadialIndex;
            if (densifyRadialIndex >= 5)
            {
                densifyRadialIndex = 0;
                ++densifyNormalIndex;
                if (densifyNormalIndex >= 3)
                {
                    densifyNormalIndex = 0;
                    ++densifyDvIndex;
                    if (densifyDvIndex >= 7)
                    {
                        densifyDvIndex = 0;
                        ++densifyTimeIndex;
                        if (densifyTimeIndex >= 7)
                        {
                            densifyTimeIndex = 0;
                            ++densifySeedIndex;
                        }
                    }
                }
            }

            if (densifySeedIndex >= densifySeeds.Count)
                stage = SearchStage.Done;
        }

        private bool TryLambertCandidate(double departureUt, double tof, out PorkchopCandidate candidate)
        {
            candidate = null;

            Vector3d pos1Raw = initialOrbit.getRelativePositionAtUT(departureUt);
            Vector3d pos2Raw = target.orbit.getRelativePositionAtUT(departureUt + tof);
            Vector3d velRaw = initialOrbit.getOrbitalVelocityAtUT(departureUt);

            Vec pos1 = ToVec(pos1Raw);
            Vec pos2 = ToVec(pos2Raw);
            Vec velocity = ToVec(velRaw);

            // Mirror current KerboScript semantics: aim beside the target body
            // at approximately parking altitude instead of Lambert-to-center.
            Vec aimNormal = Vec.Cross(pos1, pos2);
            if (aimNormal.Magnitude < 0.001)
                aimNormal = Vec.Cross(pos2, new Vec(0.0, 1.0, 0.0));
            if (aimNormal.Magnitude > 0.001)
            {
                Vec missDirection = Vec.Cross(pos2, aimNormal).Normalized();
                pos2 = pos2 + missDirection * aimOffset;
            }

            LambertSolver.Result solution = LambertSolver.Solve(
                pos1, pos2, tof, parent.gravParameter, false);
            if (!solution.Ok)
            {
                solution = LambertSolver.Solve(
                    pos1, pos2, tof, parent.gravParameter, true);
            }
            if (!solution.Ok)
                return false;

            Vec deltaInternal = solution.Vel1 - velocity;
            if (deltaInternal.Magnitude > options.DvMax * 1.15)
                return false;

            double radial;
            double normal;
            double prograde;
            if (!InternalDeltaToNode(initialOrbit, departureUt, deltaInternal,
                out radial, out normal, out prograde))
                return false;

            if (prograde > options.DvMax)
                prograde = options.DvMax;

            candidate = new PorkchopCandidate
            {
                Ut = departureUt,
                Prograde = prograde,
                Radial = radial,
                Normal = normal
            };
            return true;
        }

        private void EvaluateCandidate(PorkchopCandidate candidate)
        {
            double pe;
            if (!TryPatchedPeriapsis(candidate, out pe))
                return;

            ++HitCount;
            candidate.Periapsis = pe;
            candidate.DeltaV = Math.Sqrt(
                candidate.Prograde * candidate.Prograde +
                candidate.Radial * candidate.Radial +
                candidate.Normal * candidate.Normal);

            bool capture = IsCapturePe(pe);
            if (capture)
                ++CaptureCount;

            candidate.Score = Score(candidate, capture);
            if (candidate.Score < 0.0)
                return;

            KeepCandidate(candidate, 20);
        }

        private bool TryPatchedPeriapsis(PorkchopCandidate candidate, out double pe)
        {
            pe = -1.0;

            Vector3d posRaw = initialOrbit.getRelativePositionAtUT(candidate.Ut);
            Vector3d velRaw = initialOrbit.getOrbitalVelocityAtUT(candidate.Ut);
            Vector3d deltaInternal;
            if (!NodeToInternalDelta(
                initialOrbit,
                candidate.Ut,
                candidate.Radial,
                candidate.Normal,
                candidate.Prograde,
                out deltaInternal))
                return false;

            var transfer = new Orbit();
            transfer.UpdateFromStateVectors(
                posRaw,
                velRaw + deltaInternal,
                parent,
                candidate.Ut);
            transfer.StartUT = candidate.Ut;

            double horizon = candidate.Ut +
                Math.Max(options.PeriodSeconds * 2.5, hohmannTof * 2.0);
            transfer.EndUT = horizon;

            Orbit current = transfer;
            for (int patch = 0; patch < 5; ++patch)
            {
                var next = new Orbit();
                bool ok = PatchedConics.CalculatePatch(
                    current,
                    next,
                    Math.Max(candidate.Ut, current.StartUT),
                    solverParameters,
                    null);

                if (!ok || next.referenceBody == null)
                    return false;

                if (next.referenceBody == target)
                {
                    pe = next.PeA;
                    return IsFinite(pe);
                }

                if (next.StartUT > horizon)
                    return false;

                current = next;
            }

            return false;
        }

        private double Score(PorkchopCandidate candidate, bool capture)
        {
            double pe = candidate.Periapsis;
            if (pe < -0.5)
                return -1.0;

            if (capture)
                return candidate.DeltaV + Math.Abs(pe - options.DesiredPe) * 0.002;

            double peScore;
            if (pe < options.MinimumPe)
            {
                peScore = 5000000000.0 + (options.MinimumPe - pe);
            }
            else
            {
                double graze = options.SoiAltitude * 0.35;
                if (pe > graze)
                    peScore = 100000000.0 + (pe - options.DesiredPe);
                else
                    peScore = Math.Abs(pe - options.DesiredPe);
            }

            return 100000000.0 + peScore + candidate.DeltaV;
        }

        private bool IsCapturePe(double pe)
        {
            return pe >= options.MinimumPe && pe <= options.MaximumPe;
        }

        private void KeepCandidate(PorkchopCandidate candidate, int maxCount)
        {
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

        // Exact maneuver-node basis conversion using KSP's node convention:
        // node DeltaV = (radialOut, normal, prograde). KSP orbital state
        // vectors use the internal Y/Z ordering, so world vectors are swapped.
        private static bool NodeToInternalDelta(
            Orbit orbit,
            double ut,
            double radial,
            double normal,
            double prograde,
            out Vector3d deltaInternal)
        {
            deltaInternal = Vector3d.zero;

            Vector3d velInternal = orbit.getOrbitalVelocityAtUT(ut);
            Vector3d progradeWorld = SwapYZ(velInternal).normalized;
            Vector3d normalWorld = SwapYZ(orbit.GetOrbitNormal()).normalized;
            Vector3d radialWorld = Vector3d.Cross(normalWorld, progradeWorld).normalized;

            if (progradeWorld.sqrMagnitude < 1.0e-12 ||
                normalWorld.sqrMagnitude < 1.0e-12 ||
                radialWorld.sqrMagnitude < 1.0e-12)
                return false;

            Vector3d deltaWorld =
                progradeWorld * prograde +
                normalWorld * normal +
                radialWorld * radial;
            deltaInternal = SwapYZ(deltaWorld);
            return IsFinite(deltaInternal.x) &&
                IsFinite(deltaInternal.y) &&
                IsFinite(deltaInternal.z);
        }

        private static bool InternalDeltaToNode(
            Orbit orbit,
            double ut,
            Vec deltaInternal,
            out double radial,
            out double normal,
            out double prograde)
        {
            radial = 0.0;
            normal = 0.0;
            prograde = 0.0;

            Vector3d velInternal = orbit.getOrbitalVelocityAtUT(ut);
            Vector3d progradeWorld = SwapYZ(velInternal).normalized;
            Vector3d normalWorld = SwapYZ(orbit.GetOrbitNormal()).normalized;
            Vector3d radialWorld = Vector3d.Cross(normalWorld, progradeWorld).normalized;
            if (progradeWorld.sqrMagnitude < 1.0e-12 ||
                normalWorld.sqrMagnitude < 1.0e-12 ||
                radialWorld.sqrMagnitude < 1.0e-12)
                return false;

            Vector3d deltaWorld = SwapYZ(ToVector3d(deltaInternal));
            radial = Vector3d.Dot(deltaWorld, radialWorld);
            normal = Vector3d.Dot(deltaWorld, normalWorld);
            prograde = Vector3d.Dot(deltaWorld, progradeWorld);
            return IsFinite(radial) && IsFinite(normal) && IsFinite(prograde);
        }

        private static Vector3d SwapYZ(Vector3d value)
        {
            return new Vector3d(value.x, value.z, value.y);
        }

        private static PorkchopCandidate CopyCandidate(PorkchopCandidate source)
        {
            return new PorkchopCandidate
            {
                Ut = source.Ut,
                Prograde = source.Prograde,
                Radial = source.Radial,
                Normal = source.Normal,
                Score = source.Score,
                DeltaV = source.DeltaV,
                Periapsis = source.Periapsis
            };
        }

        private static Vec ToVec(Vector3d value)
        {
            return new Vec(value.x, value.y, value.z);
        }

        private static Vector3d ToVector3d(Vec value)
        {
            return new Vector3d(value.X, value.Y, value.Z);
        }

        private static int ClampInt(int value, int min, int max, int fallback)
        {
            if (value <= 0)
                value = fallback;
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
