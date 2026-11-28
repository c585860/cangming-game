#include "ccb_audio_synth.hpp"
#include "ccb_bridge/ccb_bridge_api.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace cangling {

namespace {

constexpr int DEFAULT_SAMPLE_RATE = 44100;
constexpr int LOW_SAMPLE_RATE = 22050;
constexpr float TWO_PI = 6.28318530717958647692f;
thread_local float g_synth_sr = 44100.0f;

struct FastRng {
    uint64_t state;
    explicit FastRng(uint64_t seed) : state(seed ? seed : 0x9E3779B97F4A7C15ULL) {}
    uint32_t next_u32() {
        uint64_t x = state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        state = x;
        return static_cast<uint32_t>((x * 0x2545F4914F6CDD1DULL) >> 32);
    }
    float next_sym() {
        return static_cast<float>(static_cast<int32_t>(next_u32())) * (1.0f / 2147483648.0f);
    }
    float next_01() {
        return static_cast<float>(next_u32() >> 8) * (1.0f / 16777216.0f);
    }
};

struct OnePoleLP {
    float z = 0.0f;
    float process(float x, float cutoff_hz, float sr = 0.0f) {
        const float eff_sr = (sr > 0.0f) ? sr : g_synth_sr;
        const float c = std::clamp(cutoff_hz, 20.0f, eff_sr * 0.42f);
        const float a = std::clamp(TWO_PI * c / eff_sr, 0.0005f, 0.98f);
        z += a * (x - z);
        return z;
    }
};

struct OnePoleHP {
    float z = 0.0f;
    float prev_x = 0.0f;
    float process(float x, float cutoff_hz, float sr = 0.0f) {
        const float eff_sr = (sr > 0.0f) ? sr : g_synth_sr;
        const float rc = 1.0f / (TWO_PI * std::clamp(cutoff_hz, 10.0f, eff_sr * 0.42f));
        const float dt = 1.0f / eff_sr;
        const float a = rc / (rc + dt);
        z = a * (z + x - prev_x);
        prev_x = x;
        return z;
    }
};

// State-Variable Bandpass Filter (authentic non-ringing broadband formant shaping; zero metallic sine-bell artifacts!)
struct SvBandpass {
    float low = 0.0f;
    float band = 0.0f;
    float process(float x, float freq_hz, float q, float sr = 0.0f) {
        const float eff_sr = (sr > 0.0f) ? sr : g_synth_sr;
        const float max_f = eff_sr * 0.36f;
        const float f = std::clamp(2.0f * std::sin(3.14159265f * std::clamp(freq_hz, 30.0f, max_f) / eff_sr), 0.005f, 1.45f);
        const float damp = std::clamp(1.0f / std::max(0.45f, q), 0.08f, 1.85f);
        low += f * band;
        const float high = x - low - damp * band;
        band += f * high;
        return band;
    }
};

struct Tap {
    int delay;
    float gain_l;
    float gain_r;
};

// Physically distinct acoustic room/environment reflection engine:
// space_mode 0 = outdoor open air (rolling horizon diffraction, zero boxy room boom)
// space_mode 1 = indoor room/shelter (fierce tight concrete/wood slapback + boxy mid-bass pressure)
// space_mode 2 = underground basement/tunnel/lab (heavy long cavernous concrete reverb tail)
void apply_space_acoustics(std::vector<float> &buf_l, std::vector<float> &buf_r,
                           int space_mode, bool distant, float wet_scale, FastRng &rng, int sr) {
    const int n = static_cast<int>(buf_l.size());
    const float srf = static_cast<float>(sr);

    // Distant air-absorption filter first (high frequencies attenuate steeply over distance)
    if (distant) {
        OnePoleLP air_l, air_r;
        OnePoleHP sub_hp_l, sub_hp_r;
        for (int i = 0; i < n; ++i) {
            const float u = static_cast<float>(i) / static_cast<float>(std::max(1, n));
            const float cut = 1850.0f * std::exp(-u * 2.2f) + 380.0f;
            buf_l[static_cast<size_t>(i)] = sub_hp_l.process(air_l.process(buf_l[static_cast<size_t>(i)], cut, srf), 55.0f, srf) * 0.88f;
            buf_r[static_cast<size_t>(i)] = sub_hp_r.process(air_r.process(buf_r[static_cast<size_t>(i)], cut, srf), 55.0f, srf) * 0.88f;
        }
    }

    std::vector<float> wet_l(static_cast<size_t>(n), 0.0f);
    std::vector<float> wet_r(static_cast<size_t>(n), 0.0f);
    std::vector<Tap> taps;

    if (space_mode == 1) {
        // INDOOR ENCLOSED ROOM: tight immediate wall slapback + dense flutter reflections
        static constexpr int ms_taps[] = { 6, 10, 15, 21, 28, 36, 46, 58, 72, 90, 114, 145 };
        for (int i = 0; i < 12; ++i) {
            const float jitter = 0.91f + 0.18f * rng.next_01();
            const int d = static_cast<int>(static_cast<float>(ms_taps[i]) * jitter * 0.001f * srf);
            const float g = wet_scale * 0.56f * std::pow(0.75f, static_cast<float>(i));
            const float lr = (i & 1) ? 0.65f : 1.22f;
            const float rr = (i & 1) ? 1.22f : 0.65f;
            taps.push_back({ d, g * lr, g * rr });
        }
    } else if (space_mode == 2) {
        // UNDERGROUND CONCRETE TUNNEL / CAVERN: deep long resonant chamber reflections
        static constexpr int ms_taps[] = { 14, 29, 48, 72, 105, 148, 202, 268, 345, 440, 560, 700 };
        for (int i = 0; i < 12; ++i) {
            const float jitter = 0.90f + 0.20f * rng.next_01();
            const int d = static_cast<int>(static_cast<float>(ms_taps[i]) * jitter * 0.001f * srf);
            const float g = wet_scale * 0.62f * std::pow(0.81f, static_cast<float>(i));
            const float lr = (i & 1) ? 0.62f : 1.25f;
            const float rr = (i & 1) ? 1.25f : 0.62f;
            taps.push_back({ d, g * lr, g * rr });
        }
    } else {
        // OUTDOOR OPEN AIR: sparse distant ground/building/horizon diffraction echoes
        static constexpr int ms_taps[] = { 34, 72, 128, 205, 305, 430 };
        for (int i = 0; i < 6; ++i) {
            const float jitter = 0.88f + 0.24f * rng.next_01();
            const int d = static_cast<int>(static_cast<float>(ms_taps[i]) * jitter * 0.001f * srf);
            const float g = wet_scale * 0.26f * std::pow(0.68f, static_cast<float>(i));
            const float lr = (i & 1) ? 0.68f : 1.18f;
            const float rr = (i & 1) ? 1.18f : 0.68f;
            taps.push_back({ d, g * lr, g * rr });
        }
    }

    for (const Tap &tp : taps) {
        for (int i = tp.delay; i < n; ++i) {
            wet_l[static_cast<size_t>(i)] += buf_l[static_cast<size_t>(i - tp.delay)] * tp.gain_l;
            wet_r[static_cast<size_t>(i)] += buf_r[static_cast<size_t>(i - tp.delay)] * tp.gain_r;
        }
    }

    OnePoleLP lp_l, lp_r;
    SvBandpass box_l, box_r;
    const float base_cut = (space_mode == 1) ? 3100.0f : ((space_mode == 2) ? 1950.0f : 1550.0f);
    for (int i = 0; i < n; ++i) {
        const float u = static_cast<float>(i) / static_cast<float>(std::max(1, n));
        const float cut = base_cut * std::exp(-u * (space_mode == 2 ? 1.7f : 2.6f)) + 210.0f;
        float wl = lp_l.process(wet_l[static_cast<size_t>(i)], cut, srf);
        float wr = lp_r.process(wet_r[static_cast<size_t>(i)], cut, srf);
        if (space_mode == 1) {
            // Enclosed room boxy mid-low acoustic pressure boost
            wl += box_l.process(wet_l[static_cast<size_t>(i)], 420.0f, 1.3f, srf) * 0.42f;
            wr += box_r.process(wet_r[static_cast<size_t>(i)], 435.0f, 1.3f, srf) * 0.42f;
        } else if (space_mode == 2) {
            // Underground concrete chamber boom
            wl += box_l.process(wet_l[static_cast<size_t>(i)], 260.0f, 1.8f, srf) * 0.55f;
            wr += box_r.process(wet_r[static_cast<size_t>(i)], 272.0f, 1.8f, srf) * 0.55f;
        }
        buf_l[static_cast<size_t>(i)] += wl;
        buf_r[static_cast<size_t>(i)] += wr;
    }
}

std::vector<uint8_t> pack_pcm16(std::vector<float> &buf_l, std::vector<float> &buf_r, float target_peak, int sr, bool stereo) {
    const size_t n = buf_l.size();
    const size_t fade_in = std::min<size_t>(n, std::max<size_t>(8, static_cast<size_t>(sr / 3000)));
    const size_t fade_out = std::min<size_t>(n, std::max<size_t>(64, static_cast<size_t>(sr / 92)));
    for (size_t i = 0; i < fade_in; ++i) {
        const float g = static_cast<float>(i) / static_cast<float>(std::max<size_t>(1, fade_in));
        buf_l[i] *= g;
        buf_r[i] *= g;
    }
    for (size_t i = 0; i < fade_out; ++i) {
        const float g = static_cast<float>(i) / static_cast<float>(std::max<size_t>(1, fade_out));
        buf_l[n - 1 - i] *= g;
        buf_r[n - 1 - i] *= g;
    }

    float peak = 0.001f;
    for (size_t i = 0; i < n; ++i) {
        buf_l[i] = std::tanh(buf_l[i] * 1.18f);
        buf_r[i] = std::tanh(buf_r[i] * 1.18f);
        peak = std::max(peak, std::max(std::abs(buf_l[i]), std::abs(buf_r[i])));
    }
    const float norm = std::min(1.85f, target_peak / peak);

    if (!stereo) {
        std::vector<uint8_t> out(n * 2u, 0u);
        for (size_t i = 0; i < n; ++i) {
            const float m = 0.5f * (buf_l[i] + buf_r[i]);
            const int16_t sm = static_cast<int16_t>(std::clamp(m * norm, -0.98f, 0.98f) * 32767.0f);
            const size_t off = i * 2u;
            out[off + 0] = static_cast<uint8_t>(sm & 0xFF);
            out[off + 1] = static_cast<uint8_t>((sm >> 8) & 0xFF);
        }
        return out;
    }

    std::vector<uint8_t> out(n * 4u, 0u);
    for (size_t i = 0; i < n; ++i) {
        const int16_t sl = static_cast<int16_t>(std::clamp(buf_l[i] * norm, -0.98f, 0.98f) * 32767.0f);
        const int16_t sr_v = static_cast<int16_t>(std::clamp(buf_r[i] * norm, -0.98f, 0.98f) * 32767.0f);
        const size_t off = i * 4u;
        out[off + 0] = static_cast<uint8_t>(sl & 0xFF);
        out[off + 1] = static_cast<uint8_t>((sl >> 8) & 0xFF);
        out[off + 2] = static_cast<uint8_t>(sr_v & 0xFF);
        out[off + 3] = static_cast<uint8_t>((sr_v >> 8) & 0xFF);
    }
    return out;
}

void synth_gunshot(int subtype, int variant, int space_mode, bool distant, float tail_scale,
                   std::vector<float> &L, std::vector<float> &R, float &peak_out, int SAMPLE_RATE) {
    FastRng rng(0x71A2F5D1ULL ^ (static_cast<uint64_t>(subtype) << 16) ^ (static_cast<uint64_t>(variant) * 0x9E3779B9ULL) ^ (static_cast<uint64_t>(space_mode) << 3));
    const float p_var = 0.955f + 0.090f * rng.next_01();
    const float ts = std::clamp(tail_scale, 0.40f, 1.15f);
    const float space_dur_extra = (space_mode == 2) ? 0.36f : ((space_mode == 1) ? 0.08f : 0.0f);

    // Energy / Primitive weapons
    if (subtype == CCB_GUN_LASER || subtype == CCB_GUN_PLASMA || subtype == CCB_GUN_LIGHTNING || subtype == CCB_GUN_BOW || subtype == CCB_GUN_FLAMETHROWER) {
        const float dur_s = ((subtype == CCB_GUN_FLAMETHROWER) ? 0.55f : (subtype == CCB_GUN_BOW ? 0.26f : 0.42f)) + space_dur_extra * 0.5f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        OnePoleLP lp_l, lp_r;
        OnePoleHP hp_l;
        SvBandpass bp_l;
        float ph = 0.0f;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            const float nr = rng.next_sym();
            float sl = 0.0f, sr = 0.0f;
            if (subtype == CCB_GUN_LASER) {
                const float f = (2400.0f * std::exp(-t * 24.0f) + 280.0f) * p_var;
                ph += TWO_PI * f / SAMPLE_RATE;
                const float snap = std::exp(-t * 160.0f) * hp_l.process(nl, 2800.0f) * 1.45f;
                const float beam = std::tanh(std::sin(ph) * 1.8f) * std::exp(-t * 18.0f) * 0.52f;
                const float sizzle = bp_l.process(nl, 4200.0f, 1.6f) * std::exp(-t * 11.0f) * 0.55f;
                sl = snap + beam + sizzle;
                sr = snap + beam + lp_r.process(nr, 4400.0f) * std::exp(-t * 11.0f) * 0.35f;
            } else if (subtype == CCB_GUN_PLASMA) {
                const float f = (320.0f * std::exp(-t * 12.0f) + 64.0f) * p_var;
                ph += TWO_PI * f / SAMPLE_RATE;
                const float thump = std::sin(ph) * std::exp(-t * 13.0f) * 0.90f;
                const float crack = std::tanh(nl * 2.4f) * std::exp(-t * 52.0f) * 0.90f;
                const float hiss = hp_l.process(nl, 1800.0f) * std::exp(-t * 7.2f) * 0.58f;
                sl = thump + crack + hiss;
                sr = thump + std::tanh(nr * 2.4f) * std::exp(-t * 52.0f) * 0.90f + hiss * 0.9f;
            } else if (subtype == CCB_GUN_LIGHTNING) {
                const float arc = (rng.next_01() < 0.045f ? 1.8f : 0.45f) * nl * std::exp(-t * 12.0f);
                const float thunder = lp_l.process(nl, 250.0f * std::exp(-t * 2.5f) + 60.0f) * std::exp(-t * 4.5f) * 1.6f;
                sl = arc + thunder;
                sr = arc * 0.85f + lp_r.process(nr, 240.0f * std::exp(-t * 2.5f) + 60.0f) * std::exp(-t * 4.5f) * 1.6f;
            } else if (subtype == CCB_GUN_BOW) {
                const float f = (135.0f + 18.0f * std::exp(-t * 28.0f)) * p_var;
                ph += TWO_PI * f / SAMPLE_RATE;
                const float twang = std::sin(ph) * std::exp(-t * 22.0f) * 0.55f;
                const float snap = bp_l.process(nl, 1250.0f, 1.4f) * std::exp(-t * 42.0f) * 0.75f;
                const float whoosh = lp_l.process(nl, 1300.0f) * std::sin(std::min(1.0f, t / 0.14f) * 3.14159f) * std::exp(-t * 11.0f) * 0.48f;
                sl = twang + snap + whoosh;
                sr = sl * 0.95f;
            } else {
                const float env = std::min(1.0f, t / 0.045f) * std::exp(-t * 3.4f);
                sl = lp_l.process(nl, 900.0f + 350.0f * std::sin(t * 28.0f)) * 1.35f * env;
                sr = lp_r.process(nr, 860.0f + 350.0f * std::cos(t * 26.0f)) * 1.35f * env;
            }
            L[static_cast<size_t>(i)] = sl;
            R[static_cast<size_t>(i)] = sr;
        }
        apply_space_acoustics(L, R, space_mode, distant, 0.52f * ts, rng, SAMPLE_RATE);
        peak_out = (subtype == CCB_GUN_BOW) ? 0.62f : 0.88f;
        return;
    }

    // Distinct Physical Acoustic Profiles per Weapon Class (ZERO tonal/bell sine waves in high frequencies!)
    float dur_s = 0.72f * ts + 0.16f + space_dur_extra;
    float crack_gain = 1.40f;
    float crack_decay = 115.0f;
    float crack_freq = 2800.0f;
    float crack_q = 0.75f;
    float punch_cut = 160.0f;
    float punch_gain = 1.25f;
    float punch_decay = 24.0f;
    float bark_freq = 680.0f;
    float bark_gain = 1.15f;
    float bark_decay = 15.0f;
    float bolt_delay = 0.025f;
    float bolt_gain = 0.35f;
    float bolt_freq = 2400.0f;
    float tail_gain = 0.46f * ts;
    float tail_decay = 3.8f / ts;
    float rev_wet = 0.70f * ts;
    bool pump_action = false;
    peak_out = 0.92f;

    switch (subtype) {
        case CCB_GUN_PISTOL:
            // Crisp, dry, snappy 9mm/.45 POP-CRACK — focused mid-high snap, short tail
            dur_s = 0.46f * ts + 0.14f + space_dur_extra;
            crack_gain = 1.55f; crack_decay = 165.0f; crack_freq = 3200.0f; crack_q = 0.85f;
            punch_cut = 210.0f; punch_gain = 0.95f; punch_decay = 38.0f;
            bark_freq = 1050.0f; bark_gain = 0.92f; bark_decay = 26.0f;
            bolt_delay = 0.019f; bolt_gain = 0.38f; bolt_freq = 3100.0f;
            tail_gain = 0.30f * ts; tail_decay = 5.8f / ts;
            peak_out = 0.86f;
            break;
        case CCB_GUN_SMG:
            // Tight, dry, punchy staccato TAK-TAK-TAK — built for crisp high-RPM full-auto bursts
            dur_s = 0.40f * ts + 0.12f + space_dur_extra;
            crack_gain = 1.42f; crack_decay = 175.0f; crack_freq = 2650.0f; crack_q = 0.95f;
            punch_cut = 190.0f; punch_gain = 0.92f; punch_decay = 42.0f;
            bark_freq = 1280.0f; bark_gain = 0.98f; bark_decay = 30.0f;
            bolt_delay = 0.015f; bolt_gain = 0.48f; bolt_freq = 2500.0f;
            tail_gain = 0.25f * ts; tail_decay = 6.8f / ts;
            peak_out = 0.85f;
            break;
        case CCB_GUN_RIFLE:
            // Authoritative 5.56/7.62 supersonic WHIP-CRACK + forceful chest bark + rolling open-air tail
            dur_s = 0.78f * ts + 0.18f + space_dur_extra;
            crack_gain = 1.85f; crack_decay = 115.0f; crack_freq = 3600.0f; crack_q = 0.65f;
            punch_cut = 145.0f; punch_gain = 1.42f; punch_decay = 21.0f;
            bark_freq = 640.0f; bark_gain = 1.25f; bark_decay = 13.5f;
            bolt_delay = 0.024f; bolt_gain = 0.36f; bolt_freq = 2250.0f;
            tail_gain = 0.56f * ts; tail_decay = 3.2f / ts;
            peak_out = 0.95f;
            break;
        case CCB_GUN_SHOTGUN:
            // Huge wide-band cavernous 12ga KABOOM + deep sub-thump + dry mechanical pump-rack!
            dur_s = 0.96f * ts + 0.22f + space_dur_extra;
            crack_gain = 1.55f; crack_decay = 64.0f; crack_freq = 1450.0f; crack_q = 0.55f;
            punch_cut = 95.0f; punch_gain = 2.05f; punch_decay = 12.5f;
            bark_freq = 390.0f; bark_gain = 1.55f; bark_decay = 8.2f;
            bolt_delay = 0.175f; bolt_gain = 0.44f; bolt_freq = 1750.0f;
            tail_gain = 0.72f * ts; tail_decay = 2.4f / ts;
            pump_action = true;
            peak_out = 0.97f;
            break;
        case CCB_GUN_HEAVY:
        case CCB_GUN_LAUNCHER:
            // Seismic .50 BMG / Cannon CRACK-THUNDER — violent overpressure & deep valley roll
            dur_s = 1.22f * ts + 0.26f + space_dur_extra;
            crack_gain = 2.05f; crack_decay = 58.0f; crack_freq = 2100.0f; crack_q = 0.52f;
            punch_cut = 78.0f; punch_gain = 2.45f; punch_decay = 9.2f;
            bark_freq = 320.0f; bark_gain = 1.75f; bark_decay = 6.2f;
            bolt_delay = 0.040f; bolt_gain = 0.45f; bolt_freq = 1550.0f;
            tail_gain = 0.88f * ts; tail_decay = 1.9f / ts;
            peak_out = 0.98f;
            break;
        case CCB_GUN_SUPPRESSED:
            // Authentic suppressed THWIP-CLACK: baffled gas hiss + dry steel bolt snap (zero bell!)
            dur_s = 0.24f + space_dur_extra * 0.4f;
            crack_gain = 0.55f; crack_decay = 190.0f; crack_freq = 2400.0f; crack_q = 0.85f;
            punch_cut = 185.0f; punch_gain = 0.52f; punch_decay = 48.0f;
            bark_freq = 920.0f; bark_gain = 0.52f; bark_decay = 36.0f;
            bolt_delay = 0.013f; bolt_gain = 0.82f; bolt_freq = 2850.0f;
            tail_gain = 0.08f; tail_decay = 15.0f;
            rev_wet = 0.22f;
            peak_out = 0.62f;
            break;
        default:
            break;
    }

    const int n = static_cast<int>(dur_s * SAMPLE_RATE);
    L.assign(static_cast<size_t>(n), 0.0f);
    R.assign(static_cast<size_t>(n), 0.0f);

    SvBandpass bp_crack_l, bp_crack_r;
    SvBandpass bp_bark_l, bp_bark_r;
    SvBandpass bp_bolt;
    OnePoleLP lp_punch, lp_tail_l, lp_tail_r;
    OnePoleHP hp_air_l, hp_air_r;

    for (int i = 0; i < n; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
        const float nl = rng.next_sym();
        const float nr = 0.62f * nl + 0.78f * rng.next_sym();

        // 1. Asymmetric ballistic N-wave shockwave + broadband muzzle crack
        const float nwave = (t < 0.0014f) ? (1.0f - t / 0.0014f) * 1.55f
                          : ((t < 0.0038f) ? -0.58f * (1.0f - (t - 0.0014f) / 0.0024f) : 0.0f);
        const float crack_env = std::exp(-t * crack_decay);
        const float cr_l = (bp_crack_l.process(nl, crack_freq * p_var, crack_q) * 1.55f + hp_air_l.process(nl, 4200.0f) * 0.65f + nwave) * crack_env * crack_gain;
        const float cr_r = (bp_crack_r.process(nr, crack_freq * p_var, crack_q) * 1.55f + hp_air_r.process(nr, 4200.0f) * 0.65f + nwave) * crack_env * crack_gain;

        // 2. Non-tonal broadband sub-bass pressure chest-thump (zero sine boing!)
        const float p_cut = (punch_cut * (0.45f + 0.85f * std::exp(-t * 28.0f))) * p_var;
        const float punch = lp_punch.process(nl * 2.2f + nwave * 0.7f, p_cut) * std::exp(-t * punch_decay) * punch_gain * 1.75f;

        // 3. Propellant combustion mid-bark (gives rifle vs pistol vs shotgun unmistakable timber!)
        const float b_freq = bark_freq * (0.55f + 0.55f * std::exp(-t * 18.0f)) * p_var;
        const float bark_env = std::exp(-t * bark_decay);
        const float bk_l = bp_bark_l.process(nl, b_freq, 0.85f) * bark_env * bark_gain * 1.35f;
        const float bk_r = bp_bark_r.process(nr, b_freq, 0.85f) * bark_env * bark_gain * 1.35f;

        // 4. Dry mechanical steel bolt-carrier / slide action click (100% filtered noise impulse — ZERO sine bell!)
        float bolt = 0.0f;
        if (t >= bolt_delay && t < bolt_delay + 0.026f) {
            const float bt = t - bolt_delay;
            const float benv = std::exp(-bt * 240.0f);
            bolt = bp_bolt.process(nl, bolt_freq * p_var, 2.2f) * benv * bolt_gain * 1.65f;
        }
        if (pump_action && t >= bolt_delay + 0.075f && t < bolt_delay + 0.110f) {
            const float bt2 = t - (bolt_delay + 0.075f);
            bolt += bp_bolt.process(nl, bolt_freq * 1.22f * p_var, 2.0f) * std::exp(-bt2 * 210.0f) * bolt_gain * 1.45f;
        }

        // 5. Rolling atmospheric diffraction tail (space-aware darkening!)
        const float t_cut = ((space_mode == 1) ? 2400.0f : 1550.0f) * std::exp(-t * 3.0f) + 180.0f;
        const float t_env = std::min(1.0f, t / 0.015f) * std::exp(-t * tail_decay);
        const float tl = lp_tail_l.process(nl, t_cut) * t_env * tail_gain;
        const float tr = lp_tail_r.process(nr, t_cut) * t_env * tail_gain;

        L[static_cast<size_t>(i)] = cr_l + punch + bk_l + bolt + tl;
        R[static_cast<size_t>(i)] = cr_r + punch + bk_r + bolt + tr;
    }

    apply_space_acoustics(L, R, space_mode, distant, rev_wet, rng, SAMPLE_RATE);
}

void synth_explosion(int subtype, int variant, int space_mode, bool distant,
                     std::vector<float> &L, std::vector<float> &R, float &peak_out, int SAMPLE_RATE) {
    FastRng rng(0xE10510EULL ^ (static_cast<uint64_t>(subtype) << 12) ^ (static_cast<uint64_t>(variant) * 0x517CC1B7ULL) ^ (static_cast<uint64_t>(space_mode) << 4));
    const float p_var = 0.94f + 0.12f * rng.next_01();

    float dur_s = 1.65f + (space_mode == 2 ? 0.45f : 0.0f);
    float sub_gain = 2.05f;
    float sub_decay = 2.6f;
    float roar_gain = 1.45f;
    float roar_decay = 2.1f;
    float crack_gain = 1.90f;
    int debris_cnt = 26;
    peak_out = 0.98f;

    if (subtype == CCB_EXPL_SMALL) {
        dur_s = 1.05f; sub_gain = 1.45f; sub_decay = 4.2f; roar_gain = 1.10f; roar_decay = 3.4f; debris_cnt = 14; peak_out = 0.90f;
    } else if (subtype == CCB_EXPL_HUGE) {
        dur_s = 2.15f + (space_mode == 2 ? 0.35f : 0.0f); sub_gain = 2.55f; sub_decay = 1.75f; roar_gain = 1.80f; roar_decay = 1.45f; crack_gain = 2.25f; debris_cnt = 40; peak_out = 0.99f;
    } else if (subtype == CCB_EXPL_FLASHBANG) {
        dur_s = 1.20f; sub_gain = 1.15f; sub_decay = 5.5f; roar_gain = 0.70f; roar_decay = 4.5f; crack_gain = 2.40f; debris_cnt = 8; peak_out = 0.95f;
    } else if (subtype == CCB_EXPL_EMP) {
        dur_s = 1.10f; sub_gain = 1.50f; sub_decay = 3.6f; roar_gain = 0.85f; roar_decay = 3.2f; crack_gain = 1.20f; debris_cnt = 6; peak_out = 0.92f;
    }

    const int n = static_cast<int>(dur_s * SAMPLE_RATE);
    L.assign(static_cast<size_t>(n), 0.0f);
    R.assign(static_cast<size_t>(n), 0.0f);

    OnePoleHP hp_l, hp_r;
    OnePoleLP lp_sub_l, lp_sub_r;
    OnePoleLP lp_roar_l, lp_roar_r;
    float sub_ph = 0.0f;
    float emp_ph = 0.0f;

    for (int i = 0; i < n; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
        const float nl = rng.next_sym();
        const float nr = 0.45f * nl + 0.89f * rng.next_sym();

        const float blast_front = (t < 0.0035f) ? (1.0f - t / 0.0035f) * 1.85f : 0.0f;
        const float crack_env = std::exp(-t * (subtype == CCB_EXPL_FLASHBANG ? 75.0f : 44.0f));
        const float cr_l = (hp_l.process(nl, 950.0f) * 1.3f + blast_front) * crack_env * crack_gain;
        const float cr_r = (hp_r.process(nr, 950.0f) * 1.3f + blast_front) * crack_env * crack_gain;

        const float sf = (24.0f + 54.0f * std::exp(-t * 9.5f)) * p_var;
        sub_ph += TWO_PI * sf / SAMPLE_RATE;
        const float sub_env = std::min(1.0f, t / 0.004f) * std::exp(-t * sub_decay);
        const float sub_osc = std::sin(sub_ph) * sub_env * sub_gain * 0.65f;
        const float sub_nl = lp_sub_l.process(nl, 92.0f * std::exp(-t * 1.1f) + 32.0f) * sub_env * sub_gain * 1.80f;
        const float sub_nr = lp_sub_r.process(nr, 90.0f * std::exp(-t * 1.1f) + 32.0f) * sub_env * sub_gain * 1.80f;

        const float billow = 0.68f + 0.32f * std::sin(t * 24.0f + 1.4f * std::sin(t * 7.5f));
        const float roar_env = std::min(1.0f, t / 0.025f) * std::exp(-t * roar_decay) * billow;
        const float rcut = (680.0f * std::exp(-t * 1.8f) + 125.0f) * p_var;
        const float ro_l = lp_roar_l.process(nl, rcut) * roar_env * roar_gain * 1.45f;
        const float ro_r = lp_roar_r.process(nr, rcut) * roar_env * roar_gain * 1.45f;

        float extra = 0.0f;
        if (subtype == CCB_EXPL_EMP) {
            const float ef = 540.0f * std::exp(-t * 5.0f) + 42.0f;
            emp_ph += TWO_PI * ef / SAMPLE_RATE;
            extra = std::sin(emp_ph) * std::exp(-t * 4.2f) * 0.78f;
        }

        L[static_cast<size_t>(i)] = cr_l + sub_osc + sub_nl + ro_l + extra;
        R[static_cast<size_t>(i)] = cr_r + sub_osc + sub_nr + ro_r + extra;
    }

    // Dry gritty rubble & shrapnel debris impacts (pure filtered noise bursts, ZERO bell ringing!)
    for (int d = 0; d < debris_cnt; ++d) {
        const float delay_s = 0.08f + std::pow(rng.next_01(), 1.45f) * (dur_s - 0.22f);
        const int start = static_cast<int>(delay_s * SAMPLE_RATE);
        const float pan = rng.next_sym();
        const float gl = std::sqrt(0.5f * (1.0f - pan));
        const float gr = std::sqrt(0.5f * (1.0f + pan));
        const float amp = (0.14f + 0.22f * rng.next_01()) * std::exp(-delay_s * 1.15f);
        const int dlen = std::min(n - start, static_cast<int>(0.022f * SAMPLE_RATE));
        SvBandpass dbp;
        const float df = 800.0f + 2600.0f * rng.next_01();
        for (int k = 0; k < dlen; ++k) {
            const float kt = static_cast<float>(k) / static_cast<float>(SAMPLE_RATE);
            const float s = dbp.process(rng.next_sym(), df, 1.3f) * std::exp(-kt * 210.0f) * amp * 1.4f;
            L[static_cast<size_t>(start + k)] += s * gl;
            R[static_cast<size_t>(start + k)] += s * gr;
        }
    }

    apply_space_acoustics(L, R, space_mode, distant, 0.85f, rng, SAMPLE_RATE);
}

void synth_misc_sfx(int kind, int subtype, int variant, int space_mode, bool distant,
                    std::vector<float> &L, std::vector<float> &R, float &peak_out, int SAMPLE_RATE) {
    FastRng rng(0x5F01A2ULL ^ (static_cast<uint64_t>(kind) << 16) ^ (static_cast<uint64_t>(subtype) << 8) ^ static_cast<uint64_t>(variant) ^ (static_cast<uint64_t>(space_mode) << 3));
    const float p_var = 0.92f + 0.16f * rng.next_01();

    if (kind == CCB_SFX_VARIANT && subtype == CCB_VAR_SHELL_CASING) {
        // Ultra-short dry brass shell micro-ticks on concrete/floor (ZERO bell/wind-chime ringing!)
        const int n = static_cast<int>(0.26f * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        const float pan = 0.28f + 0.40f * rng.next_01();
        const float gl = std::sqrt(0.5f * (1.0f - pan));
        const float gr = std::sqrt(0.5f * (1.0f + pan));
        static constexpr float bounce_t[3] = { 0.0f, 0.082f, 0.142f };
        static constexpr float bounce_g[3] = { 1.0f, 0.52f, 0.26f };
        const float surface_scale = (space_mode == 0) ? 0.42f : 1.0f; // Soft dirt/grass outdoors vs hard concrete indoors!
        for (int b = 0; b < 3; ++b) {
            const int st = static_cast<int>((bounce_t[b] + 0.014f * rng.next_01()) * SAMPLE_RATE);
            const int len = std::min(n - st, static_cast<int>(0.018f * SAMPLE_RATE));
            SvBandpass bp1, bp2;
            const float f1 = (5400.0f + 900.0f * rng.next_01()) * p_var;
            const float f2 = (8600.0f + 1200.0f * rng.next_01()) * p_var;
            for (int k = 0; k < len; ++k) {
                const float t = static_cast<float>(k) / static_cast<float>(SAMPLE_RATE);
                // Heavily damped 6ms brass tick (NOT a 60ms ringing bell!)
                const float env = std::exp(-t * 340.0f) * bounce_g[b] * surface_scale;
                const float n0 = rng.next_sym();
                const float s = (bp1.process(n0, f1, 3.2f) * 0.65f + bp2.process(n0, f2, 2.8f) * 0.55f) * env;
                L[static_cast<size_t>(st + k)] += s * gl;
                R[static_cast<size_t>(st + k)] += s * gr;
            }
        }
        peak_out = (space_mode == 0) ? 0.11f : 0.19f;
        return;
    }

    if (kind == CCB_SFX_PROJECTILE_HIT) {
        // 100% Photorealistic Ballistic Impacts — ZERO bell/chime sine tones!
        const float dur_s = (subtype == CCB_HIT_METAL) ? 0.24f : 0.19f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        OnePoleLP lp_thud, lp_body;
        SvBandpass bp_slap, bp_crunch, bp_clank;
        const bool do_zip = (subtype == CCB_HIT_METAL && (variant == 1));
        float zip_ph = 0.0f;

        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            const float nr = 0.70f * nl + 0.71f * rng.next_sym();
            float sl = 0.0f, sr = 0.0f;

            if (subtype == CCB_HIT_METAL) {
                // Violent steel armor smack + very short heavily-damped plate clank (decay 22ms, NOT a bell!)
                const float smack = bp_slap.process(nl, 3100.0f * p_var, 0.85f) * std::exp(-t * 190.0f) * 1.95f;
                const float clank = bp_clank.process(nl, 860.0f * p_var, 3.4f) * std::exp(-t * 88.0f) * 1.15f;
                const float thud = lp_thud.process(nl, 210.0f) * std::exp(-t * 54.0f) * 1.35f;
                float ricochet_zip = 0.0f;
                if (do_zip && t > 0.006f && t < 0.085f) {
                    const float zt = t - 0.006f;
                    const float zf = (3100.0f * std::exp(-zt * 28.0f) + 680.0f) * p_var;
                    zip_ph += TWO_PI * zf / SAMPLE_RATE;
                    ricochet_zip = std::sin(zip_ph) * std::min(1.0f, zt / 0.008f) * std::exp(-zt * 48.0f) * 0.24f;
                }
                sl = smack + clank + thud + ricochet_zip;
                sr = smack * 0.94f + clank + thud + ricochet_zip * 0.85f;
            } else if (subtype == CCB_HIT_WALL) {
                // Dry concrete/masonry chip crack + heavy wall thud + gritty dust scatter
                const float crack = bp_slap.process(nl, 2100.0f * p_var, 0.8f) * std::exp(-t * 145.0f) * 1.75f;
                const float thud = lp_thud.process(nl, 175.0f) * std::exp(-t * 44.0f) * 1.85f;
                const float grit = bp_crunch.process(nr, 3600.0f, 1.1f) * std::exp(-t * 36.0f) * 0.55f;
                sl = crack + thud + grit * 0.7f;
                sr = crack * 0.92f + thud + grit;
            } else {
                // Authentic ballistic flesh impact: sharp 7ms wet skin slap + deep dull muffled tissue thud + brief wet crunch
                const float slap = bp_slap.process(nl, 1650.0f * p_var, 0.75f) * std::exp(-t * 155.0f) * 1.55f;
                const float thud = lp_thud.process(nl * 1.8f, 145.0f * p_var) * std::exp(-t * 42.0f) * 2.15f;
                const float wet_env = std::min(1.0f, t / 0.006f) * std::exp(-t * 58.0f);
                const float wet = bp_crunch.process(nr, (1100.0f - 450.0f * std::min(1.0f, t * 18.0f)) * p_var, 1.1f) * wet_env * 0.95f;
                sl = slap + thud + wet;
                sr = slap * 0.92f + thud + lp_body.process(nr, 950.0f) * wet_env * 0.65f;
            }
            L[static_cast<size_t>(i)] = sl;
            R[static_cast<size_t>(i)] = sr;
        }
        apply_space_acoustics(L, R, space_mode, distant, 0.35f, rng, SAMPLE_RATE);
        peak_out = 0.66f;
        return;
    }

    if (kind == CCB_SFX_MELEE) {
        const float dur_s = (subtype == CCB_MELEE_SWING) ? 0.16f : 0.22f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        OnePoleLP lp_l;
        SvBandpass bp1;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            float s = 0.0f;
            if (subtype == CCB_MELEE_SWING) {
                const float env = std::sin(std::min(1.0f, t / dur_s) * 3.14159f);
                s = bp1.process(nl, (440.0f + 780.0f * env) * p_var, 1.0f) * env * 0.95f;
            } else if (subtype == CCB_MELEE_HIT_METAL) {
                s = (bp1.process(nl, 1150.0f * p_var, 3.0f) * std::exp(-t * 72.0f) * 1.4f
                   + lp_l.process(nl, 240.0f) * std::exp(-t * 48.0f) * 1.3f);
            } else {
                s = (lp_l.process(nl, 165.0f * p_var) * std::exp(-t * 36.0f) * 1.9f
                   + bp1.process(nl, 980.0f * p_var, 0.9f) * std::exp(-t * 85.0f) * 1.2f);
            }
            L[static_cast<size_t>(i)] = s;
            R[static_cast<size_t>(i)] = s;
        }
        apply_space_acoustics(L, R, space_mode, distant, 0.30f, rng, SAMPLE_RATE);
        peak_out = (subtype == CCB_MELEE_SWING) ? 0.42f : 0.70f;
        return;
    }

    if (kind == CCB_SFX_FOOTSTEP) {
        // 8-Material Physical Acoustic Footstep Synthesizer (0=grass, 1=wood, 2=metal, 3=glass, 4=water, 5=stone, 6=dirt, 7=snow)
        const float dur_s = (subtype == 4) ? 0.19f : ((subtype == 7) ? 0.145f : ((subtype == 3) ? 0.135f : 0.105f));
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        OnePoleLP lp_l, lp_r;
        OnePoleHP hp_l;
        SvBandpass bp1, bp2;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            const float nr = 0.65f * nl + 0.76f * rng.next_sym();
            float sl = 0.0f, sr = 0.0f;
            switch (subtype) {
                case 0: { // Grass / foliage: soft brushed swish + muffled heel thump
                    const float env = std::min(1.0f, t / 0.018f) * std::exp(-t * 30.0f);
                    const float swish = bp1.process(nl, 2400.0f * p_var, 0.8f) * env * 0.72f;
                    const float heel = lp_l.process(nl, 180.0f) * std::exp(-t * 48.0f) * 0.55f;
                    sl = swish + heel;
                    sr = bp2.process(nr, 2550.0f * p_var, 0.8f) * env * 0.68f + heel;
                    break;
                }
                case 1: { // Wood floor: warm hollow board thud + subtle timber resonance
                    const float thud = lp_l.process(nl, 240.0f * p_var) * std::exp(-t * 44.0f) * 1.45f;
                    const float body = bp1.process(nl, 480.0f * p_var, 2.1f) * std::exp(-t * 58.0f) * 0.92f;
                    const float tap = bp2.process(nr, 1650.0f * p_var, 1.4f) * std::exp(-t * 140.0f) * 0.35f;
                    sl = thud + body + tap;
                    sr = thud * 0.95f + body * 1.05f + tap;
                    break;
                }
                case 2: { // Metal grating/deck: damped solid metallic boot impact (ZERO bell ring!)
                    const float thump = lp_l.process(nl, 290.0f * p_var) * std::exp(-t * 52.0f) * 1.25f;
                    const float clank = bp1.process(nl, 1420.0f * p_var, 2.8f) * std::exp(-t * 95.0f) * 1.05f;
                    const float plate = bp2.process(nr, 2850.0f * p_var, 2.4f) * std::exp(-t * 135.0f) * 0.65f;
                    sl = thump + clank + plate;
                    sr = thump + clank * 0.92f + plate * 1.08f;
                    break;
                }
                case 3: { // Broken glass / window shards: crisp staccato micro-crackle
                    const float base = lp_l.process(nl, 320.0f) * std::exp(-t * 60.0f) * 0.65f;
                    const float gr1 = bp1.process(nl, 4800.0f * p_var, 1.9f) * std::exp(-t * 42.0f) * (0.4f + 0.6f * std::max(0.0f, std::sin(t * 260.0f)));
                    const float gr2 = hp_l.process(nr, 5600.0f) * std::exp(-t * 55.0f) * 0.55f;
                    sl = base + gr1 + gr2;
                    sr = base + gr1 * 0.85f + gr2 * 1.15f;
                    break;
                }
                case 4: { // Water puddle / shallow water: realistic wet splash + bubbly squelch!
                    const float sp_env = std::min(1.0f, t / 0.012f) * std::exp(-t * 17.0f);
                    const float sweep_f = (1900.0f - 1100.0f * std::min(1.0f, t * 7.0f)) * p_var;
                    const float splash_l = bp1.process(nl, sweep_f, 1.05f) * sp_env * 1.25f;
                    const float splash_r = bp2.process(nr, sweep_f * 1.08f, 1.05f) * sp_env * 1.22f;
                    const float spray = hp_l.process(nl, 3400.0f) * std::exp(-t * 24.0f) * 0.62f;
                    const float low = lp_l.process(nl, 280.0f) * std::exp(-t * 32.0f) * 0.65f;
                    sl = splash_l + spray + low;
                    sr = splash_r + spray * 0.92f + low;
                    break;
                }
                case 5: { // Concrete / stone / sidewalk: crisp solid heel-toe grit tap
                    const float heel = lp_l.process(nl, 340.0f * p_var) * std::exp(-t * 68.0f) * 1.35f;
                    const float grit = bp1.process(nl, 2250.0f * p_var, 1.15f) * std::exp(-t * 115.0f) * 0.88f;
                    const float toe = (t > 0.026f) ? bp2.process(nr, 1850.0f * p_var, 1.2f) * std::exp(-(t - 0.026f) * 130.0f) * 0.58f : 0.0f;
                    sl = heel + grit + toe;
                    sr = heel + grit * 0.94f + toe * 1.06f;
                    break;
                }
                case 7: { // Snow: unmistakable compressed dry-snow crunch!
                    const float c_env = std::min(1.0f, t / 0.022f) * std::exp(-t * 21.0f);
                    const float crunch_l = bp1.process(nl, (1350.0f + 950.0f * std::exp(-t * 18.0f)) * p_var, 0.95f) * c_env * 1.15f;
                    const float crunch_r = bp2.process(nr, (1500.0f + 800.0f * std::exp(-t * 20.0f)) * p_var, 0.95f) * c_env * 1.10f;
                    const float ice = hp_l.process(nl, 3800.0f) * c_env * 0.55f;
                    const float pad = lp_l.process(nl, 220.0f) * std::exp(-t * 34.0f) * 0.72f;
                    sl = crunch_l + ice + pad;
                    sr = crunch_r + ice * 0.90f + pad;
                    break;
                }
                default: { // 6 = Dirt / gravel / soil: earthy crunch + loose pebble scatter
                    const float env = std::min(1.0f, t / 0.012f) * std::exp(-t * 36.0f);
                    const float body = lp_l.process(nl, 380.0f * p_var) * std::exp(-t * 52.0f) * 1.05f;
                    const float gravel_l = bp1.process(nl, 1750.0f * p_var, 0.9f) * env * 0.95f;
                    const float gravel_r = bp2.process(nr, 2100.0f * p_var, 0.95f) * env * 0.88f;
                    sl = body + gravel_l;
                    sr = body + gravel_r;
                    break;
                }
            }
            L[static_cast<size_t>(i)] = sl;
            R[static_cast<size_t>(i)] = sr;
        }
        if (space_mode >= 1) {
            apply_space_acoustics(L, R, space_mode, false, space_mode == 2 ? 0.36f : 0.22f, rng, SAMPLE_RATE);
        }
        peak_out = (subtype == 4 || subtype == 7) ? 0.34f : 0.30f;
        return;
    }

    if (subtype == CCB_VAR_THUNDER) {
        // Authentic delayed rolling thunderstorm rumble (deep sub-pressure wave + cascading sky crackle)
        const float dur_s = distant ? 3.8f : 2.9f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        OnePoleLP lp_sub_l, lp_sub_r, lp_mid_l, lp_mid_r;
        SvBandpass bp_crack;
        const float roll_freq1 = 1.4f + rng.next_01() * 1.1f;
        const float roll_freq2 = 3.1f + rng.next_01() * 1.8f;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            const float nr = 0.45f * nl + 0.89f * rng.next_sym();
            const float atk = std::min(1.0f, t / (distant ? 0.28f : 0.06f));
            const float decay = std::exp(-t * (distant ? 0.85f : 1.15f));
            const float rumble_mod = 0.62f + 0.38f * std::sin(TWO_PI * roll_freq1 * t) * std::cos(TWO_PI * roll_freq2 * t + 0.9f);
            const float cut_sub = (distant ? 115.0f : 185.0f) * (0.45f + 0.55f * std::exp(-t * 0.9f));
            const float sub_l = lp_sub_l.process(nl, cut_sub) * atk * decay * rumble_mod * 2.6f;
            const float sub_r = lp_sub_r.process(nr, cut_sub * 0.96f) * atk * decay * rumble_mod * 2.6f;
            const float cut_mid = (distant ? 320.0f : 680.0f) * std::exp(-t * 1.2f) + 95.0f;
            const float mid_l = lp_mid_l.process(nl, cut_mid) * atk * std::exp(-t * 1.45f) * 1.15f;
            const float mid_r = lp_mid_r.process(nr, cut_mid) * atk * std::exp(-t * 1.45f) * 1.15f;
            const float crack = (!distant && t < 0.35f) ? bp_crack.process(nl, 1250.0f * p_var, 0.7f) * std::exp(-t * 14.0f) * 0.95f : 0.0f;
            L[static_cast<size_t>(i)] = sub_l + mid_l + crack;
            R[static_cast<size_t>(i)] = sub_r + mid_r + crack * 0.85f;
        }
        peak_out = distant ? 0.62f : 0.86f;
        return;
    }

    if (subtype == CCB_VAR_DRIP) {
        // Resonant underground cavern water droplet (tiny rising bubble pitch + damp tunnel echo)
        const float dur_s = 0.52f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        float phase = 0.0f;
        const float f0 = (1180.0f + rng.next_01() * 520.0f) * p_var;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float f = f0 * (1.0f + 1.45f * std::min(1.0f, t * 28.0f));
            phase += TWO_PI * f / static_cast<float>(SAMPLE_RATE);
            const float env = std::min(1.0f, t / 0.0025f) * std::exp(-t * 48.0f);
            const float s = std::sin(phase) * env * 0.85f;
            L[static_cast<size_t>(i)] = s;
            R[static_cast<size_t>(i)] = s;
        }
        apply_space_acoustics(L, R, 2, false, 0.65f, rng, SAMPLE_RATE);
        peak_out = 0.32f;
        return;
    }

    if (subtype == CCB_VAR_GLASS_BREAK) {
        // Realistic shattering window glass: crisp broadband crack + cascading shard tinkles
        const float dur_s = 0.48f;
        const int n = static_cast<int>(dur_s * SAMPLE_RATE);
        L.assign(static_cast<size_t>(n), 0.0f);
        R.assign(static_cast<size_t>(n), 0.0f);
        SvBandpass bp1, bp2, bp3;
        OnePoleHP hp1;
        for (int i = 0; i < n; ++i) {
            const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
            const float nl = rng.next_sym();
            const float nr = rng.next_sym();
            const float crack = hp1.process(nl, 2800.0f) * std::exp(-t * 36.0f) * 1.4f;
            const float sh1 = bp1.process(nl, 4400.0f * p_var, 2.6f) * std::exp(-t * 14.0f) * (0.4f + 0.6f * std::max(0.0f, std::sin(t * 175.0f)));
            const float sh2 = bp2.process(nr, 6800.0f * p_var, 2.8f) * std::exp(-t * 11.0f) * (0.35f + 0.65f * std::max(0.0f, std::cos(t * 230.0f)));
            const float fall = (t > 0.09f) ? bp3.process(nl, 5300.0f, 2.2f) * std::exp(-(t - 0.09f) * 16.0f) * 0.72f : 0.0f;
            L[static_cast<size_t>(i)] = crack + sh1 + fall;
            R[static_cast<size_t>(i)] = crack * 0.92f + sh2 + fall * 0.85f;
        }
        apply_space_acoustics(L, R, space_mode, distant, 0.38f, rng, SAMPLE_RATE);
        peak_out = 0.72f;
        return;
    }

    // Variant sounds: dry reload mechanical mag-lock, wood door, heavy smash
    const float dur_s = (subtype == CCB_VAR_SMASH) ? 0.42f : 0.24f;
    const int n = static_cast<int>(dur_s * SAMPLE_RATE);
    L.assign(static_cast<size_t>(n), 0.0f);
    R.assign(static_cast<size_t>(n), 0.0f);
    OnePoleLP lp_l;
    SvBandpass bp_l;
    for (int i = 0; i < n; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
        const float nl = rng.next_sym();
        float s = 0.0f;
        if (subtype == CCB_VAR_RELOAD) {
            const float c1 = bp_l.process(nl, 2100.0f * p_var, 2.2f) * std::exp(-t * 240.0f);
            const float c2 = (t > 0.088f) ? bp_l.process(nl, 2950.0f * p_var, 2.4f) * std::exp(-(t - 0.088f) * 210.0f) : 0.0f;
            s = c1 * 1.1f + c2 * 1.35f;
        } else if (subtype == CCB_VAR_DOOR) {
            s = (lp_l.process(nl, 280.0f) * 1.3f + bp_l.process(nl, 850.0f * p_var, 1.2f) * 0.7f) * std::exp(-t * 32.0f);
        } else {
            const float thump = lp_l.process(nl, 145.0f) * std::exp(-t * 18.0f) * 1.8f;
            const float crunch = bp_l.process(nl, 1450.0f * std::exp(-t * 4.0f) + 320.0f, 0.8f) * std::exp(-t * 10.0f) * 1.35f;
            s = thump + crunch;
        }
        L[static_cast<size_t>(i)] = s;
        R[static_cast<size_t>(i)] = s;
    }
    if (subtype == CCB_VAR_SMASH) {
        apply_space_acoustics(L, R, space_mode, distant, 0.45f, rng, SAMPLE_RATE);
    }
    peak_out = (subtype == CCB_VAR_SMASH) ? 0.76f : 0.48f;
}

} // namespace

SynthAudioResult synthesize_ccb_combat_audio(
    int kind,
    int subtype,
    int variant,
    int space_mode,
    bool distant,
    float tail_scale)
{
    int sr = DEFAULT_SAMPLE_RATE;
    bool stereo = true;
    if (kind == CCB_SFX_FOOTSTEP ||
        (kind == CCB_SFX_VARIANT && (subtype == CCB_VAR_DOOR || subtype == CCB_VAR_RELOAD || subtype == CCB_VAR_DRIP))) {
        sr = LOW_SAMPLE_RATE;
        stereo = false;
    } else if (distant || kind == CCB_SFX_MELEE ||
               (kind == CCB_SFX_VARIANT && (subtype == CCB_VAR_THUNDER || subtype == CCB_VAR_SMASH))) {
        sr = LOW_SAMPLE_RATE;
        stereo = true;
    }

    g_synth_sr = static_cast<float>(sr);
    std::vector<float> L, R;
    float target_peak = 0.90f;

    if (kind == CCB_SFX_GUNSHOT) {
        synth_gunshot(subtype, variant, space_mode, distant, tail_scale, L, R, target_peak, sr);
    } else if (kind == CCB_SFX_EXPLOSION) {
        synth_explosion(subtype, variant, space_mode, distant, L, R, target_peak, sr);
    } else {
        synth_misc_sfx(kind, subtype, variant, space_mode, distant, L, R, target_peak, sr);
    }

    if (L.empty()) {
        L.assign(256, 0.0f);
        R.assign(256, 0.0f);
    }
    SynthAudioResult res;
    res.pcm = pack_pcm16(L, R, target_peak, sr, stereo);
    res.sample_rate = sr;
    res.stereo = stereo;
    return res;
}

std::vector<uint8_t> synthesize_ccb_combat_pcm(
    int kind,
    int subtype,
    int variant,
    int space_mode,
    bool distant,
    float tail_scale)
{
    return synthesize_ccb_combat_audio(kind, subtype, variant, space_mode, distant, tail_scale).pcm;
}

// Seamless crossfaded ambient loop synthesizer (22.05 kHz 16-bit PCM — 50-75% lower RAM, zero clicks at loop seam!)
SynthAudioResult synthesize_ccb_ambience_loop_audio(int layer_id) {
    constexpr int SAMPLE_RATE = LOW_SAMPLE_RATE;
    const bool stereo = (layer_id != 6); // Underground low-frequency cavern tone (<200 Hz) needs mono only
    g_synth_sr = static_cast<float>(SAMPLE_RATE);

    const float loop_s = (layer_id == 5) ? 6.0f : 4.0f;
    const float xfade_s = 0.45f;
    const int n_loop = static_cast<int>(loop_s * SAMPLE_RATE);
    const int n_xf = static_cast<int>(xfade_s * SAMPLE_RATE);
    const int n_tot = n_loop + n_xf;

    FastRng rng(0xA3B1E4C5ULL ^ (static_cast<uint64_t>(layer_id + 1) * 0x9E3779B97F4A7C15ULL));
    std::vector<float> raw_l(static_cast<size_t>(n_tot), 0.0f);
    std::vector<float> raw_r(static_cast<size_t>(n_tot), 0.0f);

    OnePoleLP lp_l1, lp_r1, lp_l2, lp_r2;
    OnePoleHP hp_l1, hp_r1;
    SvBandpass bp_l1, bp_r1, bp_l2, bp_r2;
    float target_peak = 0.45f;

    // Pre-schedule sparse organic bird chirp / fire pop / cricket events
    struct MiniEvt { int start; int len; float f0; float f1; float pan; float amp; };
    std::vector<MiniEvt> evts;
    if (layer_id == 5) { // Sparse natural distant forest birds (3 gentle calls over 6s)
        for (int k = 0; k < 4; ++k) {
            const int st = static_cast<int>((0.5f + rng.next_01() * (loop_s - 1.1f)) * SAMPLE_RATE);
            const float f0 = 2600.0f + rng.next_01() * 1400.0f;
            const float f1 = f0 * (0.78f + rng.next_01() * 0.42f);
            evts.push_back({ st, static_cast<int>((0.09f + rng.next_01() * 0.08f) * SAMPLE_RATE), f0, f1, rng.next_sym() * 0.75f, 0.35f + rng.next_01() * 0.25f });
            if (rng.next_01() > 0.4f) {
                evts.push_back({ st + static_cast<int>(0.16f * SAMPLE_RATE), static_cast<int>(0.09f * SAMPLE_RATE), f1 * 1.05f, f0 * 0.92f, rng.next_sym() * 0.75f, 0.28f });
            }
        }
    } else if (layer_id == 7) { // Fire wood crackles & ember pops
        for (int k = 0; k < 28; ++k) {
            const int st = static_cast<int>(rng.next_01() * (loop_s - 0.05f) * SAMPLE_RATE);
            evts.push_back({ st, static_cast<int>((0.008f + rng.next_01() * 0.018f) * SAMPLE_RATE),
                             1800.0f + rng.next_01() * 3400.0f, 0.0f, rng.next_sym() * 0.55f, 0.45f + rng.next_01() * 0.55f });
        }
    }

    for (int i = 0; i < n_tot; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(SAMPLE_RATE);
        const float nl = rng.next_sym();
        const float nr = 0.35f * nl + 0.93f * rng.next_sym();
        float sl = 0.0f, sr = 0.0f;

        switch (layer_id) {
            case 0: { // AMB_WIND_OPEN: deep natural air swell + distant gusting howl
                const float gust = 0.65f + 0.35f * std::sin(TWO_PI * 0.25f * t) * std::cos(TWO_PI * 0.50f * t + 0.7f);
                const float f_l = 190.0f + 130.0f * (0.5f + 0.5f * std::sin(TWO_PI * 0.25f * t + 0.4f));
                const float f_r = 210.0f + 125.0f * (0.5f + 0.5f * std::cos(TWO_PI * 0.25f * t + 1.2f));
                sl = (lp_l1.process(nl, 145.0f) * 1.15f + bp_l1.process(nl, f_l, 1.35f) * 0.65f) * gust;
                sr = (lp_r1.process(nr, 145.0f) * 1.15f + bp_r1.process(nr, f_r, 1.35f) * 0.65f) * gust;
                target_peak = 0.48f;
                break;
            }
            case 1: { // AMB_WIND_FOREST: organic rustling canopy leaves
                const float sway = 0.58f + 0.42f * std::sin(TWO_PI * 0.50f * t + 0.3f) * std::sin(TWO_PI * 0.25f * t + 1.1f);
                sl = (bp_l1.process(nl, 950.0f + 350.0f * sway, 0.75f) * 0.85f + bp_l2.process(nl, 2800.0f, 0.85f) * 0.42f) * sway;
                sr = (bp_r1.process(nr, 1020.0f + 320.0f * sway, 0.75f) * 0.85f + bp_r2.process(nr, 2950.0f, 0.85f) * 0.42f) * sway;
                target_peak = 0.40f;
                break;
            }
            case 2: { // AMB_RAIN_OUTDOOR: realistic broadband outdoor rain sheet + bright drop patter
                const float sheet_l = bp_l1.process(nl, 1850.0f, 0.55f) * 0.88f + hp_l1.process(nl, 4200.0f) * 0.48f;
                const float sheet_r = bp_r1.process(nr, 1920.0f, 0.55f) * 0.88f + hp_r1.process(nr, 4200.0f) * 0.48f;
                const float drop_l = (rng.next_01() > 0.9965f) ? (rng.next_sym() * 2.4f) : 0.0f;
                const float drop_r = (rng.next_01() > 0.9965f) ? (rng.next_sym() * 2.4f) : 0.0f;
                sl = sheet_l + bp_l2.process(drop_l, 3400.0f, 1.4f) * 0.75f + lp_l1.process(nl, 320.0f) * 0.38f;
                sr = sheet_r + bp_r2.process(drop_r, 3600.0f, 1.4f) * 0.75f + lp_r1.process(nr, 320.0f) * 0.38f;
                target_peak = 0.52f;
                break;
            }
            case 3: { // AMB_RAIN_INDOOR: cozy muffled low-pass rain drumming on shelter roof/windows
                const float roof_l = lp_l1.process(nl, 560.0f) * 1.15f + bp_l1.process(nl, 340.0f, 0.9f) * 0.55f;
                const float roof_r = lp_r1.process(nr, 540.0f) * 1.15f + bp_r1.process(nr, 360.0f, 0.9f) * 0.55f;
                const float pat_l = (rng.next_01() > 0.997f) ? (rng.next_sym() * 1.6f) : 0.0f;
                const float pat_r = (rng.next_01() > 0.997f) ? (rng.next_sym() * 1.6f) : 0.0f;
                sl = roof_l + lp_l2.process(pat_l, 820.0f) * 0.55f;
                sr = roof_r + lp_r2.process(pat_r, 820.0f) * 0.55f;
                target_peak = 0.42f;
                break;
            }
            case 4: { // AMB_NIGHT_CRICKETS: delicate distant nocturnal insect chorus
                const float pulse1 = std::max(0.0f, std::sin(TWO_PI * 1.75f * t)) * (0.5f + 0.5f * std::sin(TWO_PI * 26.0f * t));
                const float pulse2 = std::max(0.0f, std::sin(TWO_PI * 1.25f * t + 2.1f)) * (0.5f + 0.5f * std::sin(TWO_PI * 22.0f * t));
                const float c1 = std::sin(TWO_PI * 4180.0f * t) * pulse1 * 0.34f;
                const float c2 = std::sin(TWO_PI * 4520.0f * t) * pulse2 * 0.28f;
                const float air_l = lp_l1.process(nl, 190.0f) * 0.22f;
                const float air_r = lp_r1.process(nr, 190.0f) * 0.22f;
                sl = air_l + c1 * 0.85f + c2 * 0.40f;
                sr = air_r + c1 * 0.40f + c2 * 0.85f;
                target_peak = 0.24f;
                break;
            }
            case 5: { // AMB_DAY_BIRDS: very gentle forest air + sparse distant bird calls
                sl = lp_l1.process(nl, 240.0f) * 0.16f;
                sr = lp_r1.process(nr, 240.0f) * 0.16f;
                target_peak = 0.26f;
                break;
            }
            case 6: { // AMB_UNDERGROUND: ominous deep cavernous low rumble + damp dark room tone
                const float drone = 0.72f + 0.28f * std::sin(TWO_PI * 0.25f * t);
                sl = (lp_l1.process(nl, 88.0f) * 1.45f + bp_l1.process(nl, 142.0f, 2.2f) * 0.35f) * drone;
                sr = (lp_r1.process(nr, 84.0f) * 1.45f + bp_r1.process(nr, 156.0f, 2.2f) * 0.35f) * drone;
                target_peak = 0.38f;
                break;
            }
            case 7: { // AMB_FIRE_CRACKLE: warm low hearth flame roar (pops overlaid below)
                const float lick = 0.65f + 0.35f * std::sin(TWO_PI * 2.25f * t + 0.5f) * std::cos(TWO_PI * 3.75f * t);
                sl = lp_l1.process(nl, 260.0f) * 1.15f * lick + bp_l1.process(nl, 620.0f, 0.9f) * 0.45f * lick;
                sr = lp_r1.process(nr, 260.0f) * 1.15f * lick + bp_r1.process(nr, 660.0f, 0.9f) * 0.45f * lick;
                target_peak = 0.48f;
                break;
            }
            default:
                break;
        }
        raw_l[static_cast<size_t>(i)] = sl;
        raw_r[static_cast<size_t>(i)] = sr;
    }

    // Stamp sparse bird calls / fire wood pops cleanly into buffer
    for (const auto &ev : evts) {
        SvBandpass bp_pop;
        float ph = 0.0f;
        for (int j = 0; j < ev.len && (ev.start + j) < n_tot; ++j) {
            const float u = static_cast<float>(j) / static_cast<float>(std::max(1, ev.len));
            float s = 0.0f;
            if (layer_id == 5) {
                const float freq = ev.f0 + (ev.f1 - ev.f0) * u + 120.0f * std::sin(u * 18.0f);
                ph += TWO_PI * freq / static_cast<float>(SAMPLE_RATE);
                const float env = std::sin(u * 3.14159265f);
                s = std::sin(ph) * env * env * ev.amp * 0.42f;
            } else {
                const float env = std::exp(-u * 6.5f);
                s = bp_pop.process(rng.next_sym(), ev.f0, 1.8f) * env * ev.amp * 1.25f;
            }
            const float gl = std::clamp(1.0f - ev.pan * 0.5f, 0.25f, 1.0f);
            const float gr = std::clamp(1.0f + ev.pan * 0.5f, 0.25f, 1.0f);
            raw_l[static_cast<size_t>(ev.start + j)] += s * gl;
            raw_r[static_cast<size_t>(ev.start + j)] += s * gr;
        }
    }

    // Equal-power seamless loop crossfade between tail [n_loop .. n_loop+n_xf) and head [0 .. n_xf)
    std::vector<float> out_l(raw_l.begin(), raw_l.begin() + n_loop);
    std::vector<float> out_r(raw_r.begin(), raw_r.begin() + n_loop);
    for (int i = 0; i < n_xf; ++i) {
        const float u = static_cast<float>(i) / static_cast<float>(n_xf);
        const float w_head = std::sin(u * 1.5707963f);
        const float w_tail = std::cos(u * 1.5707963f);
        out_l[static_cast<size_t>(i)] = out_l[static_cast<size_t>(i)] * w_head + raw_l[static_cast<size_t>(n_loop + i)] * w_tail;
        out_r[static_cast<size_t>(i)] = out_r[static_cast<size_t>(i)] * w_head + raw_r[static_cast<size_t>(n_loop + i)] * w_tail;
    }

    SynthAudioResult res;
    res.pcm = pack_pcm16(out_l, out_r, target_peak, SAMPLE_RATE, stereo);
    res.sample_rate = SAMPLE_RATE;
    res.stereo = stereo;
    return res;
}

std::vector<uint8_t> synthesize_ccb_ambience_loop_pcm(int layer_id) {
    return synthesize_ccb_ambience_loop_audio(layer_id).pcm;
}

} // namespace cangling
