cmake_minimum_required(VERSION 3.22)
project(ccb_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Locate Cataclysm-Cleanwater-Bomb repository (prefer local cangling-city/Cataclysm-Cleanwater-Bomb; fallback to sibling)
get_filename_component(_CCB_LOCAL "${CMAKE_CURRENT_SOURCE_DIR}/../../Cataclysm-Cleanwater-Bomb" ABSOLUTE)
get_filename_component(_CCB_SIBLING "${CMAKE_CURRENT_SOURCE_DIR}/../../../Cataclysm-Cleanwater-Bomb" ABSOLUTE)
if(EXISTS "${_CCB_LOCAL}/src/game.cpp")
    set(CCB_ROOT "${_CCB_LOCAL}")
elseif(EXISTS "${_CCB_SIBLING}/src/game.cpp")
    set(CCB_ROOT "${_CCB_SIBLING}")
else()
    message(FATAL_ERROR "Cataclysm-Cleanwater-Bomb not found at ${_CCB_LOCAL} or ${_CCB_SIBLING}")
endif()
message(STATUS "CCB_ROOT = ${CCB_ROOT}")

# Enable ccache if available for fast incremental rebuilds across upstream syncs
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

# Sync CCB src/version.h with current upstream HEAD commit (write-if-changed so mtime NEVER bumps
# unless upstream HEAD actually changed, keeping incremental builds instant while showing the exact commit!)
find_package(Git QUIET)
set(_CCB_VER_STR "")
if(GIT_EXECUTABLE)
    execute_process(
        COMMAND "${GIT_EXECUTABLE}" -C "${CCB_ROOT}" describe --tags --always --match "cdda-*"
        RESULT_VARIABLE _VER_GIT_RES
        OUTPUT_VARIABLE _VER_GIT_OUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_VER_GIT_RES EQUAL 0 AND NOT _VER_GIT_OUT STREQUAL "")
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" -C "${CCB_ROOT}" show -s --format=%cs HEAD
            OUTPUT_VARIABLE _VER_GIT_DATE
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(_VER_GIT_DATE STREQUAL "")
            string(TIMESTAMP _VER_GIT_DATE "%Y-%m-%d")
        endif()
        set(_CCB_VER_STR "${_VER_GIT_DATE}-${_VER_GIT_OUT}")
    endif()
endif()
if(_CCB_VER_STR STREQUAL "")
    if(NOT EXISTS "${CCB_ROOT}/src/version.h")
        set(_CCB_VER_STR "unknown")
    endif()
endif()
if(NOT _CCB_VER_STR STREQUAL "")
    set(_CCB_VER_CONTENT "// NOLINT(cata-header-guard)\n#define VERSION \"${_CCB_VER_STR}\"\n")
    set(_CCB_VER_OLD "")
    if(EXISTS "${CCB_ROOT}/src/version.h")
        file(READ "${CCB_ROOT}/src/version.h" _CCB_VER_OLD)
    endif()
    if(NOT _CCB_VER_CONTENT STREQUAL _CCB_VER_OLD)
        file(WRITE "${CCB_ROOT}/src/version.h" "${_CCB_VER_CONTENT}")
        message(STATUS "Updated CCB src/version.h -> ${_CCB_VER_STR}")
    endif()
endif()

# Generate builtin_mods_generated.h into out-of-tree binary dir using write-if-changed
# so its mtime NEVER bumps unless upstream mods actually changed!
find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(BUILTIN_MODS_HEADER "${CMAKE_CURRENT_BINARY_DIR}/builtin_mods_generated.h")
set(_BUILTIN_MODS_TMP "${CMAKE_CURRENT_BINARY_DIR}/builtin_mods_generated.h.tmp")
execute_process(
    COMMAND ${Python3_EXECUTABLE} "${CCB_ROOT}/tools/generate_builtin_mods.py"
            --source "${CCB_ROOT}/data/mods"
            --output "${_BUILTIN_MODS_TMP}"
    WORKING_DIRECTORY "${CCB_ROOT}"
    RESULT_VARIABLE MOD_RES
)
if(NOT MOD_RES EQUAL 0)
    message(FATAL_ERROR "Failed generating builtin_mods_generated.h")
endif()
execute_process(
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_BUILTIN_MODS_TMP}" "${BUILTIN_MODS_HEADER}"
)
file(REMOVE "${_BUILTIN_MODS_TMP}")

# Reuse CCB's third-party (flatbuffers, fmt, ghc, imtui headless, snmalloc, zstd) + Lua/Sol
add_subdirectory("${CCB_ROOT}/src/third-party" "${CMAKE_CURRENT_BINARY_DIR}/third-party")
add_subdirectory("${CCB_ROOT}/src/lua" "${CMAKE_CURRENT_BINARY_DIR}/lua")
add_subdirectory("${CCB_ROOT}/src/sol" "${CMAKE_CURRENT_BINARY_DIR}/sol")

# Collect all core CCB sources with CONFIGURE_DEPENDS so `git pull` on upstream CCB automatically
# detects newly added/removed .cpp files and Ninja depfiles strictly recompile ONLY modified files
# and translation units that include modified headers!
file(GLOB CCB_CORE_SOURCES CONFIGURE_DEPENDS
    "${CCB_ROOT}/src/*.cpp"
    "${CCB_ROOT}/src/cata_allocator_c.c"
)
list(REMOVE_ITEM CCB_CORE_SOURCES
    "${CCB_ROOT}/src/main.cpp"
    "${CCB_ROOT}/src/platform_headless.cpp"
    "${CCB_ROOT}/src/lua_platform_disabled.cpp"
    "${CCB_ROOT}/src/cata_allocator.cpp"
    "${CCB_ROOT}/src/loading_ui.cpp"
    "${CCB_ROOT}/src/vfx_emit.cpp"
    "${CCB_ROOT}/src/uilist.cpp"
    "${CCB_ROOT}/src/sounds.cpp"
    "${CCB_ROOT}/src/animation.cpp"
)

# Generate patched uilist/sounds/animation bridges out-of-tree (each script writes ONLY if changed!)
set(UILIST_BRIDGE_CPP "${CMAKE_CURRENT_BINARY_DIR}/uilist_bridge.cpp")
set(SOUNDS_BRIDGE_CPP "${CMAKE_CURRENT_BINARY_DIR}/sounds_bridge.cpp")
set(ANIMATION_BRIDGE_CPP "${CMAKE_CURRENT_BINARY_DIR}/animation_bridge.cpp")

add_custom_command(
    OUTPUT "${UILIST_BRIDGE_CPP}"
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/patch_uilist.py"
            "${CCB_ROOT}/src/uilist.cpp" "${UILIST_BRIDGE_CPP}"
    DEPENDS "${CCB_ROOT}/src/uilist.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/patch_uilist.py"
    COMMENT "Syncing uilist_bridge.cpp (only if upstream uilist.cpp or patch changed)"
)
add_custom_command(
    OUTPUT "${SOUNDS_BRIDGE_CPP}"
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/patch_sounds.py"
            "${CCB_ROOT}/src/sounds.cpp" "${SOUNDS_BRIDGE_CPP}"
    DEPENDS "${CCB_ROOT}/src/sounds.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/patch_sounds.py"
    COMMENT "Syncing sounds_bridge.cpp (only if upstream sounds.cpp or patch changed)"
)
add_custom_command(
    OUTPUT "${ANIMATION_BRIDGE_CPP}"
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/patch_animation.py"
            "${CCB_ROOT}/src/animation.cpp" "${ANIMATION_BRIDGE_CPP}"
    DEPENDS "${CCB_ROOT}/src/animation.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/patch_animation.py"
    COMMENT "Syncing animation_bridge.cpp (only if upstream animation.cpp or patch changed)"
)

# Upstream CCB compiled as an independent incremental OBJECT library (preserves all static registrations
# with zero ar overhead):
# - Stable-only STL/fmt/flatbuffers PCH prevents cascade rebuilds on upstream header edits!
# - Zero dependency on ccb_bridge headers so modifying bridge files NEVER recompiles ccb_core!
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
    "$<$<COMPILE_LANGUAGE:CXX>:${CMAKE_CURRENT_SOURCE_DIR}/bridge_stable_pch.hpp>"
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

# Modular Godot bridge DLL (exports ONLY CCB_API pure-C functions; incremental rebuild = 1-3s!)
add_library(ccb_bridge SHARED
    bridge_state.cpp
    bridge_lifecycle.cpp
    bridge_tileset_options.cpp
    bridge_world_snapshot.cpp
    bridge_render3d.cpp
    platform_color.cpp
    platform_curses.cpp
    platform_imgui.cpp
    platform_input.cpp
    platform_loading_ui.cpp
    platform_vfx_emit.cpp
    "${UILIST_BRIDGE_CPP}"
    "${SOUNDS_BRIDGE_CPP}"
    "${ANIMATION_BRIDGE_CPP}"
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
