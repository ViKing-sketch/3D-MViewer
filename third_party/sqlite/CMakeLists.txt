add_library(sqlite3_amalgamation STATIC sqlite3.c)
target_include_directories(sqlite3_amalgamation PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(sqlite3_amalgamation PUBLIC
  SQLITE_ENABLE_FTS5
  SQLITE_ENABLE_DESERIALIZE
  SQLITE_DQS=0
  SQLITE_THREADSAFE=1
  SQLITE_DEFAULT_MEMSTATUS=0
)
if(MSVC)
  target_compile_definitions(sqlite3_amalgamation PRIVATE _CRT_SECURE_NO_WARNINGS)
  target_compile_options(sqlite3_amalgamation PRIVATE /W0)
else()
  target_compile_options(sqlite3_amalgamation PRIVATE -w)
endif()
if(UNIX AND NOT APPLE)
  target_link_libraries(sqlite3_amalgamation PUBLIC ${CMAKE_DL_LIBS})
endif()
