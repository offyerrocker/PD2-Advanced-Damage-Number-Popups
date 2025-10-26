
--[[ 
-- this is the method ach uses to detect hits
-- however, it doesn't pick up dot like fire/poison; it only detects direct hits from player weapon
Hooks:PostHook(PlayerManager,"check_skills","odp_init_pm",function(self)
	self:register_message(Message.OnEnemyShot,"odp_OnEnemyShot",function(unit,attack_data,...) 
		if attack_data.attacker_unit and (attack_data.attacker_unit == self:local_player()) then 
			ODamagePopups:CreateDamagePopup(attack_data)
		end
	end)
end)
--]]