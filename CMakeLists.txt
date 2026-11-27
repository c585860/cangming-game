cmake_minimum_required(VERSION 3.22)
project(cangling LANGUAGES CXX)

set(GODOT_CPP_DIR "" CACHE PATH "godot-cpp 4.5 source directory")
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/native/profile.json" CACHE FILEPATH "Native bindings profile")
set(GODOTCPP_TARGET template_debug CACHE STRING "Godot build target")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/native/profile.json")
add_subdirectory("${GODOT_CPP_DIR}" godot-cpp)

add_library(cangling SHARED
    native/register.cpp native/world.cpp native/city.cpp native/yangzhou_city.cpp
    native/core_packs.cpp native/ccb_vanilla.cpp native/ccb_overmap.cpp native/ccb_engine_gd.cpp native/cataclysm_city.cpp native/monsters.cpp
    native/buildings.cpp native/plan.cpp native/terrain.cpp native/streets.cpp
    native/street_plots.cpp native/navigation.cpp native/interactions.cpp native/props.cpp
    native/save.cpp native/city_survey.cpp native/building_types.cpp native/items.cpp
    native/item_catalog.cpp native/character_state.cpp native/skills.cpp native/workstations.cpp
    native/shops.cpp native/crafting.cpp native/combat.cpp native/bounties.cpp native/furniture_ops.cpp
    native/thread_pool.cpp native/memory_manager.cpp native/render_bake.cpp)
file(WRITE "${CMAKE_BINARY_DIR}/.gdignore" "\n")
target_compile_features(cangling PRIVATE cxx_std_17)
target_link_libraries(cangling PRIVATE godot-cpp)
if(MINGW)
    target_compile_options(cangling PRIVATE -finput-charset=UTF-8 -fexec-charset=UTF-8)
    target_link_options(cangling PRIVATE -static -static-libgcc -static-libstdc++)
elseif(MSVC)
    target_compile_options(cangling PRIVATE /utf-8)
endif()
set_target_properties(cangling PROPERTIES PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin")
