using System;

namespace kOS.AddOns.AOSO.Native
{
    internal struct Vec
    {
        public readonly double X;
        public readonly double Y;
        public readonly double Z;

        public Vec(double x, double y, double z)
        {
            X = x;
            Y = y;
            Z = z;
        }

        public double Magnitude
        {
            get { return Math.Sqrt(X * X + Y * Y + Z * Z); }
        }

        public Vec Normalized()
        {
            double mag = Magnitude;
            if (mag <= 0.0)
                return new Vec(0.0, 0.0, 0.0);
            return this / mag;
        }

        public bool IsFinite()
        {
            return IsFiniteNumber(X) && IsFiniteNumber(Y) && IsFiniteNumber(Z);
        }

        private static bool IsFiniteNumber(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value);
        }

        public static double Dot(Vec left, Vec right)
        {
            return left.X * right.X + left.Y * right.Y + left.Z * right.Z;
        }

        public static Vec Cross(Vec left, Vec right)
        {
            return new Vec(
                left.Y * right.Z - left.Z * right.Y,
                left.Z * right.X - left.X * right.Z,
                left.X * right.Y - left.Y * right.X);
        }

        public static Vec operator +(Vec left, Vec right)
        {
            return new Vec(left.X + right.X, left.Y + right.Y, left.Z + right.Z);
        }

        public static Vec operator -(Vec left, Vec right)
        {
            return new Vec(left.X - right.X, left.Y - right.Y, left.Z - right.Z);
        }

        public static Vec operator *(Vec value, double scale)
        {
            return new Vec(value.X * scale, value.Y * scale, value.Z * scale);
        }

        public static Vec operator *(double scale, Vec value)
        {
            return value * scale;
        }

        public static Vec operator /(Vec value, double scale)
        {
            return new Vec(value.X / scale, value.Y / scale, value.Z / scale);
        }
    }
}
