#pragma once

#include <cmath>
#include <cstdint>
#include <vector>

namespace fbv {

struct Vec2 {
  double x = 0;
  double y = 0;
};

struct Vec3 {
  double x = 0;
  double y = 0;
  double z = 0;
};

inline Vec3 operator+(Vec3 a, Vec3 b) {
  return {a.x + b.x, a.y + b.y, a.z + b.z};
}
inline Vec3 operator-(Vec3 a, Vec3 b) {
  return {a.x - b.x, a.y - b.y, a.z - b.z};
}
inline Vec3 operator*(Vec3 a, double s) {
  return {a.x * s, a.y * s, a.z * s};
}
inline double dot(Vec3 a, Vec3 b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline Vec3 cross(Vec3 a, Vec3 b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline double length(Vec3 a) {
  return std::sqrt(dot(a, a));
}
inline Vec3 normalize(Vec3 a) {
  const double n = length(a);
  if (n < 1e-15) return {};
  return a * (1.0 / n);
}

struct Mat4 {
  double m[16]{};
  static Mat4 identity() {
    Mat4 out;
    out.m[0] = out.m[5] = out.m[10] = out.m[15] = 1;
    return out;
  }
};

inline Mat4 mul(const Mat4& a, const Mat4& b) {
  Mat4 out;
  for (int row = 0; row < 4; ++row) {
    for (int col = 0; col < 4; ++col) {
      double sum = 0;
      for (int k = 0; k < 4; ++k) sum += a.m[row * 4 + k] * b.m[k * 4 + col];
      out.m[row * 4 + col] = sum;
    }
  }
  return out;
}

inline Vec3 transform_point(const Mat4& a, Vec3 p) {
  return {a.m[0] * p.x + a.m[1] * p.y + a.m[2] * p.z + a.m[3],
          a.m[4] * p.x + a.m[5] * p.y + a.m[6] * p.z + a.m[7],
          a.m[8] * p.x + a.m[9] * p.y + a.m[10] * p.z + a.m[11]};
}

inline Vec3 transform_vector(const Mat4& a, Vec3 p) {
  return {a.m[0] * p.x + a.m[1] * p.y + a.m[2] * p.z, a.m[4] * p.x + a.m[5] * p.y + a.m[6] * p.z,
          a.m[8] * p.x + a.m[9] * p.y + a.m[10] * p.z};
}

inline Mat4 frame_from_axes(Vec3 origin, Vec3 x, Vec3 y, Vec3 z) {
  Mat4 m = Mat4::identity();
  m.m[0] = x.x;
  m.m[1] = y.x;
  m.m[2] = z.x;
  m.m[3] = origin.x;
  m.m[4] = x.y;
  m.m[5] = y.y;
  m.m[6] = z.y;
  m.m[7] = origin.y;
  m.m[8] = x.z;
  m.m[9] = y.z;
  m.m[10] = z.z;
  m.m[11] = origin.z;
  return m;
}

struct Frame2 {
  Vec2 origin;
  Vec2 x{1, 0};
  Vec2 y{0, 1};
  Vec2 apply(Vec2 p) const {
    return {origin.x + x.x * p.x + y.x * p.y, origin.y + x.y * p.x + y.y * p.y};
  }
};

struct TriMesh {
  std::vector<double> position;
  std::vector<double> normal;
  std::vector<std::uint32_t> indices;
};

inline void add_triangle(TriMesh& mesh, Vec3 a, Vec3 b, Vec3 c) {
  Vec3 n = cross(b - a, c - a);
  const double nlen = length(n);
  if (nlen < 1e-18) return;
  n = n * (1.0 / nlen);
  const auto base = static_cast<std::uint32_t>(mesh.position.size() / 3);
  const Vec3 pts[3] = {a, b, c};
  for (Vec3 p : pts) {
    mesh.position.push_back(p.x);
    mesh.position.push_back(p.y);
    mesh.position.push_back(p.z);
    mesh.normal.push_back(n.x);
    mesh.normal.push_back(n.y);
    mesh.normal.push_back(n.z);
  }
  mesh.indices.push_back(base);
  mesh.indices.push_back(base + 1);
  mesh.indices.push_back(base + 2);
}

inline void add_fan(TriMesh& mesh, const std::vector<Vec3>& poly, bool reverse) {
  if (poly.size() < 3) return;
  auto at = [&](std::size_t i) { return reverse ? poly[poly.size() - 1 - i] : poly[i]; };
  for (std::size_t i = 1; i + 1 < poly.size(); ++i) add_triangle(mesh, at(0), at(i), at(i + 1));
}

inline void add_prism(TriMesh& mesh, const std::vector<Vec3>& bottom, Vec3 extrude) {
  const std::size_t n = bottom.size();
  if (n < 3) return;
  std::vector<Vec3> top;
  top.reserve(n);
  for (const Vec3& p : bottom) top.push_back(p + extrude);
  add_fan(mesh, top, false);
  add_fan(mesh, bottom, true);
  for (std::size_t i = 0; i < n; ++i) {
    const std::size_t j = (i + 1) % n;
    const Vec3 bi = bottom[i];
    const Vec3 bj = bottom[j];
    const Vec3 ti = top[i];
    const Vec3 tj = top[j];
    add_triangle(mesh, bi, bj, tj);
    add_triangle(mesh, bi, tj, ti);
  }
}

}  // namespace fbv
