default.chest = {}

-- support for MT game translation.
local S = default.get_translator

function default.chest.get_chest_formspec(pos, size)
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z
	-- Find widest and highest possible combination
	local fs_size = {
		x = math.max(size.x, 8),
		y = size.y + 5
	}
	-- Center the lists
	local x_chest  = (fs_size.x - size.x) / 2
	local x_player = (fs_size.x - 8) / 2
	local formspec = (
		"size[%i,%i]" ..
		"list[nodemeta:%s;main;%f,0.3;%i,%i;]" ..
		"list[current_player;main;%f,%f;8,1;]" ..
		"list[current_player;main;%f,%f;8,3;8]" ..
		"listring[nodemeta:%s;main]" ..
		"listring[current_player;main]"):format(
			fs_size.x, fs_size.y,
			spos, x_chest, size.x, size.y,
			x_player, size.y + 0.85,
			x_player, size.y + 2.08,
			spos) ..
		default.get_hotbar_bg(x_player, 0.85 + size.y)
	return formspec
end

function default.chest.chest_lid_obstructed(pos)
	local above = {x = pos.x, y = pos.y + 1, z = pos.z}
	local def = minetest.registered_nodes[minetest.get_node(above).name]
	-- allow ladders, signs, wallmounted things and torches to not obstruct
	if def and
			(def.drawtype == "airlike" or
			def.drawtype == "signlike" or
			def.drawtype == "torchlike" or
			(def.drawtype == "nodebox" and def.paramtype2 == "wallmounted")) then
		return false
	end
	return true
end

function default.chest.chest_lid_close(pn)
	local chest_open_info = default.chest.open_chests[pn]
	local pos = chest_open_info.pos
	local sound = chest_open_info.sound
	local swap = chest_open_info.swap

	default.chest.open_chests[pn] = nil
	for k, v in pairs(default.chest.open_chests) do
		if v.pos.x == pos.x and v.pos.y == pos.y and v.pos.z == pos.z then
			return true
		end
	end

	local node = minetest.get_node(pos)
	minetest.after(0.2, minetest.swap_node, pos, { name = "default:" .. swap,
			param2 = node.param2 })
	minetest.sound_play(sound, {gain = 0.3, pos = pos, max_hear_distance = 10})
end

default.chest.open_chests = {}

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "default:chest" then
		return
	end
	if not player or not fields.quit then
		return
	end
	local pn = player:get_player_name()

	if not default.chest.open_chests[pn] then
		return
	end

	default.chest.chest_lid_close(pn)
	return true
end)

minetest.register_on_leaveplayer(function(player)
	local pn = player:get_player_name()
	if default.chest.open_chests[pn] then
		default.chest.chest_lid_close(pn)
	end
end)

function default.chest.register_chest(name, d)
	local def = table.copy(d)
	def.drawtype = "mesh"
	def.visual = "mesh"
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.legacy_facedir_simple = true
	def.is_ground_content = false

	if not def.size then
		def.size = {x = 8, y = 4}
	end

	if def.protected then
		def.on_construct = function(pos)
			local meta = minetest.get_meta(pos)
			meta:set_string("infotext", "Locked Chest")
			meta:set_string("owner", "")
			local inv = meta:get_inventory()
			inv:set_size("main", def.size.x*def.size.y)
		end
		def.after_place_node = function(pos, placer)
			local meta = minetest.get_meta(pos)
			meta:set_string("owner", placer:get_player_name() or "")
			meta:set_string("infotext", "Locked Chest (owned by " ..
					meta:get_string("owner") .. ")")
		end
		def.can_dig = function(pos,player)
			local meta = minetest.get_meta(pos);
			local inv = meta:get_inventory()
			return inv:is_empty("main") and
					default.can_interact_with_node(player, pos)
		end
		def.allow_metadata_inventory_move = function(pos, from_list, from_index,
				to_list, to_index, count, player)
			if not default.can_interact_with_node(player, pos) then
				return 0
			end
			return count
		end
		def.allow_metadata_inventory_put = function(pos, listname, index, stack, player)
			if not default.can_interact_with_node(player, pos) then
				return 0
			end
			return stack:get_count()
		end
		def.allow_metadata_inventory_take = function(pos, listname, index, stack, player)
			if not default.can_interact_with_node(player, pos) then
				return 0
			end
			return stack:get_count()
		end
		def.on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
			if not default.can_interact_with_node(clicker, pos) then
				return itemstack
			end

			minetest.sound_play(def.sound_open, {gain = 0.3,
					pos = pos, max_hear_distance = 10})
			if not default.chest.chest_lid_obstructed(pos) then
				minetest.swap_node(pos,
						{ name = "default:" .. name .. "_open",
						param2 = node.param2 })
			end
			minetest.after(0.2, minetest.show_formspec,
					clicker:get_player_name(),
					"default:chest", default.chest.get_chest_formspec(pos, def.size))
			default.chest.open_chests[clicker:get_player_name()] = { pos = pos,
					sound = def.sound_close, swap = name }
		end
		def.on_blast = function() end
		def.on_key_use = function(pos, player)
			local secret = minetest.get_meta(pos):get_string("key_lock_secret")
			local itemstack = player:get_wielded_item()
			local key_meta = itemstack:get_meta()

			if itemstack:get_metadata() == "" then
				return
			end

			if key_meta:get_string("secret") == "" then
				key_meta:set_string("secret", minetest.parse_json(itemstack:get_metadata()).secret)
				itemstack:set_metadata("")
			end

			if secret ~= key_meta:get_string("secret") then
				return
			end

			minetest.show_formspec(
				player:get_player_name(),
				"default:chest_locked",
				default.chest.get_chest_formspec(pos)
			)
		end
		def.on_skeleton_key_use = function(pos, player, newsecret)
			local meta = minetest.get_meta(pos)
			local owner = meta:get_string("owner")
			local pn = player:get_player_name()

			-- verify placer is owner of lockable chest
			if owner ~= pn then
				minetest.record_protection_violation(pos, pn)
				minetest.chat_send_player(pn, "You do not own this chest.")
				return nil
			end

			local secret = meta:get_string("key_lock_secret")
			if secret == "" then
				secret = newsecret
				meta:set_string("key_lock_secret", secret)
			end

			return secret, "a locked chest", owner
		end
	else
		def.on_construct = function(pos)
			local meta = minetest.get_meta(pos)
			meta:set_string("infotext", "Chest")
			local inv = meta:get_inventory()
			inv:set_size("main", def.size.x*def.size.y)
		end
		def.can_dig = function(pos,player)
			local meta = minetest.get_meta(pos);
			local inv = meta:get_inventory()
			return inv:is_empty("main")
		end
		def.on_rightclick = function(pos, node, clicker)
			minetest.sound_play(def.sound_open, {gain = 0.3, pos = pos,
					max_hear_distance = 10})
			if not default.chest.chest_lid_obstructed(pos) then
				minetest.swap_node(pos, {
						name = "default:" .. name .. "_open",
						param2 = node.param2 })
			end
			minetest.after(0.2, minetest.show_formspec,
					clicker:get_player_name(),
					"default:chest", default.chest.get_chest_formspec(pos, def.size))
			default.chest.open_chests[clicker:get_player_name()] = { pos = pos,
					sound = def.sound_close, swap = name }
		end
		def.on_blast = function(pos)
			local drops = {}
			default.get_inventory_drops(pos, "main", drops)
			drops[#drops+1] = "default:" .. name
			minetest.remove_node(pos)
			return drops
		end
	end

	def.on_metadata_inventory_move = function(pos, from_list, from_index,
			to_list, to_index, count, player)
		minetest.log("action", player:get_player_name() ..
			" moves stuff in chest at " .. minetest.pos_to_string(pos))
	end
	def.on_metadata_inventory_put = function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name() ..
			" moves " .. stack:get_name() ..
			" to chest at " .. minetest.pos_to_string(pos))
	end
	def.on_metadata_inventory_take = function(pos, listname, index, stack, player)
		minetest.log("action", player:get_player_name() ..
			" takes " .. stack:get_name() ..
			" from chest at " .. minetest.pos_to_string(pos))
	end

	local def_opened = table.copy(def)
	local def_closed = table.copy(def)

	def_opened.mesh = "chest_open.obj"
	for i = 1, #def_opened.tiles do
		if type(def_opened.tiles[i]) == "string" then
			def_opened.tiles[i] = {name = def_opened.tiles[i], backface_culling = true}
		elseif def_opened.tiles[i].backface_culling == nil then
			def_opened.tiles[i].backface_culling = true
		end
	end
	def_opened.drop = "default:" .. name
	def_opened.groups.not_in_creative_inventory = 1
	def_opened.selection_box = {
		type = "fixed",
		fixed = { -1/2, -1/2, -1/2, 1/2, 3/16, 1/2 },
	}
	def_opened.can_dig = function()
		return false
	end
	def_opened.on_blast = function() end

	def_closed.mesh = nil
	def_closed.drawtype = nil
	def_closed.tiles[6] = def.tiles[5] -- swap textures around for "normal"
	def_closed.tiles[5] = def.tiles[3] -- drawtype to make them match the mesh
	def_closed.tiles[3] = def.tiles[3].."^[transformFX"

	minetest.register_node("default:" .. name, def_closed)
	minetest.register_node("default:" .. name .. "_open", def_opened)

	-- convert old chests to this new variant
	minetest.register_lbm({
		label = "update chests to opening chests",
		name = "default:upgrade_" .. name .. "_v2",
		nodenames = {"default:" .. name},
		action = function(pos, node)
			local meta = minetest.get_meta(pos)
			meta:set_string("formspec", nil)
			local inv = meta:get_inventory()
			local list = inv:get_list("default:chest")
			if list then
				inv:set_size("main", def.size.x*def.size.y)
				inv:set_list("main", list)
				inv:set_list("default:chest", nil)
			end
		end
	})
end

default.chest.register_chest("chest", {
	description = "Chest",
	tiles = {
		"default_chest_top.png",
		"default_chest_top.png",
		"default_chest_side.png",
		"default_chest_side.png",
		"default_chest_front.png",
		"default_chest_inside.png"
	},
	sounds = default.node_sound_wood_defaults(),
	sound_open = "default_chest_open",
	sound_close = "default_chest_close",
	groups = {choppy = 2, oddly_breakable_by_hand = 2},
})

default.chest.register_chest("chest_locked", {
	description = "Locked Chest",
	tiles = {
		"default_chest_top.png",
		"default_chest_top.png",
		"default_chest_side.png",
		"default_chest_side.png",
		"default_chest_lock.png",
		"default_chest_inside.png"
	},
	sounds = default.node_sound_wood_defaults(),
	sound_open = "default_chest_open",
	sound_close = "default_chest_close",
	groups = {choppy = 2, oddly_breakable_by_hand = 2},
	protected = true,
})
