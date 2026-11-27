#include "bridge_state.hpp"

#include "cached_options.h"
#include "cata_imgui.h"
#include "cursesdef.h"
#include "input.h"
#include "input_replay.h"
#include "ui_manager.h"

#include <chrono>
#include <stdexcept>

namespace {

std::chrono::steady_clock::time_point g_last_nonblock_publish{};

input_event convert_host_event(const ccb_bridge::HostEvent &ev) {
    input_event out;
    if (ev.kind == ccb_bridge::HostEventKind::Mouse) {
        out.type = input_event_t::mouse;
        out.mouse_pos = point(ev.cell_x, ev.cell_y);
        switch (ev.mouse_action) {
            case CCB_MOUSE_LEFT_DOWN:  out.add_input(MouseInput::LeftButtonPressed); break;
            case CCB_MOUSE_LEFT_UP:    out.add_input(MouseInput::LeftButtonReleased); break;
            case CCB_MOUSE_RIGHT_DOWN: out.add_input(MouseInput::RightButtonPressed); break;
            case CCB_MOUSE_RIGHT_UP:   out.add_input(MouseInput::RightButtonReleased); break;
            case CCB_MOUSE_WHEEL_UP:   out.add_input(MouseInput::ScrollWheelUp); break;
            case CCB_MOUSE_WHEEL_DOWN: out.add_input(MouseInput::ScrollWheelDown); break;
            default:                   out.add_input(MouseInput::Move); break;
        }
        return out;
    }

    // CCB's `keyboard_char` events represent already-translated characters ('!', '@', 'A', '|', Ctrl+A..Z=1..26, KEY_BTAB)
    // and NEVER carry `keymod_t::shift/ctrl/alt` in `out.modifiers` (matching CCB's SDL keychar & curses backends).
    // Inserting `keymod_t::shift` here caused Shift+1 ('!') to become "SHIFT-!", breaking Safe Mode ('!') and all Shift bindings!
    out.type = input_event_t::keyboard_char;
    out.text = ev.utf8_text;

    int k = ev.key_code;
    if (k == 0 && !ev.utf8_text.empty()) {
        k = static_cast<unsigned char>(ev.utf8_text[0]);
    }
    if (k != 0) {
        out.add_input(k);
    }
    return out;
}

} // namespace

void input_manager::pump_events() {
    auto &st = ccb_bridge::state();
    if (st.shutdown_requested.load(std::memory_order_acquire)) {
        throw ccb_bridge::ShutdownException();
    }
    std::vector<ccb_bridge::HostEvent> resizes;
    {
        std::lock_guard<std::mutex> lk(st.input_mtx);
        while (!st.input_queue.empty()) {
            const auto ev = st.input_queue.front();
            st.input_queue.pop_front();
            if (ev.kind == ccb_bridge::HostEventKind::Shutdown) {
                throw ccb_bridge::ShutdownException();
            }
            if (ev.kind == ccb_bridge::HostEventKind::Resize) {
                resizes.push_back(ev);
            }
        }
    }
    for (const auto &r : resizes) {
        ccb_bridge::apply_host_resize(r.cols, r.rows);
    }
    previously_pressed_key = 0;
}

input_event input_manager::get_input_event(const keyboard_mode /*preferred_keyboard_mode*/) {
    if (input_replay::is_replaying()) {
        const input_event replayed = input_replay::next_event();
        previously_pressed_key = replayed.get_first_input();
        return replayed;
    }
    if (test_mode) {
        throw std::runtime_error("input_manager::get_input_event called in test mode");
    }

    auto &st = ccb_bridge::state();

    // Publish latest frame before waiting; during rapid 0ms activity polls (Wait/Sleep/Craft/Auto-Move),
    // throttle snapshots to ~30Hz so long waits stay smooth, animated, and responsive.
    if (input_timeout == 0) {
        const auto now = std::chrono::steady_clock::now();
        if (now - g_last_nonblock_publish >= std::chrono::milliseconds(33)) {
            g_last_nonblock_publish = now;
            st.publish_frame();
        }
    } else {
        st.publish_frame();
    }

    while (true) {
        if (st.shutdown_requested.load(std::memory_order_acquire)) {
            throw ccb_bridge::ShutdownException();
        }

        ccb_bridge::HostEvent ev{};
        bool got_event = false;
        {
            std::unique_lock<std::mutex> lk(st.input_mtx);
            auto ready = [&]() {
                return !st.input_queue.empty() || st.shutdown_requested.load(std::memory_order_acquire);
            };
            if (input_timeout == 0) {
                // Non-blocking poll (0ms): critical for Wait ('|'), Sleep ('$'), Craft, Read, Auto-Move!
                got_event = ready();
            } else if (input_timeout > 0) {
                got_event = st.input_cv.wait_for(lk, std::chrono::milliseconds(input_timeout), ready);
            } else {
                // input_timeout < 0 (-1): block cleanly until user input or resize arrives
                st.input_cv.wait(lk, ready);
                got_event = true;
            }
            if (st.shutdown_requested.load(std::memory_order_acquire)) {
                throw ccb_bridge::ShutdownException();
            }
            if (got_event && !st.input_queue.empty()) {
                ev = std::move(st.input_queue.front());
                st.input_queue.pop_front();
            } else {
                got_event = false;
            }
        }

        if (!got_event) {
            previously_pressed_key = 0;
            input_event timeout_ev;
            timeout_ev.type = input_event_t::timeout;
            input_replay::on_record(timeout_ev);
            return timeout_ev;
        }

        if (ev.kind == ccb_bridge::HostEventKind::Shutdown) {
            throw ccb_bridge::ShutdownException();
        }
        if (ev.kind == ccb_bridge::HostEventKind::Resize) {
            ccb_bridge::apply_host_resize(ev.cols, ev.rows);
            if (input_timeout == 0) {
                // Don't loop indefinitely on 0ms polls after handling a resize
                previously_pressed_key = 0;
                input_event timeout_ev;
                timeout_ev.type = input_event_t::timeout;
                input_replay::on_record(timeout_ev);
                return timeout_ev;
            }
            continue;
        }

        input_event rval = convert_host_event(ev);
        if (imclient) {
            imclient->process_input(&rval);
        }
        previously_pressed_key = rval.get_first_input();
        input_replay::on_record(rval);
        return rval;
    }
}

void input_manager::set_timeout(const int delay) {
    input_timeout = delay;
}
