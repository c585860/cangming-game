extends RefCounted

const UI = preload("res://scripts/ui_theme.gd")
const NONE := Vector2i(-1, -1)
const TEXT := UI.INK_IVORY
const SOFT := UI.INK_SOFT


static func inventory(game: Control, contents: VBoxContainer, target: Vector2i) -> void:
	var bag: Array = game.world.inventory()
	var st: Dictionary = game.world.character_status()
	var destination: Vector2i = game.world.pos if target == NONE else target
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", UI.panel_box(UI.BG_CARD, UI.BORDER_JADE, 4, 10, 7, 1))
	contents.add_child(summary)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 3)
	summary.add_child(scol)
	game._label(scol, "铜钱  %d 文      清露草  %d 株      水壶  %d / %d ml" % [
		game.world.coins, game.world.herbs, game.world.bottle_water(), game.world.bottle_capacity()], 14, UI.GOLD)
	game._label(scol, "携带容积  %d / %d ml      总负重  %.2f kg      饱食：%s · 水分：%s" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)),
		float(st.get("carry_weight_g", 0)) / 1000.0,
		st.get("hunger_text", "正常"), st.get("thirst_text", "正常")], 12, SOFT)

	var list := ItemList.new()
	list.custom_minimum_size.y = 140
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.style_item_list(list)
	contents.add_child(list)
	for row: Dictionary in bag:
		var extra := ""
		if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
			extra = " · 热量%+d / 解渴%+d" % [int(row["kcal"]), int(row["quench"])]
		elif bool(row.get("is_clothing", false)):
			extra = " · %s · 保暖+%d · 容积+%d ml" % [row["slot"], int(row["warmth"]), int(row["storage_ml"])]
		list.add_item("  [%s] %s × %d  (%d ml · %d g%s)" % [
			row["category"], row["name"], int(row["count"]), int(row["volume_ml"]), int(row["weight_g"]), extra])
	if bag.is_empty():
		list.add_item("  行囊中暂无散装物品")
		list.set_item_disabled(0, true)

	var desc_lbl: Label = game._label(contents, "选择物品查看详情，可直接使用、穿戴或丢弃。", 12, UI.INK_DIM, true)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	contents.add_child(btn_row)

	var use_btn: Button = game._button(btn_row, "食用 / 穿戴", func():
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var row: Dictionary = bag[selected[0]]
		var id: int = int(row["id"])
		if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
			game._note(game.world.eat_item(id))
		elif bool(row.get("is_clothing", false)):
			game._note(game.world.wear_item(id))
			game.board.player_layer.queue_redraw()
		game._refresh()
		game._close_overlay()
		game._show_overlay("inventory", target), true)
	use_btn.disabled = true

	var transfer: Button = game._button(btn_row, "丢弃到脚下 (D)" if target == NONE else "放入选中容器", func():
		var selected := list.get_selected_items()
		if not selected.is_empty():
			var item: int = int(bag[selected[0]]["id"])
			game._note(game.world.place_item(destination, item))
			game.board.invalidate_world_cache()
			game._refresh()
			game._close_overlay()
			game._show_overlay("inventory", target))
	transfer.disabled = true

	list.item_selected.connect(func(i: int):
		if i < 0 or i >= bag.size():
			return
		var row: Dictionary = bag[i]
		desc_lbl.text = "%s：%s" % [row["name"], row.get("desc", "")]
		transfer.disabled = false
		var can_eat := bool(row.get("is_food", false)) or bool(row.get("is_drink", false))
		var can_wear := bool(row.get("is_clothing", false))
		use_btn.disabled = not (can_eat or can_wear)
		if can_eat:
			use_btn.text = "饮用 (E)" if bool(row["is_drink"]) else "食用 (E)"
		elif can_wear:
			use_btn.text = "穿戴 (W)"
		else:
			use_btn.text = "不可直接使用")


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
		game.board.invalidate_world_cache()
		game._refresh()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
