using System;

namespace kOS.AddOns.AOSO.Native
{
    // Zero-revolution universal-variable Lambert solver following the
    // Vallado universal-variable formulation. All trig here is radians.
    // This is independent of Unity/KSP; the bridge converts kOS vectors.
    internal static class LambertSolver
    {
        internal struct Result
        {
            public bool Ok;
            public Vec Vel1;
            public Vec Vel2;
            public string Error;
            public double Z;
            public double TofError;
        }

        private const double TwoPi = 2.0 * Math.PI;
        private const double AngleReject = 2.0 * Math.PI / 180.0;
        private const double AnglePiSpecial = 2.5 * Math.PI / 180.0;
        private const double ZUpper = 4.0 * Math.PI * Math.PI - 1.0e-7;
        private const double ZLower = -100.0;

        public static Result Solve(Vec pos1, Vec pos2, double tofSeconds, double mu, bool longWay)
        {
            Result fail = Failure("invalid");

            try
            {
                if (!pos1.IsFinite() || !pos2.IsFinite() || !IsFinite(tofSeconds) || !IsFinite(mu))
                    return Failure("non_finite");
                if (tofSeconds < 30.0)
                    return Failure("tof_lt_30");
                if (mu <= 0.0)
                    return Failure("bad_mu");

                double radius1 = pos1.Magnitude;
                double radius2 = pos2.Magnitude;
                if (radius1 < 1.0 || radius2 < 1.0)
                    return Failure("bad_radius");

                double cosTransfer = Clamp(Vec.Dot(pos1, pos2) / (radius1 * radius2), -1.0, 1.0);
                double transferAngle = Math.Acos(cosTransfer);
                if (longWay)
                    transferAngle = TwoPi - transferAngle;

                if (transferAngle < AngleReject || transferAngle > TwoPi - AngleReject)
                    return Failure("bad_angle");

                if (Math.Abs(transferAngle - Math.PI) < AnglePiSpecial)
                    return SolvePi(pos1, pos2, radius1, radius2, mu);

                double sinTransfer = Math.Sin(transferAngle);
                double oneMinusCos = 1.0 - Math.Cos(transferAngle);
                if (Math.Abs(sinTransfer) < 8.0e-4 || Math.Abs(oneMinusCos) < 8.0e-4)
                    return Failure("singular_angle");

                double aval = sinTransfer * Math.Sqrt(radius1 * radius2 / oneMinusCos);
                if (!IsFinite(aval) || Math.Abs(aval) < 1.0e-12)
                    return Failure("bad_a");

                double zRoot;
                double tofError;
                if (!SolveForZ(radius1, radius2, aval, tofSeconds, mu, out zRoot, out tofError))
                    return Failure("no_root");

                double yval;
                double calcTof;
                if (!TryTimeOfFlight(radius1, radius2, aval, zRoot, mu, out calcTof, out yval))
                    return Failure("bad_root");
                if (yval <= 0.0)
                    return Failure("bad_y");

                double fLag = 1.0 - yval / radius1;
                double gLag = aval * Math.Sqrt(yval / mu);
                double gDot = 1.0 - yval / radius2;
                if (!IsFinite(gLag) || Math.Abs(gLag) < 1.0e-12)
                    return Failure("bad_g");

                Vec vel1 = (pos2 - fLag * pos1) / gLag;
                Vec vel2 = (gDot * pos2 - pos1) / gLag;
                if (!vel1.IsFinite() || !vel2.IsFinite())
                    return Failure("non_finite_velocity");

                return new Result
                {
                    Ok = true,
                    Vel1 = vel1,
                    Vel2 = vel2,
                    Error = string.Empty,
                    Z = zRoot,
                    TofError = Math.Abs(calcTof - tofSeconds)
                };
            }
            catch
            {
                return fail;
            }
        }

        private static Result SolvePi(Vec pos1, Vec pos2, double radius1, double radius2, double mu)
        {
            double semiMajor = (radius1 + radius2) / 2.0;
            if (semiMajor < 1.0)
                return Failure("bad_pi_sma");

            double vv1 = mu * (2.0 / radius1 - 1.0 / semiMajor);
            double vv2 = mu * (2.0 / radius2 - 1.0 / semiMajor);
            if (vv1 <= 0.0 || vv2 <= 0.0)
                return Failure("bad_pi_visviva");

            Vec normal = Vec.Cross(pos1, pos2);
            if (normal.Magnitude < 1.0e-6)
                normal = Vec.Cross(pos1, new Vec(0.0, 1.0, 0.0));
            if (normal.Magnitude < 1.0e-6)
                normal = Vec.Cross(pos1, new Vec(0.0, 0.0, 1.0));
            if (normal.Magnitude < 1.0e-6)
                return Failure("pi_plane");

            normal = normal.Normalized();
            Vec prograde1 = Vec.Cross(normal, pos1.Normalized()).Normalized();
            Vec prograde2 = Vec.Cross(normal, pos2.Normalized()).Normalized();
            Vec vel1 = prograde1 * Math.Sqrt(vv1);
            Vec vel2 = prograde2 * Math.Sqrt(vv2);

            return new Result
            {
                Ok = vel1.IsFinite() && vel2.IsFinite(),
                Vel1 = vel1,
                Vel2 = vel2,
                Error = string.Empty,
                Z = 0.0,
                TofError = 0.0
            };
        }

        private static bool SolveForZ(
            double radius1,
            double radius2,
            double aval,
            double targetTof,
            double mu,
            out double zRoot,
            out double tofError)
        {
            zRoot = 0.0;
            tofError = double.PositiveInfinity;

            double baseZ = 0.0;
            double baseTof;
            double baseY;

            if (!TryTimeOfFlight(radius1, radius2, aval, baseZ, mu, out baseTof, out baseY))
            {
                double probe = 0.125;
                bool found = false;
                for (int i = 0; i < 24; ++i)
                {
                    if (probe > ZUpper)
                        probe = ZUpper;
                    if (TryTimeOfFlight(radius1, radius2, aval, probe, mu, out baseTof, out baseY))
                    {
                        baseZ = probe;
                        found = true;
                        break;
                    }
                    if (probe >= ZUpper)
                        break;
                    probe *= 2.0;
                }
                if (!found)
                    return false;
            }

            double baseErr = baseTof - targetTof;
            double tolerance = Math.Max(1.0e-6, targetTof * 1.0e-10);
            if (Math.Abs(baseErr) <= tolerance)
            {
                zRoot = baseZ;
                tofError = Math.Abs(baseErr);
                return true;
            }

            double lowZ;
            double highZ;
            double lowErr;
            double highErr;

            if (baseErr < 0.0)
            {
                lowZ = baseZ;
                lowErr = baseErr;
                highZ = baseZ;
                highErr = baseErr;
                double step = 0.25;

                bool bracketed = false;
                for (int i = 0; i < 64; ++i)
                {
                    double candidate = highZ + step;
                    if (candidate > ZUpper)
                        candidate = ZUpper;

                    double candidateTof;
                    double candidateY;
                    if (TryTimeOfFlight(radius1, radius2, aval, candidate, mu, out candidateTof, out candidateY))
                    {
                        double candidateErr = candidateTof - targetTof;
                        if (candidateErr >= 0.0)
                        {
                            highZ = candidate;
                            highErr = candidateErr;
                            bracketed = true;
                            break;
                        }
                        lowZ = candidate;
                        lowErr = candidateErr;
                        highZ = candidate;
                        highErr = candidateErr;
                    }

                    if (candidate >= ZUpper)
                        break;
                    step *= 1.65;
                }

                if (!bracketed)
                    return false;
            }
            else
            {
                highZ = baseZ;
                highErr = baseErr;
                lowZ = baseZ;
                lowErr = baseErr;
                double step = 0.25;

                bool bracketed = false;
                for (int i = 0; i < 64; ++i)
                {
                    double candidate = lowZ - step;
                    if (candidate < ZLower)
                        candidate = ZLower;

                    double candidateTof;
                    double candidateY;
                    if (TryTimeOfFlight(radius1, radius2, aval, candidate, mu, out candidateTof, out candidateY))
                    {
                        double candidateErr = candidateTof - targetTof;
                        if (candidateErr <= 0.0)
                        {
                            lowZ = candidate;
                            lowErr = candidateErr;
                            bracketed = true;
                            break;
                        }
                        highZ = candidate;
                        highErr = candidateErr;
                        lowZ = candidate;
                        lowErr = candidateErr;
                    }

                    if (candidate <= ZLower)
                        break;
                    step *= 1.65;
                }

                if (!bracketed)
                    return false;
            }

            // Bisection inside the valid zero-revolution sign-changing
            // bracket. It is deliberately boring: unlike regula falsi it
            // cannot stagnate when the high-z TOF becomes extremely steep.
            double bestZ = Math.Abs(lowErr) <= Math.Abs(highErr) ? lowZ : highZ;
            double bestErr = Math.Min(Math.Abs(lowErr), Math.Abs(highErr));

            for (int iteration = 0; iteration < 80; ++iteration)
            {
                double candidate = (lowZ + highZ) / 2.0;
                double candidateTof;
                double candidateY;
                if (!TryTimeOfFlight(radius1, radius2, aval, candidate, mu, out candidateTof, out candidateY))
                    return false;

                double candidateErr = candidateTof - targetTof;
                double absErr = Math.Abs(candidateErr);
                if (absErr < bestErr)
                {
                    bestErr = absErr;
                    bestZ = candidate;
                }

                if (absErr <= tolerance)
                {
                    zRoot = candidate;
                    tofError = absErr;
                    return true;
                }

                if (candidateErr < 0.0)
                {
                    lowZ = candidate;
                    lowErr = candidateErr;
                }
                else
                {
                    highZ = candidate;
                    highErr = candidateErr;
                }

                if (Math.Abs(highZ - lowZ) < 1.0e-12)
                    break;
            }

            zRoot = bestZ;
            tofError = bestErr;
            return bestErr <= Math.Max(1.0e-4, targetTof * 1.0e-8);
        }

        private static bool TryTimeOfFlight(
            double radius1,
            double radius2,
            double aval,
            double zval,
            double mu,
            out double tof,
            out double yval)
        {
            tof = 0.0;
            yval = 0.0;

            double cval = StumpffC(zval);
            double sval = StumpffS(zval);
            if (!IsFinite(cval) || !IsFinite(sval) || cval <= 1.0e-14)
                return false;

            double sqrtC = Math.Sqrt(cval);
            yval = radius1 + radius2 + aval * (zval * sval - 1.0) / sqrtC;
            if (!IsFinite(yval) || yval <= 0.0)
                return false;

            double ratio = yval / cval;
            if (!IsFinite(ratio) || ratio <= 0.0)
                return false;

            double xval = Math.Sqrt(ratio);
            double raw = xval * xval * xval * sval + aval * Math.Sqrt(yval);
            if (!IsFinite(raw) || raw <= 0.0)
                return false;

            tof = raw / Math.Sqrt(mu);
            return IsFinite(tof) && tof > 0.0;
        }

        private static double StumpffC(double zval)
        {
            if (zval > 1.0e-8)
            {
                double root = Math.Sqrt(zval);
                return (1.0 - Math.Cos(root)) / zval;
            }
            if (zval < -1.0e-8)
            {
                double root = Math.Sqrt(-zval);
                return (Math.Cosh(root) - 1.0) / (-zval);
            }

            // Series avoids cancellation around z=0.
            return 0.5 - zval / 24.0 + zval * zval / 720.0 - zval * zval * zval / 40320.0;
        }

        private static double StumpffS(double zval)
        {
            if (zval > 1.0e-8)
            {
                double root = Math.Sqrt(zval);
                return (root - Math.Sin(root)) / (root * root * root);
            }
            if (zval < -1.0e-8)
            {
                double root = Math.Sqrt(-zval);
                return (Math.Sinh(root) - root) / (root * root * root);
            }

            return 1.0 / 6.0 - zval / 120.0 + zval * zval / 5040.0 - zval * zval * zval / 362880.0;
        }

        private static Result Failure(string error)
        {
            return new Result
            {
                Ok = false,
                Vel1 = new Vec(0.0, 0.0, 0.0),
                Vel2 = new Vec(0.0, 0.0, 0.0),
                Error = error,
                Z = 0.0,
                TofError = 0.0
            };
        }

        private static double Clamp(double value, double min, double max)
        {
            if (value < min)
                return min;
            if (value > max)
                return max;
            return value;
        }

        private static bool IsFinite(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }
    }
}
