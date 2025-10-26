--[[ 
todo
assure popup spreading in opposite directions for readability
--]]





ODamagePopups = {
	settings = {
		use_raw_damage = true,
		mode_damage_aggregate = 2, -- controls how multiple damage instances on a single enemy are displayed: 1) none (all separate popups); 2) aggregate by enemy (any hit location); 3) aggregate by enemy and hit body
		use_damage_type_icon = false,
		use_player_only = true,
		mode_damage_style = 5, -- 1) spawn at body. 2) hit position only; 3) borderlands-style rain; 4) xiv style flytext; 5) destiny 2 style left/right splits
		use_sticky_body_position = false, -- if true, damage popups are always tethered/relative to the body position; if false, the damage popups may spawn at the hit position, but position does not follow the body position
		damage_decimal_accuracy = 2, -- number of digits after the decimal point to show in damage numbers
		damage_group_threshold = 1.0, -- hits must be within this many seconds from first hit to count in the same damage stack group (0 for infinite)
		damage_hide_zero_damage_hits = false, -- if true, hits that deal exactly 0 damage will not be shown
		popup_hold_duration = 0.66,
		popup_fade_duration = 0.33,
		popup_pulse_fontsize_mul = 2.0,
		popup_pulse_fontsize_duration = 2.0, 
		fun_allowed = 2, -- april fool's control; 1=always,2=seasonal,3=never
		
		colors_packed = {
			bullet    = 0xffffff,
			melee     = 0xd41ef9,
			poison    = 0x6bf91e,
			fire      = 0xf93f1e,
			explosion = 0xf9e51e,
			tase = 0x359bf4,
--			0xf9781e,
			misc      = 0x1eb1f9
		}
	},
	_mod_path = ModPath,
	_menu_path = ModPath .. "menu/menu.json",
	_save_path = SavePath .. "odamagepopups_settings.json",
	_default_loc_path = ModPath .. "l10n/english.json",
	
	_colors = {}, -- list of unpacked colors
	_popup_instances = {}, -- table, keyed by [string unitkey]
	_workspace = nil, -- Workspace
	_parent_panel = nil, -- Panel
	_fun_allowed = nil -- bool, determined on game load
}

function ODamagePopups:UnpackColors()
	-- unpack colors
	for id,color_dec in pairs(self.settings.colors_packed) do 
		local color_str = string.format("%x",color_dec)
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
	if self.settings.fun_allowed == 1 then
		self._fun_allowed = true
	elseif self.settings.fun_allowed == 2 then
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
	local attacker_unit = damage_info.attacker_unit
	local SETTING_DAMAGE_TYPE_ICON = self.settings.use_damage_type_icon
	local SETTING_RAW_DAMAGE = self.settings.use_raw_damage
	--local SETTING_DAMAGE_STACKING = self.settings.use_stack_damage
	local SETTING_DAMAGE_STACKING = self.settings.mode_damage_aggregate
	local SETTING_PLAYER_ONLY = self.settings.use_player_only
	local SETTING_POPUP_STYLE = self.settings.mode_damage_style
	local POPUP_HOLD_DURATION = self.settings.popup_hold_duration
	local POPUP_FADE_DURATION = self.settings.popup_fade_duration
	local SETTING_POPUP_STICKY = self.settings.use_sticky_body_position
	local SETTING_HIDE_ZERO_DAMAGE_HITS = self.settings.damage_hide_zero_damage_hits
	local DECIMAL_ACCURACY = self.settings.damage_decimal_accuracy -- should be an int
	local SETTING_DAMAGE_STACKING_TIME_GROUP_THRESHOLD = self.settings.damage_group_threshold 
	
	local SETTING_FONTSIZE_PULSE_DURATION = self.settings.popup_pulse_fontsize_duration
	local SETTING_FONTSIZE_PULSE_MULTIPLIER = self.settings.popup_pulse_fontsize_mul
	
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
		
		damage = damage * 10 -- display only
		
		local name = damage_info.name
		local body = col_ray.body
		local distance = col_ray.distance
		local hit_position = col_ray.hit_position or damage_info.pos or (ukey and hit_unit:position())
		
		local headshot = damage_info.headshot
		local variant = damage_info.variant
		local killshot = result.type == "death"
		
		local t = Application:time()
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
				font = tweak_data.hud.medium_font,
				font_size = tweak_data.hud.medium_deafult_font_size, -- this typo is intended and accurate to the tweakdata
				layer = layer,
				color = color,
				alpha = 1,
				x = 18,
				align = "left",
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
		
		-- note: "done callbacks" on the attach functions will never run, since those animations are designed to run indefinitely and will not naturally self-terminate
		if SETTING_POPUP_STYLE == 3 then
			-- vault
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_vault,nil,popup_instance,100)
		elseif SETTING_POPUP_STYLE == 4 then
			-- xiv
			popup_instance.anim_attach = popup_instance.panel:animate(self.animate_attach_xiv,nil,popup_instance,100)	
		elseif SETTING_POPUP_STYLE == 5 then
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
			local to = tweak_data.hud.medium_deafult_font_size
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

-- not used
function ODamagePopups.animate_attach_position(o,cb_done,data)
	local world_pos = data.position or Vector3()
	local screen_pos = Vector3()
	local cam_fwd_vec = Vector3()
	local pos_dir_vec = Vector3()
	local viewport_cam = managers.viewport:get_current_camera()
	local ws = data.workspace
	while true do 
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_x(screen_pos.x)
			o:set_center_y(screen_pos.y)
		else
			o:set_position(-1000,-1000)
		end
		
		coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
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
		if alive(body) and ODamagePopups.settings.use_sticky_body_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_x(screen_pos.x)
			o:set_center_y(screen_pos.y)
		else
			o:set_position(-1000,-1000)
		end
		coroutine.yield()
	end
	
	if cb_done then
		cb_done(o,data)
	end
end

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
		if alive(body) and ODamagePopups.settings.use_sticky_body_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_x(screen_pos.x + offset_x)
			o:set_center_y(screen_pos.y + offset_y)
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
		
		if alive(body) and ODamagePopups.settings.use_sticky_body_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.set(cam_fwd_vec,viewport_cam:rotation():y())
		mvector3.set(pos_dir_vec,viewport_cam:position())
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_x(screen_pos.x)
			o:set_center_y(screen_pos.y + y)
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
		if alive(body) and ODamagePopups.settings.use_sticky_body_position then
			mvector3.set(world_pos,body:oobb():center())
		end
		mvector3.subtract(pos_dir_vec,world_pos)
		mvector3.normalize(pos_dir_vec)
		
		if mvector3.dot(pos_dir_vec,cam_fwd_vec) < 0.5 then
			screen_pos = ws:world_to_screen(viewport_cam,world_pos)
			o:set_x(screen_pos.x + x)
			o:set_center_y(screen_pos.y + y)
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


function ODamagePopups.animate_color_flash(o,cb_done,data,color1,color2)
end

function ODamagePopups.animate_size_pulse(o,cb_done,data)
end

-- not used
-- starts at from_size, grows to to_size, shrinks back to from_size
function ODamagePopups.animate_text_size_pulse(o,cb_done,data,from_size,to_size,duration_max)
	from_size = from_size or o:font_size()
	to_size = to_size or (from_size * 1.5)
	duration_max = duration_max or 1
	local c_x,c_y = o:center()
	local t = 0
	local delta = to_size - from_size
	local lerp = 0
	local speed_mul = 4 * 360 / math.pi
	while t < duration_max do
		t = t + coroutine.yield()
		local lerp = math.sin(t * speed_mul / duration_max)
		o:set_font_size(from_size + delta * lerp * lerp)
		o:set_center(c_x,c_y)
	end
	o:set_font_size(from_size)
	o:set_center(c_x,c_y)
end

-- starts at from_size, grows to to_size
function ODamagePopups.animate_text_size_grow(o,cb_done,data,from_size,to_size,duration_max)
	from_size = from_size or o:font_size()
	to_size = to_size or (from_size * 1.5)
	duration_max = duration_max or 1
	local c_x,c_y = o:center()
	local t = 0
	local delta = to_size - from_size
	local lerp = 0
	local speed_mul = 2 * 360 / math.pi
	while t < duration_max do
		t = t + coroutine.yield()
		local lerp = math.sin(t * speed_mul / duration_max)
		o:set_font_size(from_size + delta * lerp * lerp)
		o:set_center(c_x,c_y)
	end
	o:set_font_size(from_size)
	o:set_center(c_x,c_y)
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
	if not BeardLib then
		loc:load_localization_file(ODamagePopups._default_loc_path)
	end
end)

Hooks:Add( "MenuManagerInitialize", "odp_MenuManagerInitialize", function(menu_manager)
	MenuCallbackHandler.asdfasdf = function(self,item)
		local value = item:value() == 'on'
		--Olib.settings.olib_toggle_1 = value
		--Olib:Save()
	end
	ODamagePopups:LoadSettings()
	--MenuHelper:LoadFromJsonFile(ODamagePopups._menu_path, ODamagePopups, ODamagePopups.settings)
end)


-- load default colors just in case the menu hook is somehow executed after the game hook
ODamagePopups:UnpackColors()
