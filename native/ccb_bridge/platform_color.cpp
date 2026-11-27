#include "bridge_state.hpp"

#include "color.h"
#include "color_loader.h"

namespace {
struct BridgeRGB {
    uint8_t r = 0;
    uint8_t g = 0;
    uint8_t b = 0;
};
} // namespace

template<>
BridgeRGB color_loader<BridgeRGB>::from_rgb(const int r, const int g, const int b) {
    return BridgeRGB{
        static_cast<uint8_t>(r < 0 ? 0 : (r > 255 ? 255 : r)),
        static_cast<uint8_t>(g < 0 ? 0 : (g > 255 ? 255 : g)),
        static_cast<uint8_t>(b < 0 ? 0 : (b > 255 ? 255 : b))
    };
}

namespace ccb_bridge {

void load_ccb_base_palette() {
    auto &st = state();
    st.init_default_palette();
    try {
        std::array<BridgeRGB, color_loader<BridgeRGB>::COLOR_NAMES_COUNT> loaded{};
        color_loader<BridgeRGB>().load(loaded);
        for (size_t i = 0; i < loaded.size() && i < 16; ++i) {
            st.palette[i] = static_cast<uint32_t>(loaded[i].r)
                          | (static_cast<uint32_t>(loaded[i].g) << 8)
                          | (static_cast<uint32_t>(loaded[i].b) << 16)
                          | (0xFFu << 24);
        }
    } catch (...) {
        // Keep authentic defaults if colors file is unavailable yet
    }
}

} // namespace ccb_bridge

// Software nc_color bit layout (preserves pair `index` so cataimgui::imvec4_from_color works for ALL ImGui/ImTui menus!)
static constexpr int A_BLINK = 0x00000800;
static constexpr int A_BOLD  = 0x00002000;
static constexpr int A_COLOR = 0x03fe0000;

nc_color nc_color::from_color_pair_index(const int idx) {
    return nc_color((idx << 17) & A_COLOR, idx);
}

int nc_color::to_color_pair_index() const {
    return (attribute_value & A_COLOR) >> 17;
}

nc_color nc_color::bold() const {
    return nc_color(attribute_value | A_BOLD, index);
}

bool nc_color::is_bold() const {
    return (attribute_value & A_BOLD) != 0;
}

nc_color nc_color::blink() const {
    return nc_color(attribute_value | A_BLINK, index);
}

bool nc_color::is_blink() const {
    return (attribute_value & A_BLINK) != 0;
}
