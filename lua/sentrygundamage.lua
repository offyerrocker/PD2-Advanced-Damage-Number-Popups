local function clbk(self,attack_data)
	local result = Hooks:GetReturn()
	if result then
		ODamagePopups:CreateDamagePopup(attack_data)
	end
end
Hooks:PostHook(SentryGunDamage,"damage_bullet",		"odp_sentrygundamage_bullet",clbk)
Hooks:PostHook(SentryGunDamage,"damage_tase",		"odp_sentrygundamage_tase",clbk)
Hooks:PostHook(SentryGunDamage,"damage_fire",		"odp_sentrygundamage_fire",clbk)
Hooks:PostHook(SentryGunDamage,"damage_explosion",	"odp_sentrygundamage_explosion",clbk)
