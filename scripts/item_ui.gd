extends RefCounted

# Authentic CCB Classic Dark Terminal Inventory Screen ('i' / 'd' / 'D' / 'B') & Water Transfer Dialog.
# Includes category filtering and CCB clothing/bedding dismantling into cloth rags.

const CCB = preload("res://scripts/ccb_theme.gd")
const NONE := Vector2i(-1, -1)
const BAG_CATS := ["全部", "兵刃", "食粮", "茶水", "医药", "着装", "典籍", "器具", "杂物"]


static func inventory(game: Control, contents: VBoxContainer, target: Vector2i) -> void:
	var all_bag: Array = game.world.inventory()
	var st: Dictionary = game.world.character_status()
	var destination: Vector2i = game.world.pos if target == NONE else target
	var active_cat: String = str(game.inv_cat) if str(game.inv_cat) in BAG_CATS else "全部"

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 5, 1))
	contents.add_child(summary)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 2)
	summary.add_child(scol)
	game._label(scol, "手持:%s (破拆:%d)  |  铜钱:%d文  |  钱庄:%d文  |  水壶:%d/%d ml" % [
		str(st.get("wielded_text", "空手")), int(st.get("bash_power", 12)),
		int(game.world.coins), int(st.get("bank_coins", 0)),
		int(game.world.bottle_water()), int(game.world.bottle_capacity())], 12, CCB.C_YELLOW)
	game._label(scol, "容积:%d/%d ml  |  总重:%.2f kg  |  饱食:%s  |  保暖:%d  |  防雨:%d%%  |  累赘:%d" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500)),
		float(st.get("carry_weight_g", 0)) / 1000.0,
		str(st.get("hunger_text", "正常")),
		int(st.get("warmth", 0)), int(st.get("rain_resist", 0)), int(st.get("encumbrance", 0))], 12, CCB.C_LTGRAY)

	# Category filter bar (1-9)
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 4)
	contents.add_child(cat_row)
	for i in range(BAG_CATS.size()):
		var cat: String = BAG_CATS[i]
		var cb := func():
			game.inv_cat = cat
			game._reopen_overlay("inventory", target)
		var b: Button = game._button(cat_row, cat, cb, cat == active_cat)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey(str(i + 1), cb)

	var bag: Array = []
	for row: Dictionary in all_bag:
		var rcat: String = str(row.get("category", ""))
		if active_cat == "全部" or rcat == active_cat or (active_cat == "杂物" and rcat == "床品"):
			bag.append(row)

	var list := ItemList.new()
	list.custom_minimum_size.y = 175
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	CCB.style_item_list(list)
	contents.add_child(list)
	for i in range(bag.size()):
		var row: Dictionary = bag[i]
		var letter := CCB.letter_key(i)
		var extra := ""
		if bool(row.get("is_food", false)) or bool(row.get("is_drink", false)):
			extra = " | 热量%+d 解渴%+d" % [int(row["kcal"]), int(row["quench"])]
		elif bool(row.get("is_clothing", false)):
			extra = " | %s 保暖+%d 防雨+%d%% 容积+%dml" % [str(row["slot"]), int(row["warmth"]), int(row.get("rain_resist", 0)), int(row["storage_ml"])]
		elif bool(row.get("is_weapon", false)) or int(row.get("bash_dmg", 0)) >= 6:
			extra = " | 威力+%d" % int(row["bash_dmg"])
		list.add_item(" %s - [%s] %s x%d  (%d ml, %d g%s)" % [
			letter, str(row["category"]), str(row["name"]), int(row["count"]),
			int(row["volume_ml"]), int(row["weight_g"]), extra])
	if bag.is_empty():
		list.add_item("  (当前分类下暂无物品)")
		list.set_item_disabled(0, true)

	var desc_lbl: Label = game._label(contents, "点选物品查看详情；1-9 切换分类；可用下方按钮或快捷键 (E吃 / W穿 / w持 / a用 / R精读 / B拆布 / d丢)。", 12, CCB.C_LTGRAY, true)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	contents.add_child(btn_row)

	var use_btn: Button = game._button(btn_row, "使用 / 食用 / 穿戴", func():
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
		elif bool(row.get("is_book", false)):
			game._close_overlay()
			game._start_study_book(id, str(row["name"]))
			return
		elif bool(row.get("is_tool", false)) or bool(row.get("is_medical", false)) or str(row.get("key", "")) == "towel":
			game._note(game.world.apply_item(id))
			game.board.player_layer.queue_redraw()
		game._refresh()
		game._reopen_overlay("inventory", target), true)
	use_btn.disabled = true

	var wield_btn: Button = game._button(btn_row, "手持 (w)", func():
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var id: int = int(bag[selected[0]]["id"])
		game._note(game.world.wield_item(id))
		game._refresh()
		game._reopen_overlay("inventory", target))
	wield_btn.disabled = true

	var dismantle_btn: Button = game._button(btn_row, "拆解布条 (B)", func():
		var selected := list.get_selected_items()
		if selected.is_empty():
			return
		var id: int = int(bag[selected[0]]["id"])
		game._note(game.world.dismantle_item(id))
		game._refresh()
		game._reopen_overlay("inventory", target))
	dismantle_btn.disabled = true

	var transfer: Button = game._button(btn_row, "丢弃到脚下 (d)" if target == NONE else "放到 (%d,%d)" % [destination.x, destination.y], func():
		var selected := list.get_selected_items()
		if not selected.is_empty():
			var item: int = int(bag[selected[0]]["id"])
			game._note(game.world.place_item(destination, item))
			game.board.invalidate_world_cache()
			game._refresh()
			game._reopen_overlay("inventory", target))
	transfer.disabled = true

	list.item_selected.connect(func(i: int):
		if i < 0 or i >= bag.size():
			return
		var row: Dictionary = bag[i]
		desc_lbl.text = "%s：%s" % [str(row["name"]), str(row.get("desc", ""))]
		transfer.disabled = false
		wield_btn.disabled = false
		var can_eat := bool(row.get("is_food", false)) or bool(row.get("is_drink", false))
		var can_wear := bool(row.get("is_clothing", false))
		var can_book := bool(row.get("is_book", false))
		var can_apply := bool(row.get("is_tool", false)) or bool(row.get("is_medical", false)) or str(row.get("key", "")) == "towel"
		var can_tear := can_wear or str(row.get("category", "")) == "床品" or str(row.get("key", "")) == "towel"
		dismantle_btn.disabled = not can_tear
		use_btn.disabled = not (can_eat or can_wear or can_book or can_apply)
		if can_eat:
			use_btn.text = "饮用 (E)" if bool(row["is_drink"]) else "食用 (E)"
		elif can_wear:
			use_btn.text = "穿戴 (W)"
		elif can_book:
			use_btn.text = "精读 (R)"
		elif can_apply:
			use_btn.text = "使用 (a)"
		else:
			use_btn.text = "不可激活")

	for i in range(mini(bag.size(), 52)):
		var letter := CCB.letter_key(i)
		var row_idx := i
		game.register_overlay_hotkey(letter, func():
			if target != NONE:
				var item: int = int(bag[row_idx]["id"])
				game._note(game.world.place_item(destination, item))
				game.board.invalidate_world_cache()
				game._refresh()
				game._reopen_overlay("inventory", target)
			else:
				list.select(row_idx)
				list.item_selected.emit(row_idx))


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
	game._label(body, "容器: %d / %d ml    水壶: %d / %d ml" % [available, limit, bottle, bottle_limit], 13, CCB.C_WHITE)
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = max_ml
	amount.value = max_ml
	amount.suffix = "ml"
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
