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

// Transient Combat / Gunfire VFX kinds
#define CCB_VFX_MUZZLE_FLASH   1u
#define CCB_VFX_TRACER         2u
#define CCB_VFX_BEAM_LASER     3u
#define CCB_VFX_BEAM_PLASMA    4u
#define CCB_VFX_BEAM_LIGHTNING 5u
#define CCB_VFX_IMPACT_SPARK   6u
#define CCB_VFX_BLAST          7u
#define CCB_VFX_FLASHBANG      8u
#define CCB_VFX_EMP            9u

// VFX caliber / visual profile hints
#define CCB_CALIBER_DEFAULT    0u
#define CCB_CALIBER_PISTOL     1u
#define CCB_CALIBER_RIFLE      2u
#define CCB_CALIBER_SHOTGUN    3u
#define CCB_CALIBER_HEAVY      4u
#define CCB_CALIBER_SUPPRESSED 5u
#define CCB_CALIBER_ENERGY     6u

// VFX flags
#define CCB_VFX_FLAG_INDOORS   0x01u
#define CCB_VFX_FLAG_FIERY     0x02u

// Real-time combat & world audio event kinds
#define CCB_SFX_GUNSHOT        1u
#define CCB_SFX_EXPLOSION      2u
#define CCB_SFX_PROJECTILE_HIT 3u
#define CCB_SFX_MELEE          4u
#define CCB_SFX_FOOTSTEP       5u
#define CCB_SFX_VARIANT        6u

// Audio subtypes
#define CCB_GUN_PISTOL         1u
#define CCB_GUN_SMG            2u
#define CCB_GUN_RIFLE          3u
#define CCB_GUN_SHOTGUN        4u
#define CCB_GUN_HEAVY          5u
#define CCB_GUN_SUPPRESSED     6u
#define CCB_GUN_LASER          7u
#define CCB_GUN_PLASMA         8u
#define CCB_GUN_LIGHTNING      9u
#define CCB_GUN_BOW           10u
#define CCB_GUN_LAUNCHER      11u
#define CCB_GUN_FLAMETHROWER  12u

#define CCB_EXPL_SMALL         1u
#define CCB_EXPL_MEDIUM        2u
#define CCB_EXPL_HUGE          3u
#define CCB_EXPL_FLASHBANG     4u
#define CCB_EXPL_EMP           5u
#define CCB_EXPL_SHOCKWAVE     6u

#define CCB_HIT_FLESH          1u
#define CCB_HIT_METAL          2u
#define CCB_HIT_WALL           3u
#define CCB_MELEE_SWING        4u
#define CCB_MELEE_HIT_FLESH    5u
#define CCB_MELEE_HIT_METAL    6u
#define CCB_VAR_RELOAD         7u
#define CCB_VAR_DOOR           8u
#define CCB_VAR_SMASH          9u
#define CCB_VAR_SHELL_CASING  10u
#define CCB_VAR_THUNDER       11u
#define CCB_VAR_DRIP          12u
#define CCB_VAR_GLASS_BREAK   13u

// World light flags
#define CCB_LIGHT_FLAG_FIRE      0x01u
#define CCB_LIGHT_FLAG_SPOTLIGHT 0x02u

// Audio flags
#define CCB_AUDIO_FLAG_INDOORS    0x01u
#define CCB_AUDIO_FLAG_DISTANT    0x02u
#define CCB_AUDIO_FLAG_SUPPRESSED 0x04u
#define CCB_AUDIO_FLAG_HAS_CASING 0x08u

// 3D renderer draw modes (exact match to CCB src/render3d.cpp draw_mode)
#define CCB_3D_MODE_BOX            0u
#define CCB_3D_MODE_XQUAD          1u
#define CCB_3D_MODE_BILLBOARD      2u
#define CCB_3D_MODE_BILLBOARD_SNAP 3u
#define CCB_3D_MODE_LINEQUAD       4u
#define CCB_3D_MODE_FLATQUAD       5u
#define CCB_3D_MODE_FLATQUAD_DECAL 6u
#define CCB_3D_MODE_LINEQUAD_DECAL 7u

// 3D renderer sprite layer pick modes
#define CCB_3D_PICK_FG             0u // Normal foreground sprite (uses subtile + rot)
#define CCB_3D_PICK_BG             1u // Background sprite (body layer / terrain bg)
#define CCB_3D_PICK_GROUND         2u // Ground slab: bg if present else fg, opaque-cropped
#define CCB_3D_PICK_FIELD          3u // Field sprite with intensity in subtile high nibble
#define CCB_3D_PICK_OVERLAY        4u // Character paperdoll overlay (gender-aware)
#define CCB_3D_PICK_SOLID          5u // Untextured solid color (fog slab / fallback)

// 3D renderer shader flag bits (exact match to CCB data/shaders/terrain3d.vert/.frag)
#define CCB_3D_FLAG_TEXTURED        (1u << 0)
#define CCB_3D_FLAG_NO_DISCARD      (1u << 1)
#define CCB_3D_FLAG_ROT_SHIFT       2u
#define CCB_3D_FLAG_SIDE_STRIP      (1u << 4)
#define CCB_3D_FLAG_GHOST           (1u << 5)
#define CCB_3D_FLAG_MEMORY          (1u << 6)
#define CCB_3D_FLAG_DITHER_ALPHA    (1u << 7)
#define CCB_3D_FLAG_SILHOUETTE_SIDE (1u << 8)
#define CCB_3D_FLAG_FAR_LOD         (1u << 9)
#define CCB_3D_FLAG_SAME_LEVEL_WALL (1u << 10)
#define CCB_3D_FLAG_CREATURE_HOSTILE  (1u << 11)
#define CCB_3D_FLAG_CREATURE_NEUTRAL  (1u << 12)
#define CCB_3D_FLAG_CREATURE_FRIENDLY (1u << 13)
#define CCB_3D_FLAG_HALF_U          (1u << 14) // Half-length fence quad: crop U to [0, 0.5]
#define CCB_3D_FLAG_FLIP_U          (1u << 15) // Mirror sprite horizontally (vehicle flank panels)
#define CCB_3D_FLAG_CROP_SPILL      (1u << 16) // Crop transparent north spill rows (vehicle hoods/panels)
#define CCB_3D_FLAG_GLASS_BAND      (1u << 17) // Top 12/32 glass band of windshield sprite
#define CCB_3D_FLAG_BASE_DROP       (1u << 18) // Drop vertical Z by scale.y * sprite.base_drop
#define CCB_3D_FLAG_ASPECT_WIDTH    (1u << 19) // Scale horizontal width by sprite.aspect * scale.y
#define CCB_3D_FLAG_PAPERDOLL_BODY  (1u << 20) // Humanoid body anchor (sets paperdoll px_scale)
#define CCB_3D_FLAG_PAPERDOLL_LAYER (1u << 21) // Paperdoll overlay aligned to preceding body
#define CCB_3D_FLAG_MALE            (1u << 22) // Gender hint for paperdoll overlay lookup
#define CCB_3D_FLAG_VEH_FOOTPRINT   (1u << 23) // Scale flat decal by sprite px_w/32, px_h/32 + offset
#define CCB_3D_FLAG_MASK_ELIGIBLE   (1u << 24) // Eligible for camera->player & cursor occlusion cutout

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
    uint8_t  want_text_input;
    uint8_t  pad_hdr[3];
} CcbTermHeader;

typedef struct CcbLoadingState {
    uint64_t seq;
    uint8_t  active;
    uint8_t  pad[3];
    char     image_path[512];
    char     tip[512];
    char     context[256];
    char     step[256];
} CcbLoadingState;

typedef struct CcbWorldVfx {
    uint64_t id;
    int32_t  ox;
    int32_t  oy;
    int32_t  tx;
    int32_t  ty;
    int32_t  z;
    float    radius;
    float    light_intensity;
    uint32_t color_rgba;
    uint16_t arc_deg;
    uint16_t delay_ms;        // Burst stagger offset in ms (synced 1:1 with firearm RPM)
    uint8_t  kind;            // CCB_VFX_*
    uint8_t  caliber_class;   // CCB_CALIBER_*
    uint8_t  shot_index;      // 0..N-1 within burst
    uint8_t  flags;           // CCB_VFX_FLAG_*
} CcbWorldVfx;

typedef struct CcbAudioEvent {
    uint64_t id;
    uint64_t burst_id;
    int32_t  x;
    int32_t  y;
    int32_t  z;
    uint16_t rpm;
    uint16_t delay_ms;
    float    volume;
    float    pan;
    float    radius;
    uint8_t  kind;            // CCB_SFX_*
    uint8_t  subtype;         // CCB_GUN_* / CCB_EXPL_* / CCB_HIT_* / CCB_VAR_*
    uint8_t  shot_index;
    uint8_t  flags;           // CCB_AUDIO_FLAG_*
} CcbAudioEvent;

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
    uint8_t  vpart_rot;       // low 4 bits = rot, high 4 bits = open(6)/broken(7) subtile
    uint8_t  field_intensity; // 1..3
    uint8_t  flags;
    uint8_t  ambient_light_u8;
    uint8_t  light_kind;      // CCB_LIGHT_*
    uint8_t  height_u8;       // physical height in meters * (255 / 3.0)
    uint8_t  surface_hold_u8; // mat_id * 36
    uint8_t  mat_r;           // GI bounce material albedo R
    uint8_t  mat_g;           // GI bounce material albedo G
    uint8_t  mat_b;           // GI bounce material albedo B
    uint32_t overlay_cp;
    uint32_t overlay_fg;
    uint32_t overlay_bg;
    uint8_t  overlay_kind;    // CCB_OV_*
    uint8_t  field_subtile;   // CCB multitile_subtiles (0..7) or 0xFF for none
    uint8_t  field_rot;       // CCB rotation (0..15)
    uint8_t  trap_sub_rot;    // low 4 bits = rot, high 4 bits = subtile + 1 (0 = none)
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
    float    dir_x;           // Unit spotlight direction X (+East); 0 if omnidirectional
    float    dir_y;           // Unit spotlight direction Y (+South); 0 if omnidirectional
    float    cone_cos;        // cos(half_angle); <= -0.5 means omnidirectional point light
    uint8_t  flags;           // CCB_LIGHT_FLAG_*
    uint8_t  pad[3];
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
    float    wind_x;          // Normalized wind direction X (+East)
    float    wind_y;          // Normalized wind direction Y (+South)
    float    wind_speed;      // CCB wind speed (0..60+)
    uint8_t  player_indoors;  // 1 if player tile is roofed/indoors
    uint8_t  player_move_mode;// 0=crouch, 1=walk, 2=run
    uint8_t  player_mat_id;   // Underfoot surface material (0..7)
    uint8_t  tree_density_u8; // 0..255 nearby tree canopy density
    char     weather_id[48];
    char     wielded_id[64];
    uint32_t minimap_seq;     // Incremented only when minimap pixels actually change
} CcbWorldHeader;

typedef struct CcbScene3DItem {
    float    px;             // CCB scene coords relative to center: +X east, +Y south, +Z up (meters)
    float    py;
    float    pz;
    float    sx;             // Box/flat: width X; Billboard/linequad: width (or height multiplier)
    float    sy;             // Box/flat: depth Y; Billboard/linequad: height
    float    sz;             // Box/xquad: height Z; Billboard: layer depth offset (toward camera)
    float    r;              // Light tint / fallback RGB
    float    g;
    float    b;
    float    sat;            // Color saturation (0..1), or tile light in NV mode
    uint32_t flags;          // CCB_3D_FLAG_*
    uint16_t sprite_str;     // Interned tileset sprite id
    uint8_t  mode;           // CCB_3D_MODE_*
    uint8_t  pick;           // CCB_3D_PICK_*
    uint8_t  subtile;        // Multitile subtile (0..7) or 0xFF; for fields: intensity in high nibble
    uint8_t  rot;            // CCB rotation (0..15)
    uint8_t  v0_u8;          // Vertical UV slice start [0..255] -> [0..1] (0 for full)
    uint8_t  v1_u8;          // Vertical UV slice end   [0..255] -> [0..1] (255 for full)
    uint16_t seed;           // Deterministic tile hash for weighted sprite variants
    int16_t  pad_i16;        // Fixed-point pad * 1000 (e.g. fence N-S = 1000, E-W = 0, paperdoll layer idx)
} CcbScene3DItem;

typedef struct CcbScene3DLight {
    float    px;             // Relative to center (+X east, +Y south, +Z up)
    float    py;
    float    pz;
    float    radius;
    float    r;
    float    g;
    float    b;
    float    intensity;
} CcbScene3DLight;

typedef struct CcbScene3DHeader {
    uint64_t generation;
    int32_t  center_x;
    int32_t  center_y;
    int32_t  center_z;
    int32_t  player_x;
    int32_t  player_y;
    int32_t  player_z;
    int32_t  season;
    int32_t  turn;
    float    daylight;       // 0..1
    float    sun_x;          // Toward sun in CCB scene coords (+X east, +Y south, +Z up)
    float    sun_y;
    float    sun_z;
    float    sun_up;         // 1.0 when sun is above horizon
    float    cloudiness;     // 0..1 weather-driven cloud cover
    float    wind_x;
    float    wind_y;
    float    nv_active;      // 1.0 when NV goggles green tint is active
    float    nv_floor;
    float    nv_overexpose;
    int32_t  memory_preset;  // 0=darken, 1=sepia_light, 2=sepia_dark, 3=blue_dark
    int32_t  item_count;
    int32_t  light_count;
    int32_t  string_count;
    int32_t  string_bytes;
    uint8_t  valid;
    uint8_t  same_level_only;
    uint8_t  controlling_vehicle;
    uint8_t  is_looking;
    int32_t  veh_ind_x;      // Vehicle direction indicator offset (INT32_MIN if none)
    int32_t  veh_ind_y;
} CcbScene3DHeader;
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
CCB_API void     ccb_push_text_input(const char *utf8_text);
CCB_API void     ccb_push_ime_edit(const char *utf8_edit);
CCB_API void     ccb_push_mouse(int action, int cell_x, int cell_y, int wheel);
CCB_API void     ccb_push_resize(int cols, int rows);

// Loading screen state (authentic vanilla CCB loading_screens + progress)
CCB_API int      ccb_get_loading_state(CcbLoadingState *out_state);

// Frame & world snapshots
CCB_API uint64_t ccb_get_generation(void);
CCB_API uint64_t ccb_get_world_generation(void);
CCB_API uint64_t ccb_get_scene3d_generation(void);
CCB_API uint64_t ccb_get_audio_generation(void);
CCB_API void     ccb_set_world_capture_radius(int rad_x, int rad_y);
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
CCB_API int      ccb_copy_world_vfx(
    CcbWorldVfx *out_vfx, int max_vfx);
CCB_API int      ccb_copy_audio_events(
    CcbAudioEvent *out_events, int max_events);

// Tileset config (synced natively with CCB Options -> Graphics -> Tileset) & looks_like catalog
CCB_API int      ccb_get_tileset_config(
    char *out_name, int max_name,
    char *out_dir, int max_dir,
    char *out_json_file, int max_json,
    int *out_use_tiles);
CCB_API int      ccb_copy_looks_like_table(char *out_buf, int max_bytes);

// Experimental Godot 3D renderer bridge (driven by CCB's exact multi-Z/visibility/geometry logic!)
CCB_API void     ccb_set_render3d_mode(int enabled, int same_level_only);
CCB_API int      ccb_copy_scene3d_snapshot(
    CcbScene3DHeader *out_header,
    CcbScene3DItem *out_items, int max_items,
    char *out_strings, int max_strings_bytes,
    CcbScene3DLight *out_lights, int max_lights);

#ifdef __cplusplus
}
#endif
