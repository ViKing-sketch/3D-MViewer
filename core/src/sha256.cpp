#include "fbv/sha256.hpp"

#include <cstring>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace fbv {
namespace {

std::uint32_t rotr(std::uint32_t x, std::uint32_t n) {
  return (x >> n) | (x << (32 - n));
}

constexpr std::uint32_t kK[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

void transform(std::uint32_t state[8], const std::uint8_t block[64]) {
  std::uint32_t w[64];
  for (int i = 0; i < 16; ++i) {
    w[i] = (std::uint32_t(block[i * 4]) << 24) | (std::uint32_t(block[i * 4 + 1]) << 16) |
           (std::uint32_t(block[i * 4 + 2]) << 8) | std::uint32_t(block[i * 4 + 3]);
  }
  for (int i = 16; i < 64; ++i) {
    const std::uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    const std::uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  std::uint32_t a = state[0];
  std::uint32_t b = state[1];
  std::uint32_t c = state[2];
  std::uint32_t d = state[3];
  std::uint32_t e = state[4];
  std::uint32_t f = state[5];
  std::uint32_t g = state[6];
  std::uint32_t h = state[7];
  for (int i = 0; i < 64; ++i) {
    const std::uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    const std::uint32_t ch = (e & f) ^ ((~e) & g);
    const std::uint32_t t1 = h + s1 + ch + kK[i] + w[i];
    const std::uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    const std::uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    const std::uint32_t t2 = s0 + maj;
    h = g;
    g = f;
    f = e;
    e = d + t1;
    d = c;
    c = b;
    b = a;
    a = t1 + t2;
  }
  state[0] += a;
  state[1] += b;
  state[2] += c;
  state[3] += d;
  state[4] += e;
  state[5] += f;
  state[6] += g;
  state[7] += h;
}

}  // namespace

Sha256 sha256_bytes(const std::uint8_t* data, std::size_t len) {
  std::uint32_t state[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::uint8_t block[64];
  std::size_t offset = 0;
  while (len - offset >= 64) {
    transform(state, data + offset);
    offset += 64;
  }
  const std::size_t rem = len - offset;
  std::memset(block, 0, sizeof(block));
  if (rem != 0) std::memcpy(block, data + offset, rem);
  block[rem] = 0x80;
  if (rem >= 56) {
    transform(state, block);
    std::memset(block, 0, sizeof(block));
  }
  const std::uint64_t bits = static_cast<std::uint64_t>(len) * 8;
  for (int i = 0; i < 8; ++i) {
    block[63 - i] = static_cast<std::uint8_t>((bits >> (8 * i)) & 0xff);
  }
  transform(state, block);
  Sha256 out;
  for (int i = 0; i < 8; ++i) {
    out.bytes[static_cast<std::size_t>(i * 4)] = static_cast<std::uint8_t>((state[i] >> 24) & 0xff);
    out.bytes[static_cast<std::size_t>(i * 4 + 1)] =
        static_cast<std::uint8_t>((state[i] >> 16) & 0xff);
    out.bytes[static_cast<std::size_t>(i * 4 + 2)] =
        static_cast<std::uint8_t>((state[i] >> 8) & 0xff);
    out.bytes[static_cast<std::size_t>(i * 4 + 3)] = static_cast<std::uint8_t>(state[i] & 0xff);
  }
  return out;
}

Sha256 sha256_bytes(std::string_view data) {
  return sha256_bytes(reinterpret_cast<const std::uint8_t*>(data.data()), data.size());
}

std::string sha256_hex(const Sha256& digest) {
  std::ostringstream os;
  os << std::hex << std::setfill('0');
  for (std::uint8_t byte : digest.bytes) {
    os << std::setw(2) << static_cast<int>(byte);
  }
  return os.str();
}

std::string sha256_file(const std::filesystem::path& path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("cannot read " + path.string());
  std::string data((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  return sha256_hex(sha256_bytes(data));
}

}  // namespace fbv
