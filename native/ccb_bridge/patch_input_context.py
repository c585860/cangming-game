#!/usr/bin/env python3
"""Route the headless CCB map zoom actions to the Godot renderer."""

import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
text = source.read_text(encoding="utf-8")


def replace_once(old, new):
    global text
    if text.count(old) != 1:
        raise RuntimeError(f"Cannot locate zoom input hook in {source}: {old}")
    text = text.replace(old, new, 1)


header = '#include "input_context.h"\n'
replace_once(header, header + '#include "bridge_state.hpp"\n')
anchor = '    scoped_activation active_context( *this );\n'
replace_once(anchor, anchor + '''    const auto has_action = [this]( const char * action ) {
        return std::find( registered_actions.begin(), registered_actions.end(), action ) !=
               registered_actions.end();
    };
    const bool bridge_map_zoom = category == "LOOK" ||
                                 ( category == "DEFAULTMODE" && has_action( "look" ) );
    if( bridge_map_zoom ) {
        if( !has_action( "zoom_in" ) ) {
            register_action( "zoom_in" );
        }
        if( !has_action( "zoom_out" ) ) {
            register_action( "zoom_out" );
        }
    }
    const auto forward_bridge_zoom = [bridge_map_zoom]( const std::string & action ) {
        if( bridge_map_zoom && ( action == "zoom_in" || action == "zoom_out" ) ) {
            ccb_bridge::state().map_zoom_steps.fetch_add( action == "zoom_in" ? 1 : -1,
                    std::memory_order_relaxed );
            return true;
        }
        return false;
    };
''')
anchor = '            inp_mngr.set_timeout( old_timeout );\n            return context_direct_action;'
replace_once(anchor, '''            if( !forward_bridge_zoom( context_direct_action ) ) {
                inp_mngr.set_timeout( old_timeout );
                return context_direct_action;
            }''')
anchor = '            result = &context_direct_action;\n            break;'
replace_once(anchor, '''            if( forward_bridge_zoom( context_direct_action ) ) {
                continue;
            }
''' + anchor)
anchor = '        const std::string &action = input_to_action( next_action );\n'
replace_once(anchor, anchor + '''        if( forward_bridge_zoom( action ) ) {
            continue;
        }
''')

if not output.exists() or output.read_text(encoding="utf-8") != text:
    output.write_text(text, encoding="utf-8")
