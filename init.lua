-- Geomorph init.lua
-- Copyright Duane Robertson (duane@duanerobertson.com), 2019
-- Distributed under the LGPLv2.1 (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html)


geomorph = {}
local mod = geomorph
local mod_name = 'geomorph'

mod.version = '20190530'
mod.path = minetest.get_modpath(minetest.get_current_modname())
mod.world = minetest.get_worldpath()

dofile(mod.path .. '/geomorph.lua')
