#include "fbv/json.hpp"
#include "fbv/sha256.hpp"
#include "fbv/zip.hpp"
#include "fbv_core.h"

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

int g_failed = 0;

void check(bool condition, const char* text, int line) {
  if (!condition) {
    std::cerr << "FAIL " << line << ": " << text << "\n";
    ++g_failed;
  }
}

#define CHECK(cond) check(static_cast<bool>(cond), #cond, __LINE__)

}  // namespace

int main() {
  const auto abc = fbv::sha256_hex(fbv::sha256_bytes(std::string_view("abc")));
  CHECK(abc == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  const auto empty = fbv::sha256_hex(fbv::sha256_bytes(std::string_view("")));
  CHECK(empty == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");

  const std::uint32_t crc = fbv::crc32_bytes(reinterpret_cast<const std::uint8_t*>("123456789"), 9);
  CHECK(crc == 0xCBF43926u);

  fbv::Json parsed;
  std::string error;
  CHECK(fbv::Json::parse("{\"n\":1,\"name\":\"Марка\",\"ok\":true,\"xs\":[1,2]}", parsed, error));
  CHECK(parsed.find("n") != nullptr && parsed.find("n")->as_int() == 1);
  CHECK(parsed.find("name")->as_string() == "Марка");
  fbv::Json again;
  CHECK(fbv::Json::parse(parsed.dump(), again, error));
  CHECK(again.find("ok")->as_bool() == true);

  const auto dir = std::filesystem::temp_directory_path() / "fbv-core-zip";
  std::filesystem::remove_all(dir);
  std::filesystem::create_directories(dir);
  fbv::ZipItem item;
  item.name = "mesh/lod0.glb";
  item.bytes = {'g', 'l', 'T', 'F'};
  std::string zip_error;
  const auto zip_path = dir / "sample.fbvpkg";
  CHECK(fbv::write_zip_stored({item}, zip_path, zip_error));
  const auto unpacked = dir / "out";
  CHECK(fbv::unzip_stored(zip_path, unpacked, zip_error));
  CHECK(std::filesystem::file_size(unpacked / "mesh" / "lod0.glb") == 4);

  char err[128] = {};
  fbv_package* missing = fbv_package_open("/no/such/package.fbvpkg", err, sizeof(err));
  CHECK(missing == nullptr);
  CHECK(err[0] != '\0');
  CHECK(std::string(fbv_core_version()) == "0.1.0");

  if (g_failed != 0) {
    std::cerr << g_failed << " core checks failed\n";
    return 1;
  }
  std::cout << "core_tests ok\n";
  return 0;
}
