#include "fbv/sqlite_util.hpp"

namespace fbv {
namespace {

void check(sqlite3* db, int rc, const char* what) {
  if (rc == SQLITE_OK || rc == SQLITE_DONE || rc == SQLITE_ROW) return;
  const char* msg = db != nullptr ? sqlite3_errmsg(db) : what;
  throw SqliteError(std::string(what) + ": " + (msg != nullptr ? msg : ""));
}

}  // namespace

void Stmt::bind_null(int index) {
  check(sqlite3_db_handle(stmt_), sqlite3_bind_null(stmt_, index), "bind null");
}

void Stmt::bind_int64(int index, std::int64_t value) {
  check(sqlite3_db_handle(stmt_), sqlite3_bind_int64(stmt_, index, value), "bind int");
}

void Stmt::bind_double(int index, double value) {
  check(sqlite3_db_handle(stmt_), sqlite3_bind_double(stmt_, index, value), "bind double");
}

void Stmt::bind_text(int index, const std::string& value) {
  check(sqlite3_db_handle(stmt_),
        sqlite3_bind_text(stmt_, index, value.c_str(), static_cast<int>(value.size()),
                          SQLITE_TRANSIENT),
        "bind text");
}

bool Stmt::step_row() {
  const int rc = sqlite3_step(stmt_);
  if (rc == SQLITE_ROW) return true;
  if (rc == SQLITE_DONE) return false;
  check(sqlite3_db_handle(stmt_), rc, "step");
  return false;
}

void Stmt::step_done() {
  const int rc = sqlite3_step(stmt_);
  if (rc != SQLITE_DONE) check(sqlite3_db_handle(stmt_), rc, "step done");
}

bool Stmt::column_is_null(int index) const {
  return sqlite3_column_type(stmt_, index) == SQLITE_NULL;
}

std::int64_t Stmt::column_int64(int index) const {
  return sqlite3_column_int64(stmt_, index);
}

double Stmt::column_double(int index) const {
  return sqlite3_column_double(stmt_, index);
}

std::string Stmt::column_text(int index) const {
  const unsigned char* text = sqlite3_column_text(stmt_, index);
  if (text == nullptr) return {};
  return reinterpret_cast<const char*>(text);
}

SqliteDb::SqliteDb(const std::filesystem::path& path, bool create) {
  open(path, create);
}

void SqliteDb::open(const std::filesystem::path& path, bool create) {
  close();
  const int flags = create ? (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) : SQLITE_OPEN_READONLY;
  const auto u8 = path.u8string();
  std::string utf8;
  utf8.reserve(u8.size());
  for (auto unit : u8) utf8.push_back(static_cast<char>(unit));
  const int rc = sqlite3_open_v2(utf8.c_str(), &db_, flags, nullptr);
  if (rc != SQLITE_OK) {
    std::string msg = db_ != nullptr ? sqlite3_errmsg(db_) : "sqlite open failed";
    close();
    throw SqliteError(msg + " (" + path.string() + ")");
  }
  exec("PRAGMA foreign_keys=ON;");
}

void SqliteDb::close() {
  if (db_ != nullptr) {
    sqlite3_close(db_);
    db_ = nullptr;
  }
}

void SqliteDb::exec(const char* sql) {
  char* err = nullptr;
  const int rc = sqlite3_exec(db_, sql, nullptr, nullptr, &err);
  if (rc != SQLITE_OK) {
    std::string msg = err != nullptr ? err : sqlite3_errmsg(db_);
    sqlite3_free(err);
    throw SqliteError(msg);
  }
}

Stmt SqliteDb::prepare(const char* sql) {
  sqlite3_stmt* statement = nullptr;
  check(db_, sqlite3_prepare_v2(db_, sql, -1, &statement, nullptr), "prepare");
  return Stmt(statement);
}

}  // namespace fbv
