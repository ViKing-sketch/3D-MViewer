#include "fbv/convert.hpp"

#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

namespace {

void print_usage() {
  std::cerr
      << "fbvconv — конвертер IFC в пакет .fbvpkg (Field BIM Viewer)\n"
      << "\n"
      << "  fbvconv <input.ifc> -o <output.fbvpkg> [опции]\n"
      << "  fbvconv --validate <пакет>\n"
      << "\n"
      << "Опции:\n"
      << "  -o, --output <path>          ZIP-пакет .fbvpkg или каталог с --directory\n"
      << "  --directory                  записать каталог пакета, а не ZIP\n"
      << "  --no-brep                    не писать brep.pack / brep.index\n"
      << "  --class <IfcWall,IfcSlab>    оставить только перечисленные классы\n"
      << "  --linear-deflection <м>      допуск триангуляции (записывается в manifest)\n"
      << "  --angular-deflection <рад>   угловой допуск (записывается в manifest)\n"
      << "  --lod <n>                    запрошенное число LOD; аналитический мешер пишет lod0\n"
      << "  --validate <пакет>           проверить пакет (код 0 или 3)\n"
      << "\n"
      << "STEP/IGES в этой сборке не импортируются: нужен OCCT XDE (задача Z06).\n";
}

std::vector<std::string> split_csv(const std::string& text) {
  std::vector<std::string> out;
  std::string current;
  for (char c : text) {
    if (c == ',') {
      if (!current.empty()) out.push_back(current);
      current.clear();
    } else if (c != ' ') {
      current.push_back(c);
    }
  }
  if (!current.empty()) out.push_back(current);
  return out;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    print_usage();
    return 1;
  }
  const std::string first = argv[1];
  if (first == "--help" || first == "-h") {
    print_usage();
    return 0;
  }
  if (first == "--validate") {
    if (argc < 3) {
      print_usage();
      return 1;
    }
    std::string report;
    const int code = fbv::validate_package(argv[2], report);
    std::cout << report;
    return code;
  }

  fbv::ConvertOptions options;
  std::string input;
  try {
    for (int i = 1; i < argc; ++i) {
      const std::string arg = argv[i];
      const auto need = [&](const char* name) {
        if (i + 1 >= argc) throw std::runtime_error(std::string("не хватает значения для ") + name);
        return std::string(argv[++i]);
      };
      if (arg == "-o" || arg == "--output") {
        options.output = need(arg.c_str());
      } else if (arg == "--directory") {
        options.as_directory = true;
      } else if (arg == "--no-brep") {
        options.write_brep = false;
      } else if (arg == "--class") {
        const auto items = split_csv(need(arg.c_str()));
        options.class_filter.insert(options.class_filter.end(), items.begin(), items.end());
      } else if (arg == "--linear-deflection") {
        options.linear_deflection_m = std::stod(need(arg.c_str()));
      } else if (arg == "--angular-deflection") {
        options.angular_deflection_rad = std::stod(need(arg.c_str()));
      } else if (arg == "--lod") {
        options.lod = std::stoi(need(arg.c_str()));
      } else if (!arg.empty() && arg[0] == '-') {
        print_usage();
        return 1;
      } else if (input.empty()) {
        input = arg;
      } else {
        print_usage();
        return 1;
      }
    }
  } catch (const std::exception& ex) {
    std::cerr << ex.what() << "\n";
    return 1;
  }
  if (input.empty() || options.output.empty()) {
    print_usage();
    return 1;
  }
  const fbv::ConvertStatus status = fbv::convert_file(input, options);
  if (status.code != 0) {
    std::cerr << status.error << "\n";
    return status.code;
  }
  std::cout << "elements: " << status.elements << "\n"
            << "with_mesh: " << status.with_mesh << "\n"
            << "warnings: " << status.warnings << "\n"
            << "output: " << options.output << "\n";
  return 0;
}
