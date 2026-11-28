#!/usr/bin/env python3
"""Generate the desktop main-menu layout fix without editing the upstream checkout."""
import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
text = source.read_text(encoding="utf-8")


def replace_between(start, end, replacement, search_from=0):
    global text
    first = text.index(start, search_from)
    last = text.index(end, first + len(start))
    text = text[:first] + replacement + text[last:]


def replace_exact(old, new):
    global text
    if text.count(old) != 1:
        raise RuntimeError(f"{source}: expected one main-menu anchor: {old!r}")
    text = text.replace(old, new, 1)


replace_between(
    "//CJK characters have a width of 2, etc\nstatic int utf8_width_notags",
    "void main_menu::display_sub_menu(",
    """std::vector<int> main_menu::print_menu_items( const catacurses::window &w_in,
        const std::vector<std::string> &vItems,
        size_t iSel, point offset, int spacing, bool main )
{
    const point win_origin( getbegx( w_in ), getbegy( w_in ) );
    const int available_width = std::max( 1, getmaxx( w_in ) - offset.x * 2 );
    struct menu_row {
        size_t begin;
        size_t end;
        int width;
    };
    std::vector<menu_row> rows;
    std::vector<std::string> labels;
    std::vector<int> widths;
    std::vector<int> starts;
    for( size_t i = 0; i < vItems.size(); ++i ) {
        const std::string item = shortcut_text( iSel == i ? hilite( c_yellow ) : c_yellow,
                                                vItems[i] );
        nc_color color = iSel == i ? hilite( c_white ) : c_white;
#ifdef MP_ENABLED
        if( main && iSel != i && i == static_cast<size_t>( getopt( main_menu_opts::COOP ) ) ) {
            color = c_light_green;
        }
#endif
        labels.push_back( string_format( main ? "[ %s ]" : "[%s]", colorize( item, color ) ) );
        const int width = std::min( available_width, utf8_width( labels.back(), true ) );
        widths.push_back( width );
        if( rows.empty() || rows.back().width + spacing + width > available_width ) {
            rows.push_back( { i, i + 1, width } );
        } else {
            rows.back().end = i + 1;
            rows.back().width += spacing + width;
        }
    }

    // Keep the bottom menu row in place. Wrap whole buttons upwards on narrow screens.
    int y = offset.y + 1 - static_cast<int>( rows.size() );
    for( const menu_row &row : rows ) {
        const int count = static_cast<int>( row.end - row.begin );
        const int extra = available_width - row.width;
        const int spread = rows.size() == 1 ? extra / ( count + 1 ) : 0;
        int x = offset.x + ( extra - spread * ( count - 1 ) ) / 2;
        for( size_t i = row.begin; i < row.end; ++i ) {
            starts.push_back( x );
            trim_and_print( w_in, point( x, y ), widths[i], c_white, labels[i] );
            if( main ) {
                const point first = win_origin + point( x, y );
                main_menu_button_map.emplace_back(
                    inclusive_rectangle<point>( first, first + point( widths[i] - 1, 0 ) ),
                    static_cast<int>( i ) );
            }
            x += widths[i] + spacing + spread;
        }
        ++y;
    }
    return starts;
}

""",
)

# Screen bounds, rendered label and clickable width must agree for long save names.
replace_exact("    const int window_width = xlen + 4;", """    xlen = std::min( xlen, TERMX - 4 );
    const int window_width = xlen + 4;""")
replace_exact("        opt.append( padding, ' ' );", "        opt.append( std::max( 0, padding ), ' ' );")

replace_between(
    "    // The New UI flavor draws the interactive menu and separator through ImGui.",
    "#ifdef MP_ENABLED",
    "",
    text.index("void main_menu::print_menu("),
)

replace_between(
    "    if( !android_ui_mode::is_new_ui_build() ) {\n        int menu_length = 0;",
    "    } else {\n        wnoutrefresh( w_open );\n    }",
    """    if( !android_ui_mode::is_new_ui_build() ) {
        print_menu_items( w_open, vMenuItems, iSel, offset, 1, true );
        const int origin_y = catacurses::getbegy( w_open );
        if( !main_menu_button_map.empty() ) {
            const int first_row = main_menu_button_map.front().first.p_min.y;
            mvwhline( w_open, point( 1, first_row - origin_y - 1 ), c_white, LINE_OXOX,
                      window_width - 2 );
            wnoutrefresh( w_open );
            if( iSel >= 0 && static_cast<size_t>( iSel ) < main_menu_button_map.size() ) {
                const auto &button = main_menu_button_map[iSel].first;
                const int center_x = button.p_min.x + ( button.p_max.x - button.p_min.x ) / 2;
                // Use the same rectangle for hover, click and the submenu anchor.
                // Keep the entire submenu above all button rows.
                display_sub_menu( iSel, point( center_x, first_row - 2 ), sel_line );
            }
        } else {
            wnoutrefresh( w_open );
        }
""",
    text.index("void main_menu::print_menu("),
)

if not output.exists() or output.read_text(encoding="utf-8") != text:
    output.write_text(text, encoding="utf-8")
