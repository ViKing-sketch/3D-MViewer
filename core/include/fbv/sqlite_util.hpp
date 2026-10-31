#pragma once

#include <sqlite3.h>

#include <cstdint>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <utility>

namespace fbv {

class SqliteError : public std::runtime_error {
 public:
  using std::runtime_error::runtime_error;
};

class Stmt {
 public:
  explicit Stmt(sqlite3_stmt* statement) : stmt_(statement) {}
  Stmt(const Stmt&) = delete;
  Stmt& operator=(const Stmt&) = delete;
  Stmt(Stmt&& other) noexcept : stmt_(other.stmt_) { other.stmt_ = nullptr; }
  ~Stmt() {
    if (stmt_ != nullptr) sqlite3_finalize(stmt_);
  }

  void bind_null(int index);
  void bind_int64(int index, std::int64_t value);
  void bind_double(int index, double value);
  void bind_text(int index, const std::string& value);
  bool step_row();
  void step_done();

  sqlite3_stmt* get() const { return stmt_; }
  bool column_is_null(int index) const;
  std::int64_t column_int64(int index) const;
  double column_double(int index) const;
  std::string column_text(int index) const;

 private:
  sqlite3_stmt* stmt_;
};

class SqliteDb {
 public:
  SqliteDb() = default;
  SqliteDb(const std::filesystem::path& path, bool create);
  SqliteDb(const SqliteDb&) = delete;
  SqliteDb& operator=(const SqliteDb&) = delete;
  SqliteDb(SqliteDb&& other) noexcept : db_(other.db_) { other.db_ = nullptr; }
  SqliteDb& operator=(SqliteDb&& other) noexcept {
    if (this != &other) {
      close();
      db_ = other.db_;
      other.db_ = nullptr;
    }
    return *this;
  }
  ~SqliteDb() { close(); }

  void open(const std::filesystem::path& path, bool create);
  void close();
  void exec(const char* sql);
  Stmt prepare(const char* sql);
  sqlite3* get() const { return db_; }

 private:
  sqlite3* db_ = nullptr;
};

}  // namespace fbv
