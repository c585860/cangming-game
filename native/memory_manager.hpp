#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace cangling {

// Automatic memory management & reclamation controller.
// Subsystems register byte-accounting and trim callbacks; MemoryManager monitors
// tracked usage against soft/hard budgets and periodic idle windows to reclaim
// cold sector caches and temporary scratch buffers automatically.
class MemoryManager {
public:
    struct Hook {
        const void *owner = nullptr;
        std::string name;
        std::function<std::size_t()> bytes_fn;
        std::function<std::size_t(bool aggressive)> trim_fn;
    };

    struct Stats {
        std::size_t current_bytes = 0;
        std::size_t soft_budget_bytes = 0;
        std::size_t hard_budget_bytes = 0;
        std::uint64_t total_freed_bytes = 0;
        std::uint64_t last_freed_bytes = 0;
        std::uint64_t auto_trim_count = 0;
    };

    static MemoryManager &instance();

    MemoryManager(const MemoryManager &) = delete;
    MemoryManager &operator=(const MemoryManager &) = delete;

    void register_hook(const void *owner, std::string name,
        std::function<std::size_t()> bytes_fn,
        std::function<std::size_t(bool aggressive)> trim_fn);

    void unregister_owner(const void *owner);

    void set_budgets(std::size_t soft_bytes, std::size_t hard_bytes, double idle_interval_sec = 10.0);

    // Called periodically from the game loop; returns true if an automatic trim ran.
    bool tick(double delta_sec);

    // Runs an immediate trim pass across all registered subsystems; returns bytes freed.
    std::size_t trim_now(bool aggressive = false);

    // Returns true once after an automatic trim so GDScript can release cold texture pages too.
    bool consume_script_trim_signal();

    Stats stats() const;
    void shutdown();

private:
    MemoryManager() = default;

    std::size_t query_total_bytes_locked() const;

    mutable std::mutex mutex_;
    std::vector<Hook> hooks_;
    std::size_t soft_budget_bytes_ = 16u * 1024u * 1024u; // 16 MB soft target
    std::size_t hard_budget_bytes_ = 32u * 1024u * 1024u; // 32 MB immediate trim threshold
    double idle_interval_sec_ = 10.0;
    double elapsed_since_check_ = 0.0;
    double elapsed_since_trim_ = 0.0;
    std::uint64_t total_freed_bytes_ = 0;
    std::uint64_t last_freed_bytes_ = 0;
    std::uint64_t auto_trim_count_ = 0;
    bool script_trim_pending_ = false;
};

} // namespace cangling
