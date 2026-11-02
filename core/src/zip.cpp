#include "fbv/zip.hpp"

#include "fbv/io.hpp"

#include <algorithm>
#include <cstring>
#include <stdexcept>

namespace fbv {
namespace {

void append_u16(std::vector<std::uint8_t>& out, std::uint16_t value) {
  out.push_back(static_cast<std::uint8_t>(value & 0xff));
  out.push_back(static_cast<std::uint8_t>((value >> 8) & 0xff));
}

void append_u32(std::vector<std::uint8_t>& out, std::uint32_t value) {
  for (int i = 0; i < 4; ++i) out.push_back(static_cast<std::uint8_t>((value >> (8 * i)) & 0xff));
}

std::uint16_t read_u16(const std::uint8_t* p) {
  return static_cast<std::uint16_t>(p[0] | (p[1] << 8));
}

std::uint32_t read_u32(const std::uint8_t* p) {
  return static_cast<std::uint32_t>(p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24));
}

bool contains_parent_ref(const std::string& name) {
  if (!name.empty() && name[0] == '/') return true;
  std::size_t start = 0;
  while (start < name.size()) {
    const std::size_t slash = name.find('/', start);
    const std::string part =
        name.substr(start, slash == std::string::npos ? std::string::npos : slash - start);
    if (part == "..") return true;
    if (slash == std::string::npos) break;
    start = slash + 1;
  }
  return false;
}

}  // namespace

std::uint32_t crc32_bytes(const std::uint8_t* data, std::size_t len) {
  std::uint32_t crc = 0xffffffffu;
  for (std::size_t i = 0; i < len; ++i) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; ++bit) {
      const std::uint32_t mask = 0u - (crc & 1u);
      crc = (crc >> 1) ^ (0xedb88320u & mask);
    }
  }
  return ~crc;
}

bool write_zip_stored(const std::vector<ZipItem>& items, const std::filesystem::path& dest,
                      std::string& error) {
  try {
    std::vector<std::uint8_t> local;
    struct Central {
      std::string name;
      std::uint32_t crc = 0;
      std::uint32_t size = 0;
      std::uint32_t offset = 0;
    };
    std::vector<Central> centrals;
    centrals.reserve(items.size());
    for (const ZipItem& item : items) {
      if (item.name.empty() || contains_parent_ref(item.name) ||
          item.name.find('\\') != std::string::npos) {
        error = "invalid zip entry name: " + item.name;
        return false;
      }
      if (item.bytes.size() > 0xffffffffu) {
        error = "zip entry exceeds 4 GiB (ZIP64 is not written): " + item.name;
        return false;
      }
      Central central;
      central.name = item.name;
      central.crc = crc32_bytes(item.bytes.data(), item.bytes.size());
      central.size = static_cast<std::uint32_t>(item.bytes.size());
      central.offset = static_cast<std::uint32_t>(local.size());
      append_u32(local, 0x04034b50u);
      append_u16(local, 20);
      append_u16(local, 0x0800);
      append_u16(local, 0);
      append_u16(local, 0);
      append_u16(local, 0);
      append_u32(local, central.crc);
      append_u32(local, central.size);
      append_u32(local, central.size);
      append_u16(local, static_cast<std::uint16_t>(item.name.size()));
      append_u16(local, 0);
      local.insert(local.end(), item.name.begin(), item.name.end());
      local.insert(local.end(), item.bytes.begin(), item.bytes.end());
      centrals.push_back(std::move(central));
    }
    const std::uint32_t cd_offset = static_cast<std::uint32_t>(local.size());
    std::vector<std::uint8_t> central_dir;
    for (const Central& central : centrals) {
      append_u32(central_dir, 0x02014b50u);
      append_u16(central_dir, 20);
      append_u16(central_dir, 20);
      append_u16(central_dir, 0x0800);
      append_u16(central_dir, 0);
      append_u16(central_dir, 0);
      append_u16(central_dir, 0);
      append_u32(central_dir, central.crc);
      append_u32(central_dir, central.size);
      append_u32(central_dir, central.size);
      append_u16(central_dir, static_cast<std::uint16_t>(central.name.size()));
      append_u16(central_dir, 0);
      append_u16(central_dir, 0);
      append_u16(central_dir, 0);
      append_u16(central_dir, 0);
      append_u32(central_dir, 0);
      append_u32(central_dir, central.offset);
      central_dir.insert(central_dir.end(), central.name.begin(), central.name.end());
    }
    const std::uint32_t cd_size = static_cast<std::uint32_t>(central_dir.size());
    std::vector<std::uint8_t> eocd;
    append_u32(eocd, 0x06054b50u);
    append_u16(eocd, 0);
    append_u16(eocd, 0);
    append_u16(eocd, static_cast<std::uint16_t>(centrals.size()));
    append_u16(eocd, static_cast<std::uint16_t>(centrals.size()));
    append_u32(eocd, cd_size);
    append_u32(eocd, cd_offset);
    append_u16(eocd, 0);
    local.insert(local.end(), central_dir.begin(), central_dir.end());
    local.insert(local.end(), eocd.begin(), eocd.end());
    write_binary(dest, local);
    return true;
  } catch (const std::exception& ex) {
    error = ex.what();
    return false;
  }
}

bool zip_directory_stored(const std::filesystem::path& directory, const std::filesystem::path& dest,
                          std::string& error) {
  std::vector<ZipItem> items;
  std::vector<std::filesystem::path> files;
  for (const auto& entry : std::filesystem::recursive_directory_iterator(directory)) {
    if (entry.is_regular_file()) files.push_back(entry.path());
  }
  std::sort(files.begin(), files.end());
  for (const auto& file : files) {
    ZipItem item;
    item.name = std::filesystem::relative(file, directory).generic_string();
    const auto bytes = read_binary(file);
    item.bytes.assign(bytes.begin(), bytes.end());
    items.push_back(std::move(item));
  }
  return write_zip_stored(items, dest, error);
}

bool unzip_stored(const std::filesystem::path& zip_file, const std::filesystem::path& dest,
                  std::string& error) {
  try {
    const auto bytes = read_binary(zip_file);
    if (bytes.size() < 22) {
      error = "zip is too small";
      return false;
    }
    const std::size_t scan =
        std::min<std::size_t>(bytes.size(), static_cast<std::size_t>(22 + 65535));
    const std::size_t min_i = bytes.size() > scan ? bytes.size() - scan : 0;
    std::size_t eocd = static_cast<std::size_t>(-1);
    for (std::size_t i = bytes.size() - 22;; --i) {
      if (read_u32(bytes.data() + i) == 0x06054b50u) {
        eocd = i;
        break;
      }
      if (i <= min_i) break;
    }
    if (eocd == std::string::npos) {
      error = "zip end of central directory not found";
      return false;
    }
    const std::uint16_t count = read_u16(bytes.data() + eocd + 10);
    const std::uint32_t cd_size = read_u32(bytes.data() + eocd + 12);
    const std::uint32_t cd_offset = read_u32(bytes.data() + eocd + 16);
    if (static_cast<std::uint64_t>(cd_offset) + cd_size > bytes.size()) {
      error = "zip central directory is out of range";
      return false;
    }
    std::filesystem::create_directories(dest);
    std::size_t cursor = cd_offset;
    for (std::uint16_t n = 0; n < count; ++n) {
      if (cursor + 46 > bytes.size() || read_u32(bytes.data() + cursor) != 0x02014b50u) {
        error = "bad zip central directory";
        return false;
      }
      const std::uint16_t method = read_u16(bytes.data() + cursor + 10);
      const std::uint32_t comp_size = read_u32(bytes.data() + cursor + 20);
      const std::uint16_t name_len = read_u16(bytes.data() + cursor + 28);
      const std::uint16_t extra_len = read_u16(bytes.data() + cursor + 30);
      const std::uint16_t comment_len = read_u16(bytes.data() + cursor + 32);
      const std::uint32_t local_off = read_u32(bytes.data() + cursor + 42);
      if (cursor + 46 + name_len > bytes.size()) {
        error = "truncated zip name";
        return false;
      }
      const std::string name(reinterpret_cast<const char*>(bytes.data() + cursor + 46), name_len);
      cursor += 46 + name_len + extra_len + comment_len;
      if (!name.empty() && name.back() == '/') continue;
      if (contains_parent_ref(name)) {
        error = "zip entry escapes the destination: " + name;
        return false;
      }
      if (method != 0 || comp_size == 0xffffffffu) {
        error = "only STORE-method zip entries are supported (" + name + ")";
        return false;
      }
      if (static_cast<std::uint64_t>(local_off) + 30 > bytes.size()) {
        error = "bad local header for " + name;
        return false;
      }
      if (read_u32(bytes.data() + local_off) != 0x04034b50u) {
        error = "missing local header for " + name;
        return false;
      }
      const std::uint16_t local_name = read_u16(bytes.data() + local_off + 26);
      const std::uint16_t local_extra = read_u16(bytes.data() + local_off + 28);
      const std::size_t data_off =
          static_cast<std::size_t>(local_off) + 30 + local_name + local_extra;
      if (data_off + comp_size > bytes.size()) {
        error = "truncated zip entry " + name;
        return false;
      }
      const auto out_path = dest / std::filesystem::path(name);
      write_binary(out_path, bytes.data() + data_off, comp_size);
    }
    return true;
  } catch (const std::exception& ex) {
    error = ex.what();
    return false;
  }
}

}  // namespace fbv
