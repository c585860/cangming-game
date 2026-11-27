cmake_minimum_required(VERSION 3.22)
project(ccb_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Locate sibling Cataclysm-Cleanwater-Bomb repository (zero edits to upstream repo!)
get_filename_component(CCB_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../Cataclysm-Cleanwater-Bomb" ABSOLUTE)
if(NOT EXISTS "${CCB_ROOT}/src/game.cpp")
    message(FATAL_ERROR "Cataclysm-Cleanwater-Bomb not found at ${CCB_ROOT}")
endif()
message(STATUS "CCB_ROOT = ${CCB_ROOT}")

# Enable ccache if available for fast incremental rebuilds
find_program(CCACHE_BIN ccache)
if(CCACHE_BIN)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_BIN}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_BIN}")
    message(STATUS "Using ccache: ${CCACHE_BIN}")
endif()

# Options matching CCB's HEADLESS + Lua + Localize build (no SDL3, no ncurses!)
set(TILES OFF CACHE BOOL "" FORCE)
set(CURSES OFF CACHE BOOL "" FORCE)
set(HEADLESS ON CACHE BOOL "" FORCE)
set(LOCALIZE ON CACHE BOOL "" FORCE)
set(CATA_ENABLE_LUA_PLATFORM ON CACHE BOOL "" FORCE)
set(CATA_BUILD_COOP_RUNTIME OFF CACHE BOOL "" FORCE)
set(CATA_REPO_ROOT "${CCB_ROOT}" CACHE PATH "" FORCE)

if(NOT MSVC)
    add_compile_options(-mcx16 -fsigned-char)
endif()

# Ensure version.h exists in CCB src (uses CCB's own version.cmake)
if(NOT EXISTS "${CCB_ROOT}/src/version.h")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -P "${CCB_ROOT}/src/version.cmake"
        WORKING_DIRECTORY "${CCB_ROOT}"
        RESULT_VARIABLE VER_RES
    )
    if(NOT VER_RES EQUAL 0)
        message(FATAL_ERROR "Failed generating CCB version.h")
    endif()
endif()

# Generate builtin_mods_generated.h into our out-of-tree binary dir
find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(BUILTIN_MODS_HEADER "${CMAKE_CURRENT_BINARY_DIR}/builtin_mods_generated.h")
execute_process(
    COMMAND ${Python3_EXECUTABLE} "${CCB_ROOT}/tools/generate_builtin_mods.py"
            --source "${CCB_ROOT}/data/mods"
            --output "${BUILTIN_MODS_HEADER}"
    WORKING_DIRECTORY "${CCB_ROOT}"
    RESULT_VARIABLE MOD_RES
)
if(NOT MOD_RES EQUAL 0)
    message(FATAL_ERROR "Failed generating builtin_mods_generated.h")
endif()

# Reuse CCB's third-party (flatbuffers, fmt, ghc, imtui headless, snmalloc, zstd) + Lua/Sol
add_subdirectory("${CCB_ROOT}/src/third-party" "${CMAKE_CURRENT_BINARY_DIR}/third-party")
add_subdirectory("${CCB_ROOT}/src/lua" "${CMAKE_CURRENT_BINARY_DIR}/lua")
add_subdirectory("${CCB_ROOT}/src/sol" "${CMAKE_CURRENT_BINARY_DIR}/sol")

# Collect all 670 core CCB sources, swapping out ONLY main.cpp & platform_headless.cpp
file(GLOB CCB_CORE_SOURCES
    "${CCB_ROOT}/src/*.cpp"
    "${CCB_ROOT}/src/cata_allocator_c.c"
)
list(REMOVE_ITEM CCB_CORE_SOURCES
    "${CCB_ROOT}/src/main.cpp"
    "${CCB_ROOT}/src/platform_headless.cpp"
    "${CCB_ROOT}/src/lua_platform_disabled.cpp"
    "${CCB_ROOT}/src/cata_allocator.cpp"
)

add_library(ccb_core OBJECT ${CCB_CORE_SOURCES})
target_include_directories(ccb_core PUBLIC
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CCB_ROOT}/src"
)
target_compile_definitions(ccb_core PUBLIC
    HEADLESS
    IMTUI
    LOCALIZE
    RELEASE
    CMAKE
    GIT_VERSION
    CATA_ENABLE_LUA_PLATFORM=1
    NO_STALE_DATA_WARN
)
target_link_libraries(ccb_core PUBLIC third-party libsol)
target_precompile_headers(ccb_core PUBLIC
    "$<$<COMPILE_LANGUAGE:CXX>:${CCB_ROOT}/pch/main-pch.hpp>"
)
if(NOT MSVC)
    target_compile_options(ccb_core PRIVATE
        -Wno-error
        -Wno-unused-parameter
        -Wno-sign-compare
        -Wno-deprecated-declarations
    )
endif()

# System & localization dependencies (static linking so ccb_bridge.dll is self-contained)
find_package(Threads REQUIRED)
find_library(ZLIB_STATIC_LIB NAMES libz.a z REQUIRED)
find_path(LIBINTL_INCLUDE_DIR libintl.h)
find_library(LIBINTL_LIB NAMES libintl.a intl)
find_library(LIBICONV_LIB NAMES libiconv.a iconv)

if(LIBINTL_INCLUDE_DIR)
    target_include_directories(ccb_core PUBLIC "${LIBINTL_INCLUDE_DIR}")
endif()

# Modular Godot bridge DLL (exports ONLY CCB_API pure-C functions!)
add_library(ccb_bridge SHARED
    bridge_state.cpp
    bridge_lifecycle.cpp
    bridge_tileset_options.cpp
    bridge_world_snapshot.cpp
    platform_color.cpp
    platform_curses.cpp
    platform_imgui.cpp
    platform_input.cpp
)
target_compile_definitions(ccb_bridge PRIVATE CCB_BRIDGE_EXPORTS)
target_include_directories(ccb_bridge PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(ccb_bridge PRIVATE
    ccb_core
    Threads::Threads
    "${ZLIB_STATIC_LIB}"
)
if(LIBINTL_LIB)
    target_link_libraries(ccb_bridge PRIVATE "${LIBINTL_LIB}")
endif()
if(LIBICONV_LIB)
    target_link_libraries(ccb_bridge PRIVATE "${LIBICONV_LIB}")
endif()

if(WIN32)
    target_link_libraries(ccb_bridge PRIVATE
        gdi32 winmm imm32 ole32 oleaut32 version ws2_32 bcrypt dbghelp
    )
endif()
if(MINGW)
    target_compile_options(ccb_bridge PRIVATE -finput-charset=UTF-8 -fexec-charset=UTF-8)
    target_link_options(ccb_bridge PRIVATE -static-libgcc -static-libstdc++ -Wl,-Bstatic -lwinpthread -Wl,-Bdynamic)
endif()

get_filename_component(CANGLING_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../bin" ABSOLUTE)
set_target_properties(ccb_bridge PROPERTIES
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CANGLING_BIN_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${CANGLING_BIN_DIR}"
)
file(WRITE "${CMAKE_BINARY_DIR}/.gdignore" "\n")
