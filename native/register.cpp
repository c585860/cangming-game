#include "world.hpp"
#include "memory_manager.hpp"
#include "thread_pool.hpp"
#include <godot_cpp/godot.hpp>

using namespace godot;

extern "C" GDExtensionBool GDE_EXPORT cangling_init(GDExtensionInterfaceGetProcAddress address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(address, library, initialization);
    init.register_initializer([](ModuleInitializationLevel level) {
        if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
            GDREGISTER_CLASS(cangling::CanglingWorld);
        }
    });
    init.register_terminator([](ModuleInitializationLevel level) {
        if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
            cangling::MemoryManager::instance().shutdown();
            cangling::ThreadPool::instance().shutdown();
        }
    });
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
