
local ejoy2dx = require "ejoy2dx"
local sprite = require "ejoy2d.sprite"
local spritepack = require "ejoy2d.spritepack"
local particle = require "ejoy2dx.particle"
local render = require "ejoy2dx.render"
local interpreter = require "ejoy2dx.interpreter"
local framework = require "ejoy2d.framework"
local matrix = require "ejoy2d.matrix"

--globals
------------------------------------------------------------------
package_source = {}  		-- all package res
particle_source = particle.configs
package_edit = {} 		  -- user created packages
sprite_sample = {}			-- editor created sprite
focus_sprite = nil				-- current focuse sprite
focus_sprite_root = nil	-- the root of the focus sprite

--controller
------------------------------------------------------------------
local info_render = render:create(99998, "editor")
local info_label = sprite.label({width=400, height=24,size=16,color=0xFFcc3333, edge=1, align='l'})
info_label:ps(5, 8)
info_render:show(info_label)
info_render.is_editor = true
local info_list = {}
local function show_info(txt)
	table.insert(info_list, 1, txt)
	if #info_list > 5 then
		info_list[#info_list] = nil
	end
	info_label.text = table.concat(info_list, "\n")
end

local touch_handler = framework.EJOY2D_TOUCH
local gesture_handler = framework.EJOY2D_GESTURE
local message_handler = framework.EJOY2D_MESSAGE
local drag_target = nil
local drag_src_x = nil
local drag_src_y = nil

local function on_select_sprite(root, spr)
	if focus_sprite_root == root and focus_sprite == spr then
		return
	end
	focus_sprite = spr
	focus_sprite_root = root

	bdbox.clear()
	if not focus_sprite_root or not focus_sprite then return end
	bdbox.show_bd(focus_sprite_root, focus_sprite)

	local p = focus_sprite:get_particle()
	if p then
		local cfg = particle:get_para(p)
		interpreter:broadcast({ope="particle_cfg", data=cfg})
		return
	end

	local sprite_type = focus_sprite.type
	if sprite_type == ejoy2dx.SPRITE_TYPE_LABEL then
		interpreter:broadcast({ope="label_cfg", data={text=spr.text}})
	elseif sprite_type == ejoy2dx.SPRITE_TYPE_PICTURE then
		print(".............picture")
	end
end

local function on_touch(x,y,what,id)
	if what == 1 then --begin
		local touched, root = render:test(x, y)
		if touched then
			drag_target = touched
			drag_src_x, drag_src_y = x, y

			on_select_sprite(root, touched)			
		end
	elseif what == 3 then --move
		if drag_target then
			drag_target:ps2(x - drag_src_x, y - drag_src_y)
			drag_src_x, drag_src_y = x, y
			bdbox.show_bd(focus_sprite_root, drag_target)
		end
	elseif what == 2 then --end
		drag_target = nil
		drag_src_x, drag_src_y = nil, nil
	end
	return true
end

local function on_gesture(what, x1, y1, x2, y2, state)
	print("gesture")
end

local function on_message(id, stat, str_data, num_data)
	if stat == "FINISH" then
	elseif stat == "CANCEL" then
	elseif stat == "KEYDOWN" then
		hotkey:on_keydown(str_data, num_data)
	elseif stat == "KEYUP" then
		hotkey:on_keyup(str_data, num_data)
	end
end

function edit_mode(on)
	if on == 1 then
		ejoy2dx.game_stat:pause()
		framework.EJOY2D_TOUCH = on_touch
		framework.EJOY2D_GESTURE = on_gesture
		framework.EJOY2D_MESSAGE = on_message
		framework.inject()
		show_info("Enter edit mode")
	else
		ejoy2dx.game_stat:resume()
		framework.EJOY2D_TOUCH = touch_handler
		framework.EJOY2D_GESTURE = gesture_handler
		framework.EJOY2D_MESSAGE = message_handler
		framework.inject()
		show_info("Leave edit mode")
	end
end

--wrapper of the env in interpreter
local src_env = env
function env(...)
	renders = {}
	for k, v in pairs(render.renders) do
		local rd={}
		for i, j in pairs(v) do
			if type(j) ~= "table" then
				rawset(rd, i, j)
			end
		end
		table.insert(renders, rd)
		local sprites = {}
		rd.sorted_sprites = sprites
		for i, j in ipairs(v.sorted_sprites) do
			local data = j.usr_data
			if data then
				table.insert(sprites, data)
			else
				table.insert(sprites, j)
			end
		end
	end
	src_env(...)
end

--pack
------------------------------------------------------------------
local meta_to_source = {}

local raw_pack = spritepack.pack
local function c_pack(data)
	local meta = raw_pack(data)
	meta_to_source[meta] = data
	return meta
end
spritepack.pack = c_pack

local raw_init = spritepack.init
local function c_init(name, texture, meta)
	local ret = raw_init(name, texture, meta)
	local src = assert(meta_to_source[meta])
	assert(not package_source[name])
	package_source[name] = src
	return ret
end
spritepack.init = c_init

local sprite_id = 0
local raw_sprite = sprite.new
local function c_sprite(packname, name)
	local spr = raw_sprite(packname, name)
	sprite_id = sprite_id + 1
	spr.usr_data.edit = {packname=packname, name=name, id=sprite_id}
	return spr
end
sprite.new = c_sprite

local raw_direct_new = sprite.direct_new
local function c_direct_new(packname, id)
	local spr = raw_direct_new(packname, id)
	sprite_id = sprite_id + 1
	spr.usr_data.edit = {packname=packname, name=id, id=sprite_id}
	return spr
end
sprite.direct_new = c_direct_new

--upward
------------------------------------------------------------------
function u_del_current_sprite()
	if focus_sprite_root == focus_sprite and focus_sprite then
		info_render:hide(focus_sprite)
		info_render:resort()
		bdbox.clear()
		focus_sprite = nil
		focus_sprite_root = nil

		interpreter:broadcast({ope="delete"})
	end
end

--downward
------------------------------------------------------------------
function set_render_visible(layer, visible)
	local r = render:get(layer)
	if r then
		if visible == 0 then
			show_info("Hide render "..(r.name or layer))
			r.draw_call = nil
		else
			show_info("Show render "..(r.name or layer))
			r.draw_call = r._draw
		end
	end
end

local function get_sprite(layer, idx, ...)
	local r = render:get(layer)
	if r then
		local spr = r.sorted_sprites[idx]
		local root = spr
		if spr then
			local args = {...}
			for k, v in ipairs(args) do
				local child = spr:fetch(v)
				if not child then
					child = spr:fetch_by_index(tonumber(v))
				end
				spr = child
			end
		end
		return spr, root
	end
end
function new_sprite(packname, name)
	local spr = sprite.new(packname, name)
	info_render:show(spr, 0, render.center)
	info_render:resort()
	table.insert(sprite_sample, spr)
	sprite_sample[spr] = #sprite_sample

	on_select_sprite(spr, spr)
	env(nil, "renders")
end

function new_particle(packname, name)
	if not focus_sprite then return end
	local p = particle:new(packname, name)
	focus_sprite:set_particle(p)
end

function del_sprite(layer, idx, ...)
	local r = render:get(layer)
	if r then
		local spr = get_sprite(layer, idx, ...)
		if spr then
			r:hide(spr)
			r:resort()
			bdbox.clear()
			env(nil, "renders")

			focus_sprite = nil
			focus_sprite_root = nil
		end
	end
end

function set_sprite_visible(layer, idx, visible)
	local r = render:get(layer)
	if r then
		local spr = r.sorted_sprites[idx]
		if spr then
			local data = spr.usr_data.render
			if visible == 0 then
				show_info("Hide sprite")
				data.old_blend_mode = data.blend_mode
				data.blend_mode = "hide"
			else
				show_info("Show sprite")
				data.blend_mode = data.old_blend_mode
			end
		end
	end
end

function toggle_child_visible(layer, idx, ...)
	local spr = get_sprite(layer, idx, ...)
	spr.visible = not spr.visible
end

function select_sprite(layer, idx, ...)
	local a, b = get_sprite(layer, idx, ...)
	on_select_sprite(a, b)
end

function move_to_render(tar_layer, layer, idx, ...)
	local spr = get_sprite(layer, idx, ...)
	if spr then
		local old_r = render:get(layer)
		local r = render:get(tar_layer)
		if r and old_r then
			old_r:hide(spr)
			old_r:resort()
			r:show(spr, 0, render.center)
			r:resort()
			env(nil, "renders")
		end
	end
end

function set_particle_attr(key, val)
	if not focus_sprite then return end
	local p = focus_sprite:get_particle()
	if not p then return end
	particle:update_para(p, key, val)
end

function set_label_attr(key, val)
	if not focus_sprite then return end
	if focus_sprite[key] then
		focus_sprite[key] = val
	end
end