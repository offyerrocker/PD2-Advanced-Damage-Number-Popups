--[[ 
todo
assure popup spreading in opposite directions for readability

unbound panel size to prevent possible clipping with very large glyphs
teammate popup settings

speed var setting
position offset setting (angle variance for spread)

colorpicker: (suggested) default palettes

warframe damage numbers?
--]]



ODamagePopups = {
	settings = {
--		general_master_enabled = true,
		general_fun_allowed = 2, -- april fool's control; 1=always,2=seasonal,3=never
		general_use_raw_damage = false,
		general_use_player_damage_only = true,
		general_hide_zero_damage_hits = false, -- if true, hits that deal exactly 0 damage will not be shown
		general_damage_decimal_accuracy = 2, -- number of digits after the decimal point to show in damage numbers
		
		group_damage_aggregate_mode = 2, -- controls how multiple damage instances on a single enemy are displayed: 1) none (all separate popups); 2) aggregate by enemy (any hit location); 3) aggregate by enemy and hit body
		group_damage_time_window = 1.0, -- hits must be within this many seconds from first hit to count in the same damage stack group (0 for infinite)
		group_damage_use_refresh = true, -- if true, refresh time window on hit; if false, only count seconds from first hit
		appearance_use_damage_type_icon = false, -- deprecated because i think it's ugly
		appearance_popup_style = 1, -- 1) spawn at hit position. 2) borderlands-style rain; 3) xiv style flytext; 4) destiny 2 style left/right splits
		appearance_use_body_relative_position = false, -- if true, damage popups are always tethered/relative to the body position; if false, the damage popups may spawn at the hit position, but position does not follow the body position
		appearance_popup_hold_duration = 0.4,
		appearance_popup_fade_duration = 0.25,
		appearance_popup_font_custom_enabled = false,
		appearance_popup_font_size = 44.0, -- font size
		appearance_popup_font_name = "fonts/font_eurostile_ext",
		appearance_popup_fontsize_pulse_mul = 2.0,
		appearance_popup_fontsize_pulse_duration = 0.42, 
		
		palettes = {
			"ff0000",
			"ffff00",
			"00ff00",
			"00ffff",
			"0000ff",
			"880000",
			"888800",
			"008800",
			"008888",
			"000088",
			"ff8800",
			"88ff00",
			"00ff88",
			"0088ff",
			"8800ff",
			"884400",
			"448800",
			"008844",
			"004488",
			"440088",
			"ffffff",
			"bbbbbb",
			"888888",
			"444444",
			"000000"
		},
		colors_packed = {
			bullet    = 0xffffff,
			melee     = 0xd41ef9,
			poison    = 0x6bf91e,
			fire      = 0xf93f1e,
			explosion = 0xf9e51e,
			tase      = 0x359bf4,
--			0xf9781e,
			misc      = 0x1eb1f9
		}
	},
	_mod_path = ModPath,
	_menu_path = ModPath .. "menu/",
	_save_path = SavePath .. "odamagepopups_settings.json",
	_default_loc_path = ModPath .. "l10n/english.json",
	_menu_main_id = "menu_odp_options_main",
	_COLORPICKER_URL = "https://modworkshop.net/mod/29641",
	_QKI_URL = "https://pd2mods.z77.fr/quick_keyboard_input.html",
	
	_colors = {}, -- list of unpacked colors
	_popup_instances = {}, -- table, keyed by [string unitkey]
	_workspace = nil, -- Workspace
	_parent_panel = nil, -- Panel
	_fun_allowed = nil -- bool, determined on game load
}

function ODamagePopups:UnpackColors()
	-- unpack colors
	for id,color_dec in pairs(self.settings.colors_packed) do 
		local color_str = string.format("%06x",color_dec)
		self._colors[id] = Color(color_str)
	end
end

function ODamagePopups:GetColor(id)
	return id and self._colors[id]
end

function ODamagePopups:LoadSettings()
	local file = io.open(self._save_path, "r")
	if file then
		for k, v in pairs(json.decode(file:read("*all"))) do
			self.settings[k] = v
		end
	end
	
	self:UnpackColors()
end

function ODamagePopups:SaveSettings()
	local file = io.open(self._save_path,"w+")
	if file then
		file:write(json.encode(self.settings))
		file:close()
	end
end

-- on player spawned
function ODamagePopups:OnLoad()
	self:CheckHUD()
	
	-- april fool's check
	if self.settings.general_fun_allowed == 1 then
		self._fun_allowed = true
	elseif self.settings.general_fun_allowed == 2 then
		local today = os.date("*t",os.time())
		self._fun_allowed = today.month == 4 and today.day == 1
	else -- 3 or fallback
		self._fun_allowed = false
	end
end

function ODamagePopups:CheckHUD()
	if not alive(self._workspace) then
		local ws = managers.gui_data:create_fullscreen_workspace()
		self._workspace = ws
		self._parent_panel = ws:panel()
	end
end


function ODamagePopups:CreateDamagePopup(damage_info)
	if not self.settings.general_master_enabled then 
		return
	end
	
	local attacker_unit = damage_info.attacker_unit
	local SETTING_DAMAGE_TYPE_ICON = self.settings.appearance_use_damage_type_icon
	local SETTING_RAW_DAMAGE = self.settings.general_use_raw_damage
	--local SETTING_DAMAGE_STACKING = self.settings.use_stack_damage
	local SETTING_DAMAGE_STACKING = self.settings.group_damage_aggregate_mode
	local SETTING_PLAYER_ONLY = self.settings.general_use_player_damage_only
	local SETTING_POPUP_STYLE = self.settings.appearance_popup_style
	local POPUP_HOLD_DURATION = self.settings.appearance_popup_hold_duration
	local POPUP_FADE_DURATION = self.settings.appearance_popup_fade_duration
	local SETTING_POPUP_STICKY = self.settings.appearance_use_body_relative_position
	local SETTING_HIDE_ZERO_DAMAGE_HITS = self.settings.general_hide_zero_damage_hits
	local DECIMAL_ACCURACY = self.settings.general_damage_decimal_accuracy -- should be an int
	local SETTING_DAMAGE_STACKING_TIME_GROUP_THRESHOLD = self.settings.group_damage_time_window 
	local SETTING_DAMAGE_STACKING_TIME_REFRESH_ENABLED = self.settings.group_damage_use_refresh
	
	local SETTING_FONTSIZE_PULSE_DURATION = self.settings.appearance_popup_fontsize_pulse_duration
	local SETTING_FONTSIZE_PULSE_MULTIPLIER = self.settings.appearance_popup_fontsize_pulse_mul
	local SETTING_FONT_NAME = self.settings.appearance_popup_font_custom_enabled and self.settings.appearance_popup_font_name or tweak_data.menu.pd2_large_font
	local SETTING_FONT_SIZE = self.settings.appearance_popup_font_size or tweak_data.hud.medium_deafult_font_size
	
	if not alive(attacker_unit) then
		return
	end
	
	if attacker_unit:base() and attacker_unit:base().thrower_unit then
		attacker_unit = attacker_unit:base():thrower_unit()
	end
	
	if not SETTING_PLAYER_ONLY or attacker_unit == managers.player:local_player() then
		local col_ray = damage_info.col_ray or {}
		local result = damage_info.result or {}
		local hit_unit = col_ray.unit
		local ukey = alive(hit_unit) and tostring(hit_unit:key()) -- UNIT MAY BE NIL if damage is explosion!
		local tbl_key = ukey or tostring(damage_info)
		local damage = SETTING_RAW_DAMAGE and damage_info.raw_damage or damage_info.damage
		if not damage then
			return
		end
		
		if SETTING_HIDE_ZERO_DAMAGE_HITS and damage == 0 then
			return
		end
		
		damage = damage * 10 -- displayed health/damage numbers are 10x their internal values. why? good question
		
		local name = damage_info.name
		local body = col_ray.body
		local distance = col_ray.distance
		local hit_position = col_ray.hit_position or damage_info.pos or (ukey and hit_unit:position())
		
		local headshot = damage_info.headshot
		local variant = damage_info.variant
		local killshot = result.type == "death"
		
		local t = TimerManager:game():time()
		local color_1 = Color.white
		local color_2 = Color.black
		local layer = 1
		local font_size = 32
		
		local popup_instance = nil
		
		do
			local prev_instance = ukey and self._popup_instances[ukey] -- existing popup instance on this enemy
			if prev_instance then
				local timecheck_success = true
				-- check if damage is within the damage group's time threshold
				if SETTING_DAMAGE_STACKING_TIME_GROUP_THRESHOLD and SETTING_DAMAGE_STACKING_TIME_GROUP_THRESHOLD ~= 0 then
					local damage_group_t = prev_instance.start_t or 0
					if t - damage_group_t <= SETTING_DAMAGE_STACKING_TIME_GROUP_THRESHOLD then
						-- is within this damage group
					else
						-- timed out, don't accept new damage (make a new instance)
						timecheck_success = false
					end
				end
				
				-- check if prev instance is valid according to user grouping rules
				if timecheck_success then
					if SETTING_DAMAGE_STACKING == 3 then
						if alive(body) and body == prev_instance.body then
							popup_instance = prev_instance
						end
					elseif SETTING_DAMAGE_STACKING == 2 then
						if ukey == prev_instance.ukey then -- unit being alive is implicit if ukey is truthy
							popup_instance = prev_instance
						end
					else -- 1 or unspecified/fallback
						-- no stacking behavior; make a new instance
					end
				end
				
				if popup_instance then
					damage = damage + (popup_instance.damage or 0)
				else
					-- if not reusing the previous instance,
					-- remove the old instance and use the same ukey for the new instance;
					-- we won't be operating any more on it anyway,
					-- so we'll let it run its course and self-terminate
					self._popup_instances[tbl_key] = nil
					prev_instance.key = nil
--					local new_key = tostring(prev_instance)
--					prev_instance.key = new_key
--					self._popup_instances[new_key] = prev_instance -- assign a new unique key; not actually necessary to reregister it since it won't be used anymore
				end
			end
		end
		
		local parent_panel = self._parent_panel
		local function cb_done(o,data)
			-- remove panel and unregister popup
			parent_panel:remove(o)
			if data and data.key then
				self._popup_instances[data.key] = nil
			end
		end
		
		local color = self:GetColor(variant) or self:GetColor("misc")
		
		local icon_texture,icon_rect
		if SETTING_DAMAGE_TYPE_ICON then
			if variant == "bullet" then
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("wp_target")
			elseif variant == "melee" then
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("pd2_melee")
			elseif variant == "poison" then
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("pd2_methlab")
			elseif variant == "fire" then
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("pd2_fire")
			elseif variant == "explosion" then
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("pd2_c4")
			else
				icon_texture,icon_rect = tweak_data.hud_icons:get_icon_data("pd2_kill")
			end
		end
		
		local damage_string
		if self._fun_allowed then
			if math.floor(damage) == 69 then
				damage_string = "69 (nice)" --not localized!
			else
				damage_string = self.to_roman_numerals_str(damage)
			end
			-- alt. exp
--			damage_string = string.format("%e",damage)
			
			-- alt. hex
--			if DECIMAL_ACCURACY > 1 then
--				damage_string = string.format("%0." .. tostring(DECIMAL_ACCURACY - 1) .. "a",damage)
--			else
--				damage_string = string.format("%a",damage)
--			end
		else
			if math.log(damage,10) > 10 then
				if DECIMAL_ACCURACY > 1 then
					damage_string = string.format("%." .. tostring(DECIMAL_ACCURACY) .. "g",damage) -- shortest representation (float or exp)
				else
					damage_string = string.format("%.1g",damage)
				end
			else
				if DECIMAL_ACCURACY > 1 then
					damage_string = string.format("%0." .. tostring(DECIMAL_ACCURACY - 1) .. "f",damage)
				else
					damage_string = string.format("%d",damage)
				end
			end
		end
		
		if popup_instance then
			popup_instance.text:set_text(damage_string)
			
			if popup_instance.anim_attach then
				popup_instance.panel:stop(popup_instance.anim_attach)
				popup_instance.anim_attach = nil
			end
			if popup_instance.anim_fadeout then
				popup_instance.panel:stop(popup_instance.anim_fadeout)
				popup_instance.anim_fadeout = nil
			end
			popup_instance.panel:set_alpha(1)
			
			if SETTING_DAMAGE_TYPE_ICON and alive(popup_instance.icon) then
				popup_instance.icon:set_image(icon_texture,unpack(icon_rect))
			end
			popup_instance.body = body or popup_instance.body 
			popup_instance.damage = damage
			
			if SETTING_DAMAGE_STACKING_TIME_REFRESH_ENABLED then 
				popup_instance.start_t = t
			end
		else
			local panel = parent_panel:panel({
				name = "damage_popup_" .. tostring(damage_info),
				w = 200,
				h = 200,
				x = -1000,
				y = -1000,
				layer = 1
			})
			
			local icon
			if SETTING_DAMAGE_TYPE_ICON then
				local icon_w,icon_h = 16,16
				icon = panel:bitmap({
					name = "icon",
					texture = icon_texture,
					texture_rect = icon_rect,
					w = icon_w,
					h = icon_h,
					y = (panel:h() - icon_h) / 2,
					valign = "grow",
					halign = "grow",
					visible = true
				})
			end
			
			local text = panel:text({
				name = "text",
				text = damage_string,
				font = SETTING_FONT_NAME, --tweak_data.hud.medium_font,
				font_size = SETTING_FONT_SIZE, --tweak_data.hud.medium_deafult_font_size, -- this typo is intended and accurate to the tweakdata
				layer = layer,
				color = color,
				alpha = 1,
				x = SETTING_DAMAGE_TYPE_ICON and 18 or 0,
				align = "center",
				vertical = "center",
				valign = "grow",
				halign = "grow",
				visible = true
			})
			
			popup_instance = {
				damage = damage,
				body = body,
				position = hit_position,
				--anim_attach = attach_thread,
				--anim_fadeout = fadeout_thread,
				--anim_pulse = nil,
				start_t = t,
				ukey = ukey, -- identifier for the hit unit specifically; only used for checking damage grouping
				key = tbl_key, -- lookup key to self._popup_instances for this instance (can be changed post init; do not assume final)
				
				workspace = self._workspace,
				panel = panel,
				text = text,
				icon = icon
			}
			
			self._popup_instances[tbl_key] = popup_instance
		
		end
		
--		if alive(popup_instance.panel) then
--			local x,y,w,h = popup_instance.text:text_rect() -- this will crash if used on a gui Text object with an invalid font, so... don't do that. stop having it be invalid
--			popup_instance.panel:set_size(w + 4,h + 4)
--		end
		
		-- note: "done callbacks" on the attach functions will never run, since those animations are designed to run indefinitely and will not naturally self-terminate
		if SETTING_POPUP_STYLE == 2 then
			-- bl2
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_vault,nil,popup_instance,100)
		elseif SETTING_POPUP_STYLE == 3 then
			-- xiv
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_xiv,nil,popup_instance,100)	
		elseif SETTING_POPUP_STYLE == 4 then
			-- destiny
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_destiny,nil,popup_instance,100,0.9)
		else -- alive(body) and SETTING_POPUP_STYLE == 1 then
			-- attach to body part
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_body,nil,popup_instance)
		end
		
		if headshot and alive(popup_instance.text) then
			if popup_instance.anim_pulse then
				popup_instance.text:stop(popup_instance.anim_pulse)
			end
			local to = SETTING_FONT_SIZE
			local from = to * SETTING_FONTSIZE_PULSE_MULTIPLIER
			popup_instance.anim_pulse = popup_instance.text:animate(self.animate_text_size_grow,nil,popup_instance,from,to,SETTING_FONTSIZE_PULSE_DURATION)
		end
		
		popup_instance.anim_fadeout = popup_instance.panel:animate(self.animate_popup_fadeout,cb_done,popup_instance,POPUP_HOLD_DURATION,POPUP_FADE_DURATION,nil,nil)
	end
end

function ODamagePopups:ClearPopups()
	if alive(self._parent_panel) then
		for k,popup in pairs(self._popup_instances) do 
			if alive(popup.panel) then
				self._parent_panel:remove(popup.panel)
			end
			self._popup_instances[k] = nil
		end
	else
		for k,popup in pairs(self._popup_instances) do 
			self._popup_instances[k] = nil
		end
	end
end

function ODamagePopups.to_roman_numerals_str(n)
	local letters = {
		[1] = "I",
		[5] = "V",
		[10] = "X",
		[50] = "L",
		[100] = "C",
		[500] = "D",
		[1000] = "M"
	}
	local s = ""
	
	-- thousands
	if n > 4000 then
		-- someday we'll come up with the technology to represent numbers larger than 4000...
		return "MMMM+"
	end
	
	local num_thousands = math.floor(n/1000)
	local rem_thousands = n % 1000
	s = string.rep(letters[1000],num_thousands) .. s
	
	-- hundreds
	local num_hundreds = math.floor(rem_thousands/100)
	local rem_hundreds = rem_thousands % 100
	if num_hundreds == 9 then -- 900 -> CM
		s = s .. letters[100] .. letters[1000]
	elseif num_hundreds >= 5 then -- 500+ -> D .. C(n)
		s = s .. letters[500] .. string.rep(letters[100],num_hundreds - 5)
	elseif num_hundreds == 4 then -- 400 -> CD
		s = s .. letters[100] .. letters[500]
	else -- C(n)
		s = s .. string.rep(letters[100],num_hundreds)
	end
	
	-- tens
	local num_tens = math.floor(rem_hundreds/10)
	local rem_tens = rem_thousands % 10
	if num_tens == 9 then -- 90 -> LC
		s = s .. letters[10] .. letters[100]
	elseif num_tens >= 5 then -- 50+ > L .. X(n)
		s = s .. letters[50] .. string.rep(letters[10],num_tens - 5)
	elseif num_tens == 4 then -- 40 -> XL
		s = s .. letters[10] .. letters[50]
	else
		s = s .. string.rep(letters[10],num_tens)
	end
	
	-- ones
	local num_ones = rem_tens
	if num_ones == 9 then -- 9 -> IX
		s = s .. letters[1] .. letters[10]
	elseif num_ones >= 5 then -- 5+ > V .. I(n)
		s = s .. letters[5] .. string.rep(letters[1],num_ones - 5)
	elseif num_ones == 4 then -- 4 -> IV
		s = s .. letters[1] .. letters[5]
	else
		s = s .. string.rep(letters[1],num_ones)
	end
	
	return s
end

function ODamagePopups.animate_attach_body(o,cb_done,data)
	local body = data.body
	local world_pos = data.position or Vector3()
	local screen_pos = Vector3()
	local cam_fwd_vec = Vector3()
	local pos_dir_vec = Vector3()
	local viewport_cam = managers.viewport:get_current_camera()
	local ws = data.workspace
	while true do 
		if alive(body) and ODamagePopups.settings.appearance_use_body_relative_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_center(screen_pos.x,screen_pos.y)
		else
			o:set_position(-1000,-1000)
		end
		coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
end

-- simulates gravity on popups, and a semirandom direction vector
function ODamagePopups.animate_attach_vault(o,cb_done,data,fly_speed)
	-- spray in random direction depending on t
	local t = Application:time()
	fly_speed = (fly_speed or 10)
	local speed_mul = 360 / math.pi
	local dir_y = -math.abs(math.sin(t * speed_mul)) * fly_speed
	local dir_x = math.cos(t * speed_mul) * fly_speed
	local offset_x,offset_y = 0,0
	local body = data.body
	local world_pos = data.position or Vector3()
	local screen_pos = Vector3()
	local cam_fwd_vec = Vector3()
	local pos_dir_vec = Vector3()
	local viewport_cam = managers.viewport:get_current_camera()
	local ws = data.workspace
	local dt = 0
	while true do 
		if alive(body) and ODamagePopups.settings.appearance_use_body_relative_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_center(screen_pos.x + offset_x,screen_pos.y + offset_y)
		else
			o:set_position(-1000,-1000)
		end
		
		dir_y = dir_y + (fly_speed * 9.8 * dt) -- imitate gravity acceleration
		
		offset_x = offset_x + (dir_x * dt)
		offset_y = offset_y + (dir_y * dt)
		
		dt = coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
end

-- moves vertically at a linear speed
function ODamagePopups.animate_attach_xiv(o,cb_done,data,fly_speed)
	fly_speed = fly_speed or 2 --pixels/sec
	
	local body = data.body
	local world_pos = data.position or Vector3()
	local screen_pos = Vector3()
	local cam_fwd_vec = Vector3()
	local pos_dir_vec = Vector3()
	local viewport_cam = managers.viewport:get_current_camera()
	local ws = data.workspace
	local y = 0
	local dt = 0
	while true do 
		y = y - (fly_speed * dt)
		
		if alive(body) and ODamagePopups.settings.appearance_use_body_relative_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_center(screen_pos.x,screen_pos.y + y)
		else
			o:set_position(-1000,-1000)
		end
		dt = coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
end

-- moves horizontally with "friction"
function ODamagePopups.animate_attach_destiny(o,cb_done,data,fly_speed,decay)
	fly_speed = fly_speed or 2 --pixels/sec
	fly_speed = fly_speed * (1 + (math.random() - 0.5))
	decay = 0.9 or decay or 0.3 -- speed decay; 0.3 => decays by -30% every second
	
	local body = data.body
	local world_pos = data.position or Vector3()
	local screen_pos = Vector3()
	local cam_fwd_vec = Vector3()
	local pos_dir_vec = Vector3()
	local viewport_cam = managers.viewport:get_current_camera()
	local ws = data.workspace
	local x,y = 0,0
	local x_speed = fly_speed
	local y_speed
	local dt = 0
	local decay_dt = 0
	local t = Application:time()
	
	-- explicit -/+ cases since sign() can return 0 for 0
	local _r = t * 10 * 360/math.pi
	local x_sign
	if math.sin(_r + math.random()) < 0 then
		x_sign = -1
	else
		x_sign = 1
	end
	-- it's okay if motion is perfectly horizontal, so sign() is acceptable here
	local y_speed = math.cos(_r + math.random()) * fly_speed / 5
	local y_sign = math.sign(y_speed)
	y_speed = math.abs(y_speed)
	
	while true do 
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		if alive(body) and ODamagePopups.settings.appearance_use_body_relative_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_center(screen_pos.x + x,screen_pos.y + y)
		else
			o:set_position(-1000,-1000)
		end
		dt = coroutine.yield()
		
		decay_dt = 1 - decay*dt
		y_speed = y_speed ^ decay_dt
		y = y + (y_sign * y_speed * dt)
		
		x_speed = x_speed ^ decay_dt
		x = x + (x_sign * x_speed * dt)
	end
	
	if cb_done then
		cb_done(o,data)
	end
end

-- function ODamagePopups.animate_color_flash(o,cb_done,data,color1,color2) end

-- starts at from_size, grows (or shrinks) to to_size
-- ONLY use on Text gui objects!
function ODamagePopups.animate_text_size_grow(o,cb_done,data,from_size,to_size,duration_max)
	from_size = from_size or o:font_size()
	to_size = to_size or (from_size * 1.5)
	duration_max = duration_max or 1
--	local pw,ph = o:parent():size()
--	local x,y,w,h = 0,0,0,0
	local c_x,c_y = o:center()
	local t = 0
	local delta = to_size - from_size
	local lerp = 0
	local speed_mul = 90
	while t < duration_max do
		t = t + coroutine.yield()
		lerp = math.sin(t * speed_mul / duration_max)
		o:set_font_size(from_size + delta * lerp * lerp)
		--o:set_center(c_x,c_y)
--		x,y,w,h = o:text_rect()
--		o:set_x((pw - w) / 2)
	end
	o:set_font_size(to_size)
	--o:set_center(c_x,c_y)
	
	if cb_done then
		cb_done(o,data)
	end
end

function ODamagePopups.animate_popup_fadeout(o,cb_done,data,hold_duration,fade_duration,from_a,to_a,...)
	hold_duration = hold_duration or 1
	fade_duration = fade_duration or 1
	local max_fade_duration = fade_duration
	from_a = from_a or o:alpha()
	to_a = to_a or 0
	
	local d_a = from_a - to_a -- progressing from 1 -> 0, so d_a is inverted
	local lerp = 0
	
	while hold_duration > 0 do 
		local dt = coroutine.yield()
		hold_duration = hold_duration - dt -- coroutine.yield() returns dt in this case
	end
	
	while fade_duration > 0 do 
		lerp = fade_duration / max_fade_duration
		
		o:set_alpha(to_a + lerp * lerp * d_a)
		
		fade_duration = fade_duration - coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
end



Hooks:Add("LocalizationManagerPostInit", "odp_LocalizationManagerPostInit", function(loc)
	if true or not BeardLib then
		loc:load_localization_file(ODamagePopups._default_loc_path)
	end
end)


Hooks:Add("MenuManagerSetupCustomMenus", "odp_MenuManagerSetupCustomMenus", function(menu_manager, nodes)
	MenuHelper:NewMenu(ODamagePopups._menu_main_id)
end)

-- not used
--Hooks:Add("MenuManagerPopulateCustomMenus", "odp_MenuManagerPopulateCustomMenus", function(menu_manager, nodes) end)

Hooks:Add("MenuManagerBuildCustomMenus", "odp_MenuManagerBuildCustomMenus", function( menu_manager, nodes )
	--create main menu
	nodes[ODamagePopups._menu_main_id] = MenuHelper:BuildMenu(
		ODamagePopups._menu_main_id,{
			area_bg = "none",
			back_callback = nil,
			focus_changed_callback = nil
		}
	)
	MenuHelper:AddMenuItem(nodes.blt_options,ODamagePopups._menu_main_id,"menu_odp_options_main_title","menu_odp_options_main_desc")
end)

Hooks:Add( "MenuManagerInitialize", "odp_MenuManagerInitialize", function(menu_manager)
	
	-- GENERAL ---------------------------------------------------------------------------
	MenuCallbackHandler.callback_odp_general_master_enabled = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.general_master_enabled = value
		if not value then
			ODamagePopups:ClearPopups()
		end
		ODamagePopups:SaveSettings()
	end
	MenuCallbackHandler.callback_odp_general_fun_allowed = function(self,item)
		-- note: this is an index to a multiplechoice, not a toggle
		local value = item:value()
		ODamagePopups.settings.general_fun_allowed = value
		ODamagePopups:SaveSettings()
	end
	MenuCallbackHandler.callback_odp_general_use_raw_damage = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.general_use_raw_damage = value
		ODamagePopups:SaveSettings()
	end
	
	
	MenuCallbackHandler.callback_odp_general_use_player_damage_only = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.general_use_player_damage_only = value
		ODamagePopups:SaveSettings()
	end
	MenuCallbackHandler.callback_odp_general_hide_zero_damage_hits = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.general_hide_zero_damage_hits = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_general_damage_decimal_accuracy = function(self,item)
		local value = item:value()
		ODamagePopups.settings.general_damage_decimal_accuracy = value
		ODamagePopups:SaveSettings()
	end
	
	
	-- GROUPING ---------------------------------------------------------------------------
	
	MenuCallbackHandler.callback_odp_group_damage_aggregate_mode = function(self,item)
		local value = item:value()
		ODamagePopups.settings.group_damage_aggregate_mode = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_group_damage_time_window = function(self,item)
		local value = item:value()
		ODamagePopups.settings.group_damage_time_window = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_group_damage_use_refresh = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.group_damage_use_refresh = value
		ODamagePopups:SaveSettings()
	end
	
	
	-- APPEARANCE ---------------------------------------------------------------------------
	
	MenuCallbackHandler.callback_odp_appearance_use_damage_type_icon = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.appearance_use_damage_type_icon = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_appearance_popup_style = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_style = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_appearance_use_body_relative_position = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.appearance_use_body_relative_position = value
		ODamagePopups:SaveSettings()
	end
	
	
	MenuCallbackHandler.callback_odp_appearance_popup_hold_duration = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_hold_duration = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_appearance_popup_fade_duration = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_fade_duration = value
		ODamagePopups:SaveSettings()
	end
	
	
	
	MenuCallbackHandler.callback_odp_appearance_popup_fontsize_pulse_mul = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_fontsize_pulse_mul = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_appearance_popup_fontsize_pulse_duration = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_fontsize_pulse_duration = value
		ODamagePopups:SaveSettings()
	end
		-- appearance: customization
	
	
	MenuCallbackHandler.callback_odp_appearance_popup_font_size = function(self,item)
		local value = item:value()
		ODamagePopups.settings.appearance_popup_font_size = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_quickkeyboardinput_custom_font_name = function(self,item)
		ODamagePopups:ShowQKIMenu("font")
	end
		
	
	MenuCallbackHandler.callback_odp_appearance_popup_font_custom_enabled = function(self,item)
		local value = item:value() == "on"
		ODamagePopups.settings.appearance_popup_font_custom_enabled = value
		ODamagePopups:SaveSettings()
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_bullet = function(self,item)
		ODamagePopups:ShowColorpickerMenu("bullet")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_melee = function(self,item)
		ODamagePopups:ShowColorpickerMenu("melee")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_poison = function(self,item)
		ODamagePopups:ShowColorpickerMenu("poison")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_fire = function(self,item)
		ODamagePopups:ShowColorpickerMenu("fire")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_explosion = function(self,item)
		ODamagePopups:ShowColorpickerMenu("explosion")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_tase = function(self,item)
		ODamagePopups:ShowColorpickerMenu("tase")
	end
	
	MenuCallbackHandler.callback_odp_colorpicker_customize_misc = function(self,item)
		ODamagePopups:ShowColorpickerMenu("misc")
	end
	
	ODamagePopups:LoadSettings()
	MenuHelper:LoadFromJsonFile(ODamagePopups._menu_path .. "menu_general.json", ODamagePopups, ODamagePopups.settings)
	MenuHelper:LoadFromJsonFile(ODamagePopups._menu_path .. "menu_appearance.json", ODamagePopups, ODamagePopups.settings)
	MenuHelper:LoadFromJsonFile(ODamagePopups._menu_path .. "menu_grouping.json", ODamagePopups, ODamagePopups.settings)
	--MenuHelper:LoadFromJsonFile(ODamagePopups._menu_path, ODamagePopups, ODamagePopups.settings)
end)

function ODamagePopups:CreateColorpicker()
	if ColorPicker and not self._colorpicker then
		self._colorpicker = ColorPicker:new("offysdamagepopups"
		--[[
		{
			color = Color.white,
			palettes = {},
			done_callback = nil,
			changed_callback = nil
		}--]]
		)
	end
	return self._colorpicker
end

function ODamagePopups:ShowColorpickerMenu(id)
	if not _G.ColorPicker then 
		ODamagePopups:ShowColorpickerMissingDialog()
		return
	end
	local colorpicker = self:CreateColorpicker()
	if colorpicker then 
		self:UnpackColors() -- just in case, re-process colors from strings in settings to Color objects
		local color = assert(self._colors[id]) -- if id doesn't exist... we shouldn't be here
		colorpicker:Show({
			color = color,
			palettes = self:GetPaletteColors(),
			done_callback = callback(self,self,"callback_colorpicker_confirm",id),
			changed_callback = nil
		})
	end
end

function ODamagePopups:ShowQKIMissingDialog()
	QuickMenu:new(
		managers.localization:text("menu_odp_dialog_missing_colorpicker_title"),
		managers.localization:text("menu_odp_dialog_missing_colorpicker_desc",
			{
				URL = self._QKI_URL,
				PATH = self._save_path
			}
		),
		{
			{
				text = managers.localization:text("menu_ok"),
				is_cancel_button = true,
				is_focused_button = true
			}
		},
		true
	)
end

function ODamagePopups:ShowColorpickerMissingDialog()
	QuickMenu:new(
		managers.localization:text("menu_odp_dialog_missing_colorpicker_title"),
		managers.localization:text("menu_odp_dialog_missing_colorpicker_desc",
			{
				URL = self._COLORPICKER_URL,
				PATH = self._save_path
			}
		),
		{
			{
				text = managers.localization:text("menu_ok"),
				is_cancel_button = true,
				is_focused_button = true
			}
		},
		true
	)
end

function ODamagePopups:callback_qki_confirm(id,text)
	self.settings.appearance_popup_font_name = text
	self:SaveSettings()
end

function ODamagePopups:callback_colorpicker_confirm(id,color,palettes,success)
	if success then 
		self.settings.colors_packed[id] = tonumber("0x" .. ColorPicker.color_to_hex(color),16)
	end
	
	if palettes then
		self:SetPaletteCodes(palettes)
	end
	
	if success or palettes then 
		self:SaveSettings()
	end
end

function ODamagePopups:GetPaletteColors()
	local result = {}
	for i,hex in ipairs(self.settings.palettes) do 
		result[i] = Color(hex)
	end
	return result
	
end

function ODamagePopups:SetPaletteCodes(tbl)
	if type(tbl) == "table" then 
		for i,color in ipairs(tbl) do 
			self.settings.palettes[i] = ColorPicker.color_to_hex(color)
		end
	else
		log("Error: SetPaletteCodes(" .. tostring(tbl) .. ") Bad palettes table from ColorPicker callback")
	end
end

function ODamagePopups:ShowQKIMenu(id)
	if _G.QuickKeyboardInput then
		local is_pc_controller = managers.controller:get_default_wrapper_type() == "pc" or managers.controller:get_default_wrapper_type() == "steam" or managers.controller:get_default_wrapper_type() == "vr"
		local yes_legend = is_pc_controller and managers.localization:btn_macro("continue") or managers.localization:get_default_macro("BTN_ACCEPT")
		local no_legend = is_pc_controller and managers.localization:btn_macro("back") or managers.localization:get_default_macro("BTN_CANCEL")
		_G.QuickKeyboardInput:new(
			managers.localization:text("menu_odp_dialog_custom_font_title"),
			managers.localization:text("menu_odp_dialog_custom_font_desc",{BTN_CONFIRM = utf8.to_upper(yes_legend),BTN_CANCEL = utf8.to_upper(no_legend)}),
			self.settings.appearance_popup_font_name or "",
			callback(self,self,"callback_qki_confirm",id),
			127,
			true
		)
	else
		self:ShowQKIMissingDialog()
	end
end

-- load default colors just in case the menu hook is somehow executed after the game hook
ODamagePopups:UnpackColors()