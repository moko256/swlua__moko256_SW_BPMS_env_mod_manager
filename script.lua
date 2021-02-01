-- SPDX-License-Identifier: MIT

-- SW_BPMS env mod manager
-- Created by @moko256

--[[
Target version: v1.0.32

Definitions:
- tile zero point: a global matrix to be (0,0,0) in local matrix in each tile.
- config addon: addon comopnents that have settings with specific tag. (tags: SW_BPMS_config_hide=addon_name1[|addon_name2..])
- label = icon + text
- building = (vehicle / object) that are spawned
- position: a building's global matrix
- field = an addon + locations
- spawning: whether field is spawning(not equal to simulating) or not

Comment type annotating format:
- List<T>:	table that the key is equal to index and the value type is T.
- List<K, V>: similar to map but K is equal to index.
- Map<K, V>: table that the key type is K and the value type is V.

--]]

g_savedata = {
	spawned_buildings = {}, -- List<Building>
	tile_zero_point = {}, -- List<tile_filename, MapPosition>
	fields_spawning = {}, -- List<addon_index, bool>
}

created = false
fields = {} -- List<field_ctrl_id, Field>

zero_matrix = nil -- matrix

function Field(addon_index, location_indexes, labels, name)
	return {
		addon_index = addon_index,
		location_indexes = location_indexes, -- List<location_index>
		labels = labels, -- List<Label>
		name = name,
	}
end

function LocalField(addon_index, location_indexes, labels, name)
	return {
		addon_index = addon_index,
		location_indexes = location_indexes, -- List<location_index>
		labels = labels, -- List<LocalLabel> ***differ from non-local
		name = name,
	}
end

function Building(building_id, building_type, addon_index)
	return {
		id = building_id,
		type = building_type,
		addon_index = addon_index,
	}
end

function Label(ui_id, icon, text, position)
	return {
		ui_id = ui_id,
		icon = icon,
		text = text,
		position = position, -- MapPosition
	}
end

function LocalLabel(ui_id, icon, text, position, tile_filename)
	return {
		ui_id = ui_id,
		icon = icon,
		text = text,
		position = position, -- MapPosition
		tile_filename = tile_filename, -- ***differ from non-local
	}
end

function MapPosition(x, z)
	return { x = x, z = z }
end

function showLabels(labels) -- List<Label>
	for labels_index, label in pairs(labels) do
		server.addMapLabel(-1, label.ui_id, label.icon, label.text, label.position.x, label.position.z)
	end
end

function hideLabels(labels)
	for labels_index, label in pairs(labels) do
		server.removeMapObject(-1, label.ui_id)
	end
end

function spawnField(field) -- Field
	for locations_loop_i, location_index in pairs(field.location_indexes) do
		server.spawnAddonLocation(zero_matrix, field.addon_index, location_index)
	end
	showLabels(field.labels)
end

function despawnBuilding(building) -- Building
	if building.type == "vehicle" then
		server.despawnVehicle(building.id, true)
	else
		server.despawnObject(building.id, true)
	end
end


function onCreate(is_world_create)
	zero_matrix = matrix.translation(0, 0, 0)
	local this_addon_index = server.getAddonIndex()
	
	local pattern_sw_bpms = "^[Ss][Ww]_[Bb][Pp][Mm][Ss]_"
	local pattern_sw_bpms_tag = "^SW_BPMS_([^=]+)=(.+)$"
	local pattern_int = "^[0-9]+$"
	
	local local_fields = {} -- List<Field>
	local config_hide = {} -- Map<addon_name, true>
	local tile_data = {} -- Map<tile_filename, location_index>
	
	for addon_index = 0, server.getAddonCount() - 1 do
		local addon_data = server.getAddonData(addon_index)
		local is_sw_bpms = string.match(addon_data.name, pattern_sw_bpms) ~= nil
		local local_locations = {} -- List<location_index>
		local local_labels = {} -- List<LocalLabel>

		for location_index = 0, addon_data.location_count - 1 do
			local location_data = server.getLocationData(addon_index, location_index)
			local is_env = location_data.env_mod
			
			if addon_index == this_addon_index then
				tile_data[location_data.tile] = location_index
			elseif is_sw_bpms ~= is_env then -- xor
				table.insert(local_locations, location_index)

				for component_index = 0, location_data.component_count - 1 do
					local component_data = server.getLocationComponentData(addon_index, location_index, component_index)
					local label_icon = 1 -- cross
					local cx, cy, cz = matrix.position(component_data.transform)
					local label_position = MapPosition(cx, cz)

					for tag_index, tag in pairs(component_data.tags) do
						local _, _, tag_operator, tag_value = string.find(tag, pattern_sw_bpms_tag)
						if tag_operator ~= nil and tag_value ~= nil then
							if tag_operator == "config_hide" then
								for tag_config_index, tag_config in pairs(string.split(tag_value, "|")) do
									local hide_addon_index, found = server.getAddonIndex(tag_config)
									if found then
										config_hide[hide_addon_index] = true
									end
								end
							elseif tag_operator == "map_icon" then
								local int_match = string.match(tag_value, pattern_int)
								if int_match ~= nil then
									label_icon = tonumber(int_match)
								end
							end
						end
					end

					if component_data.display_name ~= nil then
						table.insert(local_labels, LocalLabel(server.getMapID(), label_icon, component_data.display_name, label_position, location_data.tile))
					end
				end
			end
		end

		if #local_locations ~= 0 then
			table.insert(local_fields, LocalField(addon_index, local_locations, local_labels, addon_data.name))
			if is_world_create then
				g_savedata.fields_spawning[addon_index] = not is_sw_bpms
			end
		end
	end

	for local_fields_index, local_field in pairs(local_fields) do
		local labels = {}
		for local_labels_index, local_label in pairs(local_field.labels) do
			local tile_filename = local_label.tile_filename
			local map_position = g_savedata.tile_zero_point[tile_filename]
			if map_position == nil then
				local tile_location = tile_data[tile_filename]
				if tile_location ~= nil then
					local map_position_matrix = server.spawnAddonLocation(zero_matrix, this_addon_index, tile_location)
					local gx, gy, gz = matrix.position(map_position_matrix)
					g_savedata.tile_zero_point[tile_filename] = MapPosition(gx, gz)
				end
			end
			if map_position ~= nil then
				local mx, mz = local_label.position.x, local_label.position.z
				local gx, gz = map_position.x, map_position.z
				table.insert(labels, Label(local_label.ui_id, local_label.icon, local_label.text, MapPosition(mx+gx, mz+gz)))
			else
				server.removeMapID(-1, local_label.ui_id)
			end
		end
		table.insert(fields, Field(local_field.addon_index, local_field.location_indexes, labels, local_field.name))
	end

	if is_world_create then
		local addons_managing = {} -- Map<addon_index, true>
		for fields_index, field in pairs(fields) do
			addons_managing[field.addon_index] = true
		end

		for spawned_buildings_index = #g_savedata.spawned_buildings, 1, -1 do
			local spawned_building = g_savedata.spawned_buildings[spawned_buildings_index]
			if config_hide[spawned_building.addon_index] ~= nil then
				table.remove(g_savedata.spawned_buildings, spawned_buildings_index)
				despawnBuilding(spawned_building)
				g_savedata.fields_spawning[spawned_building.addon_index] = false
			elseif addons_managing[spawned_building.addon_index] == nil then
				table.remove(g_savedata.spawned_buildings, spawned_buildings_index)
			end
		end

		for field_ctrl_id, field in pairs(fields) do
			if config_hide[field.addon_index] == nil and g_savedata.fields_spawning[field.addon_index] == false then
				spawnField(field)
				g_savedata.fields_spawning[field.addon_index] = true
			end
		end
	end
	
	-- == TODO: consider making method to use in onPlayerJoin
	for fields_index, field in pairs(fields) do
		if g_savedata.fields_spawning[field.addon_index] then
			showLabels(field.labels)
		end
	end

	created = true
end


function onPlayerJoin(steam_id, name, peer_id, admin, auth)
	for fields_index, field in pairs(fields) do
		if g_savedata.fields_spawning[field.addon_index] then
			showLabels(field.labels)
		end
	end
end

function onSpawnAddonComponent(building_id, component_name, building_type, addon_index)
	local addon_contains = false
	for field_ctrl_id, field in pairs(fields) do
		if field.addon_index == addon_index then
			addon_contains = true
			break
		end
	end
	if (created and addon_contains) or (not created) then
		table.insert(g_savedata.spawned_buildings, Building(building_id, building_type, addon_index))
	end
end


function printf(fmt, ...)
	server.announce("printf", string.format(fmt, ...), -1)
end


-- Commands
function printToChat(peer_id, msg)
	server.announce("[?bm]", msg, peer_id)
end

function printToNotify(title, msg, type)
	server.notify(-1, title, msg, type)
end


function showField(field)
	if not g_savedata.fields_spawning[field.addon_index] then
		g_savedata.fields_spawning[field.addon_index] = true
		spawnField(field)
	end
end

function cmd_h(peer_id)
	printToChat(
		peer_id,
		"--- SW-BMPS Building Manager ---\n"
		.."?bm l              : display all buildings\n"
		.."?bm s a          : spawn all\n"
		.."?bm s [num] : spawn at num\n"
		.."?bm d a         : despawn all\n"
		.."?bm d [num]: despawn at num\n"
		.."?bm h            : display this help and exit"
	)
end

function cmd_l(peer_id)
	local msg = "List of managing:\n[num] O==spawned 'name'"
	for field_ctrl_id, field in ipairs(fields) do
		local status = nil
		if g_savedata.fields_spawning[field.addon_index] then
			status = "O"
		else
			status = "X"
		end
		msg = msg..string.format("\n[%d] %s '%s'", field_ctrl_id, status, field.name)
	end
	printToChat(peer_id, msg.."\nend")
end

function cmd_s_a(peer_id)
	printf("a")
	for _k, field in pairs(fields) do
		showField(field)
	end
	-- notify
end

function cmd_d_a(peer_id)
	printf("b")
	for _k, building in pairs(g_savedata.spawned_buildings) do
		despawnBuilding(building)
	end
	for _k, field in pairs(fields) do
		hideLabels(field.labels)
		g_savedata.fields_spawning[field.addon_index] = false
	end
	-- notify
end

function cmd_s_n(peer_id, args)
	printf("c")
	local field_ctrl_id = tonumber(args)
	if 1 <= field_ctrl_id and field_ctrl_id <= #fields then
		showField(fields[field_ctrl_id])
		-- notify
	end
end

function cmd_d_n(peer_id, args)
	printf("d")
	local field_ctrl_id = tonumber(args)
	if 1 <= field_ctrl_id and field_ctrl_id <= #fields then
		local field = fields[field_ctrl_id]
		local addon_index = field.addon_index
		for _k, building in pairs(g_savedata.spawned_buildings) do
			if building.addon_index == addon_index then
				despawnBuilding(building)
			end
		end
		hideLabels(field.labels)
		g_savedata.fields_spawning[addon_index] = false
	end
end

function cmd_x()
	--for debug
end

cmds = {
	{"l", cmd_l},
	{"s a", cmd_s_a},
	{"s ([0-9]+)", cmd_s_n},
	{"d a", cmd_d_a},
	{"d ([0-9]+)", cmd_d_n},
	{"h", cmd_h},
	{"x", cmd_x},
}

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, one, two, three, four, five)
	if command == "?d" then
		printf("~~")
		for k,v in pairs(fields) do
			printf("a %d %d %s", k, v.addon_index, v.name)
			for k,v in pairs(v.location_indexes) do
				printf("	l %d %d", k, v)
			end
			for k,v in pairs(v.labels) do
				printf("	m %d %d %s %d %d", v.ui_id, v.icon, v.text, v.position.x, v.position.y)
			end
		end
		for k,v in pairs(g_savedata.spawned_buildings) do
			printf("s %d %s %d", v.id, v.type, v.addon_index)
		end
	elseif command == "?bm" then
		local args = string.sub(full_message, 5, -1)
		printf(args)
		for _k, cmd in pairs(cmds) do
			local matches = string.match(args, "^%s-"..string.gsub(cmd[1], " ", "%%s-").."%s-$")
			if matches ~= nil then
				cmd[2](user_peer_id, matches)
				break
			end
		end
	end
end