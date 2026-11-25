#pragma once

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace cangling {

// Automatic multi-core CPU thread pool.
// Lazily spawns worker threads sized to hardware_concurrency() - 1 (leaving one core
// for Godot's main/render loop), and distributes parallel ranges using lock-free
// atomic chunk stealing so uneven workloads balance cleanly across all cores.
class ThreadPool {
public:
    static ThreadPool &instance();

    ThreadPool(const ThreadPool &) = delete;
    ThreadPool &operator=(const ThreadPool &) = delete;

    // Ensures worker threads are spawned. Safe to call repeatedly.
    void ensure_started();

    // Stops and joins all worker threads cleanly (called on GDExtension shutdown).
    void shutdown();

    // Runs fn(chunk_begin, chunk_end) across [begin, end) using worker threads + caller.
    void parallel_for(int begin, int end, int grain, const std::function<void(int, int)> &fn);

    // Enqueues an asynchronous fire-and-forget job onto the pool.
    void enqueue(std::function<void()> task);

    int hardware_threads() const;
    int worker_count() const;
    std::uint64_t tasks_executed() const { return executed_tasks_.load(std::memory_order_relaxed); }

private:
    ThreadPool() = default;
    ~ThreadPool();

    void worker_loop();

    mutable std::mutex queue_mutex_;
    std::condition_variable wake_cv_;
    std::queue<std::function<void()>> queue_;
    std::vector<std::thread> workers_;
    bool started_ = false;
    bool stopping_ = false;
    std::atomic<std::uint64_t> executed_tasks_{0};
};

} // namespace cangling
