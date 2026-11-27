#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#  if defined(CCB_BRIDGE_EXPORTS)
#    define CCB_API __declspec(dllexport)
#  else
#    define CCB_API __declspec(dllimport)
#  endif
#else
#  define CCB_API __attribute__((visibility("default")))
#endif

// Terminal cell flags
#define CCB_CELL_TERRAIN 0x01u
#define CCB_CELL_IMGUI   0x02u
#define CCB_CELL_CURSOR  0x04u
#define CCB_CELL_CONT    0x08u

// Mouse actions
#define CCB_MOUSE_MOVE        0
#define CCB_MOUSE_LEFT_DOWN   1
#define CCB_MOUSE_LEFT_UP     2
#define CCB_MOUSE_RIGHT_DOWN  3
#define CCB_MOUSE_RIGHT_UP    4
#define CCB_MOUSE_WHEEL_UP    5
#define CCB_MOUSE_WHEEL_DOWN  6

// Special key codes (match CCB curses/input.h constants)
#define CCB_KEY_ESCAPE     27
#define CCB_KEY_TAB        9
#define CCB_KEY_ENTER      10
#define CCB_KEY_DOWN       0x102
#define CCB_KEY_UP         0x103
#define CCB_KEY_LEFT       0x104
#define CCB_KEY_RIGHT      0x105
#define CCB_KEY_HOME       0x106
#define CCB_KEY_BACKSPACE  0x107
#define CCB_KEY_F0         0x108
#define CCB_KEY_DC         0x14A
#define CCB_KEY_NPAGE      0x152
#define CCB_KEY_PPAGE      0x153
#define CCB_KEY_BTAB       0x161
#define CCB_KEY_END        0x168

// Visibility level for each world tile
#define CCB_VIS_UNSEEN     0
#define CCB_VIS_MEMORIZED  1
#define CCB_VIS_DARK       2
#define CCB_VIS_VISIBLE    3
#define CCB_VIS_FRINGE     4 // Static geometry fringe 1 tile past sight edge for smooth sub-tile GPU raycast FOV

// Tile bit flags
#define CCB_TILE_OUTSIDE      0x01u
#define CCB_TILE_OPAQUE       0x02u
#define CCB_TILE_HAS_CORPSE   0x04u
#define CCB_TILE_IS_WATER     0x08u
#define CCB_TILE_IS_ROOFED    0x10u
#define CCB_TILE_HAS_OVERLAY  0x20u
#define CCB_TILE_APERTURE_X   0x40u
#define CCB_TILE_DEEP_WATER   0x80u

// Semantic lighting geometry classes (matches cangling-city solar_visibility / atmosphere shaders)
#define CCB_LIGHT_GROUND      0u
#define CCB_LIGHT_WALL        1u
#define CCB_LIGHT_WIN_CLOSED  2u
#define CCB_LIGHT_WIN_OPEN    3u
#define CCB_LIGHT_DOOR_OPEN   4u
#define CCB_LIGHT_TREE        5u
#define CCB_LIGHT_SHRUB       6u
#define CCB_LIGHT_FURNITURE   7u

// Path point kinds (auto-move route & mouse destination preview)
#define CCB_PATH_AUTOMOVE     1u
#define CCB_PATH_PREVIEW      2u
#define CCB_PATH_DESTINATION  3u

// Overlay sub-kinds encoded in CcbWorldTile::overlay_kind
#define CCB_OV_NONE           0u
#define CCB_OV_HIGHLIGHT      1u // Aim line, throw path, bullet line, highlighted cursor
#define CCB_OV_HIT_FLASH      2u // Red/yellow combat impact flash on creature
#define CCB_OV_EXPLOSION      3u // Blast wave / fireball glyphs
#define CCB_OV_BULLET         4u // Flying bullet / projectile glyph
#define CCB_OV_ZONE           5u // Zone manager (~ green area)
#define CCB_OV_SOUND          6u // Unseen sound marker (?)
#define CCB_OV_CURSOR         7u // Explicit cursor / target X / unobscuring arrows

// Creature flags
#define CCB_CRITTER_PLAYER   0x01u
#define CCB_CRITTER_HOSTILE  0x02u
#define CCB_CRITTER_FRIENDLY 0x04u
#define CCB_CRITTER_NPC      0x08u
#define CCB_CRITTER_MALE     0x10u

#pragma pack(push, 1)
typedef struct CcbTermCell {
    uint32_t codepoint;
    uint32_t fg_rgba;
    uint32_t bg_rgba;
    uint8_t  width;
    uint8_t  flags;
    uint16_t reserved;
} CcbTermCell;

typedef struct CcbTermHeader {
    uint64_t generation;
    int32_t  cols;
    int32_t  rows;
    int32_t  terrain_x;
    int32_t  terrain_y;
    int32_t  terrain_w;
    int32_t  terrain_h;
    int32_t  cursor_x;
    int32_t  cursor_y;
    uint8_t  has_terrain;
    uint8_t  in_game;
    uint8_t  is_looking;
    uint8_t  paused;
} CcbTermHeader;

typedef struct CcbWorldTile {
    uint16_t ter_str;
    uint16_t furn_str;
    uint16_t trap_str;
    uint16_t vpart_str;
    uint16_t field_str;
    uint16_t item_str;
    uint16_t corpse_str;
    uint16_t item_count;
    uint8_t  vis;
    uint8_t  lit_level;
    uint8_t  ter_subtile;     // CCB multitile_subtiles (0..7) or 0xFF for none
    uint8_t  ter_rot;         // CCB rotation (0..15)
    uint8_t  furn_subtile;    // CCB multitile_subtiles (0..7) or 0xFF for none
    uint8_t  furn_rot;        // CCB rotation (0..15)
    uint8_t  vpart_rot;
    uint8_t  field_intensity;
    uint8_t  flags;
    uint8_t  ambient_light_u8;
    uint8_t  light_kind;      // CCB_LIGHT_*
    uint8_t  height_u8;       // physical height in meters * (255 / 3.0)
    uint8_t  surface_hold_u8; // 0=grass, 128=dirt, 255=stone/asphalt
    uint8_t  mat_r;           // GI bounce material albedo R
    uint8_t  mat_g;           // GI bounce material albedo G
    uint8_t  mat_b;           // GI bounce material albedo B
    uint32_t overlay_cp;
    uint32_t overlay_fg;
    uint32_t overlay_bg;
    uint8_t  overlay_kind;    // CCB_OV_*
    uint8_t  pad_ov[3];
} CcbWorldTile;

typedef struct CcbWorldCreature {
    int32_t  x;
    int32_t  y;
    uint32_t uid;             // Stable per-creature identifier for 60fps smooth glide
    uint16_t sprite_str;
    uint8_t  flags;
    uint8_t  hp_pct;
    uint16_t wield_str;
    uint16_t worn_str[4];
} CcbWorldCreature;

typedef struct CcbWorldLight {
    int32_t  x;
    int32_t  y;
    float    intensity;
    uint32_t color_rgba;
} CcbWorldLight;

typedef struct CcbWorldPathPoint {
    int32_t  x;
    int32_t  y;
    uint8_t  kind;            // CCB_PATH_*
    uint8_t  pad[3];
} CcbWorldPathPoint;

typedef struct CcbWorldSct {
    int32_t  x;
    int32_t  y;
    uint32_t color_rgba;
    uint8_t  step;
    uint8_t  max_steps;
    char     text[62];
} CcbWorldSct;

typedef struct CcbWorldHeader {
    uint64_t generation;
    int32_t  origin_x;
    int32_t  origin_y;
    int32_t  width;
    int32_t  height;
    int32_t  z;
    int32_t  center_x;
    int32_t  center_y;
    int32_t  player_x;
    int32_t  player_y;
    int32_t  player_z;
    int32_t  turn;
    int32_t  minutes_of_day;
    int32_t  season;
    int32_t  day_of_season;
    float    daylight_level;
    float    player_light;
    int32_t  creature_count;
    int32_t  light_count;
    int32_t  path_count;
    int32_t  sct_count;
    int32_t  string_count;
    int32_t  string_bytes;
    int32_t  minimap_size;
    uint8_t  valid;
    uint8_t  player_male;
    uint8_t  is_looking;
    uint8_t  is_underground;
    char     weather_id[48];
    char     wielded_id[64];
} CcbWorldHeader;
#pragma pack(pop)

// Lifecycle
CCB_API int      ccb_start(const char *base_dir, const char *user_dir, int cols, int rows);
CCB_API void     ccb_shutdown(void);
CCB_API int      ccb_is_running(void);
CCB_API int      ccb_is_waiting_resume(void);
CCB_API void     ccb_resume_session(void);
CCB_API void     ccb_request_return_to_launcher(void);
CCB_API int      ccb_get_status_message(char *buf, int buf_size);

// Input
CCB_API void     ccb_push_key(int key_code, const char *utf8_text, int ctrl, int alt, int shift);
CCB_API void     ccb_push_mouse(int action, int cell_x, int cell_y, int wheel);
CCB_API void     ccb_push_resize(int cols, int rows);

// Frame & world snapshots
CCB_API uint64_t ccb_get_generation(void);
CCB_API int      ccb_copy_terminal_frame(CcbTermHeader *out_header, CcbTermCell *out_cells, int max_cells);
CCB_API int      ccb_copy_world_snapshot(
    CcbWorldHeader *out_header,
    CcbWorldTile *out_tiles, int max_tiles,
    char *out_strings, int max_strings_bytes,
    CcbWorldCreature *out_creatures, int max_creatures,
    CcbWorldLight *out_lights, int max_lights,
    char *out_worn_csv, int max_worn_bytes,
    uint8_t *out_minimap_rgba, int max_minimap_bytes);
CCB_API int      ccb_copy_world_effects(
    CcbWorldPathPoint *out_path, int max_path,
    CcbWorldSct *out_sct, int max_sct);

// Tileset config (synced natively with CCB Options -> Graphics -> Tileset) & looks_like catalog
CCB_API int      ccb_get_tileset_config(
    char *out_name, int max_name,
    char *out_dir, int max_dir,
    char *out_json_file, int max_json,
    int *out_use_tiles);
CCB_API int      ccb_copy_looks_like_table(char *out_buf, int max_bytes);

#ifdef __cplusplus
}
#endif
