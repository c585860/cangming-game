#include "memory_manager.hpp"

#include <algorithm>

namespace cangling {

MemoryManager &MemoryManager::instance() {
    static MemoryManager manager;
    return manager;
}

void MemoryManager::register_hook(const void *owner, std::string name,
        std::function<std::size_t()> bytes_fn,
        std::function<std::size_t(bool aggressive)> trim_fn) {
    std::lock_guard<std::mutex> lock(mutex_);
    for (Hook &hook : hooks_) {
        if (hook.owner == owner && hook.name == name) {
            hook.bytes_fn = std::move(bytes_fn);
            hook.trim_fn = std::move(trim_fn);
            return;
        }
    }
    hooks_.push_back(Hook{owner, std::move(name), std::move(bytes_fn), std::move(trim_fn)});
}

void MemoryManager::unregister_owner(const void *owner) {
    std::lock_guard<std::mutex> lock(mutex_);
    hooks_.erase(std::remove_if(hooks_.begin(), hooks_.end(),
        [owner](const Hook &h) { return h.owner == owner; }), hooks_.end());
}

void MemoryManager::set_budgets(std::size_t soft_bytes, std::size_t hard_bytes, double idle_interval_sec) {
    std::lock_guard<std::mutex> lock(mutex_);
    soft_budget_bytes_ = std::max<std::size_t>(soft_bytes, 1024u * 1024u);
    hard_budget_bytes_ = std::max(hard_bytes, soft_budget_bytes_ + 1024u * 1024u);
    idle_interval_sec_ = std::max(1.0, idle_interval_sec);
}

std::size_t MemoryManager::query_total_bytes_locked() const {
    std::size_t total = 0;
    for (const Hook &hook : hooks_) {
        if (hook.bytes_fn) {
            total += hook.bytes_fn();
        }
    }
    return total;
}

bool MemoryManager::tick(double delta_sec) {
    if (delta_sec <= 0.0) {
        return false;
    }
    bool should_trim = false;
    bool aggressive = false;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        elapsed_since_check_ += delta_sec;
        elapsed_since_trim_ += delta_sec;
        // Sample usage at most twice per second to avoid any per-frame overhead.
        if (elapsed_since_check_ < 0.5) {
            return false;
        }
        elapsed_since_check_ = 0.0;
        const std::size_t used = query_total_bytes_locked();
        if (used >= hard_budget_bytes_) {
            should_trim = true;
            aggressive = true;
        } else if (used >= soft_budget_bytes_ && elapsed_since_trim_ >= 2.0) {
            should_trim = true;
            aggressive = false;
        } else if (elapsed_since_trim_ >= idle_interval_sec_) {
            should_trim = true;
            aggressive = false;
        }
    }
    if (!should_trim) {
        return false;
    }
    const std::size_t freed = trim_now(aggressive);
    return freed > 0;
}

std::size_t MemoryManager::trim_now(bool aggressive) {
    std::vector<std::function<std::size_t(bool)>> trimmers;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        trimmers.reserve(hooks_.size());
        for (const Hook &hook : hooks_) {
            if (hook.trim_fn) {
                trimmers.push_back(hook.trim_fn);
            }
        }
    }
    std::size_t freed = 0;
    for (const auto &fn : trimmers) {
        freed += fn(aggressive);
    }
    {
        std::lock_guard<std::mutex> lock(mutex_);
        elapsed_since_trim_ = 0.0;
        last_freed_bytes_ = freed;
        if (freed > 0) {
            total_freed_bytes_ += freed;
            ++auto_trim_count_;
            script_trim_pending_ = true;
        }
    }
    return freed;
}

bool MemoryManager::consume_script_trim_signal() {
    std::lock_guard<std::mutex> lock(mutex_);
    const bool pending = script_trim_pending_;
    script_trim_pending_ = false;
    return pending;
}

MemoryManager::Stats MemoryManager::stats() const {
    std::lock_guard<std::mutex> lock(mutex_);
    Stats s;
    s.current_bytes = query_total_bytes_locked();
    s.soft_budget_bytes = soft_budget_bytes_;
    s.hard_budget_bytes = hard_budget_bytes_;
    s.total_freed_bytes = total_freed_bytes_;
    s.last_freed_bytes = last_freed_bytes_;
    s.auto_trim_count = auto_trim_count_;
    return s;
}

void MemoryManager::shutdown() {
    std::lock_guard<std::mutex> lock(mutex_);
    hooks_.clear();
    elapsed_since_check_ = 0.0;
    elapsed_since_trim_ = 0.0;
    script_trim_pending_ = false;
}

} // namespace cangling
