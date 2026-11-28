#pragma once

#include <cstdint>
#include <vector>

namespace cangling {

struct SynthAudioResult {
    std::vector<uint8_t> pcm;
    int sample_rate = 44100;
    bool stereo = true;
};

// High-definition Physical Acoustic Combat Synthesizer with adaptive sample rate & channel layout
// (44.1 kHz stereo for close gunfire/blasts/hits/glass; 22.05 kHz mono/stereo for footsteps/distant/thunder/doors).
SynthAudioResult synthesize_ccb_combat_audio(
    int kind,
    int subtype,
    int variant,
    int space_mode,
    bool distant,
    float tail_scale = 1.0f);

// Backwards-compatible PCM-only helper
std::vector<uint8_t> synthesize_ccb_combat_pcm(
    int kind,
    int subtype,
    int variant,
    int space_mode,
    bool distant,
    float tail_scale = 1.0f);

// Seamless crossfaded ambient loop generator (22.05 kHz 16-bit PCM — 50-75% lower RAM, zero clicks at seam):
// layer_id: 0=wind_open, 1=wind_forest, 2=rain_outdoor, 3=rain_indoor,
//           4=night_crickets, 5=day_birds, 6=underground_cavern, 7=fire_crackle
SynthAudioResult synthesize_ccb_ambience_loop_audio(int layer_id);
std::vector<uint8_t> synthesize_ccb_ambience_loop_pcm(int layer_id);

} // namespace cangling
