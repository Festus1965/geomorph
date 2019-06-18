-- Geomorph init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


local mod = geomorph
local mod_name = 'geomorph'
local math_min = math.min
local math_max = math.max
local math_floor = math.floor


local null_vector = {x = 1, y = 1, z = 1}
local ladder_transform = { [0] = 4, 2, 5, 3 }


local action_names = {
	cube = true,
	cylinder = true,
	ladder = true,
	puzzle = true,
	sphere = true,
	stair = true,
}


local stone_types = {
	{'default:cobble', 'default:stonebrick', 'default:stone', 'default:stoneblock'},
	{'default:desert_cobble', 'default:desert_stonebrick', 'default:desert_stone', 'default:desert_stone_block'},
	{'default:sandstonebrick', 'default:sandstonebrick', 'default:sandstone', 'default:sandstone_block'},
	{'default:desert_sandstone_brick', 'default:desert_sandstone_brick', 'default:desert_sandstone', 'default:desert_sandstone_block'},
	{'default:silver_sandstone_brick', 'default:silver_sandstone_brick', 'default:silver_sandstone', 'default:silver_sandstone_block'},
}


function vector.max(v1, v2)
	if type(v1) == 'number' then
		v1 = vector.new(v1, v1, v1)
	end

	if type(v2) == 'number' then
		v2 = vector.new(v2, v2, v2)
	end

	local v3 = vector.new(0, 0, 0)
	v3.x = math_max(v1.x, v2.x)
	v3.y = math_max(v1.y, v2.y)
	v3.z = math_max(v1.z, v2.z)
	return v3
end


function vector.min(v1, v2)
	if type(v1) == 'number' then
		v1 = vector.new(v1, v1, v1)
	end

	if type(v2) == 'number' then
		v2 = vector.new(v2, v2, v2)
	end

	local v3 = vector.new(0, 0, 0)
	v3.x = math_min(v1.x, v2.x)
	v3.y = math_min(v1.y, v2.y)
	v3.z = math_min(v1.z, v2.z)
	return v3
end


function mod.rotate_coords(item, rot, csize)
	local min = table.copy(null_vector)
	local max = table.copy(null_vector)

	if rot == 0 then
		min.x = item.location.x
		max.x = item.location.x + item.size.x - 1
		min.z = item.location.z
		max.z = item.location.z + item.size.z - 1
	elseif rot == 1 then
		min.x = item.location.z
		max.x = item.location.z + item.size.z - 1
		min.z = csize.x - (item.location.x + item.size.x)
		max.z = csize.x - item.location.x - 1
	elseif rot == 2 then
		min.x = csize.x - (item.location.x + item.size.x)
		max.x = csize.x - item.location.x - 1
		min.z = csize.z - (item.location.z + item.size.z)
		max.z = csize.z - item.location.z - 1
	elseif rot == 3 then
		min.x = csize.z - (item.location.z + item.size.z)
		max.x = csize.z - item.location.z - 1
		min.z = item.location.x
		max.z = item.location.x + item.size.x - 1
	end

	min.y = item.location.y
	max.y = item.location.y + item.size.y - 1

	min = vector.max(0, min)
	max = vector.min(vector.add(csize, -1), max)

	return min, max
end
local rotate_coords = mod.rotate_coords


---------------
-- Geomorph class
---------------
local Geomorph = {}
Geomorph.__index = Geomorph
Geomorph.action_names = action_names


function Geomorph.new(description)
	local self = setmetatable({
		shapes = {},
	}, Geomorph)

	if description then
		self.areas = description.areas
		self.base_heat = description.base_heat
		self.base_humidity = description.base_humidity
		self.name = description.name

		if description.data then
			for _, i in ipairs(description.data) do
				self:add(i)
			end
		end
	end

	return self
end
mod.Geomorph = Geomorph


function Geomorph:create_shape(t)
	local action = t.act or t.action
	local location = t.loc or t.location
	local lining = t.line or t.lining
	local param2 = t.p2 or t.param2

	local intersect = t.intersect
	if type(intersect) == 'string' then
		intersect = { [minetest.get_content_id(t.intersect)] = true }
	elseif type(intersect) == 'table' then
		local t2 = {}
		local con
		for n, v in pairs(intersect) do
			if type(v) == 'string' then
				t2[minetest.get_content_id(v)] = true
				con = true
			end
		end
		if con then
			intersect = t2
		end
	end

	if not action then
		return
	end

	if action_names[action] then
		if not (location and t.size and (action == 'puzzle' or t.node)) then
			return
		end
	else
		print(mod_name .. ': can\'t create a ' .. action)
		return
	end

	if action_names[action] then
		local shape = {
			action = action,
			axis = t.axis,
			chance = t.chance,
			clear_up = t.clear_up,
			depth = t.depth,
			depth_fill = t.depth_fill,
			floor = t.floor,
			height = t.height,
			hollow = t.hollow,
			intersect = intersect,
			lining = lining,
			location = location,
			node = t.node,
			param2 = param2,
			random = t.random,
			size = t.size,
			underground = t.underground,
		}

		return shape
	end
end


function Geomorph:add(t)
	local shape = self:create_shape(t)
	if shape then
		table.insert(self.shapes, shape)
	end
end


function Geomorph:write_to_map(mgen, rot, replace)
	if not rot then
		rot = mgen.gpr:next(0, 3)
	end

	if replace and type(replace) ~= 'table' then
		print(mod_name .. ': bad replace')
		return
	end

	for _, shape in ipairs(self.shapes) do
		local copy

		-- linings - fills the surface of the volume
		if shape.lining then
			copy = table.copy(shape)
			copy.location = vector.add(copy.location, -1)
			copy.size = vector.add(copy.size, 2)
			copy.node = shape.lining
			--copy.potholes = potholes and potholes
			--copy.stain = copy.stain or cobble
			copy.hollow = 5
			--print(dump(copy))
			self:write_shape(copy, mgen, rot)
		end

		if shape.floor
		and (
			shape.action == 'cube'
			or (
				shape.action == 'cylinder'
				and (shape.axis == 'y' or shape.axis == 'Y')
			)
		) then
			copy = table.copy(shape)
			copy.location = table.copy(copy.location)
			copy.location.y = copy.location.y - 1
			copy.size = table.copy(copy.size)
			copy.size.y = 1
			copy.node = shape.floor
			--copy.potholes = potholes and potholes
			--copy.stain = copy.stain or cobble
			self:write_shape(copy, mgen, rot)
		end

		if replace and replace[shape.node] then
			copy = table.copy(shape)
			copy.node = replace[shape.node]
			self:write_shape(copy, mgen, rot)
		else
			self:write_shape(shape, mgen, rot)
		end
	end
end


function Geomorph:write_shape(shape, mgen, rot)
	if not rot then
		print(mod_name .. ': can\'t write without rotation.')
	end

	if shape.action == 'cube' then
		self:write_cube(shape, mgen, rot)
	elseif shape.action == 'cylinder' then
		self:write_cylinder(shape, mgen, rot)
	elseif shape.action == 'ladder' then
		self:write_ladder(shape, mgen, rot)
	elseif shape.action == 'sphere' then
		self:write_sphere(shape, mgen, rot)
	elseif shape.action == 'stair' then
		self:write_stair(shape, mgen, rot)
	elseif shape.action == 'puzzle' then
		self:write_puzzle(shape, mgen, rot)
	else
		print(mod_name .. ': can\'t create a ' .. shape.action)
	end
end


function Geomorph:write_cube(shape, mgen, rot)
	local area = mgen.area
	local csize = mgen.csize
	local data = mgen.data
	local heightmap = mgen.heightmap
	local minp = mgen.minp
	local p2data = mgen.p2data
	local ystride = mgen.area.ystride

	local min, max = rotate_coords(shape, rot, csize)
	local node_num = mgen.node[shape.node]
	local underground = shape.underground
	local hollow = shape.hollow
	local random = shape.random
	local intersect = shape.intersect

	local n_air = mgen.node['air']

	local p2 = shape.param2
	if p2 then
		local rp2 = p2 % 32
		local extra = math_floor(p2 / 32)
		p2 = (rp2 + rot) % 4 + extra * 32
	end

	local hmin, hmax
	if hollow then
		hmin = vector.add(min, hollow)
		hmax = vector.subtract(max, hollow)
	end

	for z = min.z, max.z do
		local index = z * csize.x + min.x + 1
		local hollow_z_good = (not hollow or z <= hmin.z or z >= hmax.z)
		for x = min.x, max.x do
			local hollow_x_good = (not hollow or x <= hmin.x or x >= hmax.x)
			local ivm = area:index(minp.x + x, minp.y + min.y, minp.z + z)
			local top_y = max.y

			if underground then
				local height = heightmap[index]
				if height then
					top_y = math_min(max.y, height - underground)
				end
			end
			if shape.height then
				top_y = math_min(top_y, min.y + shape.height)
			end

			for y = min.y, top_y do
				local hollow_y_good = (not hollow or y <= hmin.y or y >= hmax.y)
				local ok = (hollow_z_good or hollow_x_good or hollow_y_good)
				ok = (ok and (not random or mgen.gpr:next(1, math_max(1, random)) == 1))

				if ok then
					if not intersect
					or (type(intersect) == 'table' and intersect[data[ivm]])
					or (intersect == true and data[ivm] ~= n_air) then
						data[ivm] = node_num
						p2data[ivm] = p2
					end
				end

				ivm = ivm + ystride
			end

			index = index + 1
		end
	end
end


function Geomorph:write_sphere(shape, mgen, rot)
	local area = mgen.area
	local csize = mgen.csize
	local data = mgen.data
	local heightmap = mgen.heightmap
	local minp = mgen.minp
	local p2data = mgen.p2data
	local ystride = mgen.area.ystride

	local min, max = rotate_coords(shape, rot, csize)
	local node_num = mgen.node[shape.node]
	local underground = shape.underground
	local intersect = shape.intersect
	local random = shape.random

	local n_air = mgen.node['air']

	local p2 = shape.param2
	if p2 then
		local rp2 = p2 % 32
		local extra = math_floor(p2 / 32)
		p2 = (rp2 + rot) % 4 + extra * 32
	end

	local radius = math.max(shape.size.x, shape.size.y, shape.size.z) / 2
	local radius_s = radius * radius
	local center = vector.divide(vector.add(min, max), 2)
	local proportions = vector.divide(vector.subtract(max, vector.subtract(min, 1)), radius * 2)
	local h_radius, h_radius_s

	if shape.hollow then
		h_radius = radius - shape.hollow
		h_radius_s = h_radius * h_radius
	end

	for z = min.z, max.z do
		local index = z * mgen.csize.x + min.x + 1
		local zv = (z - center.z) / proportions.z
		local zvs = zv * zv
		for x = min.x, max.x do
			local ivm = area:index(minp.x + x, minp.y + min.y, minp.z + z)
			local top_y = max.y

			if underground then
				local height = heightmap[index]
				if height then
					top_y = math_min(max.y, height - underground)
				end
			end
			if shape.height then
				top_y = math_min(top_y, min.y + shape.height)
			end
			local xv = (x - center.x) / proportions.x
			local xvs = xv * xv

			for y = min.y, top_y do
				local yv = (y - center.y) / proportions.y
				local dist = xvs + yv * yv + zvs
				local radius_good = (dist <= radius_s)
				local hollow_good = (not h_radius or dist > h_radius_s)

				local ok = (not random or mgen.gpr:next(1, math_max(1, random)) == 1)
				if ok and radius_good and hollow_good then
					if not intersect
					or (type(intersect) == 'table' and intersect[data[ivm]])
					or (intersect == true and data[ivm] ~= n_air) then
						data[ivm] = node_num
						p2data[ivm] = p2
					end
				end

				ivm = ivm + ystride
			end
			index = index + 1
		end
	end
end


function Geomorph:write_cylinder(shape, mgen, rot)
	if not shape.axis then
		print(mod_name .. ': can\'t create a cylinder without an axis')
		return
	end

	local area = mgen.area
	local csize = mgen.csize
	local data = mgen.data
	local heightmap = mgen.heightmap
	local minp = mgen.minp
	local ystride = mgen.area.ystride

	local min, max = rotate_coords(shape, rot, csize)
	local node_num = mgen.node[shape.node]
	local underground = shape.underground
	local hollow = shape.hollow
	local axis = shape.axis
	local intersect = shape.intersect

	local n_air = mgen.node['air']

	if rot == 1 or rot == 3 then
		if axis == 'x' or axis == 'X' then
			axis = 'z'
		elseif axis == 'z' or axis == 'Z' then
			axis = 'x'
		end
	end

	local do_radius = {
		x=(axis ~= 'x' and axis ~= 'X'),
		y=(axis ~= 'y' and axis ~= 'Y'),
		z=(axis ~= 'z' and axis ~= 'Z'),
	}

	local radius = math.max(shape.size.x, shape.size.y, shape.size.z) / 2
	local radius_s = radius * radius
	local center = vector.divide(vector.add(min, max), 2)
	local proportions = vector.divide(vector.subtract(max, min), radius * 2)
	local h_radius, h_radius_s

	if hollow then
		h_radius = radius - shape.hollow
		h_radius_s = h_radius * h_radius
	end

	for z = min.z, max.z do
		local xv, xvs, yv, zv, zvs
		local index = z * mgen.csize.x + min.x + 1
		if do_radius.z then
			zv = (z - center.z) / proportions.z
			zvs = zv * zv
		end
		for x = min.x, max.x do
			local ivm = area:index(minp.x + x, minp.y + min.y, minp.z + z)
			local top_y = max.y

			if underground then
				local height = heightmap[index]
				if height then
					top_y = math_min(max.y, height - underground)
				--elseif min.y > -32 then
				--	top_y = min.y - 1
				end
			end
			if do_radius.x then
				xv = (x - center.x) / proportions.x
				xvs = xv * xv
			end

			for y = min.y, top_y do
				if do_radius.y then
					yv = (y - center.y) / proportions.y
				end

				local radius_good = false
				local hollow_good = (not hollow)

				if do_radius.x and do_radius.y then
					local dist = xvs + yv * yv
					radius_good = (dist <= radius_s)
					if hollow then
						hollow_good = (dist > h_radius_s)
						and (z < min.z + hollow and z > max.z - hollow)
					end
				elseif do_radius.x and do_radius.z then
					local dist = xvs + zvs
					radius_good = (dist <= radius_s)
					if hollow then
						hollow_good = (dist > h_radius_s)
						and (y < min.y + hollow and y > max.y - hollow)
					end
				elseif do_radius.y and do_radius.z then
					local dist = yv * yv + zvs
					radius_good = (dist <= radius_s)
					if hollow then
						hollow_good = (dist > h_radius_s)
						and (x < min.x + hollow and x > max.x - hollow)
					end
				end

				if radius_good and hollow_good then
					if not intersect
					or (type(intersect) == 'table' and intersect[data[ivm]])
					or (intersect == true and data[ivm] ~= n_air) then
						data[ivm] = node_num
					end
				end

				ivm = ivm + ystride
			end
			index = index + 1
		end
	end
end


function Geomorph:write_stair(shape, mgen, rot)
	if not shape.param2 then
		print(mod_name .. ': can\'t make a stair with no p2')
		return
	end

	local area = mgen.area
	local csize = mgen.csize
	local data = mgen.data
	local heightmap = mgen.heightmap
	local minp = mgen.minp
	local p2data = mgen.p2data
	local ystride = mgen.area.ystride

	local min, max = rotate_coords(shape, rot, csize)
	local node_num = mgen.node[shape.node]
	local underground = shape.underground
	local depth_fill = shape.depth_fill
	local p2 = shape.param2
	if p2 then
		local rp2 = p2 % 32
		local extra = math_floor(p2 / 32)
		p2 = (rp2 + rot) % 4 + extra * 32
	end
	local depth = (shape.depth and shape.depth > -1) and shape.depth
	local s_hi = (shape.height and shape.height > 0) and shape.height or 2

	local n_stone = mgen.node['default:stone']
	local n_air = mgen.node['air']
	local n_depth = depth_fill and mgen.node[depth_fill] or n_stone

	for z = min.z, max.z do
		local index = z * csize.x + min.x + 1
		for x = min.x, max.x do
			local top_y = max.y

			if underground then
				local height = heightmap[index]
				if height then
					top_y = math_min(max.y, height - underground)
				end
			end

			local dy
			if p2 == 0 then
				dy = z - min.z
			elseif p2 == 1 then
				dy = x - min.x
			elseif p2 == 2 then
				dy = max.z - z
			elseif p2 == 3 then
				dy = max.x - x
			end
			dy = math_min(dy, top_y)

			local s_lo = depth and dy - depth or 0
			local y1 = minp.y + min.y + s_lo
			local ivm = area:index(minp.x + x, y1, minp.z + z)
			for y = s_lo, dy - 1 do
				data[ivm] = n_depth
				p2data[ivm] = 0
				ivm = ivm + ystride
			end
			data[ivm] = node_num
			p2data[ivm] = p2

			-----------------------------------------
			-- issues with max height ??
			-----------------------------------------
			y1 = minp.y + min.y + dy + 1
			ivm = area:index(minp.x + x, y1, minp.z + z)
			for y = 0, s_hi do
				data[ivm] = n_air
				p2data[ivm] = 0
				ivm = ivm + ystride
			end
			-----------------------------------------

			index = index + 1
		end
	end
end


function Geomorph:write_ladder(shape, mgen, rot)
	local area = mgen.area
	local csize = mgen.csize
	local data = mgen.data
	local heightmap = mgen.heightmap
	local minp = mgen.minp
	local p2data = mgen.p2data
	local ystride = mgen.area.ystride

	local min, max = rotate_coords(shape, rot, csize)
	local node_num = mgen.node[shape.node]
	local underground = shape.underground

	local p2 = shape.param2
	-- 2 X+   3 X-   4 Z+   5 Z-
	for i = 0, 3 do
		if ladder_transform[i] == p2 then
			p2 = ladder_transform[(i + rot) % 4]
			break
		end
	end

	for z = min.z, max.z do
		local index = z * csize.x + min.x + 1
		for x = min.x, max.x do
			local ivm = area:index(minp.x + x, minp.y + min.y, minp.z + z)
			local top_y = max.y

			if underground then
				local height = heightmap[index]
				if height then
					top_y = math_min(max.y, height - underground)
				end
			end

			for y = min.y, top_y do
				data[ivm] = node_num
				p2data[ivm] = p2

				ivm = ivm + ystride
			end

			index = index + 1
		end
	end
end


function Geomorph:write_puzzle(shape, mgen, rot)
	local chance = shape.chance or 20
	if mgen.gpr:next(1, math_max(1, chance)) == 1 then
		self:write_match_three(shape, mgen, rot)

		local l = vector.add(shape.location, vector.floor(vector.divide(shape.size, 2)))
		l.y = shape.location.y
		self:write_chest(l, mgen, rot)
	end
end


function Geomorph:write_chest(location, mgen, rot)
	local s = {
		action = 'cube',
		location = location,
		node = 'default:chest',
		size = vector.new(1, 1, 1)
	}
	self:write_cube(s, mgen, rot)
end


function Geomorph:write_match_three(shape, mgen, rot)
	--local width = shape.size.z - 4
	local p1

	local p = table.copy(shape)
	p.location = vector.add(p.location, -2)
	p.location.y = p.location.y + 2
	p.size = vector.add(p.size, 4)
	p.size.y = p.size.y - 6 + (shape.clear_up or 0)
	p.node = 'air'
	self:write_cube(p, mgen, rot)

	p = table.copy(shape)
	p.node = 'match_three:top'
	p.location.y = p.location.y + shape.size.y - 2
	p.size.y = 1
	self:write_cube(p, mgen, rot)

	p1 = table.copy(p)
	p1.node = 'match_three:clear_scrith'
	p1.location.y = shape.location.y - 1
	self:write_cube(p1, mgen, rot)

	p = table.copy(p)
	p.location.x = p.location.x + 1
	p.location.z = p.location.z + 1
	p.size.x = p.size.x - 2
	p.size.z = p.size.z - 2
	p.node = 'match_three:clear_scrith'
	self:write_cube(p, mgen, rot)
end


mod.registered_geomorphs = {}
function mod.register_geomorph(g)
	if not g.name then
		print(mod_name .. ': cannot register a nameless geomorph')
		return
	end

	local geo = Geomorph.new(g)
	if geo then
		mod.registered_geomorphs[g.name] = geo
	end
end
