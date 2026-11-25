extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const NONE := Vector2i(-1, -1)
const TEXT := UI.INK_IVORY
const SOFT := UI.INK_SOFT


static func inventory(game: Control, contents: VBoxContainer, target: Vector2i) -> void:
	var bag: Array = game.world.inventory()
	var destination: Vector2i = game.world.pos if target == NONE else target
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 10, 7, 1))
	contents.add_child(summary)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 3)
	summary.add_child(scol)
	game._label(scol, "铜钱  %d 文      清露草  %d 株" % [game.world.coins, game.world.herbs], 15, UI.GOLD)
	game._label(scol, "行囊水壶  %d / %d 毫升" % [game.world.bottle_water(), game.world.bottle_capacity()], 14, SOFT)
	var list := ItemList.new()
	list.custom_minimum_size.y = 96
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.style_item_list(list)
	contents.add_child(list)
	for row: Dictionary in bag:
		list.add_item("  %s  × %d" % [row["name"], row["count"]])
	if bag.is_empty():
		list.add_item("  行囊中暂无散装物品")
		list.set_item_disabled(0, true)
	var transfer: Button = game._button(contents, "放下选中物品" if target == NONE else "放入选中物品", func():
		var selected := list.get_selected_items()
		if not selected.is_empty():
			var item: int = bag[selected[0]]["id"]
			game._note(game.world.place_item(destination, item))
			game._close_overlay()
			game._show_overlay("inventory", target), true)
	transfer.disabled = true
	list.item_selected.connect(func(_i: int): transfer.disabled = false)


static func water(game: Control, p: Vector2i, fill: bool) -> void:
	var limit: int = game.world.water_capacity_at(p)
	var available: int = game.world.water_at(p)
	var bottle: int = game.world.bottle_water()
	var bottle_limit: int = game.world.bottle_capacity()
	var max_ml := mini(available, bottle_limit - bottle) if fill else mini(bottle, limit - available)
	if not game.world.near(p) or max_ml <= 0:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "装入水壶" if fill else "从水壶倒入"
	dialog.ok_button_text = "确定"
	dialog.cancel_button_text = "取消"
	dialog.theme = game.theme
	dialog.exclusive = true
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(286, 74)
	dialog.add_child(body)
	game._label(body, "容器：%d / %d 毫升    水壶：%d / %d 毫升" % [available, limit, bottle, bottle_limit], 14, TEXT)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = max_ml
	amount.value = max_ml
	amount.suffix = "毫升"
	body.add_child(amount)
	game.add_child(dialog)
	dialog.confirmed.connect(func():
		amount.apply()
		game._note(game.world.transfer_water(p, int(amount.value), fill))
		game._refresh()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
