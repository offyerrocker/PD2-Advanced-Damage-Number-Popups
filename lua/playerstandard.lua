Hooks:PostHook(PlayerStandard,"enter","odamagepopups_onplayerspawned",function(self, state_data, enter_data)
	ODamagePopups:OnLoad()
	CopDamage.register_listener("odamagepopups_on_cop_damage",{"on_damage"},callback(ODamagePopups,ODamagePopups,"CreateDamagePopup"))
end)