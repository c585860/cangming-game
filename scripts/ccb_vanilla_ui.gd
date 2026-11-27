extends RefCounted

# Thin Dispatcher Facade for Modular Pure-Vanilla CCB UI Modules under scripts/ccb/

const InvUI = preload("res://scripts/ccb/inventory_ui.gd")
const PickupUI = preload("res://scripts/ccb/pickup_ui.gd")
const CharUI = preload("res://scripts/ccb/character_ui.gd")
const CraftUI = preload("res://scripts/ccb/craft_ui.gd")
const OvermapUI = preload("res://scripts/ccb/overmap_ui.gd")
const ArmorUI = preload("res://scripts/ccb/armor_layers_ui.gd")
const AdvInvUI = preload("res://scripts/ccb/advanced_inv_ui.gd")
const NearbyUI = preload("res://scripts/ccb/nearby_ui.gd")
const DebugUI = preload("res://scripts/ccb/debug_ui.gd")
const Menus = preload("res://scripts/ccb_vanilla_menus.gd")


static func inventory_panel(game: Control, contents: VBoxContainer) -> void: InvUI.inventory_panel(game, contents)
static func pickup_menu(game: Control, contents: VBoxContainer, target := Vector2i(-1, -1)) -> void: PickupUI.build(game, contents, target)
static func bio_mutation_panel(game: Control, contents: VBoxContainer) -> void: CharUI.build(game, contents)
static func craft_panel(game: Control, contents: VBoxContainer) -> void: CraftUI.build(game, contents)
static func overmap_panel(game: Control, contents: VBoxContainer) -> void: OvermapUI.build(game, contents)
static func armor_layers_panel(game: Control, contents: VBoxContainer) -> void: ArmorUI.build(game, contents)
static func advanced_inv_panel(game: Control, contents: VBoxContainer) -> void: AdvInvUI.build(game, contents)
static func list_nearby_menu(game: Control, contents: VBoxContainer) -> void: NearbyUI.list_nearby(game, contents)
static func debug_menu_panel(game: Control, contents: VBoxContainer) -> void: DebugUI.build(game, contents)

static func eat_menu(game: Control, contents: VBoxContainer) -> void: InvUI.eat_menu(game, contents)
static func wear_menu(game: Control, contents: VBoxContainer) -> void: InvUI.wear_menu(game, contents)
static func take_off_menu(game: Control, contents: VBoxContainer) -> void: InvUI.take_off_menu(game, contents)
static func wield_menu(game: Control, contents: VBoxContainer) -> void: InvUI.wield_menu(game, contents)
static func apply_menu(game: Control, contents: VBoxContainer) -> void: InvUI.apply_menu(game, contents)
static func read_menu(game: Control, contents: VBoxContainer) -> void: InvUI.read_menu(game, contents)
static func butcher_menu(game: Control, contents: VBoxContainer) -> void: InvUI.butcher_menu(game, contents)

static func action_menu_panel(game: Control, contents: VBoxContainer) -> void: Menus.action_menu_panel(game, contents)
static func pause_menu_panel(game: Control, contents: VBoxContainer) -> void: Menus.pause_menu_panel(game, contents)
static func sidebar_manager_panel(game: Control, contents: VBoxContainer) -> void: Menus.sidebar_manager_panel(game, contents)
static func tileset_options_panel(game: Control, contents: VBoxContainer) -> void: Menus.tileset_options_panel(game, contents)
static func help_panel(game: Control, contents: VBoxContainer) -> void: Menus.help_panel(game, contents)
static func missions_panel(game: Control, contents: VBoxContainer) -> void: Menus.missions_panel(game, contents)
static func build_look_inspector_text(world: RefCounted, target: Vector2i) -> String: return Menus.build_look_inspector_text(world, target)
