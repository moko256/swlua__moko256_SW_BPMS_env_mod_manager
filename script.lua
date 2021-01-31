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


function despawnBuilding(building) -- Building
	if building.type == "vehicle" then
		server.despawnVehicle(building.building_id, true)
	else
		server.despawnObject(building.building_id, true)
	end
end


function onCreate(is_world_create)
	zero_matrix = matrix.translation(0, 0, 0)
	local this_addon_index = server.getAddonIndex()
	
	local patter_sw_bpms = "SW_BPMS_|sw_bpms_"
	local pattern_sw_bpms_tag = "^SW_BPMS_(.+?)=(.*)$", "i"
	local pattern_int = "^[0-9].+$"
	
	local local_fields = {} -- List<Field>
	local config_hide = {} -- List<addon_name>
	local tile_data = {} -- Map<tile_filename, location_index>
	
	for addon_index = 0, server.getAddonCount() - 1 do
		local addon_data = server.getAddonData(addon_index)
		local is_sw_bpms = string.match(addon_data.name, patter_sw_bpms) ~= nil
		local local_locations = {} -- List<location_index>
		local local_labels = {} -- List<Label>

		for location_index = 0, addon_data.location_count - 1 do
			local location_data = server.getLocationData(addon_index, location_index)
			local is_env = location_data.env_mod
			
			if addon_index == this_addon_index then
				tile_data[location_data.tile] = location_index
			elseif is_sw_bpms ~= not is_env then -- xor
				table.insert(local_locations, location_index)

				for component_index = 0, location_data.component_count - 1 do
					local component_data = server.getLocationComponentData(addon_index, location_index, component_index)
					local label_icon = 1 -- cross

					for tag_index, tag in pairs(component_data.tags) do
						local tag_matches = string.match(tag, pattern_sw_bpms_tag)
						if tag_matches ~= nil then
							local tag_operator, tag_value = tag_matches
							if tag_operator == "config_hide" then
								for tag_config_index, tag_config in pairs(string.split(tag_value, "|")) do
									table.insert(config_hide, tag_config)
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
			g_savedata.fields_spawning[addon_index] = not is_sw_bpms
		end
	end

	for local_fields_index, local_field in pairs(local_fields) do
		local labels = {}
		for local_labels_index, local_label in pairs(local_field.labels) do
			local tile_filename = local_label.tile_filename
			local map_position = g_savedata.tile_zero_point[tile_filename]
			if map_position == nil then
				local map_position_matrix = server.spawnAddonLocation(zero_matrix, this_addon_index, tile_data[tile_filename])
				local gx, gy, gz = matrix.position(map_position_matrix)
				g_savedata.tile_zero_point[tile_filename] = MapPosition(gx, gz)
			end
			if map_position ~= nil then
				local mx, mz = local_label.position
				local gx, gz = map_position
				table.insert(labels, Label(local_label.ui_id, local_label.icon, local_label.text, MapPosition(mx+gx, mz+gz)))
			else
				server.removeMapID(-1, local_label.ui_id)
			end
		end
		table.insert(fields, Field(local_field.addon_index, local_field.location_indexes, local_field.labels, local_field.name))
	end

	if is_world_create then
		local is_spawned_addons = {} -- Map<addon_index, true>
		for spawned_buildings_index, spawned_building in pairs(g_savedata.spawned_buildings) do
			spawned_addon_locations[spawned_building.addon_index] = true
		end
		for fields_index, field in pairs(fields) do
			is_spawned_addons[field.addon_index] = nil
		end
		for spawned_addons_index, is_spawned_addon in pairs(is_spawned_addons) do
			for spawned_buildings_index = #g_savedata.spawned_buildings, 1, -1 do
				if g_savedata.spawned_buildings[spawned_buildings_index].addon_index == spawned_addons_index then
					table.remove(g_savedata.spawned_buildings, spawned_buildings_index)
				end
			end
		end

		for config_hide_index, hide_addon_name in pairs(config_hide) do
			local hide_addon_index, found = server.getAddonIndex(hide_addon_name)
			if found then
				for spawned_buildings_index = #g_savedata.spawned_buildings, 1, -1 do
					local spawned_building = g_savedata.spawned_buildings[spawned_buildings_index]
					if hide_addon_index == spawned_building.addon_index then
						despawnBuilding(spawned_building)
						table.remove(g_savedata.spawned_buildings, spawned_buildings_index)
						g_savedata.fields_spawning[field.addon_index] = false
					end
				end
			end
		end
	end
	
	-- == TODO: consider making method to use in onPlayerJoin
	for fields_index, field in pairs(fields) do
		if g_savedata.fields_spawning[field.addon_index] then
			for labels_index, label in pairs(field.labels) do
				server.addMapLabel(-1, label.ui_id, label.type, label.text, label.position.x, label.position.z)
			end
		end
	end

	created = true
end


function onPlayerJoin(steam_id, name, peer_id, admin, auth)
end

function onSpawnAddonComponent(building_id, component_name, building_type, addon_index)
end

function onCustomCommand(full_message, user_peer_id, is_admin, is_auth, command, one, two, three, four, five)
	if command == "?bm" then
	end
end