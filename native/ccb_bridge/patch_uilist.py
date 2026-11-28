#!/usr/bin/env python3
"""Generates patched uilist_bridge.cpp in build dir from upstream CCB src/uilist.cpp (zero upstream edits)."""
import sys
from pathlib import Path

src_path = Path(sys.argv[1])
dst_path = Path(sys.argv[2])
text = src_path.read_text(encoding="utf-8")

def replace_exact(src: str, old: str, new: str, label: str) -> str:
    if old not in src:
        raise RuntimeError(f"patch_uilist.py: failed to find anchor [{label}] in {src_path}")
    return src.replace(old, new, 1)

# 1. Fit menu_size to actual available content region whenever desired_bounds is set (fixes 4-row wishitem/wishmonster/wishmutate!)
text = replace_exact(
    text,
    """    ImVec2 menu_size = parent.calculated_menu_size;
    if( parent.force_desired_bounds && parent.desired_bounds.has_value() ) {
        menu_size = uilist_menu_size_for_available_region( ImGui::GetContentRegionAvail(),
                    parent.extra_space_left, parent.extra_space_right );
    }""",
    """    ImVec2 menu_size = parent.calculated_menu_size;
    const bool use_avail_bounds = parent.desired_bounds.has_value() &&
        ( parent.force_desired_bounds ||
          ( parent.desired_bounds->h > 0.0f && parent.desired_bounds->h <= 1.0f ) ||
          ( parent.desired_bounds->w > 0.0f && parent.desired_bounds->w <= 1.0f ) );
    if( use_avail_bounds ) {
        menu_size = uilist_menu_size_for_available_region( ImGui::GetContentRegionAvail(),
                    parent.extra_space_left, parent.extra_space_right );
    }""",
    "draw_controls_use_avail_bounds",
)

text = replace_exact(
    text,
    """        if( parent.force_desired_bounds && parent.desired_bounds.has_value() ) {
            // Query this after entering the table cell: it is the exact vertical space left after
            // window padding, category tabs, and the cell's top padding have been consumed.
            menu_size.y = uilist_menu_size_for_available_region(
                              ImGui::GetContentRegionAvail(), 0.0F, 0.0F ).y;
        }""",
    """        if( use_avail_bounds ) {
            // Query this after entering the table cell: it is the exact vertical space left after
            // window padding, category tabs, and the cell's top padding have been consumed.
            menu_size.y = uilist_menu_size_for_available_region(
                              ImGui::GetContentRegionAvail(), 0.0F, 0.0F ).y;
            if( parent.desc_enabled ) {
                menu_size.y = std::max( 4.0F, menu_size.y - 4.0F * ImGui::GetTextLineHeightWithSpacing() );
            }
        }""",
    "draw_controls_cell_height",
)

# 2. Accurate CJK/UTF-8 display width in ImTui mode so Chinese menus never clip on the right
text = replace_exact(
    text,
    """static ImVec2 calc_size( std::string_view line )
{
    return ImGui::CalcTextSize( remove_color_tags( line ).c_str() );
}""",
    """static ImVec2 calc_size( std::string_view line )
{
#ifdef TUI
    const std::string clean = remove_color_tags( line );
    size_t max_w = 0;
    size_t lines = 1;
    size_t start = 0;
    while( start <= clean.size() ) {
        const size_t nl = clean.find( '\\n', start );
        const std::string_view seg = ( nl == std::string::npos )
            ? std::string_view( clean ).substr( start )
            : std::string_view( clean ).substr( start, nl - start );
        max_w = std::max<size_t>( max_w, static_cast<size_t>( utf8_width( seg ) ) );
        if( nl == std::string::npos ) {
            break;
        }
        ++lines;
        start = nl + 1;
    }
    return ImVec2( static_cast<float>( max_w ), static_cast<float>( lines ) * ImGui::GetTextLineHeight() );
#else
    return ImGui::CalcTextSize( remove_color_tags( line ).c_str() );
#endif
}""",
    "calc_size_tui_utf8",
)

# 3. Scale fractional desired_bounds (0 < w/h <= 1.0) by MainViewport size AND cap menu_size.x so right panel stays on-screen!
text = replace_exact(
    text,
    """    float max_avail_height = main_view_max_y;
    if( desired_bounds.has_value() ) {
        float desired_height = desired_bounds.value().h;
        if( desired_height != -1 ) {
            max_avail_height = std::min( max_avail_height, desired_height );
        }
    }
    calculated_menu_size.y = std::min(
                                 max_avail_height - additional_height,
                                 vmax * ImGui::GetTextLineHeightWithSpacing() ) + frame_padding_y;

    extra_space_left = 0.0;
    extra_space_right = 0.0;
    if( callback != nullptr ) {
        extra_space_left = callback->desired_extra_space_left( ) + s.FramePadding.x;
        extra_space_right = callback->desired_extra_space_right( ) + s.FramePadding.x;
    }

    float longest_line_width = std::max( { title_size.x, text_size.x,
                                           calculated_menu_size.x, desc_size.x } );
    calculated_bounds.w = extra_space_left + extra_space_right + longest_line_width
                          + window_padding_x + window_border;
    calculated_bounds.h = calculated_menu_size.y + additional_height;""",
    """    const ImVec2 vp_size = ImGui::GetMainViewport()->Size;
    float max_avail_height = main_view_max_y;
    float max_avail_width = std::max( 20.0f, vp_size.x - window_padding_x - window_border );
    if( desired_bounds.has_value() ) {
        float desired_height = desired_bounds.value().h;
        if( desired_height > 0.0f && desired_height <= 1.0f ) {
            desired_height *= vp_size.y;
        }
        if( desired_height > 0.0f ) {
            max_avail_height = std::min( vp_size.y, desired_height );
        }
        float desired_width = desired_bounds.value().w;
        if( desired_width > 0.0f && desired_width <= 1.0f ) {
            desired_width *= vp_size.x;
        }
        if( desired_width > 0.0f ) {
            max_avail_width = std::min( max_avail_width, desired_width - window_padding_x - window_border );
        }
    }
    calculated_menu_size.y = std::max(
                                 ImGui::GetTextLineHeightWithSpacing() * 4.0f,
                                 std::min(
                                     std::max( 1.0f, max_avail_height - additional_height ),
                                     vmax * ImGui::GetTextLineHeightWithSpacing() ) ) + frame_padding_y;

    extra_space_left = 0.0;
    extra_space_right = 0.0;
    if( callback != nullptr ) {
        extra_space_left = callback->desired_extra_space_left( ) + s.FramePadding.x;
        extra_space_right = callback->desired_extra_space_right( ) + s.FramePadding.x;
    }

    const float max_menu_x = std::max( 16.0f, max_avail_width - extra_space_left - extra_space_right - 2.0f );
    if( calculated_menu_size.x > max_menu_x ) {
        calculated_menu_size.x = max_menu_x;
        calculated_label_width = std::max( 8.0f, max_menu_x - calculated_hotkey_width - calculated_secondary_width - padding * 3.0f );
    }

    float longest_line_width = std::min( max_menu_x, std::max( { title_size.x, text_size.x,
                                           calculated_menu_size.x, desc_size.x } ) );
    calculated_bounds.w = std::min( vp_size.x, extra_space_left + extra_space_right + longest_line_width
                          + window_padding_x + window_border );
    calculated_bounds.h = std::min( vp_size.y, calculated_menu_size.y + additional_height );""",
    "calc_data_bounds_scaling",
)

dst_path.parent.mkdir(parents=True, exist_ok=True)
if not dst_path.exists() or dst_path.read_text(encoding="utf-8") != text:
    dst_path.write_text(text, encoding="utf-8")
