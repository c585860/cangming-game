#include "thread_pool.hpp"

#include <algorithm>
#include <memory>

namespace cangling {

ThreadPool &ThreadPool::instance() {
    static ThreadPool pool;
    return pool;
}

ThreadPool::~ThreadPool() {
    shutdown();
}

int ThreadPool::hardware_threads() const {
    const unsigned int hw = std::thread::hardware_concurrency();
    return hw > 0 ? static_cast<int>(hw) : 2;
}

int ThreadPool::worker_count() const {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    if (started_) {
        return static_cast<int>(workers_.size());
    }
    const int hw = hardware_threads();
    return std::clamp(hw - 1, 1, 16);
}

void ThreadPool::ensure_started() {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    if (started_) {
        return;
    }
    stopping_ = false;
    const int hw = hardware_threads();
    const int count = std::clamp(hw - 1, 1, 16);
    workers_.reserve(static_cast<std::size_t>(count));
    for (int i = 0; i < count; ++i) {
        workers_.emplace_back([this]() { worker_loop(); });
    }
    started_ = true;
}

void ThreadPool::shutdown() {
    std::vector<std::thread> to_join;
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        if (!started_) {
            return;
        }
        stopping_ = true;
        to_join.swap(workers_);
        started_ = false;
    }
    wake_cv_.notify_all();
    for (std::thread &worker : to_join) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    std::lock_guard<std::mutex> lock(queue_mutex_);
    while (!queue_.empty()) {
        queue_.pop();
    }
}

void ThreadPool::enqueue(std::function<void()> task) {
    if (!task) {
        return;
    }
    ensure_started();
    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        if (stopping_) {
            return;
        }
        queue_.push(std::move(task));
    }
    wake_cv_.notify_one();
}

void ThreadPool::parallel_for(int begin, int end, int grain, const std::function<void(int, int)> &fn) {
    if (begin >= end || !fn) {
        return;
    }
    const int total = end - begin;
    const int safe_grain = std::max(1, grain);
    if (total <= safe_grain) {
        fn(begin, end);
        executed_tasks_.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    ensure_started();
    const int workers = std::max(1, worker_count());
    const int total_threads = workers + 1;
    const int target_chunks = total_threads * 4;
    const int chunk = std::max(safe_grain, (total + target_chunks - 1) / target_chunks);
    const int num_chunks = (total + chunk - 1) / chunk;
    if (num_chunks <= 1) {
        fn(begin, end);
        executed_tasks_.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    struct SharedState {
        std::atomic<int> next_index;
        std::atomic<int> active_helpers;
        std::mutex done_mutex;
        std::condition_variable done_cv;
        int end_index;
        int chunk_size;
        const std::function<void(int, int)> *callback;
    };

    auto state = std::make_shared<SharedState>();
    state->next_index.store(begin, std::memory_order_relaxed);
    state->end_index = end;
    state->chunk_size = chunk;
    state->callback = &fn;

    const int helpers = std::min(workers, num_chunks - 1);
    state->active_helpers.store(helpers, std::memory_order_relaxed);

    auto run_chunks = [state, this]() {
        while (true) {
            const int start = state->next_index.fetch_add(state->chunk_size, std::memory_order_relaxed);
            if (start >= state->end_index) {
                break;
            }
            const int stop = std::min(start + state->chunk_size, state->end_index);
            (*state->callback)(start, stop);
            executed_tasks_.fetch_add(1, std::memory_order_relaxed);
        }
    };

    {
        std::lock_guard<std::mutex> lock(queue_mutex_);
        if (stopping_) {
            state->active_helpers.store(0, std::memory_order_relaxed);
        } else {
            for (int i = 0; i < helpers; ++i) {
                queue_.push([state, run_chunks]() {
                    run_chunks();
                    if (state->active_helpers.fetch_sub(1, std::memory_order_acq_rel) == 1) {
                        std::lock_guard<std::mutex> done_lock(state->done_mutex);
                        state->done_cv.notify_one();
                    }
                });
            }
        }
    }
    if (helpers > 0) {
        wake_cv_.notify_all();
    }

    // Calling thread participates directly so no core sits idle.
    run_chunks();

    // Wait for any in-flight worker helpers to finish their current chunk.
    if (state->active_helpers.load(std::memory_order_acquire) > 0) {
        std::unique_lock<std::mutex> done_lock(state->done_mutex);
        state->done_cv.wait(done_lock, [&state]() {
            return state->active_helpers.load(std::memory_order_acquire) == 0;
        });
    }
}

void ThreadPool::worker_loop() {
    while (true) {
        std::function<void()> task;
        {
            std::unique_lock<std::mutex> lock(queue_mutex_);
            wake_cv_.wait(lock, [this]() { return stopping_ || !queue_.empty(); });
            if (stopping_ && queue_.empty()) {
                return;
            }
            task = std::move(queue_.front());
            queue_.pop();
        }
        if (task) {
            task();
        }
    }
}

} // namespace cangling
