extends RefCounted

# Classic Wuxia MUD × CCB Market, Pawnshop, Bank & Inn UI Panel.
# Services:
#  1 = Merchant (Buy + Sell surplus), 2 = Pawnshop (Sell/Pawn), 3 = Bank (Deposit/Withdraw), 4 = Inn (Rent 2F room + Tea/Buns)

const CCB = preload("res://scripts/ccb_theme.gd")


static func open_panel(game: Control, contents: VBoxContainer, npc_pos: Vector2i) -> void:
	var world: Object = game.world
	var info: Dictionary = world.shop_info_at(npc_pos)
	if info.is_empty():
		game._label(contents, "此处暂无商贸服务。", 13, CCB.C_DKGRAY)
		return
	var svc: int = int(info.get("service", 0))
	var npc_name: String = str(info.get("npc_name", "掌柜"))
	var title: String = str(info.get("title", "铺面"))
	var coins: int = int(info.get("coins", world.coins))
	var bank_coins: int = int(info.get("bank_coins", 0))
	var inn_active: bool = bool(info.get("inn_active", false))

	var banner := PanelContainer.new()
	banner.add_theme_stylebox_override("panel", CCB.box(CCB.BG_HEADER, CCB.BORDER, 8, 6, 1))
	contents.add_child(banner)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 2)
	banner.add_child(bcol)
	game._label(bcol, "%s（%s）  |  随身铜钱: %d 文  |  通济钱庄存银: %d 文" % [title, npc_name, coins, bank_coins], 13, CCB.C_YELLOW)
	var st: Dictionary = world.character_status()
	game._label(bcol, "行囊容积: %d / %d ml  |  按对应字母快速交易，按 Esc 关闭" % [
		int(st.get("carry_volume_ml", 0)), int(st.get("max_carry_volume_ml", 2500))
	], 11, CCB.C_LTGRAY)

	# --- BANK SERVICE (通济钱庄) ---
	if svc == 3:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		contents.add_child(box)
		game._label(box, "[ 通济钱庄 · 银钱存取 ]", 13, CCB.C_CYAN)
		var specs := [
			["a", "存入 10 文铜钱", true, 10],
			["b", "存入 50 文铜钱", true, 50],
			["c", "存入全部随身铜钱 (%d 文)" % coins, true, maxi(1, coins)],
			["d", "取出 10 文铜钱", false, 10],
			["e", "取出 50 文铜钱", false, 50],
			["f", "取出全部钱庄存银 (%d 文)" % bank_coins, false, maxi(1, bank_coins)],
		]
		for spec: Array in specs:
			var key: String = str(spec[0])
			var label: String = "%s - %s" % [key, str(spec[1])]
			var is_dep: bool = bool(spec[2])
			var amt: int = int(spec[3])
			var cb := func():
				var msg: String = world.bank_deposit(npc_pos, amt) if is_dep else world.bank_withdraw(npc_pos, amt)
				game._note(msg)
				game._play_sfx("coin")
				game._refresh()
				game._reopen_overlay("shop", npc_pos)
			var btn: Button = game._button(box, label, cb, is_dep and coins > 0)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			game.register_overlay_hotkey(key, cb)
		return

	# --- INN GUESTROOM BANNER (悦来客栈) ---
	if svc == 4:
		var inn_row := HBoxContainer.new()
		inn_row.add_theme_constant_override("separation", 8)
		contents.add_child(inn_row)
		var inn_txt := "[R] 悦来客栈二楼上房：已开房（卧榻恢复翻倍且驱寒）" if inn_active else "[R] 花费 5 文铜钱租下二楼上房（24时辰内卧榻恢复翻倍+驱寒）"
		var rent_cb := func():
			game._note(world.rent_inn_room_at(npc_pos))
			game._play_sfx("coin")
			game._refresh()
			game._reopen_overlay("shop", npc_pos)
		var rbtn: Button = game._button(inn_row, inn_txt, rent_cb, not inn_active)
		rbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey("R", rent_cb)

	# --- BUY / SELL TAB TOGGLE (Merchant vs Pawn) ---
	var mode: String = str(game.shop_mode) if str(game.shop_mode) in ["buy", "sell"] else "buy"
	if svc == 2:
		mode = "sell"
	else:
		var tab_row := HBoxContainer.new()
		tab_row.add_theme_constant_override("separation", 6)
		contents.add_child(tab_row)
		var b_cb := func():
			game.shop_mode = "buy"
			game._reopen_overlay("shop", npc_pos)
		var s_cb := func():
			game.shop_mode = "sell"
			game._reopen_overlay("shop", npc_pos)
		var bb: Button = game._button(tab_row, "[1] 选购铺面货品", b_cb, mode == "buy")
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb: Button = game._button(tab_row, "[2] 出售行囊物品", s_cb, mode == "sell")
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.register_overlay_hotkey("1", b_cb)
		game.register_overlay_hotkey("2", s_cb)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	contents.add_child(scroll)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 4)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	if mode == "buy":
		var stock: Array = info.get("items", [])
		if stock.is_empty():
			game._label(list_box, "此铺面暂无上架货品。", 12, CCB.C_DKGRAY)
			return
		for i in range(stock.size()):
			var row: Dictionary = stock[i]
			var item_id: int = int(row.get("id", -1))
			var price: int = int(row.get("price", 1))
			var letter := CCB.letter_key(i)
			var afford := coins >= price
			var txt := "%s - [%s] %s  —  %d 文   (%s)" % [
				letter, str(row.get("category", "")), str(row.get("name", "")), price, str(row.get("desc", ""))
			]
			var buy_cb := func():
				game._note(world.buy_item_from(npc_pos, item_id))
				game._play_sfx("coin")
				game._refresh()
				game._reopen_overlay("shop", npc_pos)
			var btn: Button = game._button(list_box, txt, buy_cb, afford)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not afford:
				btn.add_theme_color_override("font_color", CCB.C_DKGRAY)
			if letter != "-":
				game.register_overlay_hotkey(letter, buy_cb)
	else:
		var bag: Array = world.inventory()
		if bag.is_empty():
			game._label(list_box, "行囊为空，暂无可典当或出售的物品。", 12, CCB.C_DKGRAY)
			return
		for i in range(bag.size()):
			var row: Dictionary = bag[i]
			var item_id: int = int(row.get("id", -1))
			var bp: int = int(row.get("base_price", 2))
			var est: int = maxi(1, int(round(float(bp) * (0.55 if svc == 2 else 0.44))))
			var letter := CCB.letter_key(i)
			var txt := "%s - [%s] %s x%d  —  估价约 %d 文" % [
				letter, str(row.get("category", "")), str(row.get("name", "")), int(row.get("count", 1)), est
			]
			var sell_cb := func():
				game._note(world.sell_item_to(npc_pos, item_id))
				game._play_sfx("coin")
				game._refresh()
				game._reopen_overlay("shop", npc_pos)
			var btn: Button = game._button(list_box, txt, sell_cb, true)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if letter != "-":
				game.register_overlay_hotkey(letter, sell_cb)
