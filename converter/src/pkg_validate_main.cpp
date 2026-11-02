#include "fbv/convert.hpp"

#include <iostream>

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "pkg_validate <пакет.fbvpkg или каталог>\n";
    return 1;
  }
  std::string report;
  const int code = fbv::validate_package(argv[1], report);
  std::cout << report;
  return code;
}
